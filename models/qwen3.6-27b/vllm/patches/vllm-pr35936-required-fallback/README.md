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
a matching drop-in mount target. The PR's streaming-side hunks target a
pre-parser-manager code path that has been refactored on `nightly-1acd67a79`;
non-streaming clients (MLS-Bench, our curl repro, most agent harnesses)
exercise only the engine-side fix.

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

## Drop Trigger

Remove this overlay when vLLM PR #35936, or an equivalent fix, is merged
and present in the pinned vLLM image. At that point also revert
`MLS-Bench/configs/club-3090.yaml` (the `thinking.enabled` comment block
can come out).
