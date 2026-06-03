#!/usr/bin/env bash
# scan-and-bench.sh
# Знаходить нові (ще не тестовані) GGUF моделі в MODEL_DIR,
# запускає кожну, вимірює TPS і проводить hermesagent-20.
#
# Usage:
#   bash scripts/scan-and-bench.sh
#   MODEL_DIR=/data/models bash scripts/scan-and-bench.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="${MODEL_DIR:-/data/models}"
PORT=8019
URL="http://localhost:$PORT"
CONTAINER="scan-and-bench-runner"

TIMESTAMP=$(date +%Y%m%dT%H%M%S)
LOG_DIR="$REPO_ROOT/results/quality"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/scan-bench-$TIMESTAMP.txt"

log()  { echo "[scan-bench] $*" | tee -a "$SUMMARY"; }
sep()  { log ""; log "═══════════════════════════════════════════════════"; log "$*"; log "═══════════════════════════════════════════════════"; }

# ── Вже протестовані — пропускаємо ───────────────────────────────────────────
SKIP=(
  "Carnice-Qwen3.6-MoE-35B-A3B-APEX-MTP-I-Quality.gguf"
  "carnice-v2-27b-Q5_K_M.gguf"
  "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  "NousResearch_Hermes-4.3-36B-Q4_K_M.gguf"
  "agent.xortron-q5_k_m.gguf"
  "Qwopus3.5-9B-coder-Exp-Q5_K_S.gguf"
  "Qwen3.6-27B-DFlash-IQ4_XS.gguf"     # drafter
  "Qwen3.6-27B-Q5_K_S.gguf"             # beellama target
  "Qwen3.6-27B-UD-Q5_K_XL.gguf"
  "Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
  "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
  "Qwen3.6-40B-Deck-Opus-NEO-CODE-HERE-2T-OT-Q4_K_S.gguf"
  "Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf"
  "Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf"
  "zai-org_GLM-4.7-Flash-Q5_K_L.gguf"
  "hermes-qwen3.5-35b-a3b-Q4_K_M.gguf"  # 1.7 GB — MTP head, не повна модель
  "mmproj-F16.gguf"
)

should_skip() {
  local base
  base=$(basename "$1")
  for s in "${SKIP[@]}"; do
    [[ "$base" == "$s" ]] && return 0
  done
  return 1
}

# ── Визначення профілю моделі ─────────────────────────────────────────────────
# Повертає: ctx image extra_flags
model_profile() {
  local path="$1"
  local name
  name=$(basename "$path")
  local size_gb
  size_gb=$(du -BG "$path" | cut -f1 | tr -d 'G')

  local image="ghcr.io/ggml-org/llama.cpp:server-cuda"
  local ctx=32768
  local extra=""

  # MoE моделі (дешевий KV — можна більше ctx)
  if echo "$name" | grep -qiE "(35B-A3B|30B-A3B|MoE|moe)"; then
    ctx=65536
    # Якщо модель >23 GB — треба offload
    if [[ $size_gb -gt 23 ]]; then
      extra='-ot "exps=CPU"'
    fi
  fi

  # MTP моделі
  if echo "$name" | grep -qiE "(MTP|mtp)"; then
    extra="$extra --spec-type draft-mtp --spec-draft-n-max 3"
  fi

  # Занадто великі dense моделі (>22 GB) — менший ctx
  if echo "$name" | grep -qiE "(40B|36B|34B)"; then
    ctx=16384
  fi

  echo "$ctx $image $extra"
}

stop_container() {
  docker stop "$CONTAINER" 2>/dev/null || true
  docker rm   "$CONTAINER" 2>/dev/null || true
}

wait_ready() {
  local tries=0
  until curl -sf "$URL/health" >/dev/null 2>&1; do
    sleep 3
    tries=$((tries + 1))
    if [[ $tries -gt 80 ]]; then
      log "FAIL: container did not become ready after 240s"
      docker logs "$CONTAINER" 2>&1 | tail -20 | tee -a "$SUMMARY"
      return 1
    fi
  done
  sleep 2
}

measure_tps() {
  local start end tokens elapsed
  start=$(date +%s%N)
  local resp
  resp=$(curl -sf "$URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"local","messages":[{"role":"user","content":"Write a short paragraph about artificial intelligence."}],"max_tokens":100,"stream":false,"thinking":false}' \
    2>/dev/null) || { echo "0"; return; }
  end=$(date +%s%N)
  tokens=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['usage']['completion_tokens'])" 2>/dev/null || echo "0")
  elapsed=$(( (end - start) / 1000000 ))
  if [[ $tokens -gt 0 && $elapsed -gt 0 ]]; then
    python3 -c "print(f'{$tokens / ($elapsed / 1000):.1f}')"
  else
    echo "0"
  fi
}

# ── Основний цикл ─────────────────────────────────────────────────────────────
log "scan-and-bench started: $TIMESTAMP"
log "MODEL_DIR: $MODEL_DIR"

RESULTS=()

while IFS= read -r -d '' gguf; do
  name=$(basename "$gguf")
  size_gb=$(du -BG "$gguf" | cut -f1 | tr -d 'G')

  # Пропускаємо вже протестовані
  if should_skip "$gguf"; then
    log "SKIP (already tested): $name"
    continue
  fi

  # Пропускаємо файли <2 GB (drafters, heads)
  if [[ $size_gb -lt 2 ]]; then
    log "SKIP (too small, likely drafter/head): $name (${size_gb}G)"
    continue
  fi

  sep "MODEL: $name  (${size_gb} GB)"

  # Визначаємо профіль
  read -r ctx image extra_flags <<< "$(model_profile "$gguf")"
  log "Profile: ctx=$ctx  image=$(basename $image)  extra=$extra_flags"

  stop_container

  # Запускаємо контейнер
  log "Starting container..."
  eval docker run -d --name "$CONTAINER" \
    --restart no \
    --gpus '"device=0"' \
    -p "$PORT:8080" \
    -v "/data/models:/models:ro" \
    "$image" \
    --host 0.0.0.0 --port 8080 \
    --model "/models/${gguf#$MODEL_DIR/}" \
    -ngl 99 \
    --ctx-size "$ctx" \
    -b 4096 -ub 1024 \
    -ctk q4_0 -ctv q4_0 -fa on \
    --jinja \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
    $extra_flags \
    >> "$SUMMARY" 2>&1 || { log "FAIL: docker run failed"; continue; }

  # Чекаємо готовності
  if ! wait_ready; then
    stop_container
    RESULTS+=("❌ BOOT_FAIL | $name")
    continue
  fi

  # Вимірюємо TPS
  log "Measuring TPS..."
  tps=$(measure_tps)
  log "TPS: $tps"

  if [[ "$tps" == "0" ]]; then
    log "WARN: model returned no tokens — possible template issue"
    stop_container
    RESULTS+=("⚠️  NO_OUTPUT | $name | 0 TPS")
    continue
  fi

  # Пропускаємо hermesagent якщо дуже повільна (< 15 TPS = timeout hell)
  if python3 -c "import sys; sys.exit(0 if float('$tps') >= 15 else 1)"; then
    # Запускаємо hermesagent-20
    sep "$name — hermesagent-20"
    log "Running hermesagent-20 (TPS=$tps)..."
    hermes_out="$LOG_DIR/scan-hermes-${name%%.gguf}-$TIMESTAMP.json"
    set +e
    CONTAINER="$CONTAINER" URL="$URL" \
      bash "$SCRIPT_DIR/quality-test.sh" \
      --pack hermesagent-20 \
      2>&1 | tee -a "$SUMMARY"
    hermes_exit=$?
    set -e

    # Парсимо score з останнього рядка
    score=$(grep -oP '\d+ / 20 \| \d+%' "$SUMMARY" | tail -1 || echo "?")
    log "hermesagent-20 result: $score"
    RESULTS+=("✅ $tps TPS | $score | $name")
  else
    log "SKIP hermesagent: TPS=$tps < 15 (would timeout on every scenario)"
    RESULTS+=("⚠️  TOO_SLOW ($tps TPS) | $name")
  fi

  stop_container
  log "Done: $name"

done < <(find "$MODEL_DIR" -name "*.gguf" -not -path "*/.cache/*" -print0 | sort -z)

# ── Фінальний звіт ────────────────────────────────────────────────────────────
sep "RESULTS SUMMARY"
for r in "${RESULTS[@]}"; do
  log "  $r"
done
log ""
log "Full log: $SUMMARY"
