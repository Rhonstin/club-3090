#!/usr/bin/env bash
# Install PR #35936 required-tool fallback overlay into vLLM's site-packages.
#
# WHY a sidecar instead of an RO bind-mount:
# Genesis P64 (qwen3coder MTP streaming early-return), P68 (auto-force
# tool_choice=required), and P69 (long-context tool-format reminder) all
# write hooks INTO chat_completion/serving.py at vllm-import time. An RO
# bind-mount blocks those writes with `Errno 30: Read-only file system`,
# and Genesis explicitly warns "partial state risk; container should be
# torn down."
#
# Sidecar copies our files into the container's RW layer BEFORE Genesis
# runs, so Genesis can write its hooks freely on top. Same pattern we
# used for `patch_tolist_cudagraph.py` before Genesis absorbed it.
#
# Today chat_completion/serving.py is byte-identical to the upstream
# nightly (PR #35936's streaming hunks don't apply on our pin), so
# Genesis writes its hooks onto a clean copy. Slot stays future-ready
# for when streaming hunks land — our changes will sit underneath
# Genesis writes.
#
# Idempotent: cp overwrites unconditionally (per-boot fresh copy is
# correct behaviour — Genesis re-applies on each fresh container).

set -euo pipefail

SRC_CC="${CLUB3090_PR35936_CHAT_COMPLETION_SRC:-/etc/club3090/pr35936-chat-completion-serving.py}"
DST_CC="/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/chat_completion/serving.py"

SRC_ENGINE="${CLUB3090_PR35936_ENGINE_SRC:-/etc/club3090/pr35936-engine-serving.py}"
DST_ENGINE="/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/engine/serving.py"

if [ -r "$SRC_CC" ]; then
  cp "$SRC_CC" "$DST_CC"
  echo "[club3090/pr35936] chat_completion/serving.py installed from $SRC_CC" >&2
else
  echo "[club3090/pr35936] WARN: $SRC_CC not found; chat_completion/serving.py left untouched" >&2
fi

if [ -r "$SRC_ENGINE" ]; then
  cp "$SRC_ENGINE" "$DST_ENGINE"
  echo "[club3090/pr35936] engine/serving.py installed from $SRC_ENGINE" >&2
else
  echo "[club3090/pr35936] WARN: $SRC_ENGINE not found; engine/serving.py left untouched (PR #35936 fix INACTIVE)" >&2
fi
