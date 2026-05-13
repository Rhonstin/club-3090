#!/usr/bin/env python3
"""kv-calc.py — predict per-card VRAM budget for vLLM composes.

Predicts (per card, after TP split):
  - Model weights
  - KV pool (attention layers only — recurrent / SSM states show up in activation)
  - Activation peak (model-specific: Qwen GDN forward, Gemma SWA + dense MLP)
  - Cudagraph + workspace overhead
  - Drafter overhead (MTP / DFlash)
  - Total vs available VRAM
  - Verdict: PASS / TIGHT / FAIL

Two models modelled:
  - Qwen 3.6 27B (DeltaNet hybrid: 16 full_attention + 48 GDN)
  - Gemma 4 31B (SWA + dense MLP: 10 full_attention + 50 sliding_attention)

vLLM rate-limits KV pool to fit available budget; this predictor models that
capping behavior. When the requested KV pool exceeds what fits, the verdict
is TIGHT (vLLM will cap pool — effective concurrency reduced) not FAIL.

Anchored to:
  - PerfMamba (arxiv 2511.22849) — Qwen GDN block-wise state materialization scaling
    https://arxiv.org/html/2511.22849
  - TurboQuant (arxiv 2504.19874, ICLR 2026) — TQ3 byte savings
    https://arxiv.org/abs/2504.19874
  - PagedAttention (arxiv 2309.06180) — KV pool layout
    https://arxiv.org/abs/2309.06180

Calibrated against measured BENCHMARKS.md rows per model. Coefficients reflect
club-3090's empirical findings. See docs/KV_MATH.md for the derivation +
calibration trace.

Usage:
  bash tools/kv-calc.py --compose dual-turbo --vram 24                                     # Qwen (default model)
  bash tools/kv-calc.py --model gemma-4-31b --compose gemma-dual-int8 --vram 24
  bash tools/kv-calc.py --model gemma-4-31b --solve-max-ctx --kv-format int8_per_token_head --tp 2 --vram 24
  bash tools/kv-calc.py --calibration  # both models, grouped per-model
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Optional


# =============================================================================
# Model specs
# =============================================================================

# ---- Qwen3.6-27B AutoRound INT4 — from config.json text_config ----
QWEN36_27B = {
    "model_id": "qwen3.6-27b",
    "model_family": "qwen3-next-hybrid",
    "hidden_size": 5120,
    "num_hidden_layers": 64,
    "num_gdn_layers": 48,        # linear_attention layers (Gated DeltaNet)
    "num_attn_layers": 16,       # full_attention layers
    "num_attn_heads": 24,
    "num_kv_heads": 4,           # GQA
    "head_dim_attn": 256,        # attention head dim
    "linear_num_v_heads": 48,    # GDN value heads
    "linear_num_k_heads": 16,    # GDN key heads (GQA-style at the GDN level too)
    "linear_v_head_dim": 128,    # GDN value head dim
    "linear_k_head_dim": 128,    # GDN key head dim
    "linear_conv_kernel_dim": 4,
    "weights_total_gb": 17.5,    # AutoRound INT4 storage on disk
    "mamba_state_bytes": 4,      # mamba_ssm_dtype=float32
    "chunk_size": 256,           # fla.ops.chunk default
    "max_ctx_supported": 262144,
    "attention_k_eq_v": False,   # Qwen stores K and V independently
}

# ---- Gemma 4 31B — from config.json text_config ----
# Layer pattern: [sliding_attention × 5, full_attention × 1] × 10
#                = 50 sliding-attention + 10 full-attention.
GEMMA4_31B = {
    "model_id": "gemma-4-31b",
    "model_family": "gemma4-swa-dense",
    "hidden_size": 5376,
    "intermediate_size": 21504,
    "num_hidden_layers": 60,
    "num_full_attn_layers": 10,         # full_attention (growing KV, head_dim=512)
    "num_sliding_attn_layers": 50,      # sliding_attention (fixed window, head_dim=256)
    "num_attn_heads": 32,
    "num_kv_heads": 16,                 # GQA 2:1
    "head_dim_sliding": 256,            # sliding_attention head dim
    "global_head_dim": 512,             # full_attention head dim (asymmetric)
    "sliding_window": 1024,
    "weights_int4_gb": 18.0,            # AutoRound INT4 on disk
    "weights_awq_gb": 17.0,             # cyankiwi AWQ-4bit (lower on-card due to AWQ packing)
    "weights_bf16_gb": 58.0,            # unquantized — does not fit on 24 GB
    "max_ctx_supported": 262144,
    "drafter_mtp_gb": 0.97,             # google/gemma-4-31b-it-assistant (FP16)
    "drafter_dflash_gb": 2.9,           # z-lab/gemma-4-31b-it-dflash
    "attention_k_eq_v": True,           # vLLM allocator exploits K==V tying (per_token uses ×1 not ×2)
}

MODEL_SPECS = {
    "qwen3.6-27b": QWEN36_27B,
    "gemma-4-31b": GEMMA4_31B,
}


# =============================================================================
# KV format bytes-per-element
# =============================================================================
# (one element = one head dim of one head; K and V counted separately for
# models where attention_k_eq_v=False. For Gemma the K==V tying halves this
# at the formula level — see kv_pool_per_card_bytes.)
# Source: vLLM/HF docs + TurboQuant paper + PR #40391 (INT8 per-token-head).

KV_FORMAT_BYTES = {
    "fp16":                  2.0,
    "bf16":                  2.0,
    "fp8_e5m2":              1.0,
    "fp8_e4m3":              1.0,
    "int8_per_token_head":   1.01,        # 1.0 int8 + per-token-head fp16 scale (~1% amortized)
    "q4_0":                  0.5 + 0.0625, # 4-bit + per-group scale
    "k8v4":                  0.75,         # avg of K=int8 V=int4
    "turboquant_3bit_nc":    0.375 + 0.05, # 3 bits + small QJL overhead
}


# =============================================================================
# Per-model activation coefficients
# =============================================================================

# ---- Qwen GDN activation-peak per-layer per-token coefficient (bytes) ----
# Calibrated empirically against measured BENCHMARKS rows. PerfMamba's
# O(γ·D·N·L) scaling sets the form; this captures fla.ops.chunk
# implementation details + KV-format-dependent dequant overhead.
QWEN_GDN_ACTIVATION_COEF = {
    "fp16":               135,
    "bf16":               135,
    "fp8_e5m2":           130,
    "fp8_e4m3":           130,
    "int8_per_token_head": 130,
    "q4_0":               155,
    "k8v4":               155,
    "turboquant_3bit_nc": 165,
}

# ---- Gemma activation peak (mostly constant in ctx) ----
# Unlike Qwen GDN, Gemma's activation peak comes from dense MLP forward +
# SWA windowed-attention prefill, both bounded by chunked-prefill chunk_size.
# Result: roughly CONSTANT in max_ctx. Calibrated as a per-TP base (GB) plus
# a small per-token term to capture residual ctx scaling.
GEMMA_ACTIVATION_CONST_GB = 1.5     # per card at TP=1 — calibrated, ~scales as 1/TP
GEMMA_ACTIVATION_PER_TOKEN_BYTES = 8  # tiny ctx scaling term to keep solver well-behaved


# =============================================================================
# Compose presets (per-model)
# =============================================================================
# Pulled from each compose's CLI args. Update if a compose changes.
# Compose IDs are namespaced: Qwen uses bare names (back-compat); Gemma uses gemma-* prefix.

COMPOSES = {
    "qwen3.6-27b": {
        "minimal":          {"max_ctx": 32768,  "max_num_seqs": 4, "tp": 1, "kv_format": "fp8_e5m2",            "mem_util": 0.90, "mtp": False},
        "long-text":        {"max_ctx": 180000, "max_num_seqs": 1, "tp": 1, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.93, "mtp": True},
        "long-text-no-mtp": {"max_ctx": 200000, "max_num_seqs": 1, "tp": 1, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.95, "mtp": False},
        "long-vision":      {"max_ctx": 145000, "max_num_seqs": 1, "tp": 1, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.95, "mtp": True},
        "bounded-thinking": {"max_ctx": 180000, "max_num_seqs": 1, "tp": 1, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.95, "mtp": True},
        "tools-text":       {"max_ctx": 75000,  "max_num_seqs": 1, "tp": 1, "kv_format": "fp8_e5m2",            "mem_util": 0.97, "mtp": True},
        "dual":             {"max_ctx": 262144, "max_num_seqs": 2, "tp": 2, "kv_format": "fp8_e5m2",            "mem_util": 0.95, "mtp": True},
        "dual-turbo":       {"max_ctx": 262144, "max_num_seqs": 4, "tp": 2, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.95, "mtp": True},
        "dual-dflash":      {"max_ctx": 185000, "max_num_seqs": 1, "tp": 2, "kv_format": "fp16",                "mem_util": 0.95, "mtp": False, "dflash_draft_gb": 1.75},
        "dual-dflash-noviz":{"max_ctx": 200000, "max_num_seqs": 2, "tp": 2, "kv_format": "fp16",                "mem_util": 0.95, "mtp": False, "dflash_draft_gb": 1.75},
        "dual4":            {"max_ctx": 262144, "max_num_seqs": 4, "tp": 4, "kv_format": "fp8_e5m2",            "mem_util": 0.95, "mtp": True},
        "dual4-dflash":     {"max_ctx": 262144, "max_num_seqs": 2, "tp": 4, "kv_format": "fp16",                "mem_util": 0.95, "mtp": False, "dflash_draft_gb": 1.75},
    },
    "gemma-4-31b": {
        # dual/docker-compose.yml — default MTP, 32K BF16 KV, max-num-seqs=4
        "gemma-dual":        {"max_ctx": 32768,  "max_num_seqs": 4, "tp": 2, "kv_format": "bf16",                "mem_util": 0.92, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
        # dual/int8.yml default — 98K + INT8 PTH KV + 4 seqs
        "gemma-dual-int8":   {"max_ctx": 98304,  "max_num_seqs": 4, "tp": 2, "kv_format": "int8_per_token_head", "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
        # dual/int8.yml long — 262K + INT8 PTH KV + seqs=1 (model native max)
        "gemma-dual-int8-262k": {"max_ctx": 262144, "max_num_seqs": 1, "tp": 2, "kv_format": "int8_per_token_head", "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
        # dual/bf16.yml — long-ctx BF16 weights + BF16 KV (auto)
        "gemma-dual-bf16":   {"max_ctx": 200000, "max_num_seqs": 1, "tp": 2, "kv_format": "bf16",                "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
        # dual/int8-tq3.yml — TQ3 KV alt
        "gemma-dual-int8-tq3": {"max_ctx": 98304, "max_num_seqs": 4, "tp": 2, "kv_format": "turboquant_3bit_nc",  "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
        # dual/dflash.yml — DFlash drafter + 32K BF16
        "gemma-dual-dflash": {"max_ctx": 32768,  "max_num_seqs": 4, "tp": 2, "kv_format": "bf16",                "mem_util": 0.92, "weights_variant": "int4", "drafter_gb": 2.9,  "mtp": False, "dflash_draft_gb": 2.9},
        # dual/dflash-int8.yml — DFlash + INT8 PTH KV (PR #42102 unblock)
        "gemma-dual-dflash-int8": {"max_ctx": 65536, "max_num_seqs": 2, "tp": 2, "kv_format": "int8_per_token_head", "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 2.9, "mtp": False, "dflash_draft_gb": 2.9},
        # dual/awq.yml — cyankiwi AWQ weights
        "gemma-dual-awq":    {"max_ctx": 65536,  "max_num_seqs": 4, "tp": 2, "kv_format": "bf16",                "mem_util": 0.85, "weights_variant": "awq",  "drafter_gb": 0.97, "mtp": True},
        # single/docker-compose.yml — 32 GB+ required; Ampere consumer OOMs at boot
        "gemma-single":      {"max_ctx": 8192,   "max_num_seqs": 256, "tp": 1, "kv_format": "fp8_e5m2",          "mem_util": 0.95, "weights_variant": "int4", "drafter_gb": 0.97, "mtp": True},
    },
}


# =============================================================================
# Calibration: measured BENCHMARKS rows (peak per-card VRAM during bench)
# =============================================================================

CALIBRATION = {
    "qwen3.6-27b": [
        # (compose, vram_gb, measured_peak_gb, ctx_override_or_none, source_url)
        ("dual",              24, 23.6, None,   "BENCHMARKS.md#qwen36-27b dual.yml @noonghunna 2026-04-29"),
        ("dual-turbo",        24, 19.8, None,   "BENCHMARKS.md#qwen36-27b dual-turbo.yml @noonghunna 2026-04-29"),
        ("dual-dflash",       24, 23.6, None,   "BENCHMARKS.md#qwen36-27b dual-dflash.yml @noonghunna 2026-04-29"),
        ("dual-dflash-noviz", 24, 23.8, None,   "BENCHMARKS.md#qwen36-27b dual-dflash-noviz.yml @noonghunna 2026-04-29"),
        ("dual4",             24, 23.5, None,   "BENCHMARKS.md#qwen36-27b dual4.yml @whamp 2026-05-03"),
        ("dual4-dflash",      24, 22.0, None,   "BENCHMARKS.md#qwen36-27b dual4-dflash.yml @whamp 2026-05-03"),
        ("dual-dflash-noviz", 24, 21.8, 180000, "BENCHMARKS.md#qwen36-27b dual-dflash-noviz.yml @snoby 2026-05-04 (2× 4090, ctx=180K)"),
        ("long-text",         24, 22.3, None,   "BENCHMARKS.md#qwen36-27b long-text.yml @noonghunna 2026-04-30"),
        ("long-vision",       24, 23.0, None,   "BENCHMARKS.md#qwen36-27b long-vision.yml @noonghunna 2026-04-30"),
        ("bounded-thinking",  24, 21.7, None,   "BENCHMARKS.md#qwen36-27b bounded-thinking.yml @noonghunna 2026-05-04"),
        ("minimal",           24, 22.4, 65536,  "BENCHMARKS.md#qwen36-27b minimal.yml @noonghunna 2026-05-03 (mem-util 0.95, max-ctx 65536)"),
    ],
    "gemma-4-31b": [
        # All TP=2 dual configs on 2× 3090 24 GB.
        ("gemma-dual-int8",      24, 22.2, None,   "BENCHMARKS.md#gemma-4-31b dual/int8.yml @noonghunna 2026-05-08 (98K + max-num-seqs=4)"),
        ("gemma-dual-int8-262k", 24, 22.1, None,   "BENCHMARKS.md#gemma-4-31b dual/int8.yml @noonghunna 2026-05-08 (262K + max-num-seqs=1)"),
        ("gemma-dual-dflash",    24, 22.7, None,   "BENCHMARKS.md#gemma-4-31b dual/dflash.yml @noonghunna 2026-05-06 (n=7)"),
        ("gemma-dual-dflash",    24, 22.3, None,   "BENCHMARKS.md#gemma-4-31b dual/dflash.yml @noonghunna 2026-05-08 (rebench)"),
        ("gemma-dual-awq",       24, 19.8, None,   "BENCHMARKS.md#gemma-4-31b dual/awq.yml @noonghunna 2026-05-08 (AWQ-4bit, mem-util 0.85)"),
        ("gemma-dual",           24, 22.5, None,   "BENCHMARKS.md#gemma-4-31b dual/docker-compose.yml @noonghunna matched-config rebench 2026-05-09"),
        ("gemma-dual-int8",      24, 22.5, 262144, "BENCHMARKS.md#gemma-4-31b dual/int8.yml matched-config rebench 2026-05-09 (262K seqs=2)"),
    ],
}


# =============================================================================
# Prediction
# =============================================================================

@dataclass
class Prediction:
    model: str
    weights_gb: float
    kv_pool_requested_gb: float
    kv_pool_actual_gb: float          # capped at available budget (vLLM behavior)
    kv_pool_sliding_fixed_gb: float   # Gemma sliding-window fixed term (0 for Qwen)
    activation_gb: float
    cudagraph_overhead_gb: float
    drafter_gb: float
    total_gb: float
    vram_gb: float
    budget_gb: float
    pct_of_vram: float
    verdict: str
    notes: list[str]


def _weights_per_card_gb(spec, tp, weights_variant="default"):
    """Return per-card weights footprint in GB after TP split."""
    if spec["model_family"] == "qwen3-next-hybrid":
        return spec["weights_total_gb"] / tp
    elif spec["model_family"] == "gemma4-swa-dense":
        if weights_variant == "awq":
            return spec["weights_awq_gb"] / tp
        elif weights_variant == "bf16":
            return spec["weights_bf16_gb"] / tp
        else:  # int4 default
            return spec["weights_int4_gb"] / tp
    raise ValueError(f"Unknown model_family: {spec['model_family']}")


def kv_pool_per_card_bytes(spec, kv_format, max_ctx, max_num_seqs, tp, mtp_n=0):
    """Per-card KV pool bytes (growing portion only).

    Returns a tuple (growing_per_card_bytes, sliding_fixed_per_card_bytes).
    Sliding term is zero for models without sliding-window layers.

    For Qwen 3.6 (DeltaNet hybrid):
      Only the 16 full_attention layers grow KV. GDN layers have a fixed-size
      recurrent state (not seq-len-dependent), so they show up in activation.
      K and V stored independently → ×2 factor.

    For Gemma 4 (SWA + dense MLP):
      Only the 10 full_attention layers grow KV (at global_head_dim=512).
      The 50 sliding_attention layers hold a FIXED window of 1024 tokens
      (constant in ctx, contributes a separate small term).
      K==V tying IS exploited by vLLM's allocator → ×1 factor (calibrated
      against BENCHMARKS data; see docs/KV_MATH.md).
    """
    bpe = KV_FORMAT_BYTES[kv_format]

    if spec["model_family"] == "qwen3-next-hybrid":
        # K and V stored independently
        per_token = (
            spec["num_attn_layers"]
            * spec["num_kv_heads"]
            * spec["head_dim_attn"]
            * 2  # K + V
            * bpe
        )
        effective_ctx = max_ctx + mtp_n * 32
        growing = (per_token / tp) * effective_ctx * max_num_seqs
        return growing, 0.0

    elif spec["model_family"] == "gemma4-swa-dense":
        # K==V tied → ×1 storage
        per_token_growing = (
            spec["num_full_attn_layers"]
            * spec["num_kv_heads"]
            * spec["global_head_dim"]
            * 1  # K==V tied; vLLM stores once
            * bpe
        )
        # No MTP draft-token bump on Gemma — drafter is a separate model
        growing = (per_token_growing / tp) * max_ctx * max_num_seqs

        # Sliding-window fixed term — 50 layers × window × head_dim × 1 × bpe
        sliding_fixed_total = (
            spec["num_sliding_attn_layers"]
            * spec["num_kv_heads"]
            * spec["head_dim_sliding"]
            * 1  # K==V tied here too
            * bpe
            * spec["sliding_window"]
        )
        sliding_per_card = sliding_fixed_total / tp
        return growing, sliding_per_card

    raise ValueError(f"Unknown model_family: {spec['model_family']}")


def activation_peak_per_card_bytes(spec, kv_format, max_ctx, tp):
    """Per-card peak activation during prefill forward.

    For Qwen 3.6 (DeltaNet GDN): linear in seq_len, KV-format-dependent
      coefficient (PerfMamba O(γ·D·N·L) form, fla.ops.chunk implementation
      details calibrated empirically).

    For Gemma 4 (dense MLP + SWA): mostly CONSTANT in seq_len because chunked
      prefill bounds the MLP intermediate. Small per-token residual to keep
      the solver smooth.
    """
    if spec["model_family"] == "qwen3-next-hybrid":
        coef = QWEN_GDN_ACTIVATION_COEF[kv_format]
        return (coef * spec["num_gdn_layers"] * max_ctx) / tp

    elif spec["model_family"] == "gemma4-swa-dense":
        const_bytes = GEMMA_ACTIVATION_CONST_GB * 1e9
        per_token = GEMMA_ACTIVATION_PER_TOKEN_BYTES * max_ctx
        return (const_bytes + per_token) / tp

    raise ValueError(f"Unknown model_family: {spec['model_family']}")


def cudagraph_overhead_gb(mem_util, tp):
    """vLLM cudagraph capture + flashinfer workspace overhead per card.
    Roughly linear with mem_util (higher mem-util → more graphs captured).
    TP increases per-card overhead slightly due to NCCL workspaces.
    """
    base = 0.5 + 1.0 * mem_util
    tp_bump = 0.0 if tp == 1 else 0.3 * (tp - 1)
    return base + tp_bump


def predict(
    spec=QWEN36_27B,
    kv_format="fp8_e5m2",
    max_ctx=180000,
    max_num_seqs=1,
    tp=1,
    mem_util=0.95,
    vram_gb=24,
    dflash_draft_gb=0.0,
    drafter_gb=0.0,
    mtp=False,
    weights_variant="default",
) -> Prediction:
    """Predict per-card VRAM usage.

    vLLM caps KV pool to (budget - fixed_components), so the prediction
    reflects what actually gets allocated. When requested > available,
    verdict is TIGHT with a note about effective concurrency reduction.

    Args:
      drafter_gb: total drafter weight (MTP / DFlash) — split by TP.
      dflash_draft_gb: legacy alias — folded into drafter_gb if set.
    """
    weights_gb = _weights_per_card_gb(spec, tp, weights_variant)

    growing_b, sliding_b = kv_pool_per_card_bytes(
        spec, kv_format, max_ctx, max_num_seqs, tp,
        mtp_n=3 if mtp else 0,
    )
    kv_pool_requested_gb = growing_b / 1e9
    kv_pool_sliding_fixed_gb = sliding_b / 1e9

    activation_gb = activation_peak_per_card_bytes(spec, kv_format, max_ctx, tp) / 1e9
    overhead_gb = cudagraph_overhead_gb(mem_util, tp)

    # Drafter: prefer drafter_gb; fall back to legacy dflash_draft_gb.
    drafter_total = drafter_gb if drafter_gb > 0 else dflash_draft_gb
    drafter_per_card = drafter_total / tp if tp > 1 else drafter_total

    fixed_gb = weights_gb + activation_gb + overhead_gb + drafter_per_card + kv_pool_sliding_fixed_gb
    budget_gb = mem_util * vram_gb
    available_for_kv = max(0.0, budget_gb - fixed_gb)

    # vLLM caps the KV pool to fit available budget (PagedAttention allocator).
    kv_pool_actual_gb = min(kv_pool_requested_gb, available_for_kv)

    total_gb = fixed_gb + kv_pool_actual_gb
    pct = 100 * total_gb / budget_gb if budget_gb > 0 else 999.0

    notes = []

    # Verdict logic:
    #   - FAIL: fixed components alone exceed budget (no room even for minimum KV).
    #   - TIGHT: requested KV pool exceeds available — vLLM will cap, effective
    #            concurrency reduced (BOOT OK, but `--max-num-seqs` may not be
    #            honored at full max_ctx).
    #   - PASS: requested KV fits with room to spare.
    MIN_KV_GB = 1.0  # vLLM needs at least ~1 GB for paged-attention blocks
    if available_for_kv < MIN_KV_GB:
        verdict = "FAIL"
        notes.append(
            f"fixed components ({fixed_gb:.1f} GB) leave only {available_for_kv:.1f} GB for KV pool "
            f"(need ≥{MIN_KV_GB:.1f} GB minimum); vLLM pre-check will refuse — "
            f"lower max_ctx, drop a drafter, or raise mem_util"
        )
    elif kv_pool_requested_gb > available_for_kv * 1.05:
        verdict = "TIGHT"
        notes.append(
            f"requested KV pool ({kv_pool_requested_gb:.1f} GB) > available ({available_for_kv:.1f} GB) — "
            f"vLLM will cap to {available_for_kv:.1f} GB; effective concurrency may be lower than "
            f"--max-num-seqs={max_num_seqs} at full max_ctx={max_ctx:,}"
        )
    else:
        verdict = "PASS"

    # Model-specific advisory notes (preserved from v1)
    if kv_format == "turboquant_3bit_nc" and vram_gb < 24 and spec["model_family"] == "qwen3-next-hybrid":
        notes.append("⚠ TQ3 KV on <24 GB cards: consider --kv-format fp8_e5m2 (see docs/HARDWARE.md, #47)")
    if max_ctx > 50000 and tp == 1 and spec["model_family"] == "qwen3-next-hybrid" and kv_format != "fp16":
        notes.append("⚠ single-card vLLM at >50K single-prompt: Cliff 2 territory (DeltaNet GDN forward); see docs/CLIFFS.md")
    if spec["model_family"] == "gemma4-swa-dense" and kv_format == "fp8_e4m3":
        notes.append("⚠ fp8_e4m3 on Ampere (sm_86): Triton `fp8e4nv` kernel unsupported; use int8_per_token_head instead (PR #40391 via #42102)")
    if spec["model_family"] == "gemma4-swa-dense" and tp == 1 and vram_gb < 32:
        notes.append("⚠ Gemma 4 31B TP=1 needs ≥32 GB VRAM; 24 GB Ampere boot-OOMs (model weights + drafter + min KV)")

    return Prediction(
        model=spec["model_id"],
        weights_gb=weights_gb,
        kv_pool_requested_gb=kv_pool_requested_gb,
        kv_pool_actual_gb=kv_pool_actual_gb,
        kv_pool_sliding_fixed_gb=kv_pool_sliding_fixed_gb,
        activation_gb=activation_gb,
        cudagraph_overhead_gb=overhead_gb,
        drafter_gb=drafter_per_card,
        total_gb=total_gb,
        vram_gb=vram_gb,
        budget_gb=budget_gb,
        pct_of_vram=pct,
        verdict=verdict,
        notes=notes,
    )


def fmt_prediction(p: Prediction, header: str = "") -> str:
    lines = []
    if header:
        lines.append(header)
        lines.append("-" * len(header))
    lines.append(f"  Model:                    {p.model}")
    lines.append(f"  Weights:                  {p.weights_gb:>6.2f} GB / card")
    if p.kv_pool_sliding_fixed_gb > 0.01:
        lines.append(f"  KV pool — sliding fixed:  {p.kv_pool_sliding_fixed_gb:>6.2f} GB / card  (constant, doesn't grow with ctx)")
    if abs(p.kv_pool_requested_gb - p.kv_pool_actual_gb) > 0.05:
        lines.append(f"  KV pool — growing (req):  {p.kv_pool_requested_gb:>6.2f} GB / card  (requested)")
        lines.append(f"  KV pool — growing (cap):  {p.kv_pool_actual_gb:>6.2f} GB / card  (vLLM-capped to fit)")
    else:
        lines.append(f"  KV pool — growing:        {p.kv_pool_actual_gb:>6.2f} GB / card")
    lines.append(f"  Activation peak:          {p.activation_gb:>6.2f} GB / card")
    lines.append(f"  Cudagraph + workspace:    {p.cudagraph_overhead_gb:>6.2f} GB / card")
    if p.drafter_gb > 0:
        lines.append(f"  Drafter (MTP / DFlash):   {p.drafter_gb:>6.2f} GB / card")
    lines.append(f"  ─────────────────────────────────────")
    lines.append(f"  Predicted total:          {p.total_gb:>6.2f} GB / card  ({p.pct_of_vram:.0f}% of {p.budget_gb:.1f} GB engine budget)")
    lines.append(f"  Verdict:                  {p.verdict}")
    for note in p.notes:
        lines.append(f"  Note: {note}")
    return "\n".join(lines)


# =============================================================================
# Calibration runner
# =============================================================================

def _resolve_compose_for_predict(model_key, compose_id, vram, ctx_override=None):
    """Resolve a compose preset to predict() kwargs, applying optional ctx override."""
    spec = MODEL_SPECS[model_key]
    cfg = COMPOSES[model_key][compose_id]
    max_ctx = ctx_override if ctx_override is not None else cfg["max_ctx"]

    kwargs = dict(
        spec=spec,
        kv_format=cfg["kv_format"],
        max_ctx=max_ctx,
        max_num_seqs=cfg["max_num_seqs"],
        tp=cfg["tp"],
        mem_util=cfg["mem_util"],
        vram_gb=vram,
        mtp=cfg.get("mtp", False),
        weights_variant=cfg.get("weights_variant", "default"),
        drafter_gb=cfg.get("drafter_gb", 0.0),
        dflash_draft_gb=cfg.get("dflash_draft_gb", 0.0),
    )
    return kwargs


def _calibration_block(model_key: str) -> tuple[int, int]:
    """Print calibration table for one model. Returns (correct, total)."""
    rows = CALIBRATION.get(model_key, [])
    if not rows:
        return 0, 0

    spec = MODEL_SPECS[model_key]
    print(f"== {spec['model_id']} ==")
    print(f"  {'compose':<26s} {'predicted':>10s} {'budget':>9s} {'measured':>10s} {'verdict':>8s}")
    print(f"  {'─'*25:<26s} {'─'*9:>10s} {'─'*8:>9s} {'─'*9:>10s} {'─'*7:>8s}")

    correct = 0
    for row in rows:
        compose, vram, measured, ctx_override, _src = row
        kwargs = _resolve_compose_for_predict(model_key, compose, vram, ctx_override)
        p = predict(**kwargs)
        # Verdict is "correct" if (PASS/TIGHT and measured fits) or (FAIL and would OOM).
        # We don't have negative (FAIL) data points in BENCHMARKS — every row booted —
        # so verdict_correct simplifies to: PASS/TIGHT and measured < vram.
        if p.verdict in ("PASS", "TIGHT") and measured < vram:
            mark = "✓"
            correct += 1
        elif p.verdict == "FAIL" and measured >= vram:
            mark = "✓"
            correct += 1
        else:
            mark = "⨯"
        compose_disp = compose if ctx_override is None else f"{compose}@{ctx_override//1024}K"
        print(f"  {compose_disp:<26s} {p.total_gb:>8.2f} GB {p.budget_gb:>7.2f} GB {measured:>8.2f} GB {p.verdict:>7s} {mark}")

    print()
    print(f"  Verdict accuracy: {correct}/{len(rows)} ({100*correct/len(rows):.0f}%)")
    print()
    return correct, len(rows)


def run_calibration():
    print("=" * 88)
    print("Calibration — predicted per-card VRAM vs measured BENCHMARKS rows")
    print("=" * 88)
    print()
    print("  Predicted = weights + activation + overhead + drafter + (KV capped at available).")
    print("  Budget = mem_util × VRAM. Measured = nvidia-smi peak during bench (target ≈ budget).")
    print("  Verdict ✓ iff PASS/TIGHT and measured < VRAM (boot OK).")
    print()

    total_c, total_n = 0, 0
    for model_key in ("qwen3.6-27b", "gemma-4-31b"):
        c, n = _calibration_block(model_key)
        total_c += c
        total_n += n

    if total_n > 0:
        print(f"Overall: {total_c}/{total_n} ({100*total_c/total_n:.0f}%)")
        print()
    print("Notes:")
    print("  - This is a directional estimator (±1.5 GB error band on the breakdown).")
    print("  - vLLM's `gpu_worker.py` boot log is the authoritative source.")
    print("  - If predicted PASS but measured > budget, file an issue with `scripts/report.sh --bench`.")


# =============================================================================
# Max-ctx solver
# =============================================================================

def solve_max_ctx(spec, kv_format, max_num_seqs, tp, mem_util, vram_gb,
                  drafter_gb=0.0, dflash_draft_gb=0.0, mtp=False, weights_variant="default"):
    """Binary search for the largest max_ctx that keeps the verdict at PASS or TIGHT."""
    lo, hi = 1024, spec.get("max_ctx_supported", 262144)
    best = 0
    while lo <= hi:
        mid = (lo + hi) // 2
        mid = (mid // 1024) * 1024  # round to nearest 1024 for cleaner numbers
        if mid == 0:
            break
        p = predict(
            spec=spec, kv_format=kv_format, max_ctx=mid, max_num_seqs=max_num_seqs,
            tp=tp, mem_util=mem_util, vram_gb=vram_gb,
            drafter_gb=drafter_gb, dflash_draft_gb=dflash_draft_gb,
            mtp=mtp, weights_variant=weights_variant,
        )
        if p.verdict in ("PASS", "TIGHT"):
            best = mid
            lo = mid + 1024
        else:
            hi = mid - 1024
    return best


# =============================================================================
# CLI
# =============================================================================

def _all_compose_choices() -> list[str]:
    """Flat list of compose names across all models for argparse choices."""
    out = []
    for model_key in COMPOSES:
        out.extend(COMPOSES[model_key].keys())
    return sorted(set(out))


def _resolve_compose_model(compose_name: str, explicit_model: Optional[str]) -> str:
    """Infer model from compose name if --model not given.

    Composes are namespaced by prefix; Qwen uses bare names, Gemma uses gemma-*.
    """
    if explicit_model:
        return explicit_model
    for model_key, composes in COMPOSES.items():
        if compose_name in composes:
            return model_key
    return "qwen3.6-27b"  # back-compat default


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--model", choices=sorted(MODEL_SPECS.keys()),
                   help="Which model to predict for. Default: qwen3.6-27b (back-compat) or inferred from --compose.")
    p.add_argument("--compose", choices=_all_compose_choices(),
                   help="Use a shipped compose's defaults. Override individual flags below.")
    p.add_argument("--kv-format", choices=sorted(KV_FORMAT_BYTES.keys()),
                   help="KV cache format. Default: from --compose, or fp8_e5m2.")
    p.add_argument("--max-ctx", type=int, help="max_model_len. Default: from --compose, or 180000.")
    p.add_argument("--max-num-seqs", type=int, help="max_num_seqs. Default: from --compose, or 1.")
    p.add_argument("--tp", type=int, choices=[1, 2, 4], help="tensor_parallel_size. Default: from --compose, or 1.")
    p.add_argument("--mem-util", type=float, help="gpu_memory_utilization. Default: from --compose, or 0.95.")
    p.add_argument("--vram", type=float, default=24, help="VRAM per card in GB. Default 24.")
    p.add_argument("--mtp", action="store_true", default=None, help="MTP enabled (Qwen: n=3 built-in; Gemma: external drafter).")
    p.add_argument("--no-mtp", dest="mtp", action="store_false")
    p.add_argument("--drafter-gb", type=float, default=None,
                   help="Drafter model size in GB (MTP / DFlash). 0 if not using a drafter.")
    p.add_argument("--dflash-draft-gb", type=float, default=None,
                   help="(deprecated alias for --drafter-gb)")
    p.add_argument("--weights-variant", choices=["default", "int4", "awq", "bf16"], default=None,
                   help="Gemma 4 only: which weight quant variant. Default: from --compose, or int4.")
    p.add_argument("--calibration", action="store_true", help="Print predicted vs measured for both models.")
    p.add_argument("--solve-max-ctx", action="store_true", help="Binary-search for the largest max_ctx that fits.")
    p.add_argument("--json", action="store_true", help="Output prediction as JSON.")
    args = p.parse_args()

    if args.calibration:
        run_calibration()
        return 0

    # Resolve model: explicit --model > inferred from --compose > qwen3.6-27b
    model_key = _resolve_compose_model(args.compose, args.model) if args.compose else (args.model or "qwen3.6-27b")
    spec = MODEL_SPECS[model_key]

    # Resolve compose-derived defaults
    if args.compose:
        # Compose must belong to the resolved model
        if args.compose not in COMPOSES[model_key]:
            print(f"ERROR: --compose {args.compose} is not in --model {model_key}'s compose list.", file=sys.stderr)
            print(f"       Available for {model_key}: {', '.join(sorted(COMPOSES[model_key].keys()))}", file=sys.stderr)
            return 2
        cfg = COMPOSES[model_key][args.compose]
        kv_format = args.kv_format or cfg["kv_format"]
        max_ctx = args.max_ctx or cfg["max_ctx"]
        max_num_seqs = args.max_num_seqs or cfg["max_num_seqs"]
        tp = args.tp or cfg["tp"]
        mem_util = args.mem_util if args.mem_util is not None else cfg["mem_util"]
        mtp = args.mtp if args.mtp is not None else cfg.get("mtp", False)
        drafter_gb = args.drafter_gb if args.drafter_gb is not None else cfg.get("drafter_gb", 0.0)
        dflash_gb = args.dflash_draft_gb if args.dflash_draft_gb is not None else cfg.get("dflash_draft_gb", 0.0)
        weights_variant = args.weights_variant or cfg.get("weights_variant", "default")
        header = f"Predicted budget — {model_key} / {args.compose} on {args.vram} GB VRAM (kv={kv_format}, ctx={max_ctx:,}, seqs={max_num_seqs}, TP={tp}, mem={mem_util})"
    else:
        kv_format = args.kv_format or "fp8_e5m2"
        max_ctx = args.max_ctx or 180000
        max_num_seqs = args.max_num_seqs or 1
        tp = args.tp or 1
        mem_util = args.mem_util if args.mem_util is not None else 0.95
        mtp = bool(args.mtp) if args.mtp is not None else False
        drafter_gb = args.drafter_gb or 0.0
        dflash_gb = args.dflash_draft_gb or 0.0
        weights_variant = args.weights_variant or "default"
        header = f"Predicted budget — {model_key} custom config on {args.vram} GB VRAM (kv={kv_format}, ctx={max_ctx:,}, seqs={max_num_seqs}, TP={tp}, mem={mem_util})"

    if args.solve_max_ctx:
        best = solve_max_ctx(
            spec, kv_format=kv_format, max_num_seqs=max_num_seqs,
            tp=tp, mem_util=mem_util, vram_gb=args.vram,
            drafter_gb=drafter_gb, dflash_draft_gb=dflash_gb, mtp=mtp,
            weights_variant=weights_variant,
        )
        if best > 0:
            pred_at_best = predict(
                spec=spec, kv_format=kv_format, max_ctx=best, max_num_seqs=max_num_seqs,
                tp=tp, mem_util=mem_util, vram_gb=args.vram,
                drafter_gb=drafter_gb, dflash_draft_gb=dflash_gb, mtp=mtp,
                weights_variant=weights_variant,
            )
            if args.json:
                out = pred_at_best.__dict__.copy()
                out["solved_max_ctx"] = best
                print(json.dumps(out, indent=2))
            else:
                print(f"Max-ctx solver — {model_key} / {kv_format}, seqs={max_num_seqs}, TP={tp}, mem_util={mem_util}, VRAM={args.vram} GB")
                print(f"  Largest max_ctx that fits: {best:,} tokens")
                print(f"  At that ctx: predicted = {pred_at_best.total_gb:.2f} GB / card ({pred_at_best.pct_of_vram:.0f}% of budget)")
                print(f"  Verdict at that ctx: {pred_at_best.verdict}")
                for note in pred_at_best.notes:
                    print(f"  Note: {note}")
                print()
                print("Note: this is a directional estimate (±1.5 GB error band). The vLLM engine")
                print("pre-check (gpu_worker.py boot log) is authoritative.")
        else:
            print(f"No max_ctx fits at this config on {args.vram} GB. Reduce TP, swap KV format, or get bigger cards.")
        return 0

    pred = predict(
        spec=spec, kv_format=kv_format, max_ctx=max_ctx, max_num_seqs=max_num_seqs,
        tp=tp, mem_util=mem_util, vram_gb=args.vram,
        drafter_gb=drafter_gb, dflash_draft_gb=dflash_gb, mtp=mtp,
        weights_variant=weights_variant,
    )

    if args.json:
        print(json.dumps(pred.__dict__, indent=2))
    else:
        print(fmt_prediction(pred, header=header))
        print()
        print("Run `tools/kv-calc.py --calibration` to see predicted-vs-measured for all anchors.")
        print("Run `tools/kv-calc.py --solve-max-ctx ...` to find the largest max_ctx that fits.")
        print("See docs/KV_MATH.md for math + per-model architecture details.")
    return 0 if pred.verdict in ("PASS", "TIGHT") else 1


if __name__ == "__main__":
    sys.exit(main())
