#!/usr/bin/env bash
# yt-bench.sh — threads + ubatch sweep via llama-bench (як у відео)
#
# Запуск:  bash scripts/yt-bench.sh 2>&1 | tee /tmp/yt-bench-results.txt
# Потім надішли /tmp/yt-bench-results.txt в чат.
#
# УВАГА: скрипт тимчасово зупиняє llama-cpp-carnice-v2-27b
#        і перезапускає його після завершення.

set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/opt/club-3090/models-cache}"
MODEL_FILE="carnice-v2-27b-gguf/stuchapin-q4km-mtp/Carnice-V2-27B-Q4_K_M-mtp.gguf"
IMAGE="ghcr.io/ggml-org/llama.cpp:full-cuda"
SERVER_CONTAINER="llama-cpp-carnice-v2-27b"

PP=512    # prefill tokens  (відео використовував різні значення)
TG=128    # generation tokens

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "unknown")

# ---- зупинити сервер, відновити після ----------------------------------------
SERVER_WAS_RUNNING=false
if docker ps --format "{{.Names}}" | grep -q "^${SERVER_CONTAINER}$"; then
  SERVER_WAS_RUNNING=true
  echo "Зупиняю ${SERVER_CONTAINER} на час тесту..."
  docker stop "$SERVER_CONTAINER" &>/dev/null
fi

restore_server() {
  if $SERVER_WAS_RUNNING; then
    echo ""
    echo "Відновлюю ${SERVER_CONTAINER}..."
    docker start "$SERVER_CONTAINER" &>/dev/null && echo "OK"
  fi
}
trap restore_server EXIT

# ---- bench функція -----------------------------------------------------------
bench() {
  local label="$1"; shift
  echo "### ${label}"
  docker run --rm \
    --gpus "\"device=0\"" \
    -v "${MODEL_DIR}:/models:ro" \
    --entrypoint="/app/llama-bench" \
    "$IMAGE" \
    -m "/models/${MODEL_FILE}" \
    -p "$PP" -n "$TG" \
    -ngl 99 -fa 1 \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    "$@" 2>&1 \
    | grep -v "^ggml\|^load_backend\|^llama_" \
    | grep -v "^$"
  echo ""
}

# ---- header ------------------------------------------------------------------
echo "======================================================"
echo " yt-bench.sh — llama-bench threads + ubatch sweep"
echo " Model: Carnice-V2-27B Q4_K_M-mtp"
echo " GPU:   ${GPU_NAME}"
echo " Date:  $(date '+%Y-%m-%d %H:%M')"
echo " PP=${PP} tokens, TG=${TG} tokens"
echo "======================================================"
echo ""

# ---- 1. Threads sweep --------------------------------------------------------
echo "=== 1. THREADS SWEEP  (ubatch=512) ==="
echo "Шукаємо оптимальну кількість ядер."
echo "У відео: t=3 на 4-core CPU дало пік. Наш CPU: 20 threads (i9-13900H)."
echo ""
for T in 4 6 8 12 16 19; do
  bench "t=${T}  ub=512" -t "$T" -ub 512
done

# ---- 2. UBatch sweep ---------------------------------------------------------
echo "=== 2. UBATCH SWEEP  (t=6) ==="
echo "Відео: ub=2048 дало 4× faster PP (prefill). Наш поточний: ub=512."
echo ""
for UB in 256 512 1024 2048 4096; do
  bench "t=6  ub=${UB}" -t 6 -ub "$UB"
done

# ---- 3. Best combos ----------------------------------------------------------
echo "=== 3. BEST COMBO  (оптимальний t + великий ub) ==="
bench "t=8   ub=2048" -t 8  -ub 2048
bench "t=12  ub=2048" -t 12 -ub 2048
bench "t=19  ub=2048" -t 19 -ub 2048
bench "t=12  ub=4096" -t 12 -ub 4096

echo "======================================================"
echo " Готово."
echo " Результати збережено у /tmp/yt-bench-results.txt"
echo "======================================================"
