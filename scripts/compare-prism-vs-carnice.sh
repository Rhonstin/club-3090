#!/usr/bin/env bash
# compare-prism-vs-carnice.sh
# Full validation pipeline (verify-full + verify-stress + bench + quality + soak)
# for three single-card models: PRISM-PRO-DQ, Carnice I-Quality, byteshape IQ4_XS.
# At the end restarts the miner.
#
# Usage:
#   bash scripts/compare-prism-vs-carnice.sh
#
# Time estimate: ~2-3 hours total (all three models × full pipeline).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT=8020
URL="http://localhost:$PORT"

TIMESTAMP=$(date +%Y%m%dT%H%M%S)
LOG_DIR="$REPO_ROOT/results/quality"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/compare-full-$TIMESTAMP.txt"

log()  { echo "[compare] $*" | tee -a "$SUMMARY"; }
sep()  { log ""; log "======================================================="; log "$*"; log "======================================================="; }
fail() { log "ERROR: $*"; exit 1; }

wait_ready() {
    local container="$1"
    log "Waiting for $container to become ready..."
    local tries=0
    until curl -sf "$URL/health" >/dev/null 2>&1; do
        sleep 3
        tries=$((tries + 1))
        [[ $tries -gt 100 ]] && fail "$container did not become ready after 300s"
    done
    sleep 2
    log "$container is ready."
}

stop_container() {
    local name="$1"
    docker stop  "$name" 2>/dev/null || true
    docker rm    "$name" 2>/dev/null || true
}

run_pipeline() {
    local label="$1" container="$2"
    # remaining args are the docker run command (image + flags)
    shift 2

    sep "MODEL: $label"

    # Stop anything on this port
    stop_container "$container"
    # Also stop any other container that might own port 8020
    local existing
    existing=$(docker ps --format '{{.Names}}' --filter "publish=$PORT" 2>/dev/null || true)
    [[ -n "$existing" ]] && docker stop $existing 2>/dev/null || true

    log "Starting container: $container"
    docker run -d --name "$container" "$@"
    wait_ready "$container"

    # --- verify-full ---
    sep "$label — verify-full"
    CONTAINER="$container" URL="$URL" bash "$SCRIPT_DIR/verify-full.sh" 2>&1 | tee -a "$SUMMARY" || log "WARN: verify-full had failures (see above)"

    # --- verify-stress ---
    sep "$label — verify-stress"
    CONTAINER="$container" URL="$URL" bash "$SCRIPT_DIR/verify-stress.sh" 2>&1 | tee -a "$SUMMARY" || log "WARN: verify-stress had failures (see above)"

    # --- bench ---
    sep "$label — bench"
    CONTAINER="$container" URL="$URL" bash "$SCRIPT_DIR/bench.sh" 2>&1 | tee -a "$SUMMARY" || log "WARN: bench had failures (see above)"

    # --- quality: hermesagent-20 ---
    sep "$label — hermesagent-20"
    CONTAINER="$container" URL="$URL" bash "$SCRIPT_DIR/quality-test.sh" --pack hermesagent-20 2>&1 | tee -a "$SUMMARY"

    # --- quality: --medium ---
    sep "$label — quality --medium"
    CONTAINER="$container" URL="$URL" bash "$SCRIPT_DIR/quality-test.sh" --medium 2>&1 | tee -a "$SUMMARY"

    # --- soak-continuous ---
    sep "$label — soak-continuous"
    CONTAINER="$container" URL="$URL" SOAK_MODE=continuous bash "$SCRIPT_DIR/soak-test.sh" 2>&1 | tee -a "$SUMMARY" || log "WARN: soak had failures (see above)"

    stop_container "$container"
    log "Finished: $label"
}

log "Full comparison run started: $TIMESTAMP"
log "Models: PRISM-PRO-DQ · Carnice I-Quality · byteshape IQ4_XS"

# ─── 1. PRISM-PRO-DQ — mainline llama.cpp + --spec-type draft-mtp ───────────
run_pipeline \
    "PRISM-PRO-DQ 27B (mainline + draft-mtp)" \
    "llamacpp-prism-pro-dq" \
    --restart unless-stopped \
    --gpus '"device=0"' \
    -p "$PORT:8080" \
    -v "/root/.cache/huggingface/hub/models--Ex0bit--Qwen3.6-27B-PRISM-PRO-DQ:/models:ro" \
    ghcr.io/ggml-org/llama.cpp:server-cuda \
    --host 0.0.0.0 --port 8080 \
    --model "/models/snapshots/d3f5d79db0088accdd3cb9bb188ee8f747b0ef4b/Qwen3.6-27B-PRISM-PRO-DQ.gguf" \
    --ctx-size 122880 \
    -ngl 99 -b 4096 -ub 1024 -np 1 \
    -ctk q4_0 -ctv q4_0 -fa on \
    --spec-type draft-mtp \
    --jinja \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0

# ─── 2. Carnice 35B-A3B I-Quality — mainline llama.cpp ──────────────────────
run_pipeline \
    "Carnice 35B-A3B I-Quality (mainline)" \
    "llamacpp-carnice-iq" \
    --restart unless-stopped \
    --gpus '"device=0"' \
    -p "$PORT:8080" \
    -v "/data/models:/models:ro" \
    ghcr.io/ggml-org/llama.cpp:server-cuda \
    --host 0.0.0.0 --port 8080 \
    --model "/models/Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf" \
    --ctx-size 131072 \
    -ngl 99 -b 4096 -ub 1024 -np 1 \
    -ctk q4_0 -ctv q4_0 -fa on \
    --jinja \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0

# ─── 3. byteshape IQ4_XS — ik-llama cu12 + MTP ──────────────────────────────
run_pipeline \
    "byteshape IQ4_XS 35B-A3B (ik-llama cu12 + MTP)" \
    "ik-llama-byteshape" \
    --restart unless-stopped \
    --gpus '"device=0"' \
    -p "$PORT:8080" \
    -v "/data/models:/models:ro" \
    ghcr.io/ikawrakow/ik-llama-cpp:cu12-server \
    --host 0.0.0.0 --port 8080 \
    --model "/models/qwen3.6-35b-a3b-gguf/byteshape-iq4xs/Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf" \
    --fit --fit-margin 256 \
    -ngl 99 -b 4096 -ub 1024 -np 1 \
    -ctk q4_0 -ctv q4_0 -fa on \
    --recurrent-ckpt-mode auto \
    --merge-qkv \
    --multi-token-prediction \
    --draft-max 2 --draft-p-min 0.0 \
    --jinja \
    --parallel-tool-calls \
    --reasoning off \
    --reasoning-format deepseek \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
    --repeat-penalty 1.0

sep "ALL DONE"
log "Full log: $SUMMARY"

log "Starting miner..."
bash /root/miner-start.sh
