#!/usr/bin/env bash
# power-cap-sweep.sh — Power-cap A/B sweep for cross-rig efficiency-knee data
#
# Why this exists:
#   3090 sweet spot is ~330W (5% TPS loss vs ~388W stock for ~15% power
#   reduction — see @syangsao's three-cap data on issue #58). For other GPU
#   classes (4090, 5090, A5000, A6000, modded variants) the knee differs and
#   has to be measured. This script automates the sweep so contributors can
#   produce comparable cross-rig numbers without hand-editing nvidia-smi
#   commands and bench invocations.
#
# Usage:
#   sudo bash scripts/power-cap-sweep.sh                          # comprehensive sweep at 10W increments (matches @laurimyllari resolution)
#   sudo bash scripts/power-cap-sweep.sh --step-size 20           # coarser sweep (~half runtime)
#   sudo bash scripts/power-cap-sweep.sh --caps 260,280,300       # explicit caps (overrides auto-derive)
#   sudo bash scripts/power-cap-sweep.sh --gpu 1                  # specific GPU index
#   sudo bash scripts/power-cap-sweep.sh --cooling water          # tag the run as water-cooled
#   sudo bash scripts/power-cap-sweep.sh --cooling air            # tag as air-cooled
#   sudo bash scripts/power-cap-sweep.sh --cooling aio            # tag as AIO/closed-loop
#   sudo bash scripts/power-cap-sweep.sh --load-mode decode-concurrent --concurrency 8
#   sudo bash scripts/power-cap-sweep.sh --load-mode prefill-heavy
#   sudo bash scripts/power-cap-sweep.sh --no-reset               # leave at last cap (you reset manually)
#
# Load modes:
#   decode-single:
#     Original single-stream bench.sh path. Best for continuity with existing
#     contributor data, and enough to expose the efficiency knee on cards where
#     this workload already loads compute well (3090 / 4090).
#
#   decode-concurrent:
#     Runs N concurrent chat completions and reports aggregate decode TPS. Use
#     this for realistic multi-request serving load, especially on larger cards
#     where decode-single is under-loaded and produces flat power curves.
#
#     ⚠️ VARIANCE CAVEAT: decode-concurrent runs n=1 measurement per cap (one
#     batch of N concurrent requests for narr, one for code). Aggregate TPS
#     can vary 10-30% between back-to-back runs at the SAME cap because vLLM's
#     continuous-batching window is timing-sensitive — whether N requests
#     batch together vs queue sequentially depends on arrival jitter. Single
#     caps may show TPS going the "wrong direction" between adjacent caps.
#     For cross-rig anchor data, prefer one of: (a) bump --concurrency to 8
#     or 16 so per-stream noise averages out; (b) run the sweep 2-3 times
#     and median per cap; (c) read curve shape across the full 30-cap sweep
#     instead of comparing adjacent caps.
#
#   prefill-heavy:
#     Sends one large prompt with a tiny decode tail and reports prompt prefill
#     TPS. This is the cleanest intrinsic compute curve when decode workloads
#     are too small to move the card. Lower variance than decode-concurrent
#     (single request per cap, no batching jitter; nonce defeats prefix-cache
#     reuse between caps).
#
# Per-card starting points:
#   3090 / 4090: decode-single or decode-concurrent both usually surface a knee.
#   5090:        decode-concurrent N=8+ recommended.
#   RTX PRO 6000: prefill-heavy or decode-concurrent N=16+, preferably with a
#                 larger model than 27B if the endpoint can schedule it.
#
# Default sweep behavior:
#   Without --caps, the script reads power.min_limit and power.max_limit and
#   generates caps at 10W increments across the entire envelope. This matches
#   @laurimyllari's reference resolution that produced the cleanest 4090 curve.
#
#   Each cap runs a reduced bench (WARMUPS=1 RUNS=2 with 500/400 max_tokens),
#   targeting ~30s/cap of sustained load — enough for the power sampler to
#   collect 50+ under-load samples for a stable median. Per-card estimates:
#
#     3090 (100-388W) →  30 caps  ~15 min
#     4090 (150-450W) →  31 caps  ~16 min
#     5090 (250-575W) →  33 caps  ~17 min
#     A5000 (100-230W) → 14 caps  ~7 min
#
#   At heavily-throttled caps (e.g. 100W on a 3090), bench runs slower and
#   the per-cap time can stretch to ~50-60s, so total runtime is ~20 min on
#   a typical sweep. For zooming into a known-good region, use --caps
#   260,280,300 explicitly. For coarser sweeps, --step-size 20.
#
# Output:
#   - Per-cap bench logs at /tmp/power-cap-N{wattage}.log
#   - Markdown summary at /tmp/power-cap-summary.md (paste into GitHub issue/discussion)
#
# Requires sudo for `nvidia-smi -pl`. Auto-detects running container + URL +
# MODEL via the same logic as bench.sh.
#
# Why --cooling matters:
#   Air-cooled cards thermal-throttle around 80-83°C, capping effective
#   sustained power at ~310-340W on a 3090 regardless of the software cap.
#   Water-cooled / AIO cards hold lower temps (~50-65°C) and sustain full
#   board power. Same software cap on different cooling produces different
#   real curves — recording the cooling class is essential for cross-rig
#   comparison. The script does NOT auto-detect this; you must specify.

set -euo pipefail

# Defaults — override via flags
GPU_INDEX=0
CAPS=""              # empty → auto-derive from card's min/max power limits at STEP_SIZE granularity
RESET=1              # 1 = reset to stock at end; 0 = leave at last cap
COOLING="unspecified" # air|water|aio|unspecified — affects how to read the data
STEP_SIZE=10          # increment in W between caps when --caps not specified (10W matches @laurimyllari's resolution)
LOAD_MODE="decode-single"   # decode-single | decode-concurrent | prefill-heavy
CONCURRENCY=4         # parallel streams when LOAD_MODE=decode-concurrent (matches typical compose --max-num-seqs)

while [ $# -gt 0 ]; do
  case "$1" in
    --gpu)         GPU_INDEX="$2"; shift 2 ;;
    --caps)        CAPS="$2"; shift 2 ;;
    --cooling)     COOLING="$2"; shift 2 ;;
    --step-size)   STEP_SIZE="$2"; shift 2 ;;
    --load-mode)   LOAD_MODE="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --no-reset)    RESET=0; shift ;;
    -h|--help)
      sed -n '1,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *)             echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Validate --load-mode value
case "$LOAD_MODE" in
  decode-single|decode-concurrent|prefill-heavy) ;;
  *) echo "[error] --load-mode must be one of: decode-single, decode-concurrent, prefill-heavy" >&2; exit 1 ;;
esac
if ! [[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] --concurrency must be a positive integer" >&2
  exit 1
fi

# Validate --cooling value
case "$COOLING" in
  air|water|aio|unspecified) ;;
  *) echo "[error] --cooling must be one of: air, water, aio (or omit for 'unspecified')" >&2; exit 1 ;;
esac

if [ "$COOLING" = "unspecified" ]; then
  echo "[warn] --cooling not specified. Cooling class is essential context for interpreting"
  echo "[warn] the efficiency knee (air-cooled cards thermal-throttle, water-cooled don't)."
  echo "[warn] Consider re-running with: --cooling air|water|aio"
  echo
fi

# Sanity checks
if [ "$EUID" -ne 0 ]; then
  echo "[error] must run as root (nvidia-smi -pl requires sudo)" >&2
  echo "[hint]  rerun with: sudo bash scripts/power-cap-sweep.sh ..." >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "[error] nvidia-smi not found in PATH" >&2; exit 1
fi

# Determine paths — script may be invoked from anywhere
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$REPO_ROOT/scripts/bench.sh"
if [ ! -x "$BENCH" ]; then
  echo "[error] expected $BENCH" >&2; exit 1
fi

# Auto-detect URL/CONTAINER/MODEL from the running engine.
# This must happen BEFORE we exec bench.sh under our sudo context — bench.sh's
# own autodetect doesn't reliably fire when re-invoked under sudo (env vars
# get stripped, defaults kick in, wrong MODEL → HTTP 404 against the server).
if [ -z "${CONTAINER:-}" ] || [ -z "${URL:-}" ]; then
  if [[ -f "$REPO_ROOT/scripts/preflight.sh" ]]; then
    # shellcheck source=preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    preflight_autodetect_endpoint || true
  fi
fi

# preflight_autodetect_endpoint only sets URL + CONTAINER, not MODEL.
# Query the live /v1/models endpoint to derive the served model name.
if [ -z "${MODEL:-}" ] && [ -n "${URL:-}" ]; then
  MODEL=$(curl -sf --max-time 5 "${URL}/v1/models" 2>/dev/null \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "")
fi

# CONTAINER is OPTIONAL — host engine builds (e.g. llama.cpp host server, see
# club-3090#85, #87) have no container. URL + MODEL are the only hard
# requirements. If CONTAINER is unset we mark it "none" for display, which is
# also the value bench.sh expects to skip its docker-log scrape cleanly.
if [ -z "${CONTAINER:-}" ]; then
  CONTAINER="none"
fi

if [ -z "${URL:-}" ] || [ -z "${MODEL:-}" ]; then
  echo "[error] could not auto-detect a running URL + MODEL." >&2
  echo "[hint]  start a model server first (bash scripts/switch.sh <variant>)" >&2
  echo "[hint]  or pass URL=http://... MODEL=name as env vars" >&2
  echo "[hint]  CONTAINER is optional — set CONTAINER=none for host builds" >&2
  echo "[got]   URL='${URL:-}' CONTAINER='${CONTAINER:-}' MODEL='${MODEL:-}'" >&2
  exit 1
fi
export URL CONTAINER MODEL
echo "[setup] target:   container=$CONTAINER url=$URL model=$MODEL"

# Capture card's power envelope (so we can reset cleanly + auto-derive sweep range)
STOCK_TDP=$(nvidia-smi --query-gpu=power.default_limit --format=csv,noheader,nounits -i "$GPU_INDEX" | head -1 | tr -d ' ')
MIN_LIMIT=$(nvidia-smi --query-gpu=power.min_limit     --format=csv,noheader,nounits -i "$GPU_INDEX" | head -1 | tr -d ' ')
MAX_LIMIT=$(nvidia-smi --query-gpu=power.max_limit     --format=csv,noheader,nounits -i "$GPU_INDEX" | head -1 | tr -d ' ')
GPU_NAME=$(nvidia-smi --query-gpu=name                  --format=csv,noheader            -i "$GPU_INDEX" | head -1)
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total          --format=csv,noheader,nounits     -i "$GPU_INDEX" | head -1 | tr -d ' ')

SAMPLER_PID=""
cleanup() {
  if [ -n "${SAMPLER_PID:-}" ]; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
    SAMPLER_PID=""
  fi
  if [ "${RESET:-1}" -eq 1 ] && [ -n "${STOCK_TDP:-}" ]; then
    nvidia-smi -pl "$STOCK_TDP" -i "$GPU_INDEX" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

# If --caps not specified, derive a sweep at STEP_SIZE-W increments across the
# card's operating range. 10W default matches @laurimyllari's reference
# resolution that produced the cleanest 4090 curve. Works on any card class:
#   3090 (100-388W) →  30 caps  (~60 min runtime at 2 min/cap)
#   4090 (150-450W) →  31 caps  (~62 min runtime)
#   5090 (250-575W) →  33 caps  (~66 min runtime)
#   A5000 (100-230W) → 14 caps  (~30 min runtime)
# For a quicker first-look use --step-size 20 (cuts runtime in half) or
# --caps 260,280,300 (zoom into a known-good region).
if [ -z "$CAPS" ]; then
  CAPS=$(python3 -c "
min_l = int(float('${MIN_LIMIT%.*}'))
max_l = int(float('${MAX_LIMIT%.*}'))
step = max(1, int('${STEP_SIZE}'))
# Round min UP to nearest step boundary, max DOWN — keeps caps clean multiples of step.
start = ((min_l + step - 1) // step) * step
end   = (max_l // step) * step
caps = list(range(start, end + 1, step))
# Always include the exact max_limit at the end if rounding clipped it (so we
# capture the stock-or-near anchor).
if caps[-1] != max_l:
    caps.append(max_l)
print(','.join(str(c) for c in caps))
")
  AUTO_DERIVED=1
else
  AUTO_DERIVED=0
fi
NUM_CAPS=$(echo "$CAPS" | tr ',' '\n' | wc -l | tr -d ' ')
# ~30s/cap including settle + bench (1 warmup + 2 runs × 500+400 tokens).
EST_MIN=$(( (NUM_CAPS * 30 + 59) / 60 ))

echo "[setup] GPU $GPU_INDEX: $GPU_NAME ($GPU_VRAM MiB)"
echo "[setup] power envelope: ${MIN_LIMIT}W (min) → ${STOCK_TDP}W (default) → ${MAX_LIMIT}W (max)"
echo "[setup] cooling:   $COOLING"
if [ "$AUTO_DERIVED" -eq 1 ]; then
  echo "[setup] sweep caps: $NUM_CAPS caps in ${STEP_SIZE}W increments (override via --caps or --step-size)"
  echo "[setup]            $CAPS W"
else
  echo "[setup] sweep caps: $NUM_CAPS caps (user-specified)"
  echo "[setup]            $CAPS W"
fi
echo "[setup] load mode: $LOAD_MODE$([ "$LOAD_MODE" = "decode-concurrent" ] && echo " (concurrency=$CONCURRENCY)")"
echo "[setup] estimated runtime: ~${EST_MIN} min (${NUM_CAPS} caps × ~30s/cap)"
echo "[setup] reset at end: $([ $RESET -eq 1 ] && echo yes || echo no)"
echo

if [ "$LOAD_MODE" = "decode-concurrent" ]; then
  echo "[check] decode-concurrent scheduling check (best effort, N=${CONCURRENCY})"
  echo "[check] /v1/models usually exposes max_model_len, not max_num_seqs; probing with tiny concurrent requests."
  PROBE_DIR=$(mktemp -d /tmp/power-cap-concurrency-probe.XXXXXX)
  PROBE_PIDS=()
  for i in $(seq 1 "$CONCURRENCY"); do
    REQ_FILE="$PROBE_DIR/req-${i}.json"
    python3 - "$REQ_FILE" "$MODEL" <<'PY'
import json
import sys

path, model = sys.argv[1:3]
body = {
    "model": model,
    "messages": [{"role": "user", "content": "hi"}],
    "max_tokens": 1,
    "temperature": 0,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f)
PY
    (
      curl -sS -o "$PROBE_DIR/out-${i}.json" -w "%{http_code}" --max-time 30 \
        "${URL}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "@${REQ_FILE}" > "$PROBE_DIR/code-${i}.txt"
    ) &
    PROBE_PIDS+=("$!")
  done
  PROBE_FAILS=0
  for pid in "${PROBE_PIDS[@]}"; do
    if ! wait "$pid"; then
      PROBE_FAILS=$((PROBE_FAILS + 1))
    fi
  done
  PROBE_BAD_CODES=$(python3 - "$PROBE_DIR" "$CONCURRENCY" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
n = int(sys.argv[2])
bad = []
for i in range(1, n + 1):
    p = root / f"code-{i}.txt"
    code = p.read_text().strip() if p.exists() else "curl-failed"
    if code != "200":
        bad.append(f"{i}:{code}")
print(",".join(bad))
PY
)
  if [ "$PROBE_FAILS" -gt 0 ] || [ -n "$PROBE_BAD_CODES" ]; then
    echo "[warn] concurrency probe had failures/non-200 responses: pids=${PROBE_FAILS}, http=${PROBE_BAD_CODES:-none}"
    echo "[warn] If the sweep reports 503/timeouts, lower --concurrency or raise compose --max-num-seqs."
  else
    echo "[check] concurrency probe passed at N=${CONCURRENCY}"
  fi
  rm -rf "$PROBE_DIR"
  echo
fi

# Persistence mode (one-time; idempotent)
nvidia-smi -pm 1 -i "$GPU_INDEX" >/dev/null 2>&1 || true

# Sweep
RESULTS_FILE=/tmp/power-cap-summary.md
{
  echo "# Power-cap sweep — $GPU_NAME (GPU $GPU_INDEX)"
  echo ""
  echo "**GPU:** $GPU_NAME &nbsp; **VRAM:** ${GPU_VRAM} MiB &nbsp; **Stock TDP:** ${STOCK_TDP}W &nbsp; **Cooling:** ${COOLING}"
  echo "**Model:** \`${MODEL}\` &nbsp; **Engine:** \`${CONTAINER}\` &nbsp; **Endpoint:** ${URL}"
  echo "**Load mode:** \`${LOAD_MODE}\`$([ "$LOAD_MODE" = "decode-concurrent" ] && echo " (concurrency=${CONCURRENCY})")"
  echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%S)Z"
  echo ""
  if [ "$COOLING" = "unspecified" ]; then
    echo "> ⚠️  Cooling class not specified at run time. Add **air / water / AIO** when posting"
    echo "> this data — water-cooled cards sustain full board power; air-cooled thermal-throttle"
    echo "> at ~80-83 °C and may cap below the software limit regardless of \`-pl\` setting."
    echo ""
  fi
  echo "> Cross-rig comparisons require **matching model + engine class** — TPS scales with"
  echo "> model size and quant (e.g. Qwen3.6-27B-AutoRound at 30 TPS, Gemma-4-31B-AutoRound +"
  echo "> MTP at 100 TPS). The *shape* of the efficiency knee is the cross-rig signal; absolute"
  echo "> numbers only compare like-to-like."
  echo ""
  echo "| Cap (W) | Narr wall TPS | Code wall TPS | Actual power (W) | GPU temp (°C) | TPS/W (narr) |"
  echo "|--------:|--------------:|--------------:|-----------------:|--------------:|-------------:|"
} > "$RESULTS_FILE"

IFS=',' read -ra CAP_ARRAY <<< "$CAPS"
for CAP in "${CAP_ARRAY[@]}"; do
  CAP=$(echo "$CAP" | tr -d ' ')
  echo "================================================"
  echo "=== Cap: ${CAP}W (GPU $GPU_INDEX) ==="
  echo "================================================"

  # Apply cap
  if ! nvidia-smi -pl "$CAP" -i "$GPU_INDEX" 2>&1 | tail -1; then
    echo "[warn] failed to set ${CAP}W — skipping"
    continue
  fi

  # Verify cap applied
  ACTUAL_LIMIT=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits -i "$GPU_INDEX" | head -1 | tr -d ' ')
  echo "[verify] limit set to: ${ACTUAL_LIMIT}W"
  echo

  # Brief settle (let driver re-clock)
  sleep 3

  # Start background power-draw sampler at 0.5s intervals.
  # Capturing under-load power requires sampling DURING bench runs — bench.sh's
  # final "GPU state" line samples after all runs complete and may catch the
  # card mid-idle (~40W) instead of under load (~330W). The sampler writes
  # CSV: index, utilization%, power.draw_W, temp_C — we post-process for
  # median power across samples where utilization > 50% (under-load median).
  SAMPLE_FILE="/tmp/power-cap-N${CAP}-samples.csv"
  (
    while true; do
      nvidia-smi --query-gpu=index,utilization.gpu,power.draw,temperature.gpu \
        --format=csv,noheader,nounits -i "$GPU_INDEX" 2>/dev/null | head -1
      sleep 0.5
    done
  ) > "$SAMPLE_FILE" &
  SAMPLER_PID=$!

  # Run bench at reduced precision for sweep efficiency.
  # Canonical bench.sh uses WARMUPS=3 RUNS=5 + 1000/800 max_tokens =
  # 8 × (1000+800) tokens = ~14k tokens × ~10ms/token = ~2 min/cap.
  # For sweep purposes we don't need ±0.5% TPS precision — we need the curve
  # shape and stable under-load power readings. With WARMUPS=1 RUNS=2 +
  # 500/400 max_tokens = 3 × 900 tokens = 2,700 tokens → ~25-35s/cap on a
  # mid-range card, ~50s on a heavily-power-starved cap. That's enough
  # sustained load for the sampler to collect 50+ under-load samples for
  # a stable median.
  LOG_FILE="/tmp/power-cap-N${CAP}.log"
  case "$LOAD_MODE" in
    decode-single)
      # Single-stream: original bench.sh path. Captures decode-bottleneck on
      # cards where compute is the limit (3090, 4090); shows flat curve on
      # cards over-provisioned for the workload (5090 + small models).
      echo "[bench] decode-single @ ${CAP}W cap (output: $LOG_FILE)"
      if ! WARMUPS=1 RUNS=2 MAX_TOKENS_NARR=500 MAX_TOKENS_CODE=400 \
           bash "$BENCH" 2>&1 | tee "$LOG_FILE" | tail -8; then
        kill $SAMPLER_PID 2>/dev/null || true
        wait $SAMPLER_PID 2>/dev/null || true
        SAMPLER_PID=""
        echo "[warn] bench.sh failed at ${CAP}W"
        continue
      fi
      kill $SAMPLER_PID 2>/dev/null || true
      wait $SAMPLER_PID 2>/dev/null || true
      SAMPLER_PID=""
      echo

      # Extract from bench summary lines
      NARR_TPS=$(grep -A1 "summary \[narrative\]" "$LOG_FILE" | grep "wall_TPS" | head -1 | grep -oE 'mean= *[0-9]+\.[0-9]+' | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "?")
      CODE_TPS=$(grep -A1 "summary \[code\]"      "$LOG_FILE" | grep "wall_TPS" | head -1 | grep -oE 'mean= *[0-9]+\.[0-9]+' | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "?")
      ;;

    decode-concurrent)
      # Concurrent decode: spawn $CONCURRENCY parallel chat-completions.
      # Aggregates under vLLM's continuous batching → higher compute pressure
      # than single-stream → exposes compute-knee on cards that are
      # over-provisioned for single-stream (5090 + Qwen3.6-27B). Reports
      # AGGREGATE TPS (sum across all streams) so the column is directly
      # comparable across caps but NOT directly comparable to decode-single
      # numbers (different metric).
      echo "[bench] decode-concurrent @ ${CAP}W cap, N=${CONCURRENCY} (output: $LOG_FILE)"
      : > "$LOG_FILE"
      # Narrative: spawn N parallel curls, each generating 500 tokens.
      # Track curl PIDs explicitly. Plain `wait` would also wait on the
      # infinite power sampler and hang forever.
      CURL_PIDS=()
      START_NS_NARR=$(date +%s%N)
      for i in $(seq 1 "$CONCURRENCY"); do
        REQ_FILE="/tmp/power-cap-N${CAP}-narr-${i}.req.json"
        python3 - "$REQ_FILE" "$MODEL" <<'PY'
import json
import sys

path, model = sys.argv[1:3]
body = {
    "model": model,
    "messages": [{
        "role": "user",
        "content": "Write a detailed 800-word essay explaining transformer attention.",
    }],
    "max_tokens": 500,
    "temperature": 0.6,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f)
PY
        curl -sS -f --max-time 120 "${URL}/v1/chat/completions" \
          -H 'Content-Type: application/json' \
          -d "@${REQ_FILE}" \
          -o "/tmp/power-cap-N${CAP}-narr-${i}.json" 2>>"$LOG_FILE" &
        CURL_PIDS+=("$!")
      done
      CURL_FAILS=0
      for pid in "${CURL_PIDS[@]}"; do
        if ! wait "$pid"; then
          CURL_FAILS=$((CURL_FAILS + 1))
        fi
      done
      END_NS_NARR=$(date +%s%N)
      if [ "$CURL_FAILS" -gt 0 ]; then
        echo "[warn] narrative concurrent curl failures: $CURL_FAILS / $CONCURRENCY" | tee -a "$LOG_FILE"
      fi
      NARR_WALL_S=$(python3 - "$START_NS_NARR" "$END_NS_NARR" <<'PY'
import sys
start, end = map(int, sys.argv[1:3])
print((end - start) / 1e9)
PY
)
      NARR_TOTAL_TOKENS=0
      for i in $(seq 1 "$CONCURRENCY"); do
        if [ -s "/tmp/power-cap-N${CAP}-narr-${i}.json" ]; then
          T=$(python3 -c "import json; print(json.load(open('/tmp/power-cap-N${CAP}-narr-${i}.json')).get('usage',{}).get('completion_tokens',0))" 2>/dev/null || echo 0)
          NARR_TOTAL_TOKENS=$((NARR_TOTAL_TOKENS + T))
        fi
      done
      NARR_TPS=$(python3 - "$NARR_TOTAL_TOKENS" "$NARR_WALL_S" <<'PY'
import sys
tokens = int(sys.argv[1])
wall = float(sys.argv[2])
print(f"{tokens / max(wall, 0.001):.2f}")
PY
)
      echo "[narr] $CONCURRENCY streams × ~500 tok = $NARR_TOTAL_TOKENS tok in ${NARR_WALL_S}s → aggregate $NARR_TPS TPS" | tee -a "$LOG_FILE"

      # Code: same shape, code prompt
      CURL_PIDS=()
      START_NS_CODE=$(date +%s%N)
      for i in $(seq 1 "$CONCURRENCY"); do
        REQ_FILE="/tmp/power-cap-N${CAP}-code-${i}.req.json"
        python3 - "$REQ_FILE" "$MODEL" <<'PY'
import json
import sys

path, model = sys.argv[1:3]
body = {
    "model": model,
    "messages": [{
        "role": "user",
        "content": "Implement quicksort in Python with detailed comments.",
    }],
    "max_tokens": 400,
    "temperature": 0.6,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f)
PY
        curl -sS -f --max-time 120 "${URL}/v1/chat/completions" \
          -H 'Content-Type: application/json' \
          -d "@${REQ_FILE}" \
          -o "/tmp/power-cap-N${CAP}-code-${i}.json" 2>>"$LOG_FILE" &
        CURL_PIDS+=("$!")
      done
      CURL_FAILS=0
      for pid in "${CURL_PIDS[@]}"; do
        if ! wait "$pid"; then
          CURL_FAILS=$((CURL_FAILS + 1))
        fi
      done
      END_NS_CODE=$(date +%s%N)
      if [ "$CURL_FAILS" -gt 0 ]; then
        echo "[warn] code concurrent curl failures: $CURL_FAILS / $CONCURRENCY" | tee -a "$LOG_FILE"
      fi
      CODE_WALL_S=$(python3 - "$START_NS_CODE" "$END_NS_CODE" <<'PY'
import sys
start, end = map(int, sys.argv[1:3])
print((end - start) / 1e9)
PY
)
      CODE_TOTAL_TOKENS=0
      for i in $(seq 1 "$CONCURRENCY"); do
        if [ -s "/tmp/power-cap-N${CAP}-code-${i}.json" ]; then
          T=$(python3 -c "import json; print(json.load(open('/tmp/power-cap-N${CAP}-code-${i}.json')).get('usage',{}).get('completion_tokens',0))" 2>/dev/null || echo 0)
          CODE_TOTAL_TOKENS=$((CODE_TOTAL_TOKENS + T))
        fi
      done
      CODE_TPS=$(python3 - "$CODE_TOTAL_TOKENS" "$CODE_WALL_S" <<'PY'
import sys
tokens = int(sys.argv[1])
wall = float(sys.argv[2])
print(f"{tokens / max(wall, 0.001):.2f}")
PY
)
      echo "[code] $CONCURRENCY streams × ~400 tok = $CODE_TOTAL_TOKENS tok in ${CODE_WALL_S}s → aggregate $CODE_TPS TPS" | tee -a "$LOG_FILE"

      kill $SAMPLER_PID 2>/dev/null || true
      wait $SAMPLER_PID 2>/dev/null || true
      SAMPLER_PID=""
      echo
      ;;

    prefill-heavy)
      # Prefill-heavy: send a single ~50K-token prompt with max_tokens=10.
      # Prefill is compute-bound by definition (single forward pass through
      # all layers on the entire prompt). Exposes compute-knee on any card,
      # since prefill TPS scales directly with tensor-core throughput.
      # Less commonly useful than decode-concurrent for "real workload"
      # framing, but produces a clean compute-only curve for diagnostic.
      echo "[bench] prefill-heavy @ ${CAP}W cap (output: $LOG_FILE)"
      : > "$LOG_FILE"
      REQ_FILE="/tmp/power-cap-N${CAP}-prefill.req.json"
      # Generate request JSON in Python so the ~50K-token filler is escaped
      # correctly and never crosses shell argument-size limits.
      python3 - "$REQ_FILE" "$MODEL" <<'PY'
import json
import sys
import time

path, model = sys.argv[1:3]
filler = "The quick brown fox jumps over the lazy dog. " * 6500
nonce = f" Unique power-cap sweep nonce: {time.time_ns()}."
body = {
    "model": model,
    "messages": [{"role": "user", "content": nonce + " " + filler + " Summarize."}],
    "max_tokens": 10,
    "temperature": 0,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f)
PY
      START_NS=$(date +%s%N)
      if ! curl -sS -f --max-time 300 "${URL}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "@${REQ_FILE}" \
        -o "/tmp/power-cap-N${CAP}-prefill.json" 2>>"$LOG_FILE"; then
        echo "[warn] prefill-heavy curl failed at ${CAP}W" | tee -a "$LOG_FILE"
      fi
      END_NS=$(date +%s%N)
      WALL_S=$(python3 - "$START_NS" "$END_NS" <<'PY'
import sys
start, end = map(int, sys.argv[1:3])
print((end - start) / 1e9)
PY
)
      PROMPT_TOKENS=$(python3 -c "import json; print(json.load(open('/tmp/power-cap-N${CAP}-prefill.json')).get('usage',{}).get('prompt_tokens',0))" 2>/dev/null || echo 0)
      # Prefill TPS = prompt_tokens / wall (excludes the small max_tokens decode tail)
      NARR_TPS=$(python3 - "$PROMPT_TOKENS" "$WALL_S" <<'PY'
import sys
tokens = int(sys.argv[1])
wall = float(sys.argv[2])
print(f"{tokens / max(wall, 0.001):.2f}")
PY
)
      CODE_TPS="$NARR_TPS"   # use same column; prefill doesn't differentiate narr/code
      echo "[prefill] $PROMPT_TOKENS tokens in ${WALL_S}s → $NARR_TPS prefill TPS" | tee -a "$LOG_FILE"

      kill $SAMPLER_PID 2>/dev/null || true
      wait $SAMPLER_PID 2>/dev/null || true
      SAMPLER_PID=""
      echo
      ;;
  esac

  # NARR_TPS / CODE_TPS are populated per-mode inside the case above.

  # Compute median under-load power and peak temp from the sampler.
  # Filter to samples where GPU utilization > 50% (i.e. actively decoding).
  # Falls back to bench.sh's GPU-state line if sampler captured no under-load
  # samples (rare; only happens if bench.sh failed silently or finished before
  # the sampler took its first reading).
  if [ -s "$SAMPLE_FILE" ]; then
    UNDER_LOAD_STATS=$(python3 -c "
import sys
samples = []
with open('$SAMPLE_FILE') as f:
    for line in f:
        try:
            idx, util, power, temp = [x.strip() for x in line.strip().split(',')]
            if int(util) > 50:
                samples.append((float(power), int(temp)))
        except Exception:
            continue
if not samples:
    print('? ?')
else:
    powers = sorted(s[0] for s in samples)
    temps  = [s[1] for s in samples]
    median_power = powers[len(powers)//2]
    peak_temp    = max(temps)
    print(f'{median_power:.2f} {peak_temp}')
" 2>/dev/null || echo "? ?")
    ACTUAL_POWER=$(echo "$UNDER_LOAD_STATS" | awk '{print $1}')
    GPU_TEMP=$(echo "$UNDER_LOAD_STATS"      | awk '{print $2}')
  else
    ACTUAL_POWER="?"; GPU_TEMP="?"
  fi

  # Fallback to bench.sh GPU-state line if sampler returned ?
  if [ "$ACTUAL_POWER" = "?" ]; then
    GPU_STATE_LINE=$(grep -A2 "GPU state" "$LOG_FILE" | grep ",$GPU_INDEX," | head -1 || grep -A2 "GPU state" "$LOG_FILE" | grep "^${GPU_INDEX}," | head -1 || echo "")
    ACTUAL_POWER=$(echo "$GPU_STATE_LINE" | awk -F', ' '{print $5}' | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "?")
    GPU_TEMP=$(echo "$GPU_STATE_LINE"     | awk -F', ' '{print $6}' | tr -d ' ' || echo "?")
  fi

  # TPS/W efficiency calc (if both numeric)
  if [[ "$NARR_TPS" =~ ^[0-9]+\.[0-9]+$ && "$ACTUAL_POWER" =~ ^[0-9]+\.?[0-9]*$ && "$ACTUAL_POWER" != "0" ]]; then
    EFFICIENCY=$(awk "BEGIN{printf \"%.3f\", $NARR_TPS / $ACTUAL_POWER}")
  else
    EFFICIENCY="?"
  fi

  printf "[result] %sW cap → %s narr / %s code TPS @ %sW actual draw, %s°C, eff %s TPS/W\n\n" \
    "$CAP" "$NARR_TPS" "$CODE_TPS" "$ACTUAL_POWER" "$GPU_TEMP" "$EFFICIENCY"

  printf "| %s | %s | %s | %s | %s | %s |\n" \
    "$CAP" "$NARR_TPS" "$CODE_TPS" "$ACTUAL_POWER" "$GPU_TEMP" "$EFFICIENCY" \
    >> "$RESULTS_FILE"
done

# Reset
if [ "$RESET" -eq 1 ]; then
  echo "[reset] restoring GPU $GPU_INDEX to stock TDP (${STOCK_TDP}W)"
  nvidia-smi -pl "$STOCK_TDP" -i "$GPU_INDEX" 2>&1 | tail -1
else
  echo "[reset] --no-reset specified; GPU $GPU_INDEX left at last cap"
fi

# Append context to results file
{
  echo ""
  echo "**Reset:** $([ $RESET -eq 1 ] && echo "auto-reset to ${STOCK_TDP}W stock" || echo "left at last cap (--no-reset)")"
  echo ""
  echo "**Notes:**"
  case "$LOAD_MODE" in
    decode-single)
      echo "- Load mode: \`decode-single\` — original bench.sh path, 1 warm + 2 measured runs of canonical narr (500-token essay) + code (400-token quicksort)."
      echo "- TPS columns are per-request wall TPS from bench.sh summaries."
      ;;
    decode-concurrent)
      echo "- Load mode: \`decode-concurrent\` — ${CONCURRENCY} parallel chat completions for narr, then ${CONCURRENCY} parallel chat completions for code."
      echo "- TPS columns are **aggregate** throughput: total completion tokens across streams / batch wall time."
      echo "- ⚠️ **Variance caveat**: each cap is a **single batch of ${CONCURRENCY} concurrent requests** (n=1)."
      echo "  Aggregate TPS can vary 10-30% between back-to-back runs at the same cap because vLLM's"
      echo "  continuous-batching window is timing-sensitive — adjacent caps may show TPS going the"
      echo "  \"wrong direction\" without that being a real signal. Read **curve shape across the full"
      echo "  sweep**, not adjacent-cap deltas. For tighter cross-rig anchors, bump \`--concurrency\` to 8"
      echo "  or 16 so per-stream noise averages out, or run the sweep 2-3× and median per cap."
      ;;
    prefill-heavy)
      echo "- Load mode: \`prefill-heavy\` — one large prompt with \`max_tokens=10\`; both TPS columns show prompt prefill TPS."
      echo "- Prefill TPS = response \`usage.prompt_tokens\` / request wall time."
      ;;
  esac
  echo "- Actual power = **median** of 0.5s samples taken DURING the workload where util > 50% (i.e. under-load)."
  echo "- GPU temp = **peak** during workload (not a single post-bench point sample)."
  echo "- TPS/W efficiency lets you spot the knee — typically the highest cap before efficiency drops."
  echo "- If actual power < cap consistently and TPS is flat, the workload is **under-loading** this hardware:"
  echo "  the card can't use the extra power because it's not the bottleneck (smaller models on bigger"
  echo "  GPUs commonly land here). Use \`decode-concurrent\` or \`prefill-heavy\` to surface a useful curve."
  echo "- **Cooling class affects interpretation:** air-cooled cards thermal-throttle at ~80-83 °C, capping"
  echo "  effective sustained power below the software limit. Water-cooled / AIO cards stay at lower temps"
  echo "  and sustain the full software cap. Cross-rig comparisons should match cooling class for fairness."
} >> "$RESULTS_FILE"

echo
echo "================================================"
echo "Sweep complete. Summary at: $RESULTS_FILE"
echo "Raw bench logs at: /tmp/power-cap-N*.log"
echo "================================================"
echo
cat "$RESULTS_FILE"
