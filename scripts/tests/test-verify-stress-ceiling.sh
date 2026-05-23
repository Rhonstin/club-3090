#!/usr/bin/env bash
# Test for verify-stress.sh ceiling ladder (#199) — validates:
#   1. get_n_ctx() reads llama.cpp /props → default_generation_settings.n_ctx (nested)
#   2. get_n_ctx() falls back to top-level n_ctx (some llama.cpp forks)
#   3. get_n_ctx() falls back to /v1/models → max_model_len (vLLM)
#   4. get_n_ctx() returns 0 when detection fails
#   5. get_vram_free_mb() sums across GPUs (dual + single)
#   6. Ladder rung computation is correct for various n_ctx values
#   7. SKIP_CEILING=1 / SKIP_LONGCTX=1 skip the ceiling ladder
#   8. All 8 probe headers [N/8] are present in output
#   9. Small compose skips the ladder (ceiling ≤ start)
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PASS=0
FAIL=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label: expected '$expected', got '$actual'" >&2
    FAIL=$((FAIL + 1))
  fi
}
assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label:-assert_contains}: expected output to contain: $needle" >&2
    echo "--- output (last 30 lines) ---" >&2
    echo "$haystack" | tail -30 >&2
    FAIL=$((FAIL + 1))
  fi
}

# Extract helpers to temp file (avoids bash -c quoting issues with
# embedded python one-liners that contain single quotes).
HELPERS_FILE="$(mktemp --suffix=.sh)"
sed -n '/^get_n_ctx()/,/^}/p' scripts/verify-stress.sh > "$HELPERS_FILE"
sed -n '/^get_vram_free_mb()/,/^}/p' scripts/verify-stress.sh >> "$HELPERS_FILE"

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir" "$HELPERS_FILE"; }
trap cleanup EXIT

# Mock curl helper: match against the full arg string (not per-arg).
make_curl_mock() {
  cat > "${tmp_dir}/curl" <<EOF
#!/usr/bin/env bash
all="\$*"
case "\$all" in
$1
  *) exit 1 ;;
esac
EOF
  chmod +x "${tmp_dir}/curl"
}

# ---- Test get_n_ctx with REAL llama.cpp /props shape (nested) ----
# This is the critical test — real llama.cpp nests n_ctx inside
# default_generation_settings, NOT at top-level.
make_curl_mock '  */props*) printf '"'"'{"default_generation_settings":{"n_ctx":262144,"temperature":0.8}}'"'"'; exit 0 ;;'

result="$(ENGINE_KIND=llamacpp URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:$PATH" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx from /props NESTED (real llama.cpp)" "262144" "$result"

# ---- Test get_n_ctx with top-level n_ctx (some forks/old versions) ----
make_curl_mock '  */props*) printf '"'"'{"n_ctx":131072}'"'"'; exit 0 ;;'

result="$(ENGINE_KIND=llamacpp URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:$PATH" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx from /props TOP-LEVEL (fork/old)" "131072" "$result"

# ---- Test get_n_ctx with both nested and top-level (nested wins) ----
make_curl_mock '  */props*) printf '"'"'{"n_ctx":999,"default_generation_settings":{"n_ctx":200000}}'"'"'; exit 0 ;;'

result="$(ENGINE_KIND=llamacpp URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:$PATH" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx nested wins over top-level" "200000" "$result"

# ---- Test get_n_ctx fallback to /v1/models (vLLM) ----
make_curl_mock '
  */props*) exit 1 ;;
  */v1/models*) printf '"'"'{"data":[{"id":"mock","max_model_len":131072}]}'"'"'; exit 0 ;;'

result="$(ENGINE_KIND=vllm URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:$PATH" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx fallback to /v1/models (vLLM)" "131072" "$result"

# ---- Test get_n_ctx returns 0 on total failure ----
make_curl_mock ''

result="$(ENGINE_KIND=unknown URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:/usr/bin:/bin" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx returns 0 on failure" "0" "$result"

# ---- Test get_n_ctx with 512K compose (nested) ----
make_curl_mock '  */props*) printf '"'"'{"default_generation_settings":{"n_ctx":524288}}'"'"'; exit 0 ;;'

result="$(ENGINE_KIND=llamacpp URL=http://mock CONTAINER=none \
  PATH="${tmp_dir}:$PATH" \
  bash -c "source '$HELPERS_FILE'; get_n_ctx")"
assert_eq "get_n_ctx 512K compose (nested)" "524288" "$result"

# ---- Test get_vram_free_mb dual GPU ----
cat > "${tmp_dir}/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *memory.free*) printf "12000\n11500\n" ;;
esac
EOF
chmod +x "${tmp_dir}/nvidia-smi"

result="$(PATH="${tmp_dir}:/usr/bin:/bin" \
  bash -c "source '$HELPERS_FILE'; get_vram_free_mb")"
assert_eq "get_vram_free_mb dual-GPU sum" "23500" "$result"

# ---- Test get_vram_free_mb single GPU ----
cat > "${tmp_dir}/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *memory.free*) printf "23000\n" ;;
esac
EOF
chmod +x "${tmp_dir}/nvidia-smi"

result="$(PATH="${tmp_dir}:/usr/bin:/bin" \
  bash -c "source '$HELPERS_FILE'; get_vram_free_mb")"
assert_eq "get_vram_free_mb single-GPU" "23000" "$result"

# ---- Test ladder rung computation ----
compute_ladder() {
  local n_ctx="$1" start="${2:-95000}" step="${3:-30000}" frac="${4:-0.92}"
  python3 -c "
start, top, step = ${start}, int(${n_ctx} * ${frac}), ${step}
if top <= start:
    print('SKIP')
else:
    rungs = list(range(start, top, step))
    if not rungs or rungs[-1] != top:
        rungs.append(top)
    print(' '.join(str(r) for r in rungs))
"
}

# 262K compose: 95000 → 125000 → 155000 → 185000 → 215000 → 241172
ladder="$(compute_ladder 262144)"
assert_eq "ladder 262K" "95000 125000 155000 185000 215000 241172" "$ladder"

# 131K compose: 95000 → 120586
ladder="$(compute_ladder 131072)"
assert_eq "ladder 131K" "95000 120586" "$ladder"

# 200K compose: 95000 → 125000 → 155000 → 184000
ladder="$(compute_ladder 200000)"
assert_eq "ladder 200K" "95000 125000 155000 184000" "$ladder"

# 512K compose: 95000 → 125000 → ... → 482344
ladder="$(compute_ladder 524288)"
rung_count="$(echo "$ladder" | wc -w)"
assert_eq "ladder 512K rung count" "14" "$rung_count"
first="$(echo "$ladder" | awk '{print $1}')"
last="$(echo "$ladder" | awk '{print $NF}')"
assert_eq "ladder 512K first rung" "95000" "$first"
assert_eq "ladder 512K last rung" "482344" "$last"

# 32K compose: ceiling = 29440 < start 95000 → SKIP
ladder="$(compute_ladder 32768)"
assert_eq "ladder 32K (too small)" "SKIP" "$ladder"

# Custom step size: 15000
ladder="$(compute_ladder 262144 95000 15000)"
rung_count="$(echo "$ladder" | wc -w)"
assert_eq "ladder 262K step=15K rung count" "11" "$rung_count"

# Custom fraction: 0.80
ladder="$(compute_ladder 262144 95000 30000 0.80)"
last="$(echo "$ladder" | awk '{print $NF}')"
assert_eq "ladder 262K frac=0.80 last rung" "209715" "$last"

# ---- Test: full script with SKIP_CEILING / SKIP_LONGCTX ----
make_curl_mock '
  */v1/models*) printf '"'"'{"data":[{"id":"mock-model","max_model_len":262144}]}'"'"'; exit 0 ;;
  */props*) printf '"'"'{"default_generation_settings":{"n_ctx":262144}}'"'"'; exit 0 ;;
  */v1/chat/completions*) printf '"'"'{"choices":[{"message":{"content":"mock response"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":10}}'"'"'; exit 0 ;;'

cat > "${tmp_dir}/nvidia-smi" <<'MOCK_NVIDIA'
#!/usr/bin/env bash
case "$*" in
  *memory.free*) echo "23500" ;;
  *) echo "NVIDIA-SMI mock" ;;
esac
MOCK_NVIDIA
chmod +x "${tmp_dir}/nvidia-smi"

cat > "${tmp_dir}/docker" <<'MOCK_DOCKER'
#!/usr/bin/env bash
printf '{"Config":{"Image":"mock","Env":[]},"Args":[]}'
MOCK_DOCKER
chmod +x "${tmp_dir}/docker"

# Test: SKIP_CEILING=1 skips probe 8
out="$(PATH="${tmp_dir}:$PATH" PREFLIGHT_NO_AUTODETECT=1 URL=http://mock MODEL=mock-model \
  CONTAINER=none SKIP_CEILING=1 SKIP_LONGCTX=1 SKIP_TOOL_PREFILL=1 \
  bash scripts/verify-stress.sh 2>&1)" || true
assert_contains "$out" "[8/8]" "probe 8 header printed"
assert_contains "$out" "SKIP_CEILING=1" "SKIP_CEILING skip message"

# Test: SKIP_LONGCTX=1 also skips ceiling ladder
out="$(PATH="${tmp_dir}:$PATH" PREFLIGHT_NO_AUTODETECT=1 URL=http://mock MODEL=mock-model \
  CONTAINER=none SKIP_LONGCTX=1 SKIP_TOOL_PREFILL=1 \
  bash scripts/verify-stress.sh 2>&1)" || true
assert_contains "$out" "SKIP_LONGCTX=1" "SKIP_LONGCTX also skips ceiling"

# Verify all 8 probe headers are present
for i in 1 2 3 4 5 6 7 8; do
  assert_contains "$out" "[${i}/8]" "probe ${i} header"
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "test-verify-stress-ceiling: ok"
