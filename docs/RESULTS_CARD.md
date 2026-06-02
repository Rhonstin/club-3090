# Results Card

A small, fixed format for sharing a config's **measured** results — in a discussion, an issue (see the [`numbers-from-your-rig`](../.github/ISSUE_TEMPLATE/numbers-from-your-rig.yml) template), a `learnings/` note, or a PR description.

It's the empirical counterpart to a compose's `Profile (at-a-glance)` header: the header declares *what the config is*, the Results Card reports *what it measured*. Three panels, always in this order — **Serving → Quality → Takeaways**.

## When to use it

Any time you post serving/quality numbers for a `(model, engine, topology, spec-dec, KV)` config. If you're A/B-ing one knob (thinking on/off, KV format, drafter `n`, …), use two value columns in the Quality table and bold the winner per row.

## Template

```markdown
### Serving — <engine + version>, <topology>

| Config | Spec-dec | KV / ctx | decode TPS (narr / code) | TTFT | VRAM / card |
|--------|----------|----------|--------------------------|------|-------------|
| <model + quant> | <MTP / DFlash / ngram / EAGLE / none> (draft, n=) | <k/v quant> · <max ctx> | <narr> / <code> | <ms> | <GB> |

_(engine-internal decode TPS; 3 warm + 5 measured; temp/top-k/top-p; image/pin; tracking issue. Note any spec-dec accept-rate or balance caveat.)_

### Quality — 8-pack suite (`benchlocal-cli`, verifier-backed, n=<N>)

| Pack | <setting A> | <setting B> |
|------|-------------|-------------|
| toolcall-15 | x/15 | x/15 |
| instructfollow-15 | x/15 | x/15 |
| structoutput-15 | x/15 | x/15 |
| dataextract-15 | x/15 | x/15 |
| reasonmath-15 | x/15 | x/15 |
| bugfind-15 | x/15 | x/15 |
| hermesagent-20 | x/20 | x/20 |
| cli-40 | x/40 | x/40 |
| **TOTAL (8-pack)** | **x/150 (y%)** | **x/150 (y%)** |

**Optional reasoning/code packs** _(on top of the core 8-pack — kept separate so /150 stays intact)_:

| Pack | <setting A> | <setting B> |
|------|-------------|-------------|
| humaneval-plus-30 | x/30 | x/30 |
| lcb-v6-30 | x/30 | x/30 |
| aider-polyglot-30 | x/30 | x/30 |

### Takeaways

- **<headline verdict>** — the single most important finding (bold lead).
- <comparison / tradeoff bullet>
- <production / stability note>
- _tl;dr — one line._
```

## Rules that keep cards comparable

- **The core 8-pack is exactly `/150`:** `toolcall-15 + instructfollow-15 + structoutput-15 + dataextract-15 + reasonmath-15 + bugfind-15 + hermesagent-20 + cli-40` (75 + 75). **Never fold the optional packs into the 150** — `humaneval-plus-30` / `lcb-v6-30` / `aider-polyglot-30` go in their own table below. (They're 30-sample subsets; compare the A/B **delta**, not absolute % against fuller external runs.)
- **Spec-dec is its own column** — MTP / DFlash / ngram / EAGLE / none. Don't rely on the config name to carry it; the same config name can run different spec methods.
- **State the n** (warm/measured runs for TPS; `n=` for quality). Don't present a single run as ranked truth — pack noise is ±5–7, so a small total delta is a tie.
- **Reproduce the conditions** in the Serving footnote: sampling params, engine image/pin, and `thinking on/off` (benchlocal sends `enable_thinking=false` unless you pass `--enable-thinking`).

## Posting to a public discussion/issue

- **No internal paths or secrets** — grep your draft for absolute host paths, model-store paths, and tokens before posting.
- **Don't link files that aren't on a public branch** (experimental/untracked composes 404 — describe them in prose, or link the image tag instead).
- **Verify every link resolves** (repo paths via `git ls-tree`, image tags via `docker manifest inspect`).

## Worked example

The first Results Card — Qwen3.6-27B Q8 on beellama v0.3.0 DFlash, thinking ON-vs-OFF — is [club-3090 discussion #221](https://github.com/noonghunna/club-3090/discussions/221#discussioncomment-17140596).
