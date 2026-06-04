#!/usr/bin/env bash
# =============================================================================
# serve-single.sh — Launch a model on one RTX 3090, zero Docker
# =============================================================================
# Usage:
#   serve-single.sh --wiki                      profile guide + download links
#   serve-single.sh --list                      compact profile table
#   serve-single.sh --setup [llama|ik|all]      install engine binaries
#   serve-single.sh <PROFILE> [KEY=VAL ...]     launch model
#
# Profiles (single RTX 3090, CTX >= 65K):
#   q27b-mtp          Qwen3.6-27B llama.cpp Q4_K_M   200K  MTP n=2        ~52/61 TPS
#   q27b-thinking     Qwen3.6-27B llama.cpp Q4_K_M   200K  reasoning=on   ~52/61 TPS
#   q27b-vision       Qwen3.6-27B llama.cpp Q4_K_M   150K  MTP + mmproj   ~57/66 TPS
#   q27b-iq4ks        Qwen3.6-27B ik_llama  IQ4_KS   200K  MTP n=2        ~60/69 TPS
#   q27b-iq4ks-code   Qwen3.6-27B ik_llama  IQ4_KS   200K  ngram+MTP      ~59/98 TPS
#   q35b-apex         Qwen3.6-35B ik_llama  APEX      192K  q8/q5 KV       ~103/149 TPS
# =============================================================================

set -euo pipefail
LC_NUMERIC=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${MODEL_DIR:-${REPO_ROOT}/models-cache}"
BIN_DIR="${BIN_DIR:-${REPO_ROOT}/bin}"
GPU="${GPU:-0}"
REASONING="${REASONING:-off}"
KV_TYPE="${KV_TYPE:-q4_0}"
PORT="${PORT:-}"
CTX_SIZE="${CTX_SIZE:-}"

LLAMA_BIN="${BIN_DIR}/llama-cpp/llama-server"
IK_BIN="${BIN_DIR}/ik-llama/llama-server"

LLAMA_BUILD="b9246"
IK_IMAGE="ghcr.io/ikawrakow/ik-llama-cpp:cu12-server"

APEX_TEMPLATE="${REPO_ROOT}/models/qwen3.6-35b-a3b/ik-llama/patches/apex-qwen-chat-template.jinja"

# =============================================================================
# helpers
# =============================================================================

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">>> $*"; }

# =============================================================================
# --wiki
# =============================================================================
print_wiki() {
  cat <<'WIKI'

================================================================================
 serve-single.sh  WIKI  --  single RTX 3090 (24 GB), CTX >= 65K
================================================================================

PROFILES
--------
  PROFILE             ENGINE     CTX   KV quant      TPS narr/code   NOTES
  q27b-mtp            llama.cpp  200K  q4_0/q4_0     ~52 / 61        general, cliff-immune
  q27b-thinking       llama.cpp  200K  q4_0/q4_0     ~52 / 61        reasoning=on (CoT)
  q27b-vision         llama.cpp  150K  q4_0/q4_0     ~57 / 66        images + text (mmproj)
  q27b-iq4ks          ik_llama   200K  q4_0/q4_0     ~60 / 69        fast general-purpose
  q27b-iq4ks-code     ik_llama   200K  q4_0/q4_0     ~59 / 98 (!)    code (ngram+MTP)
  q35b-apex           ik_llama   192K  q8_0/q5_0     ~103 / 149 (!)  35B MoE sweet spot

WHICH PROFILE TO PICK
---------------------
  IDE agents (aider, cline, openhands, opencode):
      q27b-iq4ks-code   -- best code TPS via two-stage speculative decoding
      q27b-mtp          -- cliff-immune fallback (llama.cpp never OOMs on multi-turn KV)

  General chat / assistant:
      q27b-iq4ks        -- 15% faster decode than q27b-mtp, same 200K context

  Reasoning / math / analysis:
      q27b-thinking     -- reasoning=on, budget-forced CoT via deepseek format

  Multimodal (screenshots, diagrams, charts):
      q27b-vision       -- needs mmproj-F16.gguf alongside the main GGUF

  Maximum quality on single card:
      q35b-apex         -- 35B MoE but only 3B active params; 103/149 TPS beats 27B

SPECULATIVE DECODING EXPLAINED
--------------------------------
  MTP (Multi-Token Prediction):  built-in draft head in the same model weights.
      Draft n=2 tokens, accept if p >= 0.0. Gives +20-30% TPS on typical workloads.

  Two-stage (q27b-iq4ks-code):  ngram-mod self-speculator first, MTP fallback.
      Ngram scans the existing KV for repeated token sequences (free, no extra VRAM).
      On code/structured output where patterns repeat, ngram hits often -> +60% code TPS.

KV-CACHE QUANT TRADEOFFS (Anbeeld 3090 benchmarks, Qwen3.6-27B)
-----------------------------------------------------------------
  Quant         VRAM vs BF16   Tail precision   Notes
  q4_0 / q4_0   28%            88.9%            default -- max context
  q8_0 / q8_0   47%            94.3%            quality mode (lower CTX_SIZE needed)
  q8_0 / q5_0   asymmetric     ~92%             K-sensitive, V-tolerant sweet spot
  f16  / f16    100%            exact            debug only

  Rule: K-cache is precision-sensitive. Lower V before K when reducing quant for context.

VRAM BUDGET (approximate, single RTX 3090 24 GB)
-------------------------------------------------
  Profile           Weights   KV@default-ctx   Total      Free
  q27b-mtp          16.5 GB   3.1 GB           ~20 GB     ~4 GB
  q27b-thinking     16.5 GB   3.1 GB           ~20 GB     ~4 GB
  q27b-vision       16.5+0.8  2.3 GB (150K)    ~20 GB     ~4 GB
  q27b-iq4ks        15.1 GB   3.1 GB           ~19 GB     ~5 GB
  q27b-iq4ks-code   15.1 GB   3.1 GB           ~19 GB     ~5 GB
  q35b-apex         17.0 GB   ~5.5 GB (q8/q5)  ~23 GB     ~1 GB (tight)

  KV at q4_0 formula: ~16 attention layers x 4 kv-heads x 256 head-dim x 2 (K+V)
                       x 0.5 byte/elem x CTX_SIZE  =  16384 bytes/token

ENGINE BINARIES
---------------
  llama.cpp  -- from GitHub releases, CUDA-enabled Ubuntu build
  ik_llama   -- extracted from Docker image (requires Docker once, no container runs after)

  Install:  bash scripts/serve-single.sh --setup [llama|ik|all]
  Location: <repo-root>/bin/llama-cpp/llama-server
            <repo-root>/bin/ik-llama/llama-server

WEIGHTS DOWNLOAD
----------------
  # q27b-mtp / q27b-thinking / q27b-vision (same GGUF)
  huggingface-cli download unsloth/Qwen3.6-27B-GGUF \
    Qwen3.6-27B-Q4_K_M.gguf \
    --local-dir models-cache/qwen3.6-27b-gguf/unsloth-mtp-q4km

  # q27b-vision projector
  huggingface-cli download unsloth/Qwen3.6-27B-GGUF \
    mmproj-F16.gguf \
    --local-dir models-cache/qwen3.6-27b-gguf

  # q27b-iq4ks / q27b-iq4ks-code (MTP-enabled IQ4_KS)
  huggingface-cli download ubergarm/Qwen3.6-27B-GGUF \
    Qwen3.6-27B-MTP-IQ4_KS.gguf \
    --local-dir models-cache/qwen3.6-27b-gguf/ubergarm-mtp-iq4ks

  # q35b-apex (APEX I-Compact, ~17 GB)
  huggingface-cli download mudler/Qwen3.6-35B-A3B-APEX-MTP-GGUF \
    Qwen3.6-35B-A3B-APEX-MTP-I-Compact.gguf \
    --local-dir models-cache/qwen3.6-35b-a3b-gguf/mudler-apex-mtp

OVERRIDES (pass as KEY=VAL after the profile name)
---------------------------------------------------
  MODEL_DIR   /path/to/gguf-parent    default: <repo-root>/models-cache
  CTX_SIZE    N                       override context window
  PORT        N                       override HTTP port
  GPU         N                       CUDA_VISIBLE_DEVICES (default: 0)
  REASONING   on|off                  thinking gate (default: off)
  KV_TYPE     q4_0|q8_0|f16           KV quant (llama.cpp profiles only)

LAUNCH EXAMPLES
---------------
  bash scripts/serve-single.sh q27b-mtp
  bash scripts/serve-single.sh q27b-iq4ks-code PORT=8021
  bash scripts/serve-single.sh q35b-apex CTX_SIZE=131072
  bash scripts/serve-single.sh q27b-thinking REASONING=on
  bash scripts/serve-single.sh q27b-iq4ks MODEL_DIR=/data/models GPU=1
================================================================================
WIKI
}

# =============================================================================
# --list
# =============================================================================
print_list() {
  cat <<'LIST'
PROFILE             ENGINE     CTX   TPS narr/code   BEST FOR
q27b-mtp            llama.cpp  200K  ~52 / 61        general, cliff-immune
q27b-thinking       llama.cpp  200K  ~52 / 61        reasoning / CoT
q27b-vision         llama.cpp  150K  ~57 / 66        images + text
q27b-iq4ks          ik_llama   200K  ~60 / 69        fast general
q27b-iq4ks-code     ik_llama   200K  ~59 / 98        code / IDE agents
q35b-apex           ik_llama   192K  ~103 / 149      35B MoE, max quality
LIST
}

# =============================================================================
# --setup
# =============================================================================
setup_llama() {
  info "Installing llama.cpp ${LLAMA_BUILD} (CUDA, Ubuntu x64)..."
  require_cmd curl
  require_cmd unzip

  mkdir -p "${BIN_DIR}/llama-cpp"

  ARCH=$(uname -m)
  ARCH_LABEL="${ARCH/x86_64/x64}"
  ZIP="llama-${LLAMA_BUILD}-bin-ubuntu-${ARCH_LABEL}.zip"
  URL="https://github.com/ggerganov/llama.cpp/releases/download/${LLAMA_BUILD}/${ZIP}"

  TMP=$(mktemp -d)
  trap 'rm -rf "${TMP}"' EXIT

  info "Downloading ${URL}"
  curl -fsSL -o "${TMP}/${ZIP}" "${URL}" \
    || die "Download failed. Check https://github.com/ggerganov/llama.cpp/releases/tag/${LLAMA_BUILD} for available assets."

  info "Extracting llama-server..."
  unzip -j "${TMP}/${ZIP}" "*/llama-server" "llama-server" -d "${BIN_DIR}/llama-cpp/" 2>/dev/null \
    || unzip -j "${TMP}/${ZIP}" -d "${BIN_DIR}/llama-cpp/" 2>/dev/null
  chmod +x "${LLAMA_BIN}"

  info "Installed: ${LLAMA_BIN}"
  "${LLAMA_BIN}" --version 2>&1 | head -1 || true
}

setup_ik() {
  info "Extracting ik_llama binary from Docker image (one-time, no container runs after)..."
  require_cmd docker

  mkdir -p "${BIN_DIR}/ik-llama"

  info "Pulling ${IK_IMAGE}..."
  docker pull "${IK_IMAGE}" -q

  CID=$(docker create "${IK_IMAGE}" true)
  docker cp "${CID}:/app/llama-server" "${IK_BIN}"
  docker rm "${CID}" >/dev/null
  chmod +x "${IK_BIN}"

  info "Installed: ${IK_BIN}"
  "${IK_BIN}" --version 2>&1 | head -1 || true
}

cmd_setup() {
  local target="${1:-all}"
  case "${target}" in
    llama)      setup_llama ;;
    ik)         setup_ik ;;
    all)        setup_llama; setup_ik ;;
    *)          die "Unknown setup target '${target}'. Use: llama | ik | all" ;;
  esac
}

# =============================================================================
# check_binary
# =============================================================================
check_binary() {
  local bin="$1" name="$2" setup_cmd="$3"
  [[ -x "${bin}" ]] && return 0
  die "${name} binary not found at ${bin}
  Run: bash scripts/serve-single.sh --setup ${setup_cmd}"
}

# =============================================================================
# parse KEY=VAL overrides from remaining args
# =============================================================================
apply_overrides() {
  for arg in "$@"; do
    case "${arg}" in
      MODEL_DIR=*)  MODEL_DIR="${arg#*=}" ;;
      CTX_SIZE=*)   CTX_SIZE="${arg#*=}" ;;
      PORT=*)       PORT="${arg#*=}" ;;
      GPU=*)        GPU="${arg#*=}" ;;
      REASONING=*)  REASONING="${arg#*=}" ;;
      KV_TYPE=*)    KV_TYPE="${arg#*=}" ;;
      *)            die "Unknown override '${arg}'. Expected KEY=VAL." ;;
    esac
  done
}

# =============================================================================
# launch profiles
# =============================================================================
launch() {
  local profile="$1"; shift
  apply_overrides "$@"

  export CUDA_VISIBLE_DEVICES="${GPU}"

  case "${profile}" in

    # -------------------------------------------------------------------------
    q27b-mtp)
      check_binary "${LLAMA_BIN}" "llama.cpp" "llama"
      local model="${MODEL_DIR}/qwen3.6-27b-gguf/unsloth-mtp-q4km/Qwen3.6-27B-Q4_K_M.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}
  Download: huggingface-cli download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-Q4_K_M.gguf --local-dir models-cache/qwen3.6-27b-gguf/unsloth-mtp-q4km"
      info "Launching q27b-mtp on GPU ${GPU}, port ${PORT:-8020}, ctx ${CTX_SIZE:-200000}"
      exec "${LLAMA_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8020}" \
        -m "${model}" \
        -c "${CTX_SIZE:-200000}" -b 4096 -ub 512 \
        -ngl 99 -fa on \
        --cache-type-k "${KV_TYPE:-q4_0}" \
        --cache-type-v "${KV_TYPE:-q4_0}" \
        -np 1 \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        --jinja \
        --reasoning "${REASONING}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    # -------------------------------------------------------------------------
    q27b-thinking)
      check_binary "${LLAMA_BIN}" "llama.cpp" "llama"
      local model="${MODEL_DIR}/qwen3.6-27b-gguf/unsloth-mtp-q4km/Qwen3.6-27B-Q4_K_M.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}
  Download: huggingface-cli download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-Q4_K_M.gguf --local-dir models-cache/qwen3.6-27b-gguf/unsloth-mtp-q4km"
      info "Launching q27b-thinking on GPU ${GPU}, port ${PORT:-8020}, ctx ${CTX_SIZE:-200000}"
      exec "${LLAMA_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8020}" \
        -m "${model}" \
        -c "${CTX_SIZE:-200000}" -b 4096 -ub 512 \
        -ngl 99 -fa on \
        --cache-type-k "${KV_TYPE:-q4_0}" \
        --cache-type-v "${KV_TYPE:-q4_0}" \
        -np 1 \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        --jinja \
        --reasoning "${REASONING:-on}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    # -------------------------------------------------------------------------
    q27b-vision)
      check_binary "${LLAMA_BIN}" "llama.cpp" "llama"
      local model="${MODEL_DIR}/qwen3.6-27b-gguf/unsloth-mtp-q4km/Qwen3.6-27B-Q4_K_M.gguf"
      local mmproj="${MODEL_DIR}/qwen3.6-27b-gguf/mmproj-F16.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}"
      [[ -f "${mmproj}" ]] || die "mmproj not found: ${mmproj}
  Download: huggingface-cli download unsloth/Qwen3.6-27B-GGUF mmproj-F16.gguf --local-dir models-cache/qwen3.6-27b-gguf"
      info "Launching q27b-vision on GPU ${GPU}, port ${PORT:-8020}, ctx ${CTX_SIZE:-150000}"
      exec "${LLAMA_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8020}" \
        -m "${model}" \
        --mmproj "${mmproj}" \
        --image-min-tokens 1024 --image-max-tokens 1024 \
        -c "${CTX_SIZE:-150000}" -b 1024 -ub 1024 \
        -ngl 99 -fa on \
        --cache-type-k "${KV_TYPE:-q4_0}" \
        --cache-type-v "${KV_TYPE:-q4_0}" \
        -np 1 \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        --jinja \
        --reasoning "${REASONING}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    # -------------------------------------------------------------------------
    q27b-iq4ks)
      check_binary "${IK_BIN}" "ik_llama" "ik"
      local model="${MODEL_DIR}/qwen3.6-27b-gguf/ubergarm-mtp-iq4ks/Qwen3.6-27B-MTP-IQ4_KS.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}
  Download: huggingface-cli download ubergarm/Qwen3.6-27B-GGUF Qwen3.6-27B-MTP-IQ4_KS.gguf --local-dir models-cache/qwen3.6-27b-gguf/ubergarm-mtp-iq4ks"
      info "Launching q27b-iq4ks on GPU ${GPU}, port ${PORT:-8020}, ctx ${CTX_SIZE:-200000}"
      exec "${IK_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8020}" \
        --model "${model}" \
        -ngl 99 \
        --ctx-size "${CTX_SIZE:-200000}" -b 4096 -ub 1024 \
        -np 1 \
        -ctk "${KV_TYPE:-q4_0}" -ctv "${KV_TYPE:-q4_0}" \
        -khad -vhad \
        -ngld 99 \
        --multi-token-prediction \
        --draft-max 2 --draft-p-min 0.0 \
        --recurrent-ckpt-mode auto \
        --merge-qkv \
        -fa on \
        --jinja \
        --parallel-tool-calls \
        --reasoning "${REASONING}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    # -------------------------------------------------------------------------
    q27b-iq4ks-code)
      check_binary "${IK_BIN}" "ik_llama" "ik"
      local model="${MODEL_DIR}/qwen3.6-27b-gguf/ubergarm-mtp-iq4ks/Qwen3.6-27B-MTP-IQ4_KS.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}
  Download: huggingface-cli download ubergarm/Qwen3.6-27B-GGUF Qwen3.6-27B-MTP-IQ4_KS.gguf --local-dir models-cache/qwen3.6-27b-gguf/ubergarm-mtp-iq4ks"
      info "Launching q27b-iq4ks-code (two-stage ngram+MTP) on GPU ${GPU}, port ${PORT:-8020}, ctx ${CTX_SIZE:-200000}"
      exec "${IK_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8020}" \
        --model "${model}" \
        -ngl 99 \
        --ctx-size "${CTX_SIZE:-200000}" -b 4096 -ub 1024 \
        -np 1 \
        -ctk "${KV_TYPE:-q4_0}" -ctv "${KV_TYPE:-q4_0}" \
        -khad -vhad \
        -ngld 99 \
        --spec-stage "ngram-mod:n_max=4,n_min=2,spec-ngram-size-n=16" \
        --spec-stage "mtp:n_max=3,draft-p-min=0.0" \
        --recurrent-ckpt-mode auto \
        --merge-qkv \
        -fa on \
        --jinja \
        --parallel-tool-calls \
        --reasoning "${REASONING}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    # -------------------------------------------------------------------------
    q35b-apex)
      check_binary "${IK_BIN}" "ik_llama" "ik"
      local model="${MODEL_DIR}/qwen3.6-35b-a3b-gguf/mudler-apex-mtp/Qwen3.6-35B-A3B-APEX-MTP-I-Compact.gguf"
      [[ -f "${model}" ]] || die "GGUF not found: ${model}
  Download: huggingface-cli download mudler/Qwen3.6-35B-A3B-APEX-MTP-GGUF Qwen3.6-35B-A3B-APEX-MTP-I-Compact.gguf --local-dir models-cache/qwen3.6-35b-a3b-gguf/mudler-apex-mtp"
      [[ -f "${APEX_TEMPLATE}" ]] || die "APEX chat template not found: ${APEX_TEMPLATE}"
      info "Launching q35b-apex on GPU ${GPU}, port ${PORT:-8057}, ctx ${CTX_SIZE:-196608}"
      exec "${IK_BIN}" \
        --host 0.0.0.0 --port "${PORT:-8057}" \
        --model "${model}" \
        --fit --fit-margin 256 \
        -ngl 99 \
        --ctx-size "${CTX_SIZE:-196608}" -b 4096 -ub 1024 \
        -np 1 \
        -ctk q8_0 -ctv q5_0 \
        -khad -vhad \
        -ngld 99 \
        --multi-token-prediction \
        --draft-max 4 --draft-p-min 0.0 \
        --recurrent-ckpt-mode auto \
        --merge-qkv \
        -fa on \
        --no-mmap \
        --cache-ram 4096 \
        --jinja \
        --chat-template-file "${APEX_TEMPLATE}" \
        --parallel-tool-calls \
        --reasoning "${REASONING}" \
        --reasoning-format deepseek \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0
      ;;

    *)
      die "Unknown profile '${profile}'.
  Available: q27b-mtp  q27b-thinking  q27b-vision  q27b-iq4ks  q27b-iq4ks-code  q35b-apex
  Run: bash scripts/serve-single.sh --list"
      ;;
  esac
}

# =============================================================================
# main
# =============================================================================
main() {
  [[ $# -eq 0 ]] && { print_wiki; exit 0; }

  case "$1" in
    --wiki|-w)          print_wiki ;;
    --list|-l)          print_list ;;
    --setup|-s)         cmd_setup "${2:-all}" ;;
    --help|-h)          print_wiki ;;
    -*)                 die "Unknown flag '$1'. Use --wiki | --list | --setup | <profile>" ;;
    *)                  launch "$@" ;;
  esac
}

main "$@"
