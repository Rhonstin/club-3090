# vLLM PR #35936 required-tool fallback overlay

Local vendor of vLLM PR #35936:

<https://github.com/vllm-project/vllm/pull/35936>

Source head used for the rebase: `a26962941e1328e10863506df39376e63be1fd64`.
Target image: `vllm/vllm-openai:nightly-1acd67a795ebccdf9b9db7697ae9082058301657`.

## Bug

With `--enable-auto-tool-choice`, `--tool-call-parser qwen3_coder`, and
`tool_choice="required"`, vLLM returned an empty `tool_calls=[]` array even
though the model produced a structurally valid call. `tool_choice="auto"`
worked correctly against the same compose.

Forensics with a debug log line on our pinned nightly showed:

- Under `tool_choice="required"`, vLLM forces structured **JSON** output —
  the model emits `[{"name":"get_weather","parameters":{"city":"Tokyo"}}]`
  rather than the qwen3_coder `<tool_call>...</tool_call>` XML it would
  normally produce.
- The configured qwen3_coder parser is then asked to extract calls from
  that JSON content. It scans for the XML sentinel `<tool_call>` and finds
  nothing → `tools_called=False` → empty response.

## Rebase Notes

The upstream PR's primary fix lives in a branch gated on
`tool_parser_cls.supports_required_and_named` being `True`. For
`Qwen3CoderToolParser` on this nightly that attribute is `False`, so the
PR's hunk was dead code on our path — control instead falls through to the
"auto / fallback" branch (`elif tool_parser_cls and ...`) at the bottom of
`_parse_tool_calls_from_content`.

This overlay therefore lands the PR's intent in **both** places in
`vllm/entrypoints/openai/engine/serving.py`:

1. The original `tool_choice == "required" and supports_required_and_named`
   branch (lines ~660-702) — JSON validate first, fall back to
   `tool_parser.extract_tool_calls()` on `ValidationError` /
   `JSONDecodeError`. Inert for qwen3_coder today; preserved for any future
   parser that flips `supports_required_and_named = True`.

2. The fallback branch (lines ~733-756) — when `tool_choice == "required"`,
   try `TypeAdapter(list[FunctionDefinition]).validate_json(...)` against
   the content before invoking the parser. On success, materialise
   `FunctionCall` entries directly. On failure, fall through to the parser
   as before so XML-emitting paths keep working.

The chat completion file is vendored unchanged from the pinned nightly as
a future-ready slot. The PR's streaming-side hunks target a pre-parser-manager
code path that has been refactored on `nightly-1acd67a79`; non-streaming
clients (MLS-Bench, our curl repro, most agent harnesses) exercise only the
engine-side fix.

## Installation: sidecar pattern (v0.5.1+)

The overlay is **not** mounted directly at vLLM's site-packages paths. Instead:

1. Both files are bind-mounted at side paths under `/etc/club3090/`:
   - `pr35936-chat-completion-serving.py`
   - `pr35936-engine-serving.py`
2. `install.sh` is bind-mounted at `/etc/club3090/install-pr35936.sh`
3. The compose entrypoint invokes `bash /etc/club3090/install-pr35936.sh`
   **before** any other patch step (`python3 -m vllm._genesis.patches.apply_all`
   in Genesis-loaded composes, or `exec vllm serve` in Genesis-less ones).
4. `install.sh` copies our files into vLLM's site-packages with `cp`. The
   destination becomes a writable file in the container's RW layer.

### Why a sidecar instead of an RO bind-mount

v0.5.0 originally mounted both files directly at vLLM's site-packages paths
with `:ro`. That broke 8 Genesis-loaded composes because Genesis P64
(qwen3coder MTP streaming early-return), P68 (auto force tool_choice=required),
and P69 (long-context tool-format reminder) all write hooks into
`chat_completion/serving.py` at vllm-import time. The RO mount blocked those
writes with `Errno 30: Read-only file system`, and Genesis explicitly warned
"partial state risk; container should be torn down." Reported by @ygafarov in
[#120](https://github.com/noonghunna/club-3090/issues/120#issuecomment-4443236686);
sidecar pattern shipped in v0.5.1.

The sidecar resolves it cleanly:
- Our patched files land in the container's RW layer (not bind-mounted RO)
- Genesis can write its hooks on top freely
- Host patches dir stays canonical (no Genesis hooks bleeding into our git tree)
- Each container restart starts fresh; Genesis re-applies on a clean copy

If a future patch to our overlay also touches `chat_completion/serving.py`
(e.g. when PR #35936's streaming hunks land for a nightly we pin to), the
sidecar layout supports it without further changes — our patched content
sits on disk in the install.sh source path, gets installed before Genesis
runs, Genesis layers its hooks on top.

## Validation

End-to-end checked 2026-05-12:

- Direct curl, `tool_choice="required"`, qwen3_coder parser: now returns
  `tool_calls=[{"function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]`
  (previously `tool_calls=[]`).
- Direct curl, `tool_choice="auto"`: still returns the same populated
  `tool_calls` (no regression on XML path).
- MLS-Bench `ml-ensemble-boosting` against `dual/int8.yml` with the
  `thinking.enabled: true` workaround removed from `configs/club-3090.yaml`:
  agent completes loop with non-zero steps (was "No action returned after
  3 attempts" pre-overlay).

Sidecar pattern validated 2026-05-13 on `single/long-text.yml` (Genesis-loaded):
- `install.sh` runs before Genesis: "chat_completion/serving.py installed from /etc/club3090/..."
- Genesis P64 succeeds: "P64 applied: 2 files modified, 0 idempotent" (was failing with `Read-only file system` pre-v0.5.1)
- Genesis P68/P69 succeed: "Hook injected into create_chat_completion" (was failing pre-v0.5.1)
- Zero `Read-only file system` errors anywhere in the boot log.

## Drop Trigger

Remove this overlay when vLLM PR #35936, or an equivalent fix, is merged
and present in the pinned vLLM image. At that point also revert
`MLS-Bench/configs/club-3090.yaml` (the `thinking.enabled` comment block
can come out).
