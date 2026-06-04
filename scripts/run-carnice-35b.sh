#!/usr/bin/env bash
# Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality — single RTX 3090
# 23.5 GB weights, ~23.5 GB VRAM, 139 TPS
# hermesagent-20: 17/20 (85%) — rig record
# ctx capped at 80K (soak fails at 131K — VRAM too tight under sustained load)
# MTP head present but incompatible (mainline + cu12 both fail to init)
#
# Download: huggingface-cli download mudler/Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality-GGUF \
#   Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf \
#   --local-dir /data/models

MODEL="${MODEL:-/data/models/Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf}"
PORT="${PORT:-8020}"
GPU="${GPU:-0}"

docker rm -f llama-cpp-carnice-35b 2>/dev/null || true

docker run -d \
  --name llama-cpp-carnice-35b \
  --restart unless-stopped \
  --gpus "\"device=${GPU}\"" \
  -p "${PORT}:8080" \
  -v "/data/models:/models:ro" \
  ghcr.io/ggml-org/llama.cpp:server-cuda \
  --host 0.0.0.0 --port 8080 \
  -m "/models/Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf" \
  -c 81920 -b 4096 -ub 1024 \
  -ngl 99 -fa on \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  --jinja \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
  -np 1

echo ""
echo "Carnice I-Quality 35B started on port ${PORT}"
echo "Health: curl http://localhost:${PORT}/health"
echo "Logs:   docker logs -f llama-cpp-carnice-35b"
