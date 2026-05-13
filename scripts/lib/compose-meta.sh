#!/usr/bin/env bash
#
# Tiny parser for hardware metadata stored as compose header comments.
#
# Expected form:
#   # Requires-min-vram-gb: 24
#   # Requires-min-gpu-count: 2
#   # Tensor-parallel: 2
#   # Requires-sm: 9.0+
#
# This intentionally does not parse YAML. These fields are comments so that
# older docker compose versions and direct `docker compose -f ... up` flows keep
# working unchanged.

_compose_meta_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

_compose_meta_norm_key() {
  local key="$1"
  key="$(_compose_meta_trim "$key")"
  key="${key//_/-}"
  key="${key// /-}"
  printf '%s' "$key" | tr '[:upper:]' '[:lower:]'
}

_compose_meta_wants_key() {
  local requested="$(_compose_meta_norm_key "$1")"
  local candidate="$(_compose_meta_norm_key "$2")"

  case "$requested" in
    min-vram-gb) requested="requires-min-vram-gb" ;;
    min-gpu-count) requested="requires-min-gpu-count" ;;
    tp) requested="tensor-parallel" ;;
    sm) requested="requires-sm" ;;
  esac

  [[ "$candidate" == "$requested" ]]
}

compose_meta_get() {
  local compose_file="$1"
  local field="$2"

  [[ -f "$compose_file" ]] || return 1

  local line key value
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] || continue
    line="${line#*\#}"
    [[ "$line" == *:* ]] || continue
    key="${line%%:*}"
    value="${line#*:}"
    if _compose_meta_wants_key "$field" "$key"; then
      _compose_meta_trim "$value"
      return 0
    fi
  done < "$compose_file"

  return 1
}
