# solo3090

**Single RTX 3090 LLM inference lab.** Real benchmarks, working configs, research findings — everything needed to run and evaluate modern LLMs on a single 24 GB GPU.

> **Maintained by:** [@Rhonstin](https://github.com/Rhonstin) — this is an independent fork of [noonghunna/club-3090](https://github.com/noonghunna/club-3090), focused exclusively on single-card (1× RTX 3090) research. Multi-GPU content has been removed. If you have 2+ GPUs, the upstream repo covers that.

---

## What this is

A research repo documenting what actually works on a **single RTX 3090 24 GB**:

- Which models run, at what context, at what speed
- Benchmark results across 8 quality packs (150 scenarios) — not synthetic, real agent workflows
- Launch scripts and Docker configs for each model
- Findings on quantization, MTP speculative decoding, KV formats, VRAM limits

Everything here has been tested on hardware. No theoretical numbers.

---

## Hardware

- **GPU:** NVIDIA RTX 3090 (Ampere SM 8.6), 24 GB GDDR6X, PCIe
- **Driver:** 580.126.09 / CUDA 12 (cu12 builds required — no Forward Compatibility on consumer GPUs)
- **No NVLink, no multi-GPU** — this repo is strictly single-card

---

## Best models (2026-06-04 benchmark)

8 models tested, 3 runs each, 150 scenarios total (`--full` suite: ToolCall / InstructFollow / StructOutput / DataExtract / ReasonMath / BugFind / HermesAgent-20 / CLI-40).

| Rank | Model | Score | HA-20 | CLI-40 | TPS | Ctx |
|---:|---|---:|---:|---:|---:|---:|
| 1 | byteshape IQ4_XS Qwen3.6-35B-A3B + MTP | **73.5%** | 57% | 17/40 | 115 | 262K |
| 2 | bartowski Qwen3.6-35B Q4_K_M | 72.9% | 62% | 16/40 | **140** | 131K |
| 3 | Qwopus3.6-27B-v2 MTP n=2 | 71.8% | 70% | **20/40** | 42 | 102K |
| 3 | Carnice-V2-27B MTP n=2 | 71.8% | 62% | 18/40 | 40 | 65K |
| 6 | Gemma 4 26B-A4B Q4_K_M | 69.8% | 60% | 17/40 | 102 | 32K |
| 7 | Carnice I-Quality 35B-A3B | 63.5% | **80%** | 6.7/40 ⚠️ | 139 | 131K |
| 8 | GLM-4.7-Flash Q5_K_L | 57.1% | 50% | 9.3/40 | 107 | 65K |

**Key finding:** Single-pack benchmarks mislead. Carnice I-Quality is #1 on HermesAgent-20 (80%) but #7 overall because CLI-40 exposes catastrophic forgetting (6.7/40 = 17%). The best all-rounder with no weak spots is byteshape IQ4_XS.

Full analysis → [`docs/FULLBENCH_ANALYSIS.md`](docs/FULLBENCH_ANALYSIS.md)

---

## Quick launch

```bash
# Best all-rounder: byteshape IQ4_XS 35B-A3B (262K ctx, MTP, 115 TPS)
docker run -d --name llm \
  --restart unless-stopped \
  --gpus "device=0" \
  -p 8020:8080 \
  -v "/data/models:/data/models:ro" \
  ghcr.io/ikawrakow/ik-llama-cpp:cu12-server \
  --host 0.0.0.0 --port 8080 \
  -m /path/to/Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf \
  -ngl 99 --fit --fit-margin 256 \
  -b 4096 -ub 1024 -np 1 \
  -ctk q4_0 -ctv q4_0 -fa on \
  -khad -vhad -ngld 99 \
  --multi-token-prediction --draft-max 2 --draft-p-min 0.0 \
  --recurrent-ckpt-mode auto --merge-qkv \
  --reasoning off --reasoning-format deepseek \
  --jinja --parallel-tool-calls \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.1

# HermesAgent workflows (best HA score): Carnice I-Quality
# CLI automation: Qwopus3.6-27B-v2 MTP n=2
# Bug finding: Qwen3.6-27B Q5_K_XL MTP n=3
```

---

## Task-based model selection

| Task | Best model | Why |
|---|---|---|
| **All-round daily driver** | byteshape IQ4_XS 35B-A3B | 73.5%, 262K ctx, no weak packs |
| **HermesAgent protocol** | Carnice I-Quality 35B | 80% HA-20, only model with safety clarification |
| **CLI / shell automation** | Qwopus3.6-27B-v2 MTP | 20/40 CLI-40, perfectly consistent |
| **Bug finding / code review** | Qwen3.6-27B Q5_K_XL MTP | 93% BugFind, 100% InstructFollow |
| **Math / reasoning** | Gemma 4 26B or bartowski 35B | 87% ReasonMath |
| **Max speed** | bartowski Qwen3.6-35B Q4_K_M | 140 TPS, 72.9% overall |

---

## Docs

- [`docs/SINGLE_CARD.md`](docs/SINGLE_CARD.md) — single-card guide: VRAM math, context limits, KV format tradeoffs
- [`docs/FULLBENCH_ANALYSIS.md`](docs/FULLBENCH_ANALYSIS.md) — overnight benchmark: 8 models × 3 runs × 150 scenarios
- [`docs/HERMESAGENT_SCENARIOS.md`](docs/HERMESAGENT_SCENARIOS.md) — per-scenario pass/fail breakdown
- [`docs/QUALITY_TEST.md`](docs/QUALITY_TEST.md) — how to run quality tests
- [`BENCHMARKS.md`](BENCHMARKS.md) — full benchmark history
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — stack: engines, ports, image pinning

---

## Benchmark methodology

- **Suite:** benchlocal-cli `--full` — 8 packs, 150 scenarios
- **Protocol:** 3 runs per model, averages reported
- **Sampling:** temperature=0.6, top_p=0.95, top_k=20
- **Hardware:** 1× RTX 3090 24 GB, ik-llama cu12 or mainline llama.cpp
- Results in `results/quality/overnight-*/`

---

## Repo structure

```
models/
  qwen3.6-27b/          # Qwen3.6-27B configs (llama.cpp, ik-llama, vllm, beellama, sglang)
  qwen3.6-35b-a3b/      # Qwen3.6-35B-A3B MoE configs
  gemma-4-26b-a4b/      # Gemma 4 26B-A4B (single-card, ik-llama)
  gemma-4-31b/          # Gemma 4 31B (single-card only)
docs/                   # Guides, analysis, upstream tracker
scripts/                # launch, verify, bench, quality-test
results/                # Benchmark output JSONs
```

All compose files are `single/` topology only. Dual and multi-GPU configs have been removed.

---

## Relation to upstream

This repo is a **fork of [noonghunna/club-3090](https://github.com/noonghunna/club-3090)**. Key differences:

- Single-card (1× RTX 3090) focus only — dual/multi configs removed
- Added: full-suite benchmark results (8 packs, 150 scenarios) for ~15 models
- Added: per-task model selection guide based on benchmark data
- Fixed: ik-llama cu12 image for RTX 3090 (driver 580.126.09 has no CUDA Forward Compat)
- Added: overnight benchmark script (`scripts/overnight-bench.sh`)

Upstream fixes that apply to all rigs get PRs to upstream. Rig-specific fixes (cu12) stay in this fork only.
