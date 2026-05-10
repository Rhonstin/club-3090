# Quality testing on club-3090

Operational tests (`verify` / `verify-full` / `verify-stress` / `bench` / `soak-test`) tell you whether a compose **serves** correctly. They don't tell you whether the model **behaves** correctly — whether tool calls land on the right functions, whether instruction-follow constraints hold, whether structured-output stays valid JSON. A compose can pass every operational layer and still ship with degraded behavioral quality from quantization drift or a Genesis env-var flip.

`scripts/quality-test.sh` closes this gap. It wraps [`benchlocal-cli`](https://github.com/noonghunna/benchlocal-cli) — a CLI port of [BenchLocal](https://github.com/stevibe/BenchLocal) bench packs — and runs verifier-backed scenarios against the running compose endpoint.

## Where it sits in the pipeline

```
verify.sh         — fast smoke (15s,        "does it serve")
verify-full.sh    — functional (1-2min,     "does everything work")
verify-stress.sh  — boundary (5-10min,      "does it survive stress")
bench.sh          — throughput (3-5min,     "what's the TPS")
quality-test.sh   — behavioral (10-30min,   "does it produce useful output")  ← THIS
soak-test.sh      — stability (30-60min,    "does it stay healthy over time")
```

Each layer has a different question. Quality testing is the one that catches "passed every other gate but produces wrong tool calls or violates format constraints."

## What the packs measure

Five deterministic packs, all verifier-backed (no LLM-as-judge):

| Pack | Dimension | Why it matters for club-3090 users |
|---|---|---|
| **ToolCall-15** | Tool selection + argument correctness | IDE-agent traffic (Cline / OpenCode / Cursor) is 100% tool calls. Genesis env flips like P68/P69 cause silent-empty regressions that die here. |
| **InstructFollow-15** | Constraint-heavy instruction compliance | Catches "ignore the format constraint" drift from cudagraph mode changes or sampling tweaks. |
| **StructOutput-15** | JSON / YAML / markdown structure validity | Bounded-thinking, JSON tool args, FSM-constrained reasoning. |
| **ReasonMath-15** | Numeric reasoning | Code-reasoning correctness; Q4-quant drift surfaces here first. |
| **DataExtract-15** | Field-level extraction accuracy | RAG / document-Q&A workloads. |

Three more packs (BugFind-15, HermesAgent-20, CLI-40) are available in the upstream catalog but require sandbox infrastructure (Docker code execution / multi-tool harness / Linux exec) that isn't wired up in v0.x. Their scenarios ship in the JSONL but the verifiers return `verifier_not_implemented`.

## Modes

| Mode | Packs | Budget | When to run |
|---|---|---|---|
| `--quick` | ToolCall + InstructFollow | ~10-15 min | Per-commit gate; pre-push smoke. The two packs that catch the highest-value regressions for IDE-agent users. |
| `--medium` (default) | + StructOutput + DataExtract | ~25-30 min | Pre-release; pin bumps; new compose authoring. Generates the `Quality:` line for the compose schema. |
| `--full` | + ReasonMath + warn-skip stubbed | ~45-60 min | Cross-rig comparison; quality A/B vs another quant. |

## Install (one-time)

```bash
pip install git+https://github.com/noonghunna/benchlocal-cli.git
```

Or for development from a local clone of benchlocal-cli:

```bash
pip install -e /path/to/benchlocal-cli
```

## Run

```bash
# default --medium against the auto-detected running compose
bash scripts/quality-test.sh

# faster mode (per-commit gate)
bash scripts/quality-test.sh --quick

# full mode (pin bumps, cross-rig comparison)
bash scripts/quality-test.sh --full

# explicit endpoint override
URL=http://localhost:8011 bash scripts/quality-test.sh --quick

# attempt sandboxed packs (BugFind/HermesAgent/CLI — currently stubbed, will skip with warning)
ENABLE_SANDBOXED=1 bash scripts/quality-test.sh --full
```

Output:

1. **Markdown table to stdout** — paste-ready for BENCHMARKS quality rows
2. **JSON to `results/quality/quality-<timestamp>.json`** — full per-scenario detail for delta tracking
3. **One-liner suitable for the compose `Quality:` schema field** — paste into compose YAML header

Example output:

```
=== benchlocal-cli --medium  (endpoint: http://localhost:8020, model: qwen3.6-27b-autoround) ===

Pack                       | Pass / Total | Score | p50 latency | p95 latency | Status
ToolCall-15 (v1.0.1)       |   14 / 15    |  93%  |     8.2s    |     12.1s   | ✅
InstructFollow-15 (v1.0.0) |   13 / 15    |  87%  |    11.4s    |     17.8s   | ✅
StructOutput-15 (v1.0.0)   |   15 / 15    | 100%  |     6.9s    |      9.2s   | ✅
DataExtract-15 (v1.0.0)    |   12 / 15    |  80%  |     7.3s    |     10.5s   | ✅
─────────────────────────|──────────────|───────|─────────────|─────────────|──────
TOTAL                      |   54 / 60    |  90%  |             |             |

Failure breakdown:
  ToolCall-15           1 verifier_fail  (TC-07: wrong arg value for "filename")
  InstructFollow-15     2 verifier_fail  (IF-03 word-count, IF-09 citation-format)
  DataExtract-15        2 missing_field, 1 wrong_value

==========================================================================
Quality: line for compose schema field (paste into compose YAML header):
==========================================================================
Quality:   ToolCall-15 14/15 (93%) · InstructFollow-15 13/15 (87%) · StructOutput-15 15/15 (100%) · DataExtract-15 12/15 (80%) (--medium, packs v1.0.x, 2026-05-09)
```

## Compose `Quality:` schema field

Each compose's `Profile` header (per [`AGENTS.md`](../AGENTS.md)) can carry an optional `Quality:` line:

```yaml
# Profile (at-a-glance):
#   Model:     Qwen3.6-27B (Lorbus AutoRound INT4 + BF16 mtp.fc preserved)
#   Topology:  Dual 3090 PCIe (TP=2, no NVLink)
#   ...
#   Status:    ✅ Production
#   Quality:   ToolCall-15 14/15 (93%) · InstructFollow-15 13/15 (87%) · StructOutput-15 15/15 (100%) · DataExtract-15 12/15 (80%) (--medium, packs v1.0.x, 2026-05-09)
#   Best for:  General-purpose dual-card vision + tools + long-ctx default ⭐
```

The line documents what the compose was tested on. Cross-rig contributors running quality-test.sh against the same compose can paste their numbers as a sibling row in BENCHMARKS.md.

Compact format (one line) so the schema header doesn't bloat. Full per-scenario detail lives in the JSON saved by quality-test.sh, which can be diffed against past runs for regression tracking.

## What "passing" means

`quality-test.sh` does NOT enforce a hard pass/fail threshold. The script always exits 0 if the runner completes; you decide whether the scores are acceptable.

Suggested gates (informal, not enforced):

| Pack | Suggested floor | Notes |
|---|---|---|
| ToolCall-15 | ≥80% | Below this, IDE-agent users will report regressions |
| InstructFollow-15 | ≥80% | Below this, format-constraint workflows break |
| StructOutput-15 | ≥90% | JSON shape failures are visible immediately to users |
| DataExtract-15 | ≥75% | Slightly more tolerant; field-level scoring is granular |
| ReasonMath-15 | ≥60% | Reasoning quality varies more by quant; treat as informational |

For comparing a new pin / quant / config A/B against the previous version: a >10pp drop on any pack vs the previous baseline is a signal worth investigating before promoting `Status: ✅ Production`.

## What it doesn't replace

- **`bench.sh`** measures throughput, not quality. They're complementary.
- **`soak-test.sh`** measures stability over time. Quality + soak together catch "fast + correct + healthy."
- **NIAH (needle-in-haystack)** tests in `verify-stress.sh` measure long-context retrieval correctness — a different axis than tool-call / instruction-follow.

## Limitations (v0.x)

1. **Sandboxed packs (BugFind / HermesAgent / CLI-40) are stubbed** until verifier infrastructure lands. They appear in `--full` mode but skip with a warning.
2. **Verifier translation is lossy in places** — the upstream BenchLocal evaluators have partial-credit branches we collapsed to pass/fail. See benchlocal-cli's [`docs/EXTRACTOR_NOTES.md`](https://github.com/noonghunna/benchlocal-cli/blob/master/docs/EXTRACTOR_NOTES.md) for the specific surfaces.
3. **Single-run sampling** — each scenario runs once by default. For non-determinism debugging, use `benchlocal-cli run --pack <id> --repeat N` directly.

For the full pipeline architecture + JSONL pack format, read [benchlocal-cli's docs](https://github.com/noonghunna/benchlocal-cli/tree/master/docs).

## Filing quality regressions

If `quality-test.sh` shows a meaningful regression (e.g., ToolCall-15 drops from 14/15 to 8/15 after a Genesis pin bump), file an issue with:

1. The compose name + the change that triggered it (Genesis pin bump? new quant? cudagraph mode?)
2. The full JSON output from `results/quality/`
3. The pre-change baseline JSON for diff
4. Output of `bash scripts/report.sh --bench` for context (vLLM image SHA, Genesis commit, hardware)

The JSON blobs include enough per-scenario detail to reproduce specific failing scenarios via `benchlocal-cli reproduce` (post-v0.2 subcommand) for upstream debugging.
