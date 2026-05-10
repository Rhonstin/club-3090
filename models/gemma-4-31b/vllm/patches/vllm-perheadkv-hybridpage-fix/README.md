# Hybrid Per-Head KV Page Unification

Local vLLM overlay for testing `int8_per_token_head` and
`fp8_per_token_head` KV cache on hybrid-attention models.

## Scope

Path C from `/tmp/codex-prompt-gemma4-int8-perhead-ampere.md`: keep the
existing uniform physical page-size invariant, but use `page_size_padded` when
the current maximum page size is not divisible by smaller layer page sizes.
This is the narrower version chosen after Path A's LCM target over-allocated
the profiling KV cache.

The failure this targets:

```text
NotImplementedError: The page size of the layer is not divisible by the
maximum page size. Cannot unify by adjusting block_size.
```

The overlay is generic to hybrid models using per-token-head KV quantization.
It is not Gemma-specific. The file is based on the current Gemma DFlash
`kv_cache_utils.py` overlay so it composes with the local PR #41703 test stack.

## Mount

Mount this after any other overlay that touches `kv_cache_utils.py`:

```yaml
- ../patches/vllm-perheadkv-hybridpage-fix/v1/core/kv_cache_utils.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/core/kv_cache_utils.py:ro
```

## Change

`v1/core/kv_cache_utils.py`, `unify_kv_cache_spec_page_size`:

```python
target_page_size = max(page_sizes)
```

Layers already at `target_page_size` are unchanged. Layers whose page size
cleanly divides the target get a larger `block_size`, preserving the previous
strategy. If a layer cannot be adjusted by `block_size` but supports
`page_size_padded`, it is padded to the target. Other layer types still raise a
clear `NotImplementedError`.

## Verification

Static check:

```bash
python3 -m py_compile \
  models/gemma-4-31b/vllm/patches/vllm-perheadkv-hybridpage-fix/v1/core/kv_cache_utils.py
```

Runtime plan:

1. TP=2 Gemma DFlash with `--kv-cache-dtype int8_per_token_head`,
   `MAX_MODEL_LEN=131072`, and `GPU_MEMORY_UTILIZATION=0.95`.
2. TP=2 Gemma MTP with `--kv-cache-dtype int8_per_token_head`.
3. TP=2 Gemma DFlash with `--kv-cache-dtype fp8_per_token_head`.
4. After each successful boot, check `Available KV cache memory`, `GPU KV cache
   size`, and run `scripts/verify-full.sh`.

Observed Path A result:

```text
LCM target removed the original NotImplementedError but over-allocated the
minimal profiling KV cache. TP=2 DFlash int8_per_token_head attempted a
16.38 GiB allocation with only 11.25 GiB free and failed before real KV sizing.
```

## Drop Conditions

Drop this overlay when upstream vLLM lands an LCM/padding fix for hybrid
per-token-head KV cache page-size unification in
`vllm/v1/core/kv_cache_utils.py`.
