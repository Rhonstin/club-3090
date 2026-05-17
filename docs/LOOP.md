# The Loop phase — `[F]` of the v0.8.0 pull pipeline (#147)

Contributor/maintainer guide for the v0.8.0 **Loop** phase. The
Pull-Emit-Derived stage ([`docs/PULL_EMIT_DERIVED.md`](PULL_EMIT_DERIVED.md))
is the **producer**: for a download-eligible non-curated model it boots the
weights, smokes the endpoint, and writes the §6 capture artifacts. `[F]` is
the **consumer**: it reads that on-disk bundle, classifies what happened,
runs an inbound-trust pipeline over success anchors, and dedups failure
issues into the tracker. It is the loop that turns one user's boot/OOM into
a classified, deduped, consensus-keyable signal feeding the calibration
backbone.

`[F]` is **not** a `run_pull()` stage. Unlike `[E]` (which runs *inside*
`run_pull()`), `[F]` is offline / at-submit-time: it never puts
network/issue-tracker I/O on the gate path. `[E]` writes honest structured
truth and explicitly does **not** classify (`failure_class` is `null` in
every `[E]` manifest, and `outcome` is an interim 3-state); `[F]` is the
phase that does the classifying, trusting, deduping, and consuming.

> ### The authoritative spec is the test, not this doc
> Per the locked v0.8.0 stop-condition, the executable specs are
> authoritative. For `[F]` those are
> **`scripts/tests/test-loop-input.sh`** (CONTRACT-1: the `FInput`
> reader), **`scripts/tests/test-classifier.sh`** (CONTRACT-2: the
> two-tier classifier + the Appendix-A seed corpus),
> **`scripts/tests/test-trust-pipeline.sh`** (CONTRACT-3 / 3a: the
> inbound-trust pipeline), **`scripts/tests/test-dedup.sh`**
> (CONTRACT-4: the dedup key + label scheme + submit path), and
> **`scripts/tests/test-kvcalc-version.sh`** (CONTRACT-5: the
> content-derived version provenance). Where this prose and any of those
> tests ever disagree, **the test is correct**; fix the doc. This
> document is the explanatory companion.

For the producer it consumes see [`docs/PULL_EMIT_DERIVED.md`](PULL_EMIT_DERIVED.md);
for the gate that precedes both, [`docs/PULL_GATE.md`](PULL_GATE.md).

> **On-rig status:** the five `test-*.sh` suites listed above are green and
> are the shipped F1–F6 contract. The real `[F]` end-to-end run over live
> capture dirs (the 7 real capture dirs from the `[E]` on-rig run, a
> deliberately-induced boot-OOM, and the Appendix-A seed replay) is the
> genuine validator and is the **remaining step (F8)**. Nothing below
> describes the on-rig `[F]` run as validated; it describes the shipped,
> unit-verified F1–F6 behaviour. A green mocked suite is
> necessary-not-sufficient — that is the lesson `[E]` taught.

---

## 1. Where `[F]` sits, and the bundle it consumes

`[E]` writes, schema **v1**, redacted JSON, under:

```
<repo>/.pull-captures/<slug-sanitized>/<utc-ts>/
```

A capture directory contains four required capture points + a top-level
manifest, plus a fifth file only on the override-accepted path:

| File | Point | Role for `[F]` |
|---|---|---|
| `pt1-gate.json` | pre-download gate verdict | the predicted side of the OOM delta (`predicted_b_breakdown`, post-`[B]`) |
| `pt2-download.json` | download | download `ok` / `failure` |
| `pt3-boot.json` | boot | the raw boot `failure` (**not** classified by `[E]`), plus the container-log excerpt + the parsed `actual` numbers |
| `pt4-smoke.json` | post-boot capability-aware smoke | per-capability `green`/`red`/`unsmoked` results |
| `manifest.json` | §6.2/§6.3 manifest | every consensus/dedup input as a **first-class key** + `submission_fingerprint` + `failure_class:null` + the interim `outcome` |
| `pt5-override-capture.json` | override force-capture | present **iff** override-accepted; richer predicted/actual + `calibration_signal_not_validated:true` |

Two binding rules `[F]` enforces, both grounded in shipped `[E]` code:

* **`failure_class` is authoritatively `null` in every `[E]` manifest.**
  `[F]` computes it; F1 actively *rejects* a bundle whose manifest
  `failure_class` is non-null (a non-null value means `[E]` wrongly
  classified, which it must never do).
* **`outcome` is `[E]`'s interim honest 3-state (`failed > partial > ok`),
  NOT the §6.1 class enum.** F1 surfaces the raw value but there is
  deliberately no accessor that reinterprets it as a class. The final
  failure taxonomy is owned by the `[F]` classifier (§6.1), which derives
  it from the bundle itself.

---

## 2. F1 — the `FInput` capture-bundle reader (CONTRACT-1)

`scripts/lib/profiles/loop_input.py` parses **one** capture directory into
a strict, validated `FInput` object that the later STEPs consume. It is a
**boundary validator**: any schema/shape violation raises a typed
`CaptureBundleError` — never a silent partial parse, so downstream STEPs
can trust every field.

What F1 enforces:

* `manifest["schema"] == 1` (hard-asserted); pt1 carries `schema` and is
  asserted, pt2–pt4 do not ship a `schema` key so it is asserted
  only-where-present; each ptN's `point` value must be exactly its
  expected value.
* every CONTRACT-1 first-class consensus/dedup key is present on the
  manifest (`model`, `quant_label`, `arch_family`, `topology_class`,
  `engine_pin`, `engine_version`, `kv_calc_version`, `selected_ctx`,
  `kv_format`, `smoke_capability_set`, `topology_summary_canonical`,
  `model_id`, `submission_fingerprint`, `outcome`, …).
* pt5 is optional and loaded only when present (override-accepted path).
* **forward-compat:** F1 tolerates F3's additive keys
  (`pt1.predicted_b_breakdown`, `pt3.failure_log_excerpt`, `pt3.actual`)
  being present *or* absent — it validates only the `[E]`-shipped required
  shape and never rejects an additive key.

Key normalization is **`[F]`'s job, not `[E]`'s** (CONTRACT-1):

| Field | Normalization | Why |
|---|---|---|
| `quant_label` | **lowercased** for keying | raw value is `weight_format` case-as-emitted |
| `arch_family` | **verbatim** | it is `config.json["architectures"][0]` — already an exact identifier; re-normalizing would corrupt it |
| `model_id` | `≡ manifest["model"]` | shipped alias |
| `engine_version` | `≡ manifest["engine_pin"]` | shipped alias |

F1 also owns the canonical key builders (single-sourced here so every STEP
hashes identically):

* `consensus_key()` — the §6.2 **9-tuple** `(model, quant_label,
  arch_family, topology_class, engine_pin, kv_calc_version, selected_ctx,
  kv_format, smoke_capability_set)`. Validates *success* anchors.
* `dedup_tuple()` — the §6.3 **7-tuple** `(model_id, quant_label,
  arch_family, kv_calc_version, engine_version, failure_class,
  topology_class)`. Dedups *failure* issues. Its `failure_class` slot is
  the manifest's `None` here; F5 substitutes the classifier's class.
* `dedup_hash()` — `sha256("\x1f".join(str(p) for p in tuple))[:12]`, the
  same `\x1f`+sha256 convention `[E]` uses for `submission_fingerprint`,
  truncated to 12 hex.

The §6.2 consensus key and the §6.3 dedup key are **deliberately different
keys** — the consensus key carries `selected_ctx`/`kv_format`/
`smoke_capability_set` and no `failure_class`; the dedup key carries
`failure_class` and no ctx/KV/smoke. Conflating them re-opens a closed
design finding.

---

## 3. F2/F3 — the §6.1 two-tier failure classifier (CONTRACT-2)

`scripts/lib/profiles/classifier.py` consumes an `FInput` and emits exactly
one §6.1 class or `unknown`. The §6.1 enum is **verbatim, exactly these
six** (no 7th value can leak — enforced by `FailureClass` membership and a
`_coerce_class` that degrades any out-of-enum value to `unknown`):

```
genuine-oom | overlay-arch-drift | kernel-unsupported |
quant-unsupported | benign-cold-start | unknown
```

Two tiers; **Tier-1 (F3) plugs in front of Tier-2 (F2)**:

### Tier-1 — the OOM fast-path (F3)

A regex for the definitive OOM signature
(`torch.cuda.OutOfMemoryError` / "cuda out of memory" / variants) over the
already-redacted error substring. On a match → **always `genuine-oom`**,
decided by `Tier.TIER1`. The numbers are read from the **structured**
`[E]` fields, never from raw logs (`classifier.py` is a pure bundle reader
— it only detects the OOM *signature*; the magnitudes come from `[E]`'s
parsed `pt3.actual`).

Tier-1 needs **all three** inputs to route a kv-calc bug:

1. `pt1.predicted_b_breakdown` — the predicted `[B]` GB breakdown,
   persisted by F3's additive `[E]` touch for **all** post-`[B]` captures
   (previously only on the override path);
2. `pt3.actual.attempted_alloc_mib` — parsed by `[E]` at capture time from
   the OOM traceback in the container log;
3. `pt3.actual.gpu_worker_reported_mib` — parsed by `[E]` from the
   gpu-worker measured-peak line.

The **input precedence** (A-iii) is: pt5 structured fields > (pt3
`failure_log_excerpt` + `pt3.actual` + `pt1.predicted_b_breakdown`) > the
bare `pt3.failure` string.

**Routing gate (verbatim):** `route_as_kv_calc_bug=True` **only** when
`failure_class == genuine-oom` AND all three inputs are present. Otherwise
the failure is still classified `genuine-oom` and still filed as a normal
issue — but `route_as_kv_calc_bug=False`. This is the **honest-degrade**
rule: never a confidently-wrong kv-calc-bug filing on incomplete inputs.
The predicted-vs-actual delta (`gpu_worker_reported_mib − predicted_total`)
is computed only when both sides are usable numbers; never fabricated.

### Tier-2 — the semantic-fingerprint DB (F2)

Reached only when Tier-1 finds no OOM signature. `error_substring` is
extracted by source precedence (`pt3.failure_log_excerpt` →
`pt3.failure` → first `red` cap's `pt4.results_detail.error`), normalized
and length-capped, then `fingerprint = sha256(error_substring +
arch_family + engine_version)[:12]` (the §6.1 verbatim salt).

The seed DB ships at `scripts/lib/profiles/failure_fingerprints.yml` with
two sections:

* `exact_fingerprints:` — a hash-keyed exact-match table. **Seeded empty
  by design**: real fingerprints depend on this rig's live error text
  (the arch/engine salt makes them rig/pin-specific). It is **grown via
  maintainer-classified submissions** — when a maintainer reclassifies an
  `unknown`, the resolved `(fingerprint → class)` is appended so the next
  identical run is an O(1) hit.
* `condition_matchers:` — the **Appendix-A binding seed corpus**, ordered;
  first match wins. This is what classifies today (the exact table grows
  on top of it). Each row maps a structural/substring condition to its
  §6.1 class — e.g. the `#145` streaming-dead case (boot green, streaming
  `red`, mapped via pt4) → `quant-unsupported`; a weight-load dtype error
  → `quant-unsupported`; a missing-symbol/patch-absent error →
  `overlay-arch-drift`; an SM90/FA3 kernel assert → `kernel-unsupported`;
  a cold-start-then-green or a historical served-name-404 → the in-enum
  `benign-cold-start`; an `OutOfMemoryError` substring →
  `genuine-oom`. Anything unmatched → `unknown`.

### §6.1 routing rules (implemented)

| Class | `should_file` | Routed |
|---|---|---|
| `benign-cold-start` | **False** — suppressed (never filed) | — |
| `unknown` | **False** — to the maintainer review queue (`.pull-captures/_review-queue/`); never auto-files a kv-calc bug | — |
| any other (`genuine-oom`, `overlay-arch-drift`, `kernel-unsupported`, `quant-unsupported`) | True — files a deduped issue (F5) | kv-calc bug only via Tier-1 + all-3-present |

`route_as_kv_calc_bug` is **hard-False in F2** — only F3's Tier-1 may ever
set it True. The `failure_class` the classifier emits is the value F5
hashes into the §6.3 dedup key, so a misclassification yields a different
hash and can **never** silently merge with a real OOM (the §6.1 mislabel
safeguard).

### The F3 [E]-side additions (what F3 added to the producer)

F3 made a bounded, additive, byte-preserving touch to the `[E]` producer so
Tier-1 works on the **normal** boot path, not just the override path:

* `pt1.predicted_b_breakdown` — persisted for all post-`[B]` captures.
* `pt3.failure_log_excerpt` — a bounded, `_redact`-scrubbed
  `docker compose logs --no-color` excerpt (the **container** log, where
  the vLLM OOM traceback and the gpu-worker peak line actually land —
  *not* compose-up stderr, which structurally cannot contain the
  in-container traceback). `--no-color` is mandatory: ANSI escapes in
  container logs corrupt the Tier-1 regex.
* `pt3.actual.{attempted_alloc_mib, gpu_worker_reported_mib}` — parsed by
  `[E]` at capture time from that excerpt into structured `int|None`
  fields. `classifier.py` only **reads** these; it never touches raw
  logs.

---

## 4. F4 — the §6.2 inbound-trust pipeline (CONTRACT-3 / 3a)

`scripts/lib/profiles/trust_pipeline.py` consumes the F1 `FInput` + the
F2/F3 `ClassificationResult` and runs the 4-stage success-anchor pipeline:

```
raw  ->  candidate  ->  validated  ->  tier1
```

| Stage | Gate | Stop reason if it fails |
|---|---|---|
| **raw** | the bundle arrived `[E]`-redacted; the manifest first-class keys are the machine source (the `report.sh --redact` Markdown is an *optional* human-triage attachment, never required, never re-redacted). A well-formed `FInput` is at least `raw`. | — |
| **candidate** | re-derive `submission_fingerprint` from the manifest with `[E]`'s exact `\x1f`+sha256 8-tuple and verify it equals the claimed value; **then** the capability-aware smoke gate. | `fingerprint-mismatch` (stays `raw`); `no-green-capability` |
| **validated** | topology plausible (a basic GPU/VRAM bounds floor — not a hardware model) **AND** (multi-submission consensus on the full §6.2 9-tuple **OR** `maintainer_promoted=True`). | `topology-implausible`; `insufficient-consensus` |
| **tier1** | curated anchor only — emits the would-be `calibration/<model>.yml` row **shape** (`status: candidate-tier1`, never `active`). | derived → `derived-tier1-deferred-v0.8.1` |

Key properties grounded in the shipped code:

* **`submission_fingerprint` is re-derived and verified, never re-minted.**
  `[E]` mints it; F4 recomputes it byte-exactly and rejects a mismatch as
  a tampered/corrupt correlation. It is **correlation, not security** —
  the fields are user-controlled; the real trust gate is consensus +
  maintainer promotion.
* **Capability-aware smoke graduation is green-only.** The `graduation_set`
  is exactly the capabilities with `pt4.results[cap] == "green"`.
  `unsmoked`/`red` caps **never** graduate. A `partial` anchor graduates
  **only its green caps**, never the model wholesale — this is the
  `#145`-class guard (a model that boots and answers plain-chat while
  streaming/tools are silently dead must not graduate those caps).
* **Consensus is matching, not automation.** F4 ships the consensus-key
  *matching* primitive (count submissions whose full 9-tuple equals this
  anchor's; default `consensus_n=2`) plus the `maintainer_promoted` manual
  hook. The N≥2 auto-promotion **automation** is the deferred sub-scope;
  early-phase maintainer manual promotion is the v0.8.0 mechanism, which
  the design explicitly permits.
* **Success anchors are NOT gated on a predicted-vs-actual delta.** The
  "delta ≤ tolerance" check belongs to the §6.1 failure → kv-calc-bug
  branch (pt5 / Tier-1). A successful boot has no OOM delta. F4's
  `tolerance` argument is accepted-and-ignored on purpose so a caller that
  mistakenly passes one does not break — it has no effect on the verdict.
* **CONTRACT-3a — derived anchors are classifier+dedup-only this phase.**
  The calibration backbone hard-cross-ref-validates every row against
  `COMPOSE_REGISTRY`; a generic-dense derived model has no registry entry,
  so it **cannot** be a calibration row as-is. F4 detects
  curated-vs-derived: a derived anchor stops at `validated` with reason
  `derived-tier1-deferred-v0.8.1` (it still flows fully through the
  classifier + dedup — F4 just does not push it to the calibration
  backbone). The **derived → calibration-backbone bridge is deferred to
  v0.8.1.** A curated anchor may reach `tier1`, where F4 emits the
  would-be calibration row *shape* only — it never edits calibration YAML
  and never runs kv-calc; that ingestion is a separate, later,
  manual/maintainer concern.

---

## 5. F5 — the §6.3 dedup key + label scheme + submit path (CONTRACT-4)

`scripts/lib/profiles/dedup.py` consumes F1 + the classifier result and
runs the dedup-or-file submit path.

* **The effective dedup key.** F5 reuses F1's normalized 7-tuple and
  substitutes the **classifier's** `failure_class` into position 5 (it was
  `None` pre-classification), then hashes with F1's exact
  `sha256("\x1f".join(...))[:12]` convention via F1's own primitive (zero
  convention drift — single-sourced in `loop_input.py`). **All 7
  dimensions are in the hash** — no dimension can be silently dropped from
  the match.
* **Bounded, collision-safe labels.** Exactly three, all bounded:
  * `loop:dedup-<12hex>` — the dedup primitive;
  * `class:<failure_class>` — one of the 6 §6.1 enum values;
  * `arch:<arch_family>` — a short identifier, slug-sanitized +
    length-capped.

  **No** raw `model:` / `engine:` / `kvcalc:` / `topo:` labels are ever
  produced — those values are unbounded (arbitrary HF slugs, moving image
  pins) and live in the issue **body**, never as labels. The full
  canonical 7-tuple is written into the body as a fenced ```json block
  with a stable schema marker.
* **Verify-body-before-+1.** Query
  `gh issue list --label loop:dedup-<hash> --state all`; if a candidate
  exists, **parse its body tuple and verify it equals the full effective
  7-tuple before adding a +1**. A sha12 truncation can (astronomically
  rarely, or via a crafted body) collide — F5 never +1's on a hash-label
  match alone; a body-tuple mismatch is treated as no-match → open a new
  issue (never silently merge two distinct failures).
* **Filing policy first.** Before any `gh` I/O: `should_file == False`
  short-circuits — `benign-cold-start` is **suppressed** (not filed, not
  spooled-as-issue); `unknown` goes to the review-queue spool, not the
  tracker. F5 never files a "kv-calc bug" — `route_as_kv_calc_bug` is F3's
  calibration signal, a different pipeline; the boundary is stated in the
  code so a future reader does not wire calibration-bug filing into dedup.
* **gh-guarded, never blocks.** Every `gh` call goes through an injectable
  runner. A missing/unauthenticated/failed/timed-out `gh` degrades to a
  local spool (`.pull-captures/_dedup-queue/<hash>.json`) the maintainer
  can replay. F5 **never raises and never blocks `[E]`** — CONTRACT-1
  keeps `[F]` off the gate path. `bootstrap_labels()` idempotently creates
  the bounded `class:*` set with `gh label create --force`; `loop:dedup-*`
  and `arch:*` are created per-issue (their value space is per-failure,
  not a fixed bootstrap set).

---

## 6. F6 — version provenance integrity (CONTRACT-5)

The `kv_calc_version` string stamped into every capture manifest feeds the
§6.2 consensus key, the §6.3 dedup key, and `submission_fingerprint`. F6
makes it **content-derived**:

```
kv_calc_version = "kvcalc-v0.8.0+" + sha256(<content>)[:12]
<content> = bytes(tools/kv-calc.py)
            + sorted-concat(scripts/lib/profiles/calibration/*.yml)
```

joined with the same `\x1f` separator and sha256 convention as
`submission_fingerprint`, computed once at import. If the content surface
is unreadable for any reason the producer degrades to the bare
`"kvcalc-v0.8.0"` and never raises (`[E]`/pull must not crash over a
provenance-label refinement).

> **CONTRACT-5 (i) — residual-risk note (stated here by mandate).** Before
> F6, `kv_calc_version` was a hardcoded constant. A manual constant is
> only as strong as manual bump discipline: a calibration-affecting
> edit to `tools/kv-calc.py` or to the calibration corpus that did **not**
> change the constant would let materially-different runs **silently
> collide** on the consensus / dedup / `submission_fingerprint` keys —
> i.e. two runs with different kv-calc behaviour would be treated as the
> same anchor. Deriving the version from a content hash of the kv-calc
> math **and** the calibration corpus is the mitigation: any math or
> corpus edit moves the hash automatically, with no manual bump needed, so
> the freshness guarantee no longer depends on discipline. This is purely
> how the version *string* is computed — zero decision-logic touch (gate
> states, terminals, `[B]`, `[C1]`, verdicts, the strata table are all
> untouched). `test-kvcalc-version.sh` asserts the version moves when the
> kv-calc math changes **and** when a `calibration/*.yml` changes — the
> regression that is only satisfiable *because* the content-derivation is
> mandatory.

F6 also synced the on-rig topology fixture to the live
`detect_gpu_topology` format so `topology_summary_canonical` can be relied
on for automated validation (the G1 verification gate; the live-capture
confirmation is part of the on-rig F8 step).

---

## 7. In scope for v0.8.0 vs deferred to v0.8.1

| Item | Status |
|---|---|
| Capture-bundle reader, two-tier classifier, inbound-trust pipeline, dedup + structured-label submit path | **v0.8.0** (F1–F6, shipped + unit-verified; on-rig F8 pending) |
| **Consensus automation** (N≥2 auto-promote) | **deferred sub-scope** — v0.8.0 ships the consensus-key *matching* primitive + **maintainer manual promotion** (the design explicitly permits early-phase manual) |
| **Derived-anchor → calibration-backbone Tier-1 ingestion** | **v0.8.1** — v0.8.0 `[F]` scopes derived anchors to **classifier + dedup only**; curated-only Tier-1 |
| **GGUF / `.bin` / whichllm** | **v0.8.1** — no GGUF capture path exists; the classifier must not assume one |
| Security / threat model on `submission_fingerprint` | **out** — it is correlation, not security (fields are user-controlled); the trust gate is consensus + maintainer promotion, not crypto |
| On-rig `[F]` validation | **F8 — the remaining step** (the genuine validator; a green mocked suite is necessary-not-sufficient) |

### The §10-R9 risk, carried forward (not silently assumed away)

`[F]` does **not** assume the loop reaches self-sustaining volume. The
design carries an explicit risk that this doc states faithfully:

> Per-anchor maintainer manual promotion has the **same scaling ceiling**
> as per-model releases. v0.8.0 **reshapes, it does not escape**, the
> release treadmill — and it **bets** that community submission volume
> reaches §6.2 consensus. The explicit kill/reassess criterion: **if 90
> days post-v0.8.0 the consensus path is still <10% of validated anchors,
> the replacement mechanism has failed → reassess whether the curated
> backbone must stay the primary support surface.**

This is a carried risk, not an assumed outcome. The Loop closes the
failure-intelligence + dedup loop for every model (curated and derived)
*today*; whether it becomes self-sustaining is what the 90-day measurement
decides.

---

## 8. Running the executable specs

From the repo root:

```
bash scripts/tests/test-loop-input.sh        # CONTRACT-1 (FInput reader)
bash scripts/tests/test-classifier.sh        # CONTRACT-2 (two-tier classifier + Appendix A)
bash scripts/tests/test-trust-pipeline.sh    # CONTRACT-3 / 3a (inbound-trust pipeline)
bash scripts/tests/test-dedup.sh             # CONTRACT-4 (dedup key + labels + submit path)
bash scripts/tests/test-kvcalc-version.sh    # CONTRACT-5 (content-derived version provenance)
python3 tools/kv-calc.py --calibration       # must stay Overall: 22/22 (100%)
```

These are the authoritative spec; this document is the explanatory
companion. Where they disagree, the test wins. `[F]` is purely additive —
it touches no shipped pipeline decision logic, so the prior suites and the
kv-calc 22/22 contract are unaffected.
