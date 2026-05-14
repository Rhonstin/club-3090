# KV Cache Math — predicting per-card VRAM budget

This page documents the math behind [`tools/kv-calc.py`](../tools/kv-calc.py) — the predictor that helps you decide whether a config will fit on your hardware *before* booting it. It also explains why predictions are estimates (±1.5 GB error band) rather than precise allocations.

Four model families are documented:

| Model | Status | Architecture |
|---|---|---|
| **Qwen 3.6 27B** (dense) | Calibrated 11/11 on this stack | Qwen3-Next hybrid: 16 full-attention + 48 GDN (Gated DeltaNet) layers |
| **Gemma 4 31B** (dense) | Calibrated 7/7 on this stack | Sliding-window + dense MLP: 50 SWA + 10 full-attention layers |
| **Qwen 3.6 35B-A3B** (MoE) | Math-ready, calibration pending | Qwen3-Next hybrid + MoE: 30 GDN + 10 gated-attention layers |
| **Gemma 4 26B-A4B** (MoE) | Math-ready, calibration pending | Sliding-window + dense MoE: SWA + occasional global layers |

For models marked **calibration pending**, the architectural math derivations below are anchored to published config + model card material; absolute numbers ship as estimates until we measure them on the stack. See [Sources of Error & Accuracy](#sources-of-error--accuracy) at the end.

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

## General KV cache formula

The unified per-card KV pool math:

```
per_token_bytes = num_growing_layers
                × num_kv_heads
                × head_dim
                × k_v_tensors            ← 2 for K and V stored separately; 1 when K=V tied
                × bytes_per_kv_element   ← see KV-format table below

kv_pool_per_card = (per_token_bytes / TP) × max_ctx × max_num_seqs
```

For hybrid architectures (DeltaNet, SWA), only the **growing** attention layers contribute to this formula. Fixed-window or recurrent-state layers contribute a separate, context-independent term (see per-model sections).

### Variable glossary

| Variable | Meaning | Where it comes from |
|---|---|---|
| `num_growing_layers` | Count of attention layers whose KV cache grows with context length | Model card README — **not always in config.json** for hybrid architectures |
| `num_total_layers` | All transformer blocks (attention + DeltaNet + MoE routers + etc.) | `config.json → num_hidden_layers` |
| `num_kv_heads` | Number of KV heads (GQA / MQA factor) | `config.json → num_key_value_heads` |
| `head_dim` | Per-head dimension | `config.json → head_dim` or `hidden_size / num_attention_heads` |
| `k_v_tensors` | 2 when K and V are stored separately; 1 when the model ties K=V | Model card / model code; empirical confirmation via `Available KV cache / card` boot log |
| `bytes_per_kv_element` | Bytes per KV scalar after quantization (see table below) | KV format choice |
| `TP` | Tensor parallel degree | Compose config |
| `max_ctx` | Maximum context length the engine is configured for | Compose config |
| `max_num_seqs` | Maximum concurrent sequences | Compose config |

### `bytes_per_kv_element` by KV format

| KV format | `bytes_per_kv_element` | Notes |
|---|---:|---|
| `bf16` / `fp16` | 2.0 | Baseline; no dequant during forward |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | Requires sm_89+ for `fp8e4nv` (Ampere consumer needs e5m2) |
| `int8_per_token_head` (PR #40391) | ~1.01 | Per-token-head scale adds ~1% overhead; Ampere-friendly |
| `k8v4` | 0.75 | Mixed precision |
| `q4_0` | ~0.56 | Includes packed-quant overhead |
| `turboquant_3bit_nc` (TQ3) | ~0.425 | Genesis-supplied; cheapest KV format on this stack |

**Note on Ampere**: `fp8_e4m3` is NOT supported by the Triton kernel on sm_86 (3090/3090-Ti/A5000). Use `fp8_e5m2` (engine-level fallback) or `int8_per_token_head` (vendored via PR #42102). See [DTYPE_MATRIX.md](DTYPE_MATRIX.md).

### Per-card budget composition (all models)

```
peak ≈ weights/TP                                  ← exact, from checkpoint size
     + kv_pool_growing                             ← formula above
     + kv_pool_fixed                               ← SWA window or recurrent state (context-independent)
     + activation_peak                             ← empirical coefficient per (model, KV format)
     + cudagraph_workspace_overhead                ← empirical fit, ~0.5-1.5 GB
     + drafter_overhead/TP                         ← speculative-decoding drafter weights, if any
```

Per-model sections below derive each term concretely.

## Model architecture summary

| Model | Total layers | Growing layers | Sliding / fixed | KV heads | Head dim | K=V tied | MoE | Special notes |
|---|---:|---:|---:|---:|---:|:---:|:---:|---|
| **Qwen 3.6 27B** | 64 | 16 (full-attention) | 48 (GDN recurrent) | 4 | 256 | No (×2) | No | DeltaNet block-wise activation peak (Cliff 2). `linear_attn` in-proj stays fp16 even under INT4 quant. |
| **Qwen 3.6 35B-A3B** | 40 | 10 (gated attention) | 30 (Gated DeltaNet) | 2 | 256 | No (×2) | Yes | Pattern: `10 × (3× GDN → MoE → 1× Gated Attn → MoE)`. Active params ~3B, total 35B. MoE experts gate decode FLOPs but not KV size. |
| **Gemma 4 31B** | 60 | 10 (full-attention) | 50 (SWA, window=1024) | 16 | 256 sliding / **512 global** | Yes (×1) | No | Global layers use 2× head_dim of sliding layers. K=V tying confirmed empirically against boot-log KV cache reports. |
| **Gemma 4 26B-A4B** | TBD (likely ~40-48) | TBD (likely sparse global) | Majority SWA (window=1024) | TBD | TBD | Likely yes (×1) | Yes | A4B = 4B active params from 26B total. Layer pattern from model card README. **Numbers pending config.json + first boot.** |

**Hybrid quirks to internalize:**

- **Growing vs fixed layers**: in hybrid architectures, KV cache scales with `num_growing_layers`, not `num_total_layers`. Confusing them inflates predictions by ~3-6×.
- **DeltaNet recurrent state**: fixed size per layer, irrespective of context. Adds a small constant term (~hundreds of MB), not a per-token term.
- **K=V tying**: when present (Gemma 4 family), KV pool is *half* of what naive `×2` math predicts. Always confirm via boot log — vLLM prints `Available KV cache / card = X GiB` after model load; back-solve `per_token_bytes` against your `max_ctx` to verify the tying assumption.
- **Asymmetric head_dim**: Gemma 4's global layers use 2× the head_dim of sliding layers. The KV formula has to split into two terms.

## Extracting parameters from Hugging Face `config.json`

### What you can reliably get from `config.json`

| Parameter | Usually in config.json? | Key names |
|---|---|---|
| Total layers | Yes | `num_hidden_layers` |
| Attention heads / KV heads | Yes | `num_attention_heads`, `num_key_value_heads` |
| Head dimension | Yes | `head_dim` (or compute via `hidden_size / num_attention_heads`) |
| Sliding window size | Yes (when present) | `sliding_window` |
| GQA / MQA ratio | Yes | `num_key_value_heads < num_attention_heads` |
| Rope theta / scaling | Yes | `rope_theta`, `rope_scaling` |
| MoE basics | Yes (when present) | `num_experts`, `num_experts_per_tok` |
| Vocabulary | Yes | `vocab_size` |
| Linear-attention dims (Qwen3-Next) | Yes (newer Qwen configs) | `linear_num_key_heads`, `linear_key_head_dim`, etc. |

### What is often missing or requires README / code inspection

- **Hybrid layer pattern** (e.g. "10 × (3× DeltaNet → 1× Gated Attention)"). The TOTAL layer count is in `config.json`; the SPLIT between growing and fixed is usually only in the model card README.
- **Which specific layers are growing vs fixed** (when the pattern isn't uniform).
- **K=V tying**. Rarely a config field; check model code (`modeling_*.py`) or empirically verify via boot log.
- **Recurrent state size** for DeltaNet / Mamba / SSM layers.
- **Exact growing layer count** for newest hybrid architectures.

### Worked examples

**Qwen 3.6 27B (dense Qwen3-Next):**

```python
import json
config = json.load(open("/mnt/models/huggingface/qwen3.6-27b-autoround-int4/config.json"))
# Reads directly:
#   num_hidden_layers = 64
#   num_key_value_heads = 4
#   head_dim = 256
# But the split (16 attention vs 48 GDN) is from the model card README,
# not derivable from config.json alone.
```

**Qwen 3.6 35B-A3B (MoE, hypothetical layout once downloaded):**

```python
# config.json gives:
#   num_hidden_layers = 40
#   num_key_value_heads = 2          (typical Qwen3.6 MoE GQA ratio)
#   head_dim = 256                   (for gated attention layers)
#   num_experts = 128                (typical Qwen MoE config)
#   num_experts_per_tok = 8          (active experts per token)
#   linear_num_key_heads = ...       (DeltaNet state dim — present in newer configs)
# Still need from README:
#   The "10 × (3× GDN → MoE → 1× Gated Attn → MoE)" pattern → 10 growing layers
```

**Gemma 4 31B:**

```python
# config.json → text_config gives:
#   num_hidden_layers = 60
#   num_key_value_heads = 16
#   head_dim = 256                   (sliding layers)
#   global_head_dim = 512            (full-attention layers)
#   sliding_window = 1024
# Still need from README / model code:
#   The 5:1 sliding:global interleave pattern → 50 sliding + 10 global
#   K=V tying (`attention_k_eq_v: true` IS in config.json for Gemma 4 — lucky)
```

### Recommended workflow

1. Auto-load `config.json` via `transformers.AutoConfig` or direct JSON parse.
2. Pull every standard field listed above.
3. Cross-check the model card README for: growing-layer count, layer pattern, K=V tying, recurrent state shape.
4. Maintain a **per-model overrides table** (in your calculator or a `MODEL_SPECS` dict) that encodes the README-only quirks.
5. Empirically validate against the boot log on first launch: `docker logs <container> | grep -i "kv cache"` — compare measured per-card KV to predicted.

This is exactly how vLLM, llama.cpp, and SGLang handle it internally: standard fields from config, per-model classes for the architectural quirks.

For our v0.7.0 profile data model, this maps to: `config.json` → automatic; overrides → `scripts/lib/profiles/models/<id>.yml`; calibration → `scripts/lib/profiles/calibration/<id>.yml`. See [ADDING_MODELS.md](ADDING_MODELS.md) for the end-to-end onboarding workflow.

## Qwen 3.6 27B — per-card budget components

For Qwen3.6-27B AutoRound INT4 at TP=N, the per-card VRAM peak during bench is composed of:

```
peak ≈ weights/N + kv_pool + activation_peak + cudagraph_workspace + dflash_draft/N
```

Each term has a well-defined formula or empirical anchor.

### 1. Model weights (`weights / N`)

AutoRound INT4 weights total ~17.5 GB on disk. Under tensor parallelism, weights split across cards:

- TP=1: 17.5 GB / card
- TP=2: 8.75 GB / card
- TP=4: 4.4 GB / card

This term is exact (the checkpoint is a fixed size). DeltaNet's `linear_attn.in_proj_a` / `in_proj_b` layers stay at fp16 in AutoRound quantization (per `extra_config` in `config.json`), but the byte budget is included in the 17.5 GB total.

### 2. KV pool (attention layers only)

In the Qwen3-Next hybrid architecture, **only the 16 full_attention layers contribute to the growing KV cache**. The 48 GDN (Gated DeltaNet) layers maintain a fixed-size recurrent state instead (Yang et al., [Gated Delta Networks ICLR 2025](https://github.com/NVlabs/GatedDeltaNet)).

Applying the general formula:

```
per_token_bytes = 16 (growing layers) × 4 (kv_heads) × 256 (head_dim) × 2 (no K=V tie) × bpe
                = 32,768 × bpe bytes
```

| KV format | bpe | per-token KV (TP=1) | per-token KV (TP=2) |
|---|---:|---:|---:|
| `bf16` / `fp16` | 2.0 | 65,536 B | 32,768 B |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | 32,768 B | 16,384 B |
| `q4_0` | ~0.56 | 18,350 B | 9,175 B |
| `k8v4` | 0.75 | 24,576 B | 12,288 B |
| `turboquant_3bit_nc` (TQ3) | ~0.425 | 13,927 B | 6,963 B |

Total KV pool (per card) = `per_token_bytes / TP × max_ctx × max_num_seqs`. PagedAttention ([Kwon et al., arxiv 2309.06180](https://arxiv.org/abs/2309.06180)) wastes <4% of this in fragmentation.

**Caveat**: this formula computes *requested* KV pool. vLLM's actual allocation is bounded by `mem_util × VRAM - other_components`. If requested exceeds available, vLLM emits `estimated max model length is N` and refuses to boot — that's the trigger for FAIL verdict.

**Caveat #2**: `max_num_seqs > 1` over-predicts in `kv-calc.py`. Real vLLM rate-limits internally; the calculator doesn't model that. See [Known limitations](#known-limitations).

### 3. Activation peak (GDN forward — the Cliff 2 mechanism)

The 48 GDN layers materialize a block-wise intermediate state during prefill. This is the source of [Cliff 2](CLIFFS.md#cliff-2--deltanet-gdn-forward-intermediate-buffer).

The PerfMamba paper ([arxiv 2511.22849](https://arxiv.org/html/2511.22849)) measures this directly on the parent architecture: at sequence length 2048, **Mamba-2 SSM consumes 33.5% more memory than Mamba-1 (115.68 GB vs 86.64 GB) due to "block-wise state materialization."** The asymptotic scaling per the paper:

```
activation_peak ∝ γ × D × N × L
```

where γ = expansion factor, D = hidden dim, N = state dim, L = sequence length.

For Qwen3.6-27B's GDN layers, `fla.ops.chunk.chunk_gated_delta_rule_fwd` allocates an intermediate `h` shaped `(B, NT, H, V, K)`:

- `B` = batch
- `NT = ceil(seq_len / chunk_size)` chunks (`chunk_size=256`)
- `H` = number of heads (`linear_num_k_heads=16`, `linear_num_v_heads=48`)
- `V`, `K` = head dim (`linear_v_head_dim = linear_k_head_dim = 128`)
- Per-element 4 bytes (`mamba_ssm_dtype = fp32` on this stack)

Published O(γDNL) gives asymptotic scaling but not the absolute coefficient — that depends on `fla.ops.chunk` implementation details (tiling, streaming, register reuse). We use an **empirical coefficient** calibrated against measured BENCHMARKS rows:

| KV format | bytes/layer/token coefficient | Why this differs from fp8 |
|---|---:|---|
| `fp16` / `bf16` | ~135 | Baseline (no KV dequant during forward) |
| `fp8_e5m2` / `fp8_e4m3` | ~130 | Small dequant overhead |
| `q4_0` / `k8v4` | ~155 | Larger dequant + scale ops |
| `turboquant_3bit_nc` | ~165 | TQ3 dequant during the materialized block adds ~20-25% activation pressure |

The TQ3 → fp8 difference (~25%) is what causes the [20 GB Ampere Cliff 2 fire at 90K](HARDWARE.md#note-for-sub-24-gb-cards) — TQ3's larger activation peak exceeds the per-card budget after TP=2 split on smaller-VRAM cards. Cross-rig validated by [@efschu](https://github.com/noonghunna/club-3090/issues/47) on 2× 3080 modded.

### 4. Cudagraph + workspace overhead

vLLM's torch.compile pass captures multiple cudagraph variants (one per `(batch_size, seq_len_bucket)` combination). Each capture costs ~50-100 MB. FlashInfer adds a 394 MB workspace per card. NCCL allreduce buffers cost ~200-300 MB on TP > 1.

Empirical fit:
```
overhead = 0.5 + 1.0 × mem_util + 0.3 × (TP - 1)   # GB
```

This is rough — actual overhead depends on how many graphs vLLM captures, which depends on `max_num_seqs`, `compile_sizes`, and other internals.

### 5. DFlash draft model

Only present on `dual-dflash*.yml` composes. `z-lab/Qwen3.6-27B-DFlash` is a ~1.75 GB draft model (per card, FP16). With TP > 1, the draft itself is sharded.

## Qwen 3.6 35B-A3B (MoE) — per-card budget components

**Status**: math-ready, **calibration pending** (not yet served on this stack). Numerical values below are derived from the architecture pattern in the model card; expect re-calibration once we measure boot peaks.

### Architecture summary

Qwen 3.6 35B-A3B is a Qwen3-Next hybrid MoE:

- 40 transformer layers
- Pattern: `10 × (3× Gated DeltaNet → MoE → 1× Gated Attention → MoE)`
- **10 growing-attention layers** (gated attention with KV cache)
- **30 GDN layers** (recurrent state, fixed size)
- MoE: 128 experts, 8 active per token (typical Qwen3-Next MoE config — verify from `config.json`)
- Active params: ~3B; total params: 35B

### 1. Model weights

MoE weights are dominated by the expert FFNs. Per-card budget under TP:

| Quant (planned) | On-disk estimate | Per-card at TP=2 |
|---|---:|---:|
| AutoRound INT4 (when available) | ~22-25 GB | 11-12 GB |
| AWQ-4bit (community) | ~22-25 GB | 11-12 GB |
| BF16 (unquantized) | ~70 GB | 35 GB (does not fit on 24 GB) |

Like the dense Qwen 3.6 27B, DeltaNet `linear_attn` in-projection layers will likely stay at fp16 even under INT4 quantization. The byte count will be included in the total checkpoint size.

**Note**: MoE expert weights all live in VRAM (they're sparse-activated at FLOPs level, not at memory level). Don't confuse "active params" with "loaded params" — the budget is for the full 35B.

### 2. KV pool (10 gated-attention layers only)

Applying the general formula:

```
per_token_bytes = 10 (growing layers) × 2 (kv_heads) × 256 (head_dim) × 2 (no K=V tie) × bpe
                = 10,240 × bpe bytes
```

Compare to dense Qwen 3.6 27B's 32,768 × bpe: **the MoE's growing-KV is ~3.2× lighter per token**, because both `num_growing_layers` (10 vs 16) and `num_kv_heads` (2 vs 4) are smaller.

| KV format | bpe | per-token KV (TP=1) | per-token KV (TP=2) |
|---|---:|---:|---:|
| `bf16` / `fp16` | 2.0 | 20,480 B | 10,240 B |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | 10,240 B | 5,120 B |
| `turboquant_3bit_nc` | ~0.425 | 4,352 B | 2,176 B |

Implication: at 200K context, KV pool per card at TP=2 + fp8 = `5,120 × 200,000 = ~1.02 GB`. **The MoE is KV-light by Qwen-family standards.** The bottleneck shifts to weights + activation peak.

### 3. Activation peak (GDN forward, denser than dense 27B)

Critical: this MoE has **30 GDN layers vs 48 in the dense 27B** — fewer GDN layers means smaller per-layer activation buffer count. But the GDN forward block-wise materialization is per-layer, so the total activation peak scales with `30 × per_layer_coef × seq_len`.

Projected coefficient (untested — will require calibration):

| KV format | Projected bytes/layer/token | Reasoning |
|---|---:|---|
| `bf16` / `fp16` | ~115-130 | Slightly smaller than dense 27B (different `linear_num_k_heads` likely) |
| `fp8_e5m2` | ~110-125 | Same dequant pattern |
| `turboquant_3bit_nc` | ~140-155 | TQ3 dequant overhead similar to dense |

The activation peak should be **~60-70% of dense Qwen 3.6 27B's** (30/48 layers × similar per-layer cost). Calibration TBD.

### 4. MoE-specific considerations

MoE introduces a few new accounting items:

- **Router workspace**: small (`hidden_size × num_experts` weights, ~100-200 MB). One-time cost, not per-token.
- **Expert dispatch buffers**: vLLM allocates buffers for top-k expert routing. Empirical ~200-400 MB per card.
- **No KV-side impact**: MoE only gates FFN compute. The KV cache for the gated-attention layers is unaffected.

### 5. Cudagraph + workspace overhead

Same form as dense models:

```
overhead = 0.5 + 1.0 × mem_util + 0.3 × (TP - 1)   # GB
```

MoE may increase cudagraph capture cost slightly (more dispatch-shape buckets). Expect a small (~100-200 MB) bump in practice.

### Estimated per-card budget at TP=2, 24 GB VRAM

| Term | Value (fp8 KV, 100K ctx, seqs=1) | Notes |
|---|---:|---|
| Weights / 2 | ~11-12 GB | INT4 quant |
| KV pool (10K growing) | ~0.5 GB | Very small |
| Activation peak | ~6-7 GB | 30 GDN × per-layer, fp8 coefficient |
| Cudagraph + overhead | ~1.2 GB | Empirical fit |
| **Predicted peak** | **~19-21 GB** | Fits comfortably on 24 GB, snug on 20 GB |

**Calibration pending**. These are pre-boot projections.

## Gemma 4 31B — per-card budget components

Gemma 4 31B is structurally different from Qwen 3.6:

- **No DeltaNet, no GDN activation peak.** Dense MLP instead.
- **Hybrid on attention type**, not attention-vs-recurrence. The 60-layer stack is `[sliding_attention × 5, full_attention × 1] × 10` = **50 sliding-attention layers + 10 full-attention layers**.
- **Head-dim asymmetry** — sliding layers use `head_dim=256`, full-attention layers use `global_head_dim=512`. Per-token KV bytes for full layers is therefore 2× what naive `num_layers × head_dim` would compute.
- **K==V tying** — `attention_k_eq_v: true` in `config.json`. vLLM's allocator EXPLOITS this — K and V share storage. The KV formula uses `k_v_tensors=1`, not 2. Empirically confirmed against the matched-config rebench's `Available KV cache / card = 10.82 GiB` at 262K seqs=2.

Source: `/mnt/models/huggingface/gemma-4-31b-autoround-int4/config.json` → `text_config`.

```
peak ≈ weights/N + kv_pool_growing + kv_pool_sliding + activation_peak + cudagraph_overhead + drafter_overhead
```

### 1. Model weights (`weights / N`)

| Quant | On-disk | Per-card at TP=2 |
|---|---:|---:|
| AutoRound INT4 (`gemma-4-31b-autoround-int4`) | ~18 GB | 9.0 GB |
| AWQ-4bit (`cyankiwi/gemma-4-31B-it-AWQ-4bit`) | ~17 GB | 8.5 GB |
| BF16 (unquantized) | ~58 GB | 29 GB (does not fit on 24 GB) |

Two shipped quants on this stack: AutoRound INT4 (default) and AWQ-4bit (Tier 2 reproducer of #103). INT4 weights + INT8-per-token-head KV is the matched-config dual-3090 recipe (see `models/gemma-4-31b/vllm/compose/dual/int8.yml`).

### 2. KV pool — growing portion (10 full-attention layers)

Each stores K and V at `global_head_dim=512`, with K==V tying meaning a single store per element:

```
per_token_bytes_growing = 10 (growing layers) × 16 (kv_heads) × 512 (global_head_dim) × 1 (K=V tied) × bpe
                        = 81,920 × bpe bytes
```

Compare to Qwen 3.6 27B's `32,768 × bpe` — Gemma 4's per-token growing KV is **~2.5× heavier** than Qwen's, despite the K=V tying win. This is *the* reason Gemma 4 at 262K needs INT8 / FP8 KV on Ampere — at BF16 KV the per-card budget blows past 24 GB before reaching 50K context.

Per-token growing-KV bytes by format:

| KV format | bpe | per-token growing KV (TP=1) | per-token (TP=2) |
|---|---:|---:|---:|
| `bf16` / `fp16` | 2.0 | 163,840 B (~160 KB) | 81,920 B |
| `fp8_e5m2` / `fp8_e4m3` | 1.0 | 81,920 B (~80 KB) | 40,960 B |
| `int8_per_token_head` (PR #40391) | ~1.01 | ~82,700 B | ~41,400 B |
| `q4_0` | ~0.56 | ~45,875 B | ~22,940 B |
| `turboquant_3bit_nc` (TQ3) | ~0.425 | ~34,816 B | ~17,408 B |

Total growing-KV pool per card = `per_token_bytes_growing / TP × max_ctx × max_num_seqs`.

**Note**: on Ampere consumer cards (sm_86), `fp8_e4m3` is NOT supported. Use `int8_per_token_head` (PR #40391, vendored on this stack via PR #42102). See `models/gemma-4-31b/vllm/compose/dual/int8.yml`.

### 3. KV pool — fixed sliding portion (50 SWA layers)

The 50 sliding-attention layers maintain a fixed-size KV window (`sliding_window=1024`). K==V tying applies here too:

```
sliding_kv_bytes_total = 50 (sliding layers) × 16 (kv_heads) × 256 (head_dim) × 1 (K=V tied) × bpe × 1024 (window)
                       = 209,715,200 × bpe bytes
                       ≈ 200 MB × bpe
```

This is **constant** — it doesn't scale with `max_ctx` or `max_num_seqs`. At fp8 / int8 KV (`bpe=1`), this is ~200 MB per card (TP=1) or ~100 MB at TP=2. Small but non-zero — include it as a separate term.

### 4. Activation peak (SWA prefill + dense MLP)

Unlike Qwen 3.6's GDN block-wise state materialization, Gemma 4's activation peak comes from:

- Sliding-window attention prefill (50 layers, bounded by `sliding_window=1024`)
- Dense MLP intermediate buffer (`hidden_size=5376`, `intermediate_size=21504`)

There's no published scaling-law analogue to PerfMamba's O(γDNL) for Gemma 4. The activation coefficient is **empirical-only**, calibrated against measured BENCHMARKS rows. Expected order of magnitude: ~1.5-2.5 GB at TP=2 dual-card configs (smaller than Qwen 3.6's GDN peak because there's no per-chunk block materialization).

Weak dependence on KV format possible (slight dequant overhead during forward), but expected to be flatter than Qwen's TQ3 → fp8 25% spread — Gemma's dense MLP doesn't dequant KV during forward.

### 5. Cudagraph + workspace overhead

Same form as Qwen — empirical fit:
```
overhead = 0.5 + 1.0 × mem_util + 0.3 × (TP - 1)   # GB
```

vLLM captures multiple cudagraphs (~50-100 MB each), FlashInfer workspace (~394 MB/card), NCCL allreduce buffers (~200-300 MB at TP > 1).

### 6. Drafter overhead

Two drafter families on this stack:

| Drafter | Size | Composes |
|---|---:|---|
| `gemma-4-31b-it-assistant` (Google MTP) | 0.97 GB FP16 | `dual/docker-compose.yml`, `dual/int8.yml`, `dual/awq.yml` (with MTP n=4) |
| `gemma-4-31b-it-dflash` (z-lab DFlash) | 2.9 GB FP16 | `dual/dflash.yml`, `dual/dflash-int8.yml` |

At TP > 1, drafter weights shard across cards (`drafter_gb / TP`).

## Gemma 4 26B-A4B (MoE) — per-card budget components

**Status**: math-ready, **calibration pending**. The model card README is the source of truth for layer pattern; numbers below are estimated from architectural pattern and standard Gemma 4 family conventions. Expect refinement once we download and inspect `config.json` + boot the model.

### Architecture summary

Gemma 4 26B-A4B is a Gemma 4 MoE with sliding-window attention:

- Likely ~40-48 transformer layers (smaller than Gemma 4 31B's 60)
- Sliding-window + occasional global layers (Gemma 4 family pattern); final layer typically global
- Sliding window 1024 (same as 31B)
- K=V tying expected (Gemma 4 family convention)
- MoE: number of experts + active-per-token TBD from `config.json`
- Active params: ~4B; total params: 26B

**Exact layer counts pending the model's actual config.json on disk.** The placeholders below show the math shape — substitute real values once measured.

### 1. Model weights

| Quant (planned) | On-disk estimate | Per-card at TP=2 |
|---|---:|---:|
| AutoRound INT4 (when available) | ~16-18 GB | 8-9 GB |
| BF16 (unquantized) | ~52 GB | 26 GB (does not fit on 24 GB) |

MoE expert weights all live in VRAM (sparse-activation at FLOPs, not at memory). Active-params count (4B) doesn't reduce the loaded budget.

### 2. KV pool — growing portion (global layers only)

Estimated `N_global` global layers (TBD from README; Gemma 4 family typically uses 1 global per 5 sliding):

```
per_token_bytes_growing = N_global × num_kv_heads × global_head_dim × 1 (K=V tied) × bpe
```

If `N_global = 8` and shape matches 31B family (`num_kv_heads=16`, `global_head_dim=512`):

```
per_token_bytes_growing = 8 × 16 × 512 × 1 × bpe = 65,536 × bpe bytes
```

That's ~80% of Gemma 4 31B's growing KV per token. INT8 KV remains the right format for 24 GB Ampere at long contexts.

### 3. KV pool — fixed sliding portion

```
sliding_kv_bytes_total = N_sliding × num_kv_heads × head_dim × 1 (K=V tied) × bpe × 1024
```

If `N_sliding = 32` and shape matches 31B (`head_dim=256`):

```
sliding_kv_bytes_total = 32 × 16 × 256 × 1 × bpe × 1024 = 134,217,728 × bpe bytes ≈ 128 MB × bpe
```

Constant; doesn't scale with `max_ctx`.

### 4. Activation peak

Same mechanism as Gemma 4 31B (SWA prefill + dense MoE intermediate buffer). MoE may add a small per-expert routing overhead but **shouldn't dominate**. Empirical coefficient TBD; expected ~1-2 GB at TP=2.

### 5. MoE considerations

Same as Qwen 3.6 35B-A3B MoE:

- Router workspace (~100-200 MB, one-time)
- Expert dispatch buffers (~200-400 MB per card)
- No KV-side impact from MoE

### 6. Cudagraph + workspace overhead + drafter

Same empirical form as 31B; drafter family TBD (Google may release a Gemma 4 26B MTP assistant similar to the 31B-it-assistant).

### Estimated per-card budget at TP=2, 24 GB VRAM

| Term | Value (INT8 KV, 100K ctx, seqs=1) | Notes |
|---|---:|---|
| Weights / 2 | ~8-9 GB | INT4 quant |
| KV pool growing | ~3-4 GB | 100K × 32 KB/tok = ~3.2 GB |
| KV pool sliding | ~0.13 GB | Constant |
| Activation peak | ~1-2 GB | Smaller than 31B if fewer total layers |
| Cudagraph + overhead | ~1.2 GB | |
| **Predicted peak** | **~13-17 GB** | Comfortable headroom on 24 GB, fits 20 GB at lower ctx |

**Calibration pending**. Numbers will shift once real `config.json` values replace estimates.

## Best practices for building a KV calculator

If you're extending `kv-calc.py` for a new model — or building a similar tool from scratch — these practices reduce errors:

### 1. Auto-load standard fields, override the architectural quirks

Don't hand-author what `config.json` already encodes. Auto-load `num_hidden_layers`, `num_kv_heads`, `head_dim`, `sliding_window`, MoE counts. Keep a per-model overrides dict for hybrid layer split, K=V tying, recurrent state shape.

### 2. Encode `k_v_tensors` explicitly

Don't bake `×2` into per_token_bytes. Use the named variable `k_v_tensors` and set it per model (2 default, 1 when K=V tied). This makes K=V tying surface visible and reviewable.

### 3. Separate growing-KV from fixed-KV

For hybrid models, the math has two terms that scale differently:

- `kv_pool_growing` scales with `max_ctx × max_num_seqs`
- `kv_pool_fixed` is constant (SWA window or recurrent state size)

Compute and report them separately. Lumping them hides the asymptotic behavior.

### 4. Validate against the boot log

vLLM prints `Available KV cache / card = X GiB` after model load. Back-solve:

```
predicted_per_token_bytes = (X × 1024^3) / (max_ctx × max_num_seqs / TP)
```

Compare to your formula's `per_token_bytes`. If off by 2×, suspect K=V tying. If off by `num_layers / num_growing_layers`, you've counted the wrong layer set.

### 5. Empirical coefficients need ≥4 calibration anchors

The activation peak coefficient isn't first-principles — it's an empirical fit. Don't ship a model spec without ≥4 BENCHMARKS.md rows for that model at varying (KV format, max_ctx, max_num_seqs) configs. Fewer anchors → coefficients overfit and predict wrong.

### 6. Mark calibration status explicitly

If a model section is math-derived but uncalibrated, say so clearly in the doc (as the MoE sections above do). Don't quote a prediction as fact without a measured anchor.

### 7. Use `mem_util × VRAM` as the ceiling

vLLM's `gpu_memory_utilization` (default 0.92 on this stack) caps everything except its own internal overheads. Your predicted peak should compare against `mem_util × VRAM`, not raw VRAM.

### 8. Use the `--calibration` self-test

Track predicted-vs-measured verdict accuracy on shipped composes. Target ≥80% within ±1.5 GB. If accuracy drops after a code change, the math regressed.

## Known limitations

The calculator is empirically calibrated, not first-principles. Specifically:

1. **KV pool capping (resolved 2026-05-13)**. Earlier versions over-predicted FAIL on configs with `max_num_seqs > 1` because the requested KV pool exceeded available budget. The current calculator models vLLM's PagedAttention capping: predicted KV pool is `min(requested, budget - fixed_components)`. When the request exceeds available, verdict is `TIGHT` with a note that effective concurrency at `--max-num-seqs` may be lower than requested at full `max_ctx`. The "predicted total" in TIGHT cases equals the budget exactly — that's saturating-allocator behavior, not a modeling artifact.

2. **Activation coefficient varies by `chunk_size` and `dtype`**. We use the fla default `chunk_size=256` and `mamba_ssm_dtype=float32` (per Qwen3.6-27B config.json). If those change, the coefficient needs re-calibration. For Gemma the activation peak is a flat empirical constant; if Gemma config changes (e.g. layer-pattern ratio, sliding_window), recalibrate.

3. **No driver/allocator overhead modeling**. snoby's 4090 needed `max-model-len` 200K → 180K vs 3090 baseline. The driver-class delta isn't modeled here. We hand-wave with the `±1.5 GB` error band.

4. **No Cliff 2b accumulation modeling**. The multi-turn fragmentation cliff at ~25K accumulated tokens is empirical-only and not in this calculator. Use `SOAK_MODE=continuous` to probe it.

5. **MoE models are math-ready but not yet calibrated**. The Qwen 3.6 35B-A3B and Gemma 4 26B-A4B sections above derive math from architectural patterns; absolute numbers (activation coefficients, drafter sizes) ship as estimates until we measure them on the stack. Don't quote them as production-grade predictions.

6. **Per-model calibration required**. Adding a fifth model means deriving a new `MODEL_SPEC` block (architecture params + per-quant weights size + activation-peak mechanism) and calibrating the activation coefficient against ≥4 measured BENCHMARKS rows. Don't ship a new model spec without that.

## Calibration

Run `bash tools/kv-calc.py --calibration` to see predicted vs measured for all shipped composes, grouped per model.

| Model | Verdict accuracy | Notes |
|---|---|---|
| Qwen 3.6 27B | 11/11 = 100% (±1.5 GB band) | Refactored Phase 3 of v0.7.0 preserved this byte-for-byte |
| Gemma 4 31B | 7/7 = 100% (±1.5 GB band) | Calibrated against `dual/int8.yml` 98K+262K rows, `dual/dflash.yml`, `dual/awq.yml`, `dual/docker-compose.yml` |
| Qwen 3.6 35B-A3B | not on stack | Pending download + first calibration |
| Gemma 4 26B-A4B | not on stack | Pending download + first calibration |

Overall on calibrated models: **18/18 (100%)** as of 2026-05-14.

## When to trust the calculator vs vLLM's boot log

Always pass `--model {qwen3.6-27b,gemma-4-31b}` matching the compose you're targeting. Defaults to qwen3.6-27b if omitted.

| Question | Use this |
|---|---|
| "Will it boot?" — for a *shipped* compose on canonical 24 GB | We've already validated; check BENCHMARKS.md |
| "Will it boot?" — for a *novel* config (custom ctx, kv format, or VRAM class) | `kv-calc.py --model <M> --compose <X>` for a directional answer; then boot and read `gpu_worker.py` |
| "What's my max ctx?" — given my hardware | `kv-calc.py --model <M> --solve-max-ctx ...` for an estimate; vLLM's pre-check `estimated max model length is N` line at boot is authoritative |
| "Is TQ3 or fp8 better for my hardware?" (Qwen 3.6) | `kv-calc.py --model qwen3.6-27b` with both options; cross-check [HARDWARE.md](HARDWARE.md#note-for-sub-24-gb-cards) |
| "Is INT8 PTH or BF16 KV better for Gemma 4?" | `kv-calc.py --model gemma-4-31b --kv-format bf16` vs `int8_per_token_head` — BF16 caps at ~32K on dual-3090, INT8 PTH unlocks 262K. See `models/gemma-4-31b/vllm/compose/dual/int8.yml` header. |

## Sources of error & accuracy

The ±1.5 GB error band on shipped predictions decomposes as:

| Source | Typical magnitude | Mitigation |
|---|---:|---|
| Activation coefficient empirical fit | ±0.5 GB | More calibration anchors per model (≥4 BENCHMARKS rows) |
| Cudagraph capture variance | ±0.3 GB | The 0.5 + 1.0×mem_util + 0.3×(TP-1) fit is rough |
| FlashInfer workspace per card | ±0.1 GB | Constant; small drift between vLLM nightlies |
| Driver/allocator overhead (cross-rig) | ±0.5 GB | Unmodeled; affects 4090 vs 3090 etc. |
| PagedAttention fragmentation | <4% of KV pool | PagedAttention paper bounds; not separately modeled |
| K=V tying detection (if missed) | 2× KV pool | Validate against boot log; explicit `k_v_tensors=1` annotation |
| Wrong growing-layer count | 3-6× KV pool | Read model card README, not just config.json |

**Where the ±1.5 GB band is too tight**:

- MoE models with unmeasured activation coefficients (current state of Qwen 3.6 35B-A3B + Gemma 4 26B-A4B sections)
- Novel context regimes outside calibration range (e.g. predicting 500K context when calibrated only up to 262K)
- Configs with `max_num_seqs ≥ 4` — the cap modeling produces TIGHT verdicts where measured may be FITS or vice versa

**Where the band is conservative**:

- Single-stream configs (`max_num_seqs=1`) at moderate context (≤200K) — typically ±0.5 GB

## References

**Qwen 3.6 family (DeltaNet hybrid):**

- [PerfMamba: Performance Analysis and Pruning of Selective State Space Models (arxiv 2511.22849)](https://arxiv.org/html/2511.22849) — block-wise state materialization scaling
- [Gated Delta Networks: Improving Mamba2 with Delta Rule (NVlabs ICLR 2025)](https://github.com/NVlabs/GatedDeltaNet) — Qwen3-Next architecture
- [Mamba: Linear-Time Sequence Modeling (arxiv 2312.00752)](https://arxiv.org/abs/2312.00752) — Mamba-1 baseline for PerfMamba's deltas

**Gemma 4 family (sliding-window + dense / MoE MLP):**

- Architecture params sourced from `config.json` (Gemma 4 release post / technical doc were not used as a calibration reference — the activation coefficient is empirical-only on this stack)
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
- [ADDING_MODELS.md](ADDING_MODELS.md) — end-to-end workflow for onboarding a new model onto the stack + into the v0.7.0 profile catalog
- [DTYPE_MATRIX.md](DTYPE_MATRIX.md) — per-card KV format support
- [HARDWARE.md](HARDWARE.md) — per-card mem_util safe values + power-cap data
