#!/usr/bin/env bash
# Carnice-9B Q4_K_M (kai-os) — single RTX 3090, 128K ctx
# 5.63 GB weights — fits with ~16 GB headroom for KV
# No MTP (kai-os did not include MTP head in this GGUF)
# Download: huggingface-cli download kai-os/Carnice-9b-GGUF \
#   Carnice-9b-Q4_K_M.gguf \
#   --local-dir /opt/club-3090/models-cache/carnice-9b-gguf/kai-os-q4km

MODEL_DIR="${MODEL_DIR:-/opt/club-3090/models-cache}"
PORT="${PORT:-8022}"
GPU="${GPU:-0}"

docker rm -f llama-cpp-carnice-9b 2>/dev/null || true

docker run -d \
  --name llama-cpp-carnice-9b \
  --restart unless-stopped \
  --gpus "\"device=${GPU}\"" \
  -p "${PORT}:8080" \
  -v "${MODEL_DIR}:/models:ro" \
  ghcr.io/ggml-org/llama.cpp:server-cuda-b9246 \
  --host 0.0.0.0 --port 8080 \
  -m /models/carnice-9b-gguf/kai-os-q4km/Carnice-9b-Q4_K_M.gguf \
  -c 131072 -b 4096 -ub 512 \
  -ngl 99 -fa on \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  -np 1 \
  --jinja \
  --reasoning off --reasoning-format deepseek \
  --temp 0.6 --top-p 0.95 --top-k 20 \
  --min-p 0.0 --repeat-penalty 1.0

echo "Carnice-9B started on http://localhost:${PORT}"
echo "Logs: docker logs -f llama-cpp-carnice-9b"
