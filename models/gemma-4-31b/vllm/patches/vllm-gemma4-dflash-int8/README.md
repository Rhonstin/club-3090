# vLLM Gemma 4 DFlash + per-token-head INT8 KV — combined overlay

**Purpose:** Stack **PR #41703** (z-lab Gemma 4 DFlash drafter, 12 files) on top of
**PR #40391** (lisp19 per-token-head fp8 KV page-size fix, 5+2 files), PLUS apply
**PR #42102** (our DFlash + KV-quant coexistence fix) — to deliver
**long-context code-optimal DFlash spec-decode on Gemma 4** for Ampere consumer GPUs.

**Base nightly:** `e47c98ef7a38792996e452ef53914e21e41928e9` (2026-05-06) — same as
[`vllm-gemma4-dflash/`](../vllm-gemma4-dflash/) overlay (DFlash was rebased to that nightly by Codex).

**Status:** ✅ **WORKING** as of 2026-05-08. Validated end-to-end on dual 3090 Ampere
at full 262K max_model_len + INT8 PTH KV target + BF16 drafter.

| Compose | Spec-decode | KV format | Max ctx | Narr/Code TPS | Use case |
|---|---|---|---:|---:|---|
| `dual.yml` | MTP n=4 | bf16 | 32K | 105/141 | balanced |
| `dual-dflash.yml` | DFlash n=7 | bf16 | 32K | 95/168 | code (short ctx) |
| `dual-int8.yml` | MTP n=4 | INT8 PTH | 262K | 95/126 | narrative long-ctx |
| `dual-awq.yml` | MTP n=8 | bf16 | 118K | 101/142 | balanced long-ctx |
| **`dual-dflash-int8.yml`** ⭐⭐⭐ | **DFlash n=7** | **INT8 PTH + drafter BF16** | **262K** | **87/146** | **code-optimal long-ctx** |

The bottom row — DFlash drafter at long context — was previously unreachable on Ampere.
PR #42102 unblocks it.

## Three-layer fix at PR #42102

1. **`v1/core/kv_cache_utils.py`** — partition DFlash draft KV specs before page-size
   unify. Target specs (Gemma 4 global INT8 PTH 33,280-byte pages padded by PR #40391,
   local INT8 PTH 66,560-byte pages) go through normal unify (clean 1:2 ratio). Drafter
   specs (BF16, 131,072-byte pages — different geometry) form their own independent KV
   groups, bypassing unify entirely. Allocator sized isolated DFlash tensors by their
   own `page_size_bytes` rather than via `get_uniform_page_size()`.

2. **`model_executor/models/qwen3_dflash.py`** — override DFlash drafter `cache_dtype`
   to `"auto"` when engine global is quantized. Drafter has independent KV pool
   post-(1) so it doesn't need to inherit target's quantized dtype.

3. **`v1/attention/backends/flash_attn.py`** — in metadata scheduler, when per-spec
   `kv_quant_mode == NONE`, use the spec's local `kv_cache_dtype` rather than the
   engine global. Necessary because (2) puts BF16 in the drafter spec while the
   engine global stays INT8 PTH.

## Validation on this rig (dual 3090 Ampere)

- Boot HEALTHY at 262K max_model_len, INT8 PTH KV, mem-util 0.95, max-num-seqs=1
- KV pool 168,178 tokens — effective single-stream serving ceiling ~168K context
- Paris smoke clean (no garbled output unlike the 2026-05-06 wrong-fix attempt)
- Bench at 262K: **86.86 narr / 145.96 code TPS** (CV 0.9% / 2.2%)
- NIAH PASS at 98,444 tokens (`bronze octopus 17` recalled cleanly)
- AL 5.0-5.3 on long-ctx code (DFlash code-optimal profile preserved)
- VRAM 22.0 GB/card, 64,000 GiB available KV cache memory
- n-sweep at 262K: n=7 lowest variance (default), n=8 +4% code but CV 5.7%
- vs dual-int8.yml at 262K: **+16% code, -10% narr** — DFlash code-optimal lift

## Drop trigger

When PR #42102 + PR #41703 + PR #40391 all land + propagate to a nightly tag:

```bash
gh api repos/vllm-project/vllm/pulls/42102 --jq '.state, .merged_at'
gh api repos/vllm-project/vllm/pulls/41703 --jq '.state, .merged_at'
gh api repos/vllm-project/vllm/pulls/40391 --jq '.state, .merged_at'
```

Once all three are merged + propagated, this entire overlay can be removed —
bump the compose's nightly tag to a post-merge image and drop the volume mounts.

## Historical record

The `_pre-pr42102-historical/` directory contains snapshots of the buggy versions
of `kv_cache_utils.py` and `qwen3_dflash.py` from before PR #42102's fix. Kept
for reference; do not use.

The earlier diagnostic-print patch (added 2026-05-08 to debug the unify failure)
revealed the three distinct page sizes and confirmed the BF16 drafter coexistence
diagnosis. That patch is reverted in the current files; numbers from the diagnostic:

| Layer group | Page size (bytes) | dtype-effective |
|---|---:|---|
| Target Gemma 4 GLOBAL | 33,280 | INT8 PTH (padded by PR #40391) |
| Target Gemma 4 LOCAL | 66,560 | INT8 PTH (`block × num_kv_heads × 520`) |
| DFlash drafter (pre-fix) | 131,072 | **BF16 silently** (`block × num_kv_heads × 1024`) |

131,072 / 66,560 = 1.97 (not 2); 131,072 / 33,280 = 3.94 (not 4). No clean integer
ratios → unify rejected. PR #42102's fix sidesteps the unify entirely for the
drafter group.
