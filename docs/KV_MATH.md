# KV Cache Math — predicting per-card VRAM budget

This page documents the math behind [`tools/kv-calc.py`](../tools/kv-calc.py) — the predictor that helps you decide whether a config will fit on your hardware *before* booting it. It also explains why predictions are estimates (±1.5 GB error band) rather than precise allocations.

Two models are modelled today: **Qwen 3.6 27B** (DeltaNet hybrid) and **Gemma 4 31B** (sliding-window + dense MLP). The math differs structurally between them; this doc covers each in its own section. The CLI dispatches on `--model`.

## TL;DR

```bash
# Qwen 3.6 27B — what's my budget if I run dual-turbo on 20 GB cards?
bash tools/kv-calc.py --model qwen3.6-27b --compose dual-turbo --vram 20 --mem-util 0.82

# Gemma 4 31B — what's the largest max_ctx that fits on 24 GB cards with TP=2 + INT8 PTH KV?
bash tools/kv-calc.py --model gemma-4-31b --solve-max-ctx --tp 2 --kv-format int8_per_token_head --vram 24 --mem-util 0.92

# How accurate is the model? Show predicted vs measured for our shipped composes (both models):
bash tools/kv-calc.py --calibration
```

`--model` defaults to `qwen3.6-27b` for backward compatibility with earlier invocations.

The predictor is a directional estimator, not a precise allocator. The vLLM engine's `gpu_worker.py` boot-log report is authoritative — the calculator is for *before* boot.

## Qwen 3.6 27B — per-card budget components

For Qwen3.6-27B AutoRound INT4 at TP=N, the per-card VRAM peak during bench is composed of:

```
peak ≈ weights/N + kv_pool + activation_peak + cudagraph_workspace + dflash_draft/N
```

Each term has a well-defined formula or empirical anchor:

### 1. Model weights (`weights / N`)

AutoRound INT4 weights total ~17.5 GB on disk. Under tensor parallelism, weights split across cards:

- TP=1: 17.5 GB / card
- TP=2: 8.75 GB / card
- TP=4: 4.4 GB / card

This term is exact (the model checkpoint is a fixed size). DeltaNet's `linear_attn.in_proj_a` / `in_proj_b` layers stay at fp16 in the AutoRound quantization (per `extra_config` in `config.json`), but the byte budget is included in the 17.5 GB total.

### 2. KV pool (attention layers only)

In the Qwen3-Next hybrid architecture, **only the 16 full_attention layers contribute to the growing KV cache**. The 48 GDN (Gated DeltaNet) layers maintain a fixed-size recurrent state instead of a growing KV cache (Yang et al., [Gated Delta Networks ICLR 2025](https://github.com/NVlabs/GatedDeltaNet)).

Per-token KV cache bytes (across all attention layers, K + V):

```
per_token_bytes = num_attn_layers × num_kv_heads × head_dim × 2 × bytes_per_kv_element
                = 16        × 4              × 256      × 2 × bpe
                = 32,768 × bpe bytes
```

Where `bpe` depends on the KV format:

| KV format | `bytes_per_kv_element` | per-token KV (full) | per-token KV (TP=2) |
|---|---:|---:|---:|
| `fp16` / `bf16` | 2.0 | 65,536 B | 32,768 B |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | 32,768 B | 16,384 B |
| `q4_0` | ~0.56 | 18,350 B | 9,175 B |
| `k8v4` | 0.75 | 24,576 B | 12,288 B |
| `turboquant_3bit_nc` (TQ3) | ~0.425 | 13,927 B | 6,963 B |

Total KV pool (per card) = `per_token_bytes / TP × max_ctx × max_num_seqs`. PagedAttention ([Kwon et al., arxiv 2309.06180](https://arxiv.org/abs/2309.06180)) wastes <4% of this in fragmentation.

**Caveat**: this formula computes *requested* KV pool. vLLM's actual allocation is bounded by `mem_util × VRAM - other_components`. If requested exceeds available, vLLM emits `estimated max model length is N` and refuses to boot — that's the trigger for FAIL verdict.

**Caveat #2**: `max_num_seqs > 1` over-predicts in `kv-calc.py`. Real vLLM may rate-limit internally; my calculator doesn't model that. If your config uses `max_num_seqs=2` or higher and the calculator predicts FAIL but you've seen it boot, the calculator is over-counting. See "Known limitations" below.

### 3. Activation peak (GDN forward, the Cliff 2 mechanism)

The 48 GDN layers materialize a block-wise intermediate state during prefill. This is the source of [Cliff 2](CLIFFS.md#cliff-2--deltanet-gdn-forward-intermediate-buffer).

The PerfMamba paper ([arxiv 2511.22849](https://arxiv.org/html/2511.22849)) measures this directly on the parent architecture: at sequence length 2048, **Mamba-2 SSM consumes 33.5% more memory than Mamba-1 (115.68 GB vs 86.64 GB) due to "block-wise state materialization."** The asymptotic scaling per the paper:

```
activation_peak ∝ γ × D × N × L
```

where γ = expansion factor, D = hidden dim, N = state dim, L = sequence length.

For Qwen3.6-27B's GDN layers specifically, `fla.ops.chunk.chunk_gated_delta_rule_fwd` allocates an intermediate `h` shaped `(B, NT, H, V, K)`:
- B = batch, NT = `ceil(seq_len / chunk_size)` chunks (chunk_size=256)
- H = number of heads (linear_num_k_heads = 16, linear_num_v_heads = 48)
- V, K = head dim (linear_v_head_dim = linear_k_head_dim = 128)
- per-element 4 bytes (mamba_ssm_dtype = fp32 on this stack)

The published O(γDNL) gives the asymptotic scaling but not the absolute coefficient — that depends on `fla.ops.chunk` implementation details (tiling, streaming, register reuse). We use an **empirical coefficient** calibrated against the 8-10 measured BENCHMARKS rows:

| KV format | bytes/layer/token coefficient | Why this differs from fp8 |
|---|---:|---|
| `fp16` / `bf16` | ~135 | baseline (no KV dequant during forward) |
| `fp8_e5m2` / `fp8_e4m3` | ~130 | small dequant overhead |
| `q4_0` / `k8v4` | ~155 | larger dequant + scale ops |
| `turboquant_3bit_nc` | ~165 | TQ3 dequant during the materialized block adds ~20-25% activation pressure |

The TQ3 → fp8 difference (~25%) is what causes the [20 GB Ampere Cliff 2 fire at 90K](HARDWARE.md#note-for-sub-24-gb-cards) — TQ3's larger activation peak exceeds the per-card budget after TP=2 split on smaller-VRAM cards. Cross-rig validated by [@efschu](https://github.com/noonghunna/club-3090/issues/47) on 2× 3080 modded.

### 4. Cudagraph + workspace overhead

vLLM's torch.compile pass captures multiple cudagraph variants (one per `(batch_size, seq_len_bucket)` combination). Each capture costs ~50-100 MB. FlashInfer adds a 394 MB workspace per card. NCCL allreduce buffers cost ~200-300 MB on TP > 1.

Empirical fit:
```
overhead = 0.5 + 1.0 × mem_util + 0.3 × (TP - 1)  # GB
```

This is rough — actual overhead depends on how many graphs vLLM captures, which depends on `max_num_seqs`, `compile_sizes`, and other internals.

### 5. DFlash draft model

Only present on `dual-dflash*.yml` composes. `z-lab/Qwen3.6-27B-DFlash` is a ~1.75 GB draft model (per card, FP16). With TP > 1, the draft itself is sharded.

## Gemma 4 31B — per-card budget components

Gemma 4 31B is structurally different from Qwen 3.6:

- **No DeltaNet, no GDN activation peak.** Dense MLP instead.
- **Hybrid layer pattern** — but the hybrid is on *attention type*, not attention-vs-recurrence. The 60-layer stack is `[sliding_attention × 5, full_attention × 1] × 10` = **50 sliding-attention layers + 10 full-attention layers**.
- **Head-dim asymmetry** — sliding layers use `head_dim=256`, full layers use `global_head_dim=512`. Per-token KV bytes for the full layers is therefore double what naive `num_layers × head_dim` would compute.
- **K==V tying** — `attention_k_eq_v: true` in `config.json`. vLLM's allocator EXPLOITS this — K and V share storage. The KV term uses `×1`, not `×2`. This was confirmed empirically by calibrating the per-token byte count against measured BENCHMARKS rows (the matched-config rebench's `Available KV cache / card = 10.82 GiB` at 262K seqs=2 is consistent with ×1 storage, not ×2).

Source: `/mnt/models/huggingface/gemma-4-31b-autoround-int4/config.json` → `text_config`.

```
peak ≈ weights/N + kv_pool_growing + kv_pool_sliding + activation_peak + cudagraph_overhead + drafter_overhead
```

### 1. Model weights (`weights / N`)

| Quant | On-disk | Per-card at TP=2 |
|---|---:|---:|
| AutoRound INT4 (`gemma-4-31b-autoround-int4`) | ~18 GB | 9.0 GB |
| AWQ-4bit (`cyankiwi/gemma-4-31B-it-AWQ-4bit`) | ~17 GB usable on stack | 8.5 GB |
| BF16 (unquantized) | ~58 GB | 29 GB (does not fit on 24 GB) |

The two shipped quants on this stack are AutoRound INT4 (default) and AWQ-4bit (Tier 2 reproducer of #103). INT4 weights + INT8-per-token-head KV is the matched-config dual-3090 recipe (see `models/gemma-4-31b/vllm/compose/dual/int8.yml`).

### 2. KV pool — growing portion (full-attention layers only)

Only the 10 full-attention layers grow KV with context. Each stores K and V at `global_head_dim=512`, with K==V tying meaning a single store per element:

```
per_token_bytes_growing = num_full_attn_layers × num_kv_heads × global_head_dim × 1 × bpe
                        = 10 × 16 × 512 × 1 × bpe
                        = 81,920 × bpe bytes
```

For comparison, Qwen 3.6's growing KV is `16 × 4 × 256 × 2 × bpe = 32,768 × bpe` — Gemma 4's per-token growing KV is **~2.5× heavier** than Qwen's. This is *the* reason Gemma 4 at 262K needs INT8 / FP8 KV on Ampere — at BF16 KV the per-card budget blows past 24 GB before you reach 50K context.

Per-token growing-KV bytes by format:

| KV format | `bytes_per_kv_element` | per-token growing KV (full) | per-token (TP=2) |
|---|---:|---:|---:|
| `fp16` / `bf16` | 2.0 | 163,840 B (~160 KB) | 81,920 B |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | 81,920 B (~80 KB) | 40,960 B |
| `int8_per_token_head` (PR #40391) | ~1.01 (incl. per-token scale) | ~82,700 B | ~41,400 B |
| `q4_0` | ~0.56 | ~45,875 B | ~22,940 B |
| `turboquant_3bit_nc` (TQ3) | ~0.425 | ~34,816 B | ~17,408 B |

Total growing-KV pool per card = `per_token_bytes_growing / TP × max_ctx × max_num_seqs`.

**Note**: on Ampere consumer cards (sm_86), `fp8_e4m3` is NOT supported by the Triton kernel (`fp8e4nv` requires Hopper/Ada/Blackwell). Use `int8_per_token_head` (PR #40391, vendored on this stack via PR #42102) instead. See `models/gemma-4-31b/vllm/compose/dual/int8.yml` header for the engineering trail.

### 3. KV pool — fixed sliding portion (50 layers)

The 50 sliding-attention layers maintain a fixed-size KV window (`sliding_window=1024`). K==V tying applies here too:

```
sliding_kv_bytes_total = num_sliding_layers × num_kv_heads × head_dim × 1 × bpe × sliding_window
                       = 50 × 16 × 256 × 1 × bpe × 1024
                       = 209,715,200 × bpe bytes
                       ≈ 200 MB × bpe
```

This is constant — it doesn't scale with `max_ctx` or `max_num_seqs`. At fp8 / int8 KV (`bpe=1`), this is ~200 MB per card (TP=1) or ~100 MB at TP=2. Small but non-zero — include it as a separate term.

### 4. Activation peak (SWA prefill + dense MLP)

Unlike Qwen 3.6's GDN block-wise state materialization, Gemma 4's activation peak comes from:

- Sliding-window attention prefill (50 layers, but bounded by `sliding_window=1024`).
- Dense MLP intermediate buffer (`hidden_size=5376`, `intermediate_size=21504`).

There's no published scaling-law analogue to PerfMamba's O(γDNL) for Gemma 4. The activation coefficient is **empirical-only**, calibrated against measured BENCHMARKS.md rows. Expected order of magnitude: ~1.5-2.5 GB at TP=2 dual-card configs (smaller than Qwen 3.6's GDN peak because there's no per-chunk block materialization).

The coefficient may have weak dependence on KV format (slight dequant overhead during forward) but we expect it to be flatter than Qwen's TQ3 → fp8 25% spread — Gemma's dense MLP doesn't dequant KV during its forward.

### 5. Cudagraph + workspace overhead

Same form as Qwen — empirical fit:
```
overhead = 0.5 + 1.0 × mem_util + 0.3 × (TP - 1)  # GB
```

vLLM captures multiple cudagraphs (~50-100 MB each), FlashInfer workspace (~394 MB/card), NCCL allreduce buffers (~200-300 MB at TP > 1). Same accounting as Qwen.

### 6. Drafter overhead

Two drafter families on this stack:

| Drafter | Size | Composes |
|---|---:|---|
| `gemma-4-31b-it-assistant` (Google MTP) | 0.97 GB FP16 | `dual/docker-compose.yml`, `dual/int8.yml`, `dual/awq.yml` (with MTP n=4) |
| `gemma-4-31b-it-dflash` (z-lab DFlash) | 2.9 GB FP16 | `dual/dflash.yml`, `dual/dflash-int8.yml` |

At TP > 1, drafter weights shard across cards (`drafter_gb / TP`).

## Known limitations

**The model is empirically calibrated, not first-principles.** Specifically:

1. **KV pool capping (resolved 2026-05-13)**. Earlier versions of this calculator over-predicted FAIL on configs with `max_num_seqs > 1` because the requested KV pool exceeded available budget. The current calculator explicitly models vLLM's PagedAttention capping: the predicted KV pool is `min(requested, budget - fixed_components)`. When the request exceeds available, the verdict is `TIGHT` with a note that effective concurrency at `--max-num-seqs` may be lower than requested at full `max_ctx`. The "predicted total" in TIGHT cases equals the budget exactly — that's the saturating-allocator behavior, not a modeling artifact.

2. **Activation coefficient varies by `chunk_size` and `dtype`**. We use the fla default `chunk_size=256` and `mamba_ssm_dtype=float32` (per Qwen3.6-27B config.json). If those change, the coefficient needs re-calibration. For Gemma the activation peak is a flat empirical constant; if Gemma config changes (e.g. layer-pattern ratio, sliding_window), recalibrate.

3. **No driver/allocator overhead modeling**. snoby's 4090 needed `max-model-len` 200K → 180K vs 3090 baseline. The driver-class delta isn't modeled here. We hand-wave with the `±1.5 GB` error band.

4. **No Cliff 2b accumulation modeling**. The multi-turn fragmentation cliff at ~25K accumulated tokens is empirical-only and not in this calculator. Use `SOAK_MODE=continuous` to probe it.

5. **Two-model calibration**. Today the math is calibrated for Qwen3.6-27B and Gemma 4 31B. Adding a third model means deriving a new `MODEL_SPEC` block (architecture params + per-quant weights size + activation-peak mechanism) and calibrating the activation coefficient against ≥4 measured BENCHMARKS rows for that model. Don't ship a third-model spec without that calibration — uncalibrated coefficients give wrong verdicts.

## Calibration

Run `bash tools/kv-calc.py --calibration` to see predicted vs measured for all shipped composes, grouped per model.

| Model | Verdict accuracy | Notes |
|---|---|---|
| Qwen 3.6 27B | 9/11 = 82% (±1.5 GB band) | Two ⨯ cases are over-predictions on `max_num_seqs > 1` (limitation #1 above) |
| Gemma 4 31B | TBD by `--calibration` | Calibrated against `dual/int8.yml` 98K+262K rows, `dual/dflash.yml` 32K BF16, `dual/awq.yml` 65K BF16, `dual/docker-compose.yml` 32K BF16. Target: ≥80% within ±1.5 GB. |

## When to trust the calculator vs vLLM's boot log

Always pass `--model {qwen3.6-27b,gemma-4-31b}` matching the compose you're targeting. Defaults to qwen3.6-27b if omitted.

| Question | Use this |
|---|---|
| "Will it boot?" — for a *shipped* compose on canonical 24 GB | We've already validated; check BENCHMARKS.md |
| "Will it boot?" — for a *novel* config (custom ctx, kv format, or VRAM class) | `kv-calc.py --model <M> --compose <X>` for a directional answer; then boot and read `gpu_worker.py` |
| "What's my max ctx?" — given my hardware | `kv-calc.py --model <M> --solve-max-ctx ...` for an estimate; vLLM's pre-check `estimated max model length is N` line at boot is authoritative |
| "Is TQ3 or fp8 better for my hardware?" (Qwen 3.6) | `kv-calc.py --model qwen3.6-27b` with both options; cross-check [HARDWARE.md](HARDWARE.md#note-for-sub-24-gb-cards) |
| "Is INT8 PTH or BF16 KV better for Gemma 4?" | `kv-calc.py --model gemma-4-31b --kv-format bf16` vs `int8_per_token_head` — BF16 caps at ~32K on dual-3090, INT8 PTH unlocks 262K. See `models/gemma-4-31b/vllm/compose/dual/int8.yml` header. |

## References

**Qwen 3.6 27B (DeltaNet hybrid):**
- [PerfMamba: Performance Analysis and Pruning of Selective State Space Models (arxiv 2511.22849)](https://arxiv.org/html/2511.22849) — block-wise state materialization scaling
- [Gated Delta Networks: Improving Mamba2 with Delta Rule (NVlabs ICLR 2025)](https://github.com/NVlabs/GatedDeltaNet) — Qwen3-Next architecture
- [Mamba: Linear-Time Sequence Modeling (arxiv 2312.00752)](https://arxiv.org/abs/2312.00752) — Mamba-1 baseline for PerfMamba's deltas

**Gemma 4 31B (sliding-window + dense MLP):**
- Architecture params sourced directly from `config.json` (Gemma 4 release post / technical doc were not used as a calibration reference — the activation coefficient is empirical-only on this stack).
- [vLLM PR #40391 (rebased + vendored as PR #42102)](https://github.com/vllm-project/vllm/pull/42102) — per-token-head INT8 KV cache (the Ampere unlock for Gemma 4 at 262K)
- [vLLM PR #41745](https://github.com/vllm-project/vllm/pull/41745) — Gemma 4 MTP assistant drafter support

**Shared:**
- [TurboQuant: Online Vector Quantization with Near-optimal Distortion Rate (arxiv 2504.19874, ICLR 2026)](https://arxiv.org/abs/2504.19874) — TQ3 byte savings + technique
- [Efficient Memory Management for Large Language Model Serving with PagedAttention (arxiv 2309.06180)](https://arxiv.org/abs/2309.06180) — vLLM's KV pool allocator
- [An Investigation of FP8 Across Accelerators for LLM Inference (arxiv 2502.01070)](https://arxiv.org/html/2502.01070v1) — FP8 e5m2/e4m3 KV cache analysis
- [docs/CLIFFS.md](CLIFFS.md) — Cliff 2 mechanism + KV-format-tunability section (Qwen-specific)
- [docs/HARDWARE.md](HARDWARE.md) — 20 GB Ampere TQ3→fp8 swap rule (cross-rig validated by @efschu, Qwen-specific)

## See also

- [`tools/kv-calc.py`](../tools/kv-calc.py) — the predictor itself
- [BENCHMARKS.md](../BENCHMARKS.md) — measured cross-rig data, the calibration anchors
