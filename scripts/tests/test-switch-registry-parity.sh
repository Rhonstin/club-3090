#!/usr/bin/env bash
# CONTRACT-2b-ii — switch.sh ↔ compose_registry.py parity (registry↔launcher).
#
# The v0.8.0 compose_registry.py is the single source of truth for what is
# serveable. switch.sh used to carry a hardcoded `declare -A VARIANTS` map
# that drifted out of the registry (e.g. vllm/dual-int8 shipped in the
# registry + as dual/int8.yml but was unlaunchable via switch.sh), which
# cost a real A/B a config pivot. switch.sh now DERIVES its variant tables
# from the registry; this test fails CI on ANY mismatch in EITHER direction
# so the drift class cannot return:
#
#   - zero registered-but-unlaunchable composes (registry ⊆ launcher);
#   - zero launcher-only ghosts (launcher ⊆ registry);
#   - the derived "engine|dir|file" + default_port for every variant matches
#     what the registry resolves (so the derivation can't silently corrupt a
#     mapping while staying key-set-consistent);
#   - every derived compose file exists on disk.
#
# Pure / deterministic: no docker, no GPU, no network. switch.sh's
# `_derive_variant_tables` is exercised by sourcing the live emitter the
# same way switch.sh does, then compared to the registry directly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# 1. The registry's authoritative expansion (engine|dir|file + port).
REG_EXPECTED="$(python3 - "$ROOT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root))
from scripts.lib.profiles.compose_registry import COMPOSE_REGISTRY

for key, entry in COMPOSE_REGISTRY.items():
    engine_prefix = key.split("/", 1)[0]
    engine = "llamacpp" if engine_prefix == "llamacpp" else engine_prefix
    cp = entry["compose_path"]
    assert "/compose/" in cp, f"registry {key} compose_path lacks /compose/: {cp}"
    dirpart, filepart = cp.split("/compose/", 1)
    compose_dir = f"{dirpart}/compose"
    print(f"{key}\t{engine}|{compose_dir}|{filepart}\t{entry['default_port']}")
PY
)"

# 2. switch.sh's DERIVED tables (re-run the exact emitter switch.sh embeds by
#    extracting and sourcing the function so we test the shipped code path,
#    not a re-implementation).
declare -A REG_MAP REG_PORT
while IFS=$'\t' read -r key spec port; do
  [[ -n "$key" ]] || continue
  REG_MAP["$key"]="$spec"
  REG_PORT["$key"]="$port"
done <<< "$REG_EXPECTED"

fail=0
note() { echo "FAIL: $1" >&2; fail=1; }

# The launcher's AUTHORITATIVE resolved variant set = the FULL shipped
# `switch.sh --list` code path (so a manual post-derivation `VARIANTS[...]=`
# ghost is caught too, not just the derivation function in isolation).
# `--list` prints `  <key>  →  <dir>/<file>`. The engine token is derived
# exactly as switch.sh does (key prefix: vllm | llamacpp).
LIST_OUT="$(bash "$ROOT_DIR/scripts/switch.sh" --list 2>/dev/null)"

declare -A SW_MAP
while IFS= read -r line; do
  # match "  vllm/foo  →  models/.../compose/dir/file.yml"
  if [[ "$line" =~ ^[[:space:]]+([a-z0-9/_-]+)[[:space:]]+→[[:space:]]+(.+)$ ]]; then
    key="${BASH_REMATCH[1]}"
    relpath="${BASH_REMATCH[2]}"
    [[ -n "$key" && "$key" == */* ]] || continue
    engine_prefix="${key%%/*}"
    engine="$engine_prefix"
    [[ "$engine_prefix" == "llamacpp" ]] && engine="llamacpp"
    if [[ "$relpath" != *"/compose/"* ]]; then
      note "switch.sh --list emitted a non-/compose/ path for '$key': $relpath"
      continue
    fi
    cdir="${relpath%%/compose/*}/compose"
    cfile="${relpath#*/compose/}"
    SW_MAP["$key"]="${engine}|${cdir}|${cfile}"
  fi
done <<< "$LIST_OUT"

# Port table: re-run the SHIPPED derivation function in isolation to dump
# VARIANT_DEFAULT_PORT (the `--list` path doesn't surface ports). Combined
# with 3a/3b on the full `--list` set, any key-level ghost is already
# caught; this adds value-level port parity.
declare -A SW_PORT
while IFS=$'\t' read -r key port; do
  [[ -n "$key" ]] || continue
  SW_PORT["$key"]="$port"
done < <(
  bash -c '
    set -euo pipefail
    ROOT_DIR="'"$ROOT_DIR"'"
    src="$ROOT_DIR/scripts/switch.sh"
    awk "/^declare -A VARIANT_DEFAULT_PORT=\(\)/{f=1} f{print} /^_derive_variant_tables\$/{exit}" "$src" > "/tmp/_swderive.$$"
    # shellcheck disable=SC1090
    source "/tmp/_swderive.$$"
    rm -f "/tmp/_swderive.$$"
    for k in "${!VARIANT_DEFAULT_PORT[@]}"; do
      printf "%s\t%s\n" "$k" "${VARIANT_DEFAULT_PORT[$k]}"
    done
  ' 2>/dev/null
)

# 3a. registry ⊆ launcher (zero registered-but-unlaunchable).
for k in "${!REG_MAP[@]}"; do
  if [[ -z "${SW_MAP[$k]:-}" ]]; then
    note "registered compose '$k' is NOT launchable via switch.sh"
  fi
done

# 3b. launcher ⊆ registry (zero launcher-only ghosts).
for k in "${!SW_MAP[@]}"; do
  if [[ -z "${REG_MAP[$k]:-}" ]]; then
    note "switch.sh variant '$k' has NO compose_registry.py entry (ghost)"
  fi
done

# 3c. value parity: derived spec + port match the registry expansion.
for k in "${!REG_MAP[@]}"; do
  [[ -n "${SW_MAP[$k]:-}" ]] || continue
  if [[ "${SW_MAP[$k]}" != "${REG_MAP[$k]}" ]]; then
    note "variant '$k' spec drift: switch='${SW_MAP[$k]}' registry='${REG_MAP[$k]}'"
  fi
  if [[ "${SW_PORT[$k]:-}" != "${REG_PORT[$k]}" ]]; then
    note "variant '$k' default_port drift: switch='${SW_PORT[$k]:-<none>}' registry='${REG_PORT[$k]}'"
  fi
done

# 3d. every derived compose file exists on disk (launchable in fact).
for k in "${!SW_MAP[@]}"; do
  IFS='|' read -r _eng cdir cfile <<< "${SW_MAP[$k]}"
  if [[ ! -f "$ROOT_DIR/$cdir/$cfile" ]]; then
    note "variant '$k' resolves to a missing compose file: $cdir/$cfile"
  fi
done

# 3e. User-facing single-card compose coverage guard. A compose shipped under
# models/*/{vllm,llama-cpp,ik-llama}/compose/single must not silently drift out
# of COMPOSE_REGISTRY (discussions/184 / #379-class failure).
while IFS=$'\t' read -r relpath registered; do
  [[ -n "$relpath" ]] || continue
  if [[ "$registered" != "1" ]]; then
    note "single-card compose exists on disk but has no compose_registry.py entry: $relpath"
  fi
done < <(
  python3 - "$ROOT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root))
from scripts.lib.profiles.compose_registry import COMPOSE_REGISTRY

registered_paths = {entry["compose_path"] for entry in COMPOSE_REGISTRY.values()}
opt_out = {
    # Add intentionally-internal single-card compose paths here with a comment.
}
for engine in ("vllm", "llama-cpp", "ik-llama"):
    for path in sorted(root.glob(f"models/*/{engine}/compose/single/*.yml")):
        rel = path.relative_to(root).as_posix()
        if rel in opt_out:
            continue
        print(f"{rel}\t{1 if rel in registered_paths else 0}")
PY
)

if [[ "$fail" -ne 0 ]]; then
  echo "[switch-registry-parity] FAIL" >&2
  exit 1
fi
echo "[switch-registry-parity] PASS: ${#REG_MAP[@]} registered composes, all launchable; zero ghosts; spec+port parity"
