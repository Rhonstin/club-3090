ARG VLLM_BASE_IMAGE=vllm/vllm-openai:nightly-1acd67a795ebccdf9b9db7697ae9082058301657
FROM ${VLLM_BASE_IMAGE}
ARG VLLM_BASE_IMAGE

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="club-3090 vLLM"
LABEL org.opencontainers.image.description="vLLM nightly with club-3090 vendored overlays baked into site-packages"
LABEL org.opencontainers.image.source="https://github.com/noonghunna/club-3090"
LABEL org.opencontainers.image.vendor="club-3090"

COPY models/qwen3.6-27b/vllm/patches/vllm-marlin-pad/marlin.py /tmp/club3090-overlays/qwen-marlin-pad/model_executor/kernels/linear/mixed_precision/marlin.py
COPY models/qwen3.6-27b/vllm/patches/vllm-marlin-pad/MPLinearKernel.py /tmp/club3090-overlays/qwen-marlin-pad/model_executor/kernels/linear/mixed_precision/MPLinearKernel.py
COPY models/qwen3.6-27b/vllm/patches/vllm-pr35936-required-fallback/vllm/ /tmp/club3090-overlays/qwen-pr35936/
COPY models/gemma-4-31b/vllm/patches/vllm-gemma4-dflash-int8/ /tmp/club3090-overlays/gemma-dflash-int8/

RUN set -eux; \
    VLLM_SITE="$(python3 -c 'import importlib.util, pathlib; spec = importlib.util.find_spec("vllm"); print(pathlib.Path(spec.submodule_search_locations[0]) if spec and spec.submodule_search_locations else "")')"; \
    test -n "${VLLM_SITE}"; \
    test -d "${VLLM_SITE}"; \
    echo "Applying club-3090 overlays into ${VLLM_SITE}"; \
    find /tmp/club3090-overlays/qwen-marlin-pad -type f -name '*.py' -print0 \
      | while IFS= read -r -d '' src; do \
          rel="${src#/tmp/club3090-overlays/qwen-marlin-pad/}"; \
          install -D -m 0644 "$src" "${VLLM_SITE}/${rel}"; \
        done; \
    find /tmp/club3090-overlays/qwen-pr35936 -type f -name '*.py' -print0 \
      | while IFS= read -r -d '' src; do \
          rel="${src#/tmp/club3090-overlays/qwen-pr35936/}"; \
          install -D -m 0644 "$src" "${VLLM_SITE}/${rel}"; \
        done; \
    find /tmp/club3090-overlays/gemma-dflash-int8 -type f -name '*.py' ! -path '*/_pre-pr42102-historical/*' -print0 \
      | while IFS= read -r -d '' src; do \
          rel="${src#/tmp/club3090-overlays/gemma-dflash-int8/}"; \
          install -D -m 0644 "$src" "${VLLM_SITE}/${rel}"; \
        done; \
    mkdir -p /etc/club3090; \
    { \
      echo "vllm base image: ${VLLM_BASE_IMAGE}"; \
      echo "vendored overlays:"; \
      echo "  - vLLM PR #40361: Marlin pad-sub-tile-n for AutoRound INT4 TP shards"; \
      echo "  - vLLM PR #35936: Qwen3-Coder required-tool fallback serving patch"; \
      echo "  - vLLM PR #41703: Gemma 4 DFlash drafter"; \
      echo "  - vLLM PR #42102: DFlash + INT8 per-token-head KV coexistence"; \
      echo "source repo: https://github.com/noonghunna/club-3090"; \
    } > /etc/club3090/vllm-overlays.txt; \
    rm -rf /tmp/club3090-overlays
