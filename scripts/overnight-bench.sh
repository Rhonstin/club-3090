#!/usr/bin/env bash
# overnight-bench.sh — Нічний benchmark 8 моделей, 3 запуски кожна, --full
#
# Запуск: nohup bash scripts/overnight-bench.sh > /tmp/overnight.log 2>&1 &
# Час:    ~12-16 годин (--full ~35 хв × 8 моделей × 3 запуски)
# Результати: results/quality/overnight-<timestamp>/
#
# Після завершення: Telegram нотифікація + запуск майнера

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT=8019
URL="http://localhost:$PORT"
CONTAINER="overnight-bench"
RUNS=3
START_TIME=$(date +%s)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$REPO_ROOT/results/quality/overnight-$TIMESTAMP"
LOG="$RESULTS_DIR/overnight.log"
SUMMARY="$RESULTS_DIR/summary.md"
LLAMACPP_IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda"
IK_IMAGE="ghcr.io/ikawrakow/ik-llama-cpp:cu12-server"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$LOG") 2>&1

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
sep()  { echo ""; echo "══════════════════════════════════════════════════════════"; echo "[$(date '+%H:%M:%S')] $*"; echo "══════════════════════════════════════════════════════════"; }
notify() { bash /root/notify.sh "$1" 2>/dev/null || true; }

stop_container() {
  docker stop "$CONTAINER" 2>/dev/null || true
  docker rm   "$CONTAINER" 2>/dev/null || true
}

stop_miner() {
  local miner_pid
  miner_pid=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | head -1 || true)
  if [[ -n "$miner_pid" ]]; then
    log "Зупиняємо процес на GPU (PID $miner_pid)..."
    kill "$miner_pid" 2>/dev/null || true
    sleep 5
  fi
  pkill -f alpha-miner 2>/dev/null || true
  sleep 2
}

wait_ready() {
  local tries=0
  until curl -sf "$URL/health" >/dev/null 2>&1; do
    sleep 5; tries=$((tries+1))
    if [[ $tries -gt 72 ]]; then log "FAIL: не готовий після 360s"; return 1; fi
  done
  sleep 3
  log "Ready ($(( tries * 5 ))s)"
}

# ── Моделі ───────────────────────────────────────────────────────────────────
# Формат: label | image | model_path | ctx | kv | extra_flags
declare -a MODELS=(
  "carnice-iq|$LLAMACPP_IMAGE|/data/models/Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf|81920|q4_0|--jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "qwen27-xl|$LLAMACPP_IMAGE|/data/models/Qwen3.6-27B-UD-Q5_K_XL.gguf|32768|q4_0|--spec-type draft-mtp --spec-draft-n-max 3 --jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "qwopus-v2|$LLAMACPP_IMAGE|/data/models/Qwopus3.6-27B-v2-MTP-Q5_K_M.gguf|102400|q4_0|--spec-type draft-mtp --spec-draft-n-max 2 --jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "gemma4-26b|$IK_IMAGE|/data/models/gemma-4-26b-a4b-gguf/unsloth-q4km/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf|32768|q4_0|--reasoning off --jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "carnice-v2|$LLAMACPP_IMAGE|/data/models/Carnice-V2-27B-Q5_K_M-mtp.gguf|65536|q4_0|--spec-type draft-mtp --spec-draft-n-max 2 --reasoning off --reasoning-format deepseek --jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "bartowski-35b|$LLAMACPP_IMAGE|/data/models/qwen3.6-35b-a3b-gguf/bartowskia/Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf|131072|q4_0|--jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "glm47|$LLAMACPP_IMAGE|/data/models/zai-org_GLM-4.7-Flash-Q5_K_L.gguf|65536|q4_0|--jinja --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0"
  "byteshape-iq4xs|$IK_IMAGE|/data/models/qwen3.6-35b-a3b-gguf/byteshape-iq4xs/Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf|0|q4_0|--fit --fit-margin 256 -khad -vhad -ngld 99 --multi-token-prediction --draft-max 2 --draft-p-min 0.0 --recurrent-ckpt-mode auto --merge-qkv --reasoning off --reasoning-format deepseek --jinja --parallel-tool-calls --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.1"
)

# ── Результати ────────────────────────────────────────────────────────────────
declare -A MODEL_SCORES   # label -> "run1_passed run2_passed run3_passed"
declare -A MODEL_STATUS   # label -> OK / BOOT_FAIL / ERROR
FAILED_MODELS=()

# ── Основний цикл ─────────────────────────────────────────────────────────────
sep "overnight-bench START — $TIMESTAMP"
log "Зупиняємо майнер та всі контейнери перед стартом..."
stop_miner
docker stop $(docker ps -q) 2>/dev/null || true
sleep 3
log "GPU вільно: $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB"
log "Моделей: ${#MODELS[@]}, запусків: $RUNS, пакет: --full"
log "Результати: $RESULTS_DIR"
notify "🌙 overnight-bench старт: ${#MODELS[@]} моделей × ${RUNS} запуски (--full)"

for entry in "${MODELS[@]}"; do
  IFS='|' read -r label image model_path ctx kv extra <<< "$entry"

  sep "MODEL: $label"
  log "File:  $model_path"
  log "Image: $image"
  log "ctx=$ctx  kv=$kv"

  model_dir="$RESULTS_DIR/$label"
  mkdir -p "$model_dir"

  # Зупиняємо попередній контейнер
  stop_container

  # Запускаємо контейнер
  log "Запуск контейнера..."

  if [[ "$image" == *"ik-llama"* ]]; then
    # ik-llama: трохи інший синтаксис
    ctx_flags=""
    [[ $ctx -gt 0 ]] && ctx_flags="--ctx-size $ctx"
    eval docker run -d --name "$CONTAINER" \
      --restart no \
      --gpus '"device=0"' \
      -p "$PORT:8080" \
      -v "/data/models:/data/models:ro" \
      "$image" \
      --host 0.0.0.0 --port 8080 \
      -m "$model_path" \
      -ngl 99 \
      $ctx_flags \
      -b 4096 -ub 1024 \
      -np 1 \
      -ctk "$kv" -ctv "$kv" \
      -fa on \
      $extra \
      >> "$model_dir/container.log" 2>&1 || { log "FAIL: docker run"; FAILED_MODELS+=("$label"); MODEL_STATUS[$label]="BOOT_FAIL"; continue; }
  else
    # mainline llama.cpp
    ctx_flags=""
    [[ $ctx -gt 0 ]] && ctx_flags="-c $ctx"
    eval docker run -d --name "$CONTAINER" \
      --restart no \
      --gpus '"device=0"' \
      -p "$PORT:8080" \
      -v "/data/models:/data/models:ro" \
      "$image" \
      --host 0.0.0.0 --port 8080 \
      -m "$model_path" \
      -ngl 99 \
      $ctx_flags \
      -b 4096 -ub 1024 \
      -np 1 \
      --cache-type-k "$kv" --cache-type-v "$kv" \
      -fa on \
      $extra \
      >> "$model_dir/container.log" 2>&1 || { log "FAIL: docker run"; FAILED_MODELS+=("$label"); MODEL_STATUS[$label]="BOOT_FAIL"; continue; }
  fi

  # Чекаємо готовності
  if ! wait_ready; then
    log "BOOT_FAIL: $label"
    docker logs "$CONTAINER" 2>&1 | tail -20 >> "$model_dir/container.log"
    FAILED_MODELS+=("$label")
    MODEL_STATUS[$label]="BOOT_FAIL"
    stop_container
    continue
  fi

  # VRAM після завантаження
  vram=$(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits 2>/dev/null || echo "?,?")
  log "VRAM: $vram MiB (used, free)"

  scores=""
  run_ok=0

  for run in $(seq 1 $RUNS); do
    sep "$label — запуск $run/$RUNS"

    run_json="$model_dir/run${run}.json"
    run_log="$model_dir/run${run}.log"

    # Запускаємо --full через quality-test.sh
    set +e
    URL="$URL" bash "$SCRIPT_DIR/quality-test.sh" \
      --full \
      2>&1 | tee "$run_log"
    exit_code=$?
    set -e

    # Підхоплюємо JSON з автоматично збереженого шляху
    latest_json=$(ls -t "$REPO_ROOT/results/quality/quality-"*.json 2>/dev/null | head -1 || true)
    if [[ -n "$latest_json" && -f "$latest_json" ]]; then
      cp "$latest_json" "$run_json"
      # Парсимо сумарний score по всіх пакетах
      total_passed=$(python3 -c "
import json, sys
d = json.load(open('$run_json'))
packs = d.get('packs', [])
total_p = sum(p.get('passed',0) for p in packs)
total_t = sum(p.get('total',0) for p in packs)
print(f'{total_p}/{total_t}')
" 2>/dev/null || echo "?/?")
      log "Run $run результат: $total_passed"
      scores="$scores $total_passed"
      run_ok=$((run_ok + 1))
    else
      log "WARN: JSON не знайдено після run $run"
      scores="$scores ?/?"
    fi
  done

  MODEL_SCORES[$label]="$scores"
  MODEL_STATUS[$label]="OK ($run_ok/$RUNS runs)"
  notify "✅ $label завершено: $scores"

  stop_container
  log "Модель $label — готово"
done

# ── Фінальний звіт ────────────────────────────────────────────────────────────
sep "SUMMARY"

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

{
  echo "# overnight-bench результати"
  echo ""
  echo "Дата: $(date '+%Y-%m-%d %H:%M')"
  echo "Тривалість: ${ELAPSED} хв"
  echo "Пакет: --full (8 пакетів)"
  echo ""
  echo "## Scores (3 запуски × --full)"
  echo ""
  echo "| Модель | Run 1 | Run 2 | Run 3 | Статус |"
  echo "|---|---|---|---|---|"

  for entry in "${MODELS[@]}"; do
    IFS='|' read -r label _ <<< "$entry"
    sc="${MODEL_SCORES[$label]:-—}"
    st="${MODEL_STATUS[$label]:-—}"
    r1=$(echo $sc | awk '{print $1}')
    r2=$(echo $sc | awk '{print $2}')
    r3=$(echo $sc | awk '{print $3}')
    echo "| $label | $r1 | $r2 | $r3 | $st |"
  done

  echo ""
  if [[ ${#FAILED_MODELS[@]} -gt 0 ]]; then
    echo "## BOOT_FAIL / помилки"
    for m in "${FAILED_MODELS[@]}"; do echo "- $m"; done
  fi

  echo ""
  echo "Детальні JSON: \`$RESULTS_DIR/<model>/run{1,2,3}.json\`"
  echo ""
  echo "\`\`\`bash"
  echo "# Перегляд конкретного запуску:"
  echo "benchlocal-cli inspect $RESULTS_DIR/<model>/run1.json --failed"
  echo "\`\`\`"
} | tee "$SUMMARY"

log ""
log "Звіт збережено: $SUMMARY"

# ── Нотифікація і майнер ──────────────────────────────────────────────────────
notify "🏁 overnight-bench завершено за ${ELAPSED} хв. Результати: $RESULTS_DIR/summary.md"

log "Запуск майнера..."
bash /root/miner-start.sh >> "$LOG" 2>&1 || log "WARN: miner-start.sh завершився з помилкою"

log "Все готово. Перевір $RESULTS_DIR"
