#!/usr/bin/env bash
# power-sweep.sh — RTX 3090 power/clock sweep for LLM serving
#
# Measures decode TPS + prefill TPS at each power limit step.
# Finds the "knee": lowest wattage where both stay within tolerance.
#
# Usage:
#   bash scripts/power-sweep.sh [--port PORT] [--steps "350 320 300 280 260 240"]
#   bash scripts/power-sweep.sh --restore   # reset to 350W and exit
#
# Requires: running llama.cpp server (e.g. run-carnice-v2-27b.sh)
#           nvidia-smi with root or nvidia permission group
#           jq (apt install jq)

set -euo pipefail

PORT="${PORT:-8021}"
GPU_IDX="${GPU:-0}"
TOLERANCE="${TOLERANCE:-5}"       # % TPS drop to flag as "knee"
DECODE_TOKENS=200                 # tokens to generate for decode bench
PREFILL_WORDS=3000                # ~20K tokens (Carnice: ~6.5 chars/token)
WARMUP_TOKENS=50
RESULTS_FILE="${RESULTS_FILE:-/tmp/power-sweep-results.tsv}"

STEPS=(350 320 300 280 260 240 220 200)
RESTORE=false

# ---- arg parse ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)       PORT="$2"; shift 2 ;;
    --steps)      IFS=' ' read -r -a STEPS <<< "$2"; shift 2 ;;
    --tolerance)  TOLERANCE="$2"; shift 2 ;;
    --restore)    RESTORE=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ---- helpers -----------------------------------------------------------------
log()   { echo -e "\033[0;36m[sweep]\033[0m $*"; }
warn()  { echo -e "\033[0;33m[warn]\033[0m $*"; }
ok()    { echo -e "\033[0;32m[ok]\033[0m $*"; }
err()   { echo -e "\033[0;31m[err]\033[0m $*" >&2; }

set_power() {
  local w="$1"
  nvidia-smi -pl "$w" -i "$GPU_IDX" &>/dev/null || {
    warn "nvidia-smi -pl failed (need root?). Trying sudo..."
    sudo nvidia-smi -pl "$w" -i "$GPU_IDX"
  }
}

gpu_clocks() {
  nvidia-smi --query-gpu=clocks.mem,clocks.sm,power.draw \
    --format=csv,noheader,nounits -i "$GPU_IDX" 2>/dev/null
}

wait_server() {
  local deadline=$(( SECONDS + 20 ))
  until curl -sf "http://localhost:${PORT}/v1/models" &>/dev/null; do
    [[ $SECONDS -ge $deadline ]] && { err "Server not up on :${PORT}"; exit 1; }
    sleep 1
  done
}

# Generate $1 words of lorem-style text for prefill prompt
gen_prefill() {
  local words="$1"
  python3 -c "
import sys, random, string
random.seed(42)
vocab=['the','quick','brown','fox','jumps','over','lazy','dog','and','then','returned','to','its','lair','deep','in','forest','where','ancient','oaks','stood','tall','beside','silver','stream','that','wound','through','valley','carrying','snowmelt','from','distant','mountains','toward','sea']
print(' '.join(random.choice(vocab) for _ in range($words)))
"
}

# Returns decode_tps prefill_tps from a completion call
# Uses llama.cpp /v1/completions with timing stats
bench_once() {
  local prompt="$1"
  local n_gen="$2"
  # llama.cpp returns timing in timings{} field
  local resp
  resp=$(curl -sf "http://localhost:${PORT}/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"prompt\": \"$(echo "$prompt" | sed 's/"/\\"/g' | head -c 32000)\",
      \"n_predict\": ${n_gen},
      \"temperature\": 0.0,
      \"cache_prompt\": false
    }" --max-time 120) || { err "Request failed"; echo "0 0"; return; }

  local pt pp_tok pp_ms tg_tok tg_ms
  pt=$(echo "$resp" | jq -r '.timings.prompt_n // 0')
  pp_ms=$(echo "$resp" | jq -r '.timings.prompt_ms // 0')
  tg_tok=$(echo "$resp" | jq -r '.timings.predicted_n // 0')
  tg_ms=$(echo "$resp" | jq -r '.timings.predicted_ms // 0')

  local prefill_tps decode_tps
  prefill_tps=$(awk "BEGIN { printf \"%.1f\", ($pt > 0 && $pp_ms > 0) ? $pt / ($pp_ms/1000) : 0 }")
  decode_tps=$(awk "BEGIN { printf \"%.1f\", ($tg_tok > 0 && $tg_ms > 0) ? $tg_tok / ($tg_ms/1000) : 0 }")

  echo "$decode_tps $prefill_tps"
}

# ---- restore mode ------------------------------------------------------------
if $RESTORE; then
  set_power 350
  ok "Power limit restored to 350W"
  nvidia-smi --query-gpu=power.limit,clocks.mem,clocks.sm --format=csv,noheader -i "$GPU_IDX"
  exit 0
fi

# ---- preflight ---------------------------------------------------------------
command -v jq &>/dev/null || { err "jq not found — apt install jq"; exit 1; }
command -v nvidia-smi &>/dev/null || { err "nvidia-smi not found"; exit 1; }
wait_server

log "Carnice-27B power sweep — GPU $GPU_IDX, port $PORT"
log "Steps: ${STEPS[*]} W | decode_n=$DECODE_TOKENS | prefill_words=$PREFILL_WORDS"
log "Tolerance flag at >${TOLERANCE}% drop from 350W baseline"
echo ""

PREFILL_PROMPT=$(gen_prefill "$PREFILL_WORDS")

# Warm-up at current power (avoids cold JIT penalty on first bench)
log "Warming up (${WARMUP_TOKENS} tok)..."
bench_once "Hello, tell me about yourself." "$WARMUP_TOKENS" &>/dev/null || true
sleep 2

# ---- baseline at 350W --------------------------------------------------------
log "Baseline at 350W..."
set_power 350
sleep 3

CLOCKS_350=$(gpu_clocks)
MEM_350=$(echo "$CLOCKS_350" | cut -d',' -f1 | tr -d ' ')
SM_350=$(echo "$CLOCKS_350" | cut -d',' -f2 | tr -d ' ')

read -r DEC_350 PRE_350 < <(bench_once "$PREFILL_PROMPT" "$DECODE_TOKENS")
sleep 1
read -r DEC_350b PRE_350b < <(bench_once "$PREFILL_PROMPT" "$DECODE_TOKENS")
DEC_BASE=$(awk "BEGIN { printf \"%.1f\", ($DEC_350 + $DEC_350b)/2 }")
PRE_BASE=$(awk "BEGIN { printf \"%.1f\", ($PRE_350 + $PRE_350b)/2 }")

ok "Baseline — decode: ${DEC_BASE} t/s | prefill: ${PRE_BASE} t/s | mem: ${MEM_350} MHz | sm: ${SM_350} MHz"
echo ""

# ---- result table header -----------------------------------------------------
printf "%-7s %-10s %-12s %-12s %-10s %-10s %-10s %-10s\n" \
  "PLim(W)" "Actual(W)" "Decode(t/s)" "Prefill(t/s)" "Dec_drop%" "Pre_drop%" "Mem(MHz)" "SM(MHz)"
printf '%s\n' "$(printf '%.0s-' {1..90})"

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "PLim_W" "Actual_W" "Decode_tps" "Prefill_tps" "Dec_drop_pct" "Pre_drop_pct" "Mem_MHz" "SM_MHz" \
  > "$RESULTS_FILE"

KNEE_WATT=""
KNEE_REASON=""

# ---- sweep -------------------------------------------------------------------
for PL in "${STEPS[@]}"; do
  log "Setting ${PL}W..."
  set_power "$PL"
  sleep 4   # allow clocks to settle

  CLOCKS=$(gpu_clocks)
  MEM_MHZ=$(echo "$CLOCKS" | cut -d',' -f1 | tr -d ' ')
  SM_MHZ=$(echo "$CLOCKS" | cut -d',' -f2 | tr -d ' ')
  ACTUAL_W=$(echo "$CLOCKS" | cut -d',' -f3 | tr -d ' ')

  # Two runs, average
  read -r DEC1 PRE1 < <(bench_once "$PREFILL_PROMPT" "$DECODE_TOKENS")
  sleep 1
  read -r DEC2 PRE2 < <(bench_once "$PREFILL_PROMPT" "$DECODE_TOKENS")

  # Sample clocks DURING decode (after the bench is warm)
  CLOCKS_HOT=$(gpu_clocks)
  MEM_HOT=$(echo "$CLOCKS_HOT" | cut -d',' -f1 | tr -d ' ')
  SM_HOT=$(echo "$CLOCKS_HOT" | cut -d',' -f2 | tr -d ' ')

  DEC_AVG=$(awk "BEGIN { printf \"%.1f\", ($DEC1 + $DEC2)/2 }")
  PRE_AVG=$(awk "BEGIN { printf \"%.1f\", ($PRE1 + $PRE2)/2 }")

  DEC_DROP=$(awk "BEGIN { printf \"%.1f\", ($DEC_BASE > 0) ? (1 - $DEC_AVG/$DEC_BASE)*100 : 0 }")
  PRE_DROP=$(awk "BEGIN { printf \"%.1f\", ($PRE_BASE > 0) ? (1 - $PRE_AVG/$PRE_BASE)*100 : 0 }")

  FLAG=""
  if awk "BEGIN { exit ($DEC_DROP > $TOLERANCE || $PRE_DROP > $TOLERANCE) ? 0 : 1 }"; then
    FLAG="  ← KNEE"
    [[ -z "$KNEE_WATT" ]] && { KNEE_WATT="$PL"; KNEE_REASON="dec -${DEC_DROP}% pre -${PRE_DROP}%"; }
  fi

  printf "%-7s %-10s %-12s %-12s %-10s %-10s %-10s %-10s%s\n" \
    "${PL}W" "${ACTUAL_W}W" "${DEC_AVG}" "${PRE_AVG}" \
    "-${DEC_DROP}%" "-${PRE_DROP}%" "${MEM_HOT}" "${SM_HOT}" "$FLAG"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$PL" "$ACTUAL_W" "$DEC_AVG" "$PRE_AVG" "$DEC_DROP" "$PRE_DROP" "$MEM_HOT" "$SM_HOT" \
    >> "$RESULTS_FILE"

  sleep 2
done

# ---- summary -----------------------------------------------------------------
echo ""
printf '%s\n' "$(printf '%.0s=' {1..90})"
echo "SUMMARY"
printf '%s\n' "$(printf '%.0s=' {1..90})"

if [[ -n "$KNEE_WATT" ]]; then
  # Step ABOVE the knee is the safe minimum
  SAFE_WATT=""
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" -eq "$KNEE_WATT" && $i -gt 0 ]] && SAFE_WATT="${STEPS[$((i-1))]}"
  done
  [[ -z "$SAFE_WATT" ]] && SAFE_WATT="$KNEE_WATT"

  warn "Knee detected at ${KNEE_WATT}W (${KNEE_REASON})"
  ok  "Recommended power limit: ${SAFE_WATT}W  (one step above the knee)"
  echo ""
  echo "  To apply permanently:"
  echo "    sudo nvidia-smi -pl ${SAFE_WATT}"
  echo "    # or add to /etc/rc.local for persistence across reboots"
  echo ""
  echo "  Restore to 350W:"
  echo "    bash scripts/power-sweep.sh --restore"
else
  ok "No knee found — TPS within ${TOLERANCE}% at all steps down to ${STEPS[-1]}W"
  LAST="${STEPS[-1]}"
  ok "Recommended power limit: ${LAST}W"
  echo ""
  echo "  To apply:"
  echo "    sudo nvidia-smi -pl ${LAST}"
fi

echo ""
log "Full results saved to: $RESULTS_FILE"
echo ""

# Leave the GPU at the safe/recommended wattage (not 350W) at exit
# Comment out the next line to restore 350W after sweep
# set_power 350
