#!/usr/bin/env bash
# Carnice-V2-27B Q4_K_M-mtp (stuchapin) — single RTX 3090, 200K ctx, MTP n=2
#
# Download:
#   hf download stuchapin/Carnice-V2-27B-MTP-GGUF Carnice-V2-27B-Q4_K_M-mtp.gguf \
#     --local-dir /opt/club-3090/models-cache/carnice-v2-27b-gguf/stuchapin-q4km-mtp
#
# === Benchmark results (RTX 3090, driver 580.126.09, 2026-05-31) ===
#
# Power:    320W limit (optimal — sweep via scripts/power-sweep.sh)
#           350W → 64.5 t/s decode / 1061 t/s prefill (28-tok ctx)
#           320W → 64.5 t/s decode / 1108 t/s prefill  (-3.9% / within noise)
#           300W → 61.0 t/s decode / 999  t/s prefill  (-9.1% ← knee)
#           Power limit set in /etc/rc.local via: nvidia-smi -pl 320 -i 0
#
# MTP:      n-max=2, p-min=0.0 is the sweet spot for this model
#           76.5% acceptance rate (315 drafts / 241 accepted) for chat/essay
#           ~55-56 t/s effective decode (vs ~22-25 t/s without MTP)
#           n-max=3 tested → 52 t/s at 66% acceptance (3rd token ~50% — not worth it)
#           For code output: acceptance climbs to 85-95% automatically (no flag changes)
#
# Memory:   GDDR6X stays at 9501 MHz at ALL power limits (no throttle)
#           9751 MHz is burst-only spec; 9501 MHz is sustained under load
#           OC beyond 9501 MHz needs X11+Coolbits or Windows+Afterburner — not available headless
#
# KV quant: switched to q8_0/120K (2026-05-31) — reason: at 107K filled ctx,
#   q4_0 decode degraded to ~31 t/s (dequant overhead). q8_0 maintains ~38-42 t/s
#   at long context. Short-ctx performance identical (53 t/s).
#
# VRAM: 23398 MiB used / 24124 total → 727 MiB free (safe headroom)
#   q8_0 @ 120K = 6.56 GB KV | q8_0 @ 128K = 7.0 GB → only 439 MB free (too tight)
#   q4_0 @ 200K = 5.7 GB KV  | q8_0 @ 200K = 11.5 GB ❌ OOM
#   TurboQuant KV (fork spiritbuun/buun-llama-cpp) is the only known next step

MODEL_DIR="${MODEL_DIR:-/opt/club-3090/models-cache}"
PORT="${PORT:-8021}"
GPU="${GPU:-0}"

docker rm -f llama-cpp-carnice-v2-27b 2>/dev/null || true

docker run -d \
  --name llama-cpp-carnice-v2-27b \
  --restart unless-stopped \
  --gpus "\"device=${GPU}\"" \
  -p "${PORT}:8080" \
  -v "${MODEL_DIR}:/models:ro" \
  ghcr.io/ggml-org/llama.cpp:server-cuda-b9246 \
  --host 0.0.0.0 --port 8080 \
  -m /models/carnice-v2-27b-gguf/stuchapin-q4km-mtp/Carnice-V2-27B-Q4_K_M-mtp.gguf \
  -c 122880 -b 4096 -ub 512 -t 4 \
  -ngl 99 -fa on \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  -np 1 \
  --spec-type draft-mtp --spec-draft-n-max 2 \
  --cache-reuse 256 \
  --jinja \
  --reasoning off --reasoning-format deepseek \
  --temp 0.6 --top-p 0.95 --top-k 20 \
  --min-p 0.0 --repeat-penalty 1.0

echo "Carnice-V2-27B started on http://localhost:${PORT}"
echo "Logs: docker logs -f llama-cpp-carnice-v2-27b"
