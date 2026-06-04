#!/usr/bin/env bash
# GLM-4.7-Flash Q5_K_L — single RTX 3090, 65K ctx
# 21 GB weights, 22 GB VRAM @ 65K ctx, 107 TPS
# hermesagent-20: 13/20 (65%) — unique strengths: HA-04 (memory recall),
# HA-06 (long complex), HA-14 (cron). Best for scheduled/memory workloads.
#
# Download: huggingface-cli download zai-org/GLM-4.7-Flash-GGUF \
#   GLM-4.7-Flash-Q5_K_L.gguf --local-dir /data/models

MODEL="${MODEL:-/data/models/zai-org_GLM-4.7-Flash-Q5_K_L.gguf}"
PORT="${PORT:-8020}"
GPU="${GPU:-0}"

docker rm -f llama-cpp-glm47-flash 2>/dev/null || true

docker run -d \
  --name llama-cpp-glm47-flash \
  --restart unless-stopped \
  --gpus "\"device=${GPU}\"" \
  -p "${PORT}:8080" \
  -v "/data/models:/models:ro" \
  ghcr.io/ggml-org/llama.cpp:server-cuda \
  --host 0.0.0.0 --port 8080 \
  -m "/models/zai-org_GLM-4.7-Flash-Q5_K_L.gguf" \
  -c 65536 -b 4096 -ub 1024 \
  -ngl 99 -fa on \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  --jinja \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
  -np 1

echo ""
echo "GLM-4.7-Flash started on port ${PORT}"
echo "Health: curl http://localhost:${PORT}/health"
echo "Logs:   docker logs -f llama-cpp-glm47-flash"
