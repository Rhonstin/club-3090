# Gemma 4 FP8 KV on Ampere

Local vLLM overlay for testing `--kv-cache-dtype fp8_e5m2` on Ampere
consumer GPUs.

## Scope

Path A from `/tmp/codex-prompt-gemma4-fp8-ampere.md`: keep fp8_e5m2 as a
KV-only cache dtype and bypass query quantization for that dtype.

The upstream source currently initializes `self.query_quant` for any
`kv_cache_dtype.startswith("fp8")`, but `Attention.forward()` later asserts
that query quantization is only valid for `{"fp8", "fp8_e4m3", "nvfp4"}`.
This makes `fp8_e5m2` internally inconsistent even though the Triton attention
backend advertises it in `supported_kv_cache_dtypes`.

Runtime testing then exposed a second Python dispatch issue: the Triton KV
reshape wrapper maps every quantized KV dtype to `current_platform.fp8_dtype()`
before launching the cache-update kernel. On CUDA/Ampere that is
`torch.float8_e4m3fn`, which compiles as unsupported `fp8e4nv`. For explicit
`fp8_e5m2`, this overlay views the uint8 KV cache as `torch.float8_e5m2`
instead.

## Modified File

Mount:

```yaml
- ../patches/vllm-gemma4-fp8-ampere/model_executor/layers/attention/attention.py:/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/attention/attention.py:ro
- ../patches/vllm-gemma4-fp8-ampere/v1/attention/backends/triton_attn.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/attention/backends/triton_attn.py:ro
- ../patches/vllm-gemma4-fp8-ampere/v1/attention/ops/triton_reshape_and_cache_flash.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/attention/ops/triton_reshape_and_cache_flash.py:ro
```

`model_executor/layers/attention/attention.py`:

```python
# before
self.impl.supports_quant_query_input and (
    self.kv_cache_dtype.startswith("fp8") or self.kv_cache_dtype == "nvfp4"
)

# after
self.impl.supports_quant_query_input and self.kv_cache_dtype in {
    "fp8",
    "fp8_e4m3",
    "nvfp4",
}
```

`v1/attention/ops/triton_reshape_and_cache_flash.py`:

```python
kv_cache_torch_dtype = (
    torch.float8_e5m2
    if kv_cache_dtype == "fp8_e5m2"
    else current_platform.fp8_dtype()
    if is_quantized_kv_cache(kv_cache_dtype)
    else key_cache.dtype
)
```

The same mapping is applied to the diff-KV wrapper in that file.

`v1/attention/backends/triton_attn.py`:

```python
self.fp8_dtype = (
    torch.float8_e5m2
    if kv_cache_dtype == "fp8_e5m2"
    else current_platform.fp8_dtype()
)
```

This keeps both cache-update and cache-read views aligned to e5m2 for explicit
`--kv-cache-dtype fp8_e5m2`.

## Expected Behavior

With `--kv-cache-dtype fp8_e5m2`, query tensors remain bf16/fp16 while the KV
cache uses fp8_e5m2. This avoids the generic Attention assertion and prevents
Ampere from compiling the KV-update path as unsupported `fp8e4nv`, without
changing Gemma model code or Triton kernel bodies.

## Verification

Static check:

```bash
python3 -m py_compile \
  models/gemma-4-31b/vllm/patches/vllm-gemma4-fp8-ampere/model_executor/layers/attention/attention.py \
  models/gemma-4-31b/vllm/patches/vllm-gemma4-fp8-ampere/v1/attention/backends/triton_attn.py \
  models/gemma-4-31b/vllm/patches/vllm-gemma4-fp8-ampere/v1/attention/ops/triton_reshape_and_cache_flash.py
```

Result on 2x RTX 3090, 2026-05-06:

```text
TP=2, max_model_len=65536, gpu_memory_utilization=0.95,
kv_cache_dtype=fp8_e5m2, Gemma4 MTP n=4

PASS: vLLM accepts fp8_e5m2 and reaches worker profiling.
PASS: the original Attention.forward assertion is removed.
PASS: cache-update no longer fails with fp8e4nv after the e5m2 cache-view fixes.
BLOCKED: unified_attention compiles for e5m2 but exceeds Ampere shared memory:
         Required: 114944, Hardware limit: 101376.
```

Runtime plan after the shared-memory issue is fixed upstream:

1. TP=2 first: `dual/docker-compose.yml` plus this RO mount and
   `--kv-cache-dtype fp8_e5m2`.
2. Check boot logs for doubled KV capacity versus bf16 baseline:
   `Available KV cache memory` and `GPU KV cache size`.
3. Run `scripts/verify-full.sh` against the service.
4. TP=1 next: `single/docker-compose.yml` plus this RO mount and
   `--kv-cache-dtype fp8_e5m2`.

## Drop Conditions

Drop this overlay once upstream vLLM narrows fp8 query-quant initialization
and maps explicit `fp8_e5m2` KV-cache backend/cache-update views to
`torch.float8_e5m2` instead of `current_platform.fp8_dtype()`.
