# vLLM PR #40391 Per-Head KV Overlay

Diagnostic overlay built from upstream vLLM PR #40391 for Gemma 4
`int8_per_token_head` comparison.

This overlay is intentionally not recommended for deployment in its current
local form:

- Worker-only PR #40391 does not boot because the PR also needs its
  model/attention spec changes to set Gemma 4 padded page sizes.
- The diagnostic hybrid of Codex's generic page unifier plus PR #40391's worker
  padded-shape handling boots, but corrupts output on a simple smoke test.

See `../perheadkv-overlay-comparison.md` for the detailed result.
