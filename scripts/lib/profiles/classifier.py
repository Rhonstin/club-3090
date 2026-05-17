"""v0.8.0 Loop `[F]` — STEP F2: the §6.1 Tier-2 semantic-fingerprint classifier.

CONTRACT-2 Tier-2 (the LOCKED brief — `/opt/ai/docs/v0.8.0-loop-brief.md`
"## CONTRACT 2" + "## Appendix A"; source-of-truth design §6.1
`/opt/ai/docs/v0.8.x-design.md`). F1 (`loop_input.py`) produced the
validated `FInput`; this module CONSUMES it and emits exactly one §6.1
class or `unknown`.

Scope boundary (F2 vs F3):
  * F2 implements ONLY the §6.1 **Tier-2** semantic-fingerprint classifier
    + the seed DB + the routing rules that do NOT need Tier-1 data.
  * Tier-1 (the `torch.cuda.OutOfMemoryError` regex fast-path that emits a
    predicted-vs-actual delta = candidate kv-calc bug) is a LATER STEP F3.
    F3 needs the additive `[E]` touch (pt1.predicted_b_breakdown,
    pt3.failure_log_excerpt, pt3.actual.{...}) that F2 must NOT do. F2
    leaves a clean seam: `Tier.TIER1` exists in the enum but is never
    emitted here, and `route_as_kv_calc_bug` is HARD-WIRED False with the
    comment that F3's Tier-1 owns that gate (only `genuine-oom` WITH all
    three Tier-1 inputs present may ever set it — F2 has none of that).

§6.1 enum (VERBATIM — exactly these 6, no 7th value can leak):
    genuine-oom | overlay-arch-drift | kernel-unsupported |
    quant-unsupported | benign-cold-start | unknown

§6.1 routing (implemented + commented below):
  * classifier emits exactly one enumerated class OR `unknown`;
  * `benign-cold-start` is SUPPRESSED — `should_file=False` (never filed);
  * `unknown` -> `should_file=False` + `review_queue=True` (maintainer
    review queue `.pull-captures/_review-queue/`; NEVER auto-files a
    kv-calc bug);
  * `route_as_kv_calc_bug` is ALWAYS False in F2 — F3's Tier-1 owns it.

Mislabel safeguard: the §6.1 `failure_class` this module emits is the
value F1's `dedup_tuple()`/`dedup_hash()` consume into the §6.3 dedup key,
so a misclassification yields a different hash and can NEVER silently
merge with a real OOM.

PURE-PYTHON + the SAME PyYAML loader the rest of `scripts/lib/profiles/`
uses (`compat.py` `yaml.safe_load`) — no new dependency. House style
mirrors `deriver.py` (`class …(str, Enum)`, frozen dataclasses, return
structured results, never raise for an expected outcome).
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional

try:  # same import discipline as compat.py — reuse, do NOT add a dep.
    import yaml
except ModuleNotFoundError as exc:  # pragma: no cover - env guard
    raise RuntimeError(
        "scripts.lib.profiles.classifier requires PyYAML; install "
        "python3-yaml or pip install pyyaml"
    ) from exc

from scripts.lib.profiles.loop_input import FInput

# The seed DB ships next to this module (RED-LINE F2 file).
_DEFAULT_DB = Path(__file__).with_name("failure_fingerprints.yml")

# The normalized error-substring slice is length-bounded (same 240-char
# discipline as `[E]`'s `results_detail.error` cap, capture.py:254). The
# fingerprint salt is `arch_family + engine_version` (§6.1 verbatim).
_ERROR_SUBSTRING_CAP = 240


class FailureClass(str, Enum):
    """The §6.1 class enum — VERBATIM, exactly these 6. No additions.

    House style: `class …(str, Enum)` (mirrors `deriver.py` Confidence /
    DeriverErrorKind). The membership of THIS enum is the hard guarantee
    that no 7th value can ever leak out of `classify()`.
    """

    GENUINE_OOM = "genuine-oom"
    OVERLAY_ARCH_DRIFT = "overlay-arch-drift"
    KERNEL_UNSUPPORTED = "kernel-unsupported"
    QUANT_UNSUPPORTED = "quant-unsupported"
    BENIGN_COLD_START = "benign-cold-start"
    UNKNOWN = "unknown"


# §6.1 acceptance: `benign-cold-start` is suppressed (not filed); `unknown`
# -> maintainer review queue (never auto-files). Every OTHER class files a
# (deduped, F5) issue — but NEVER a kv-calc bug in F2 (that is F3 Tier-1).
_SUPPRESSED_NEVER_FILED = {FailureClass.BENIGN_COLD_START, FailureClass.UNKNOWN}


class Tier(str, Enum):
    """Which tier decided. F2 only ever emits `TIER2` (Tier-2 DB) or
    `NONE_UNKNOWN` (no match -> `unknown`). `TIER1` is the F3 SEAM — it is
    defined here so F3 plugs Tier-1 in front of Tier-2 without changing
    this enum, but F2 NEVER returns it.
    """

    TIER1 = "tier1"  # F3 SEAM — never emitted by F2.
    TIER2 = "tier2"
    NONE_UNKNOWN = "none-unknown"


@dataclass(frozen=True)
class ClassificationResult:
    """The §6.1 classifier verdict (returned, never raised).

    `failure_class`        — exactly one of the 6 `FailureClass` members.
    `tier`                 — which tier decided (F2: TIER2 or NONE_UNKNOWN;
                             TIER1 reserved for F3).
    `fingerprint`          — sha256(error_substring + arch_family +
                             engine_version)[:12] hex (same [:12]
                             truncation as F1 `dedup_hash`, for
                             consistency; documented in the YAML header).
    `should_file`          — False for `benign-cold-start` (suppressed) AND
                             `unknown` (review queue). True otherwise.
    `route_as_kv_calc_bug` — ALWAYS False in F2. F3's Tier-1 owns this
                             gate: only `genuine-oom` WITH all three Tier-1
                             inputs present (pt1.predicted_b_breakdown +
                             pt3.actual.attempted_alloc_mib +
                             pt3.actual.gpu_worker_reported_mib) may ever
                             set it. F2 has none of that data; hard-False.
    `review_queue`         — True iff `unknown` (-> maintainer review
                             queue `.pull-captures/_review-queue/`).
    `error_substring`      — the normalized, redacted, length-bounded slice
                             that was fingerprinted (surfaced for the F5
                             issue body / maintainer review).
    `matched_rule`         — id of the seed rule that matched, or None
                             (exact-hash hit -> the fingerprint; no match
                             -> None).
    """

    failure_class: FailureClass
    tier: Tier
    fingerprint: str
    should_file: bool
    route_as_kv_calc_bug: bool
    review_queue: bool
    error_substring: str
    matched_rule: Optional[str] = None


# ---------------------------------------------------------------------------
# error_substring extraction (CONTRACT-2 source precedence).
# ---------------------------------------------------------------------------
def _norm_error_substring(text: str) -> str:
    """Normalize + length-bound an error signal.

    Lowercase (matchers are case-insensitive by being compared lowercase),
    collapse whitespace (multi-line tracebacks -> a stable single string so
    the fingerprint is deterministic), strip, cap to `_ERROR_SUBSTRING_CAP`.
    The text is ALREADY `[E]`-redacted (pt3.failure_log_excerpt /
    results_detail.error go through `_redact_text`); F2 must NOT re-redact
    blindly (CONTRACT-3 stage-1: artifacts arrive pre-redacted).
    """
    collapsed = " ".join(str(text).split())
    return collapsed.lower()[:_ERROR_SUBSTRING_CAP]


def _extract_error_substring(finput: FInput) -> str:
    """CONTRACT-2 source precedence (works on TODAY's shipped [E] schema;
    forward-compatible with F3's additive fields, never requires them):

      1. pt3.failure_log_excerpt  — the F3/G6-A field; ABSENT until F3
                                     ships. Tolerated-if-present.
      2. pt3.failure              — the bare string; ALWAYS present in the
                                     [E]-shipped pt3 schema (capture.py).
      3. pt4 results_detail       — first `red` cap's `error`.

    `pt3.actual` is an F3-only structured object F2 NEVER reads (CONTRACT-1
    keeps `[F]` a pure bundle reader; F2 only reads what `[E]` ships today
    plus the additive excerpt if a future capture carries it).
    """
    pt3 = finput.pt3_boot or {}

    # (1) F3/G6-A forward-compat field (absent on today's [E] schema).
    excerpt = pt3.get("failure_log_excerpt")
    if excerpt:
        return _norm_error_substring(excerpt)

    # (2) the bare pt3.failure string — always present in [E]'s pt3 schema.
    failure = pt3.get("failure")
    if failure:
        return _norm_error_substring(failure)

    # (3) first red cap's redacted error in pt4.results_detail.
    pt4 = finput.pt4_smoke or {}
    results = pt4.get("results") or {}
    details = pt4.get("results_detail") or {}
    for cap, verdict in sorted(results.items()):
        if verdict == "red":
            detail = details.get(cap) or {}
            err = detail.get("error")
            if err:
                return _norm_error_substring(err)
            # red but no error text — still a real signal; key on the cap.
            return _norm_error_substring(f"smoke red:{cap}")

    return ""


def _fingerprint(error_substring: str, arch_family: str,
                 engine_version: str) -> str:
    """`sha256(error_substring + arch_family + engine_version)[:12]`.

    §6.1 verbatim salt is `arch_family + engine_version`. Truncated to 12
    hex chars to match F1's `dedup_hash` ([:12]) — consistency documented
    in `failure_fingerprints.yml`'s header.
    """
    joined = f"{error_substring}{arch_family}{engine_version}"
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:12]


# ---------------------------------------------------------------------------
# Seed DB load + Tier-2 matching.
# ---------------------------------------------------------------------------
def _load_db(db_path: Path) -> dict:
    """Load the seed DB with the SAME loader the rest of
    `scripts/lib/profiles/` uses (`compat.py` `yaml.safe_load`). No new
    dependency. A missing/empty file degrades to an all-`unknown` DB
    (honest: classify nothing rather than crash the offline loop).
    """
    if not db_path.is_file():
        return {"exact_fingerprints": {}, "condition_matchers": []}
    with db_path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    data.setdefault("exact_fingerprints", {})
    data.setdefault("condition_matchers", [])
    return data


def _pt3_timeout_but_pt4_green(finput: FInput) -> bool:
    """Appendix A row 7: pt3 boot timed-out/not-ready BUT pt4 smoked green
    (server became *healthy* after a slow first request) -> benign cold
    start.

    Requires a POSITIVE later-health signal: boot not-ok AND pt4 has at
    least ONE `green` cap AND NO `red` cap. An all-`unsmoked` pt4 is NOT a
    cold start — it means smoke never ran (the boot genuinely failed); that
    path must fall through to the log matchers / `unknown`, never be
    silently suppressed as benign.
    """
    pt3 = finput.pt3_boot or {}
    if pt3.get("ok"):
        return False
    pt4 = finput.pt4_smoke or {}
    results = pt4.get("results") or {}
    if not results:
        return False
    if any(v == "red" for v in results.values()):
        return False
    return any(v == "green" for v in results.values())


def _results_detail_http_404(finput: FInput) -> bool:
    """Appendix A row 8: historical negative control — [E] bug #1
    served-model-name 404 in pt4.results_detail (HTTP 404 status).
    """
    pt4 = finput.pt4_smoke or {}
    for detail in (pt4.get("results_detail") or {}).values():
        if isinstance(detail, dict) and detail.get("status") == 404:
            return True
    return False


def _match_condition(rule: dict, finput: FInput,
                     error_substring: str) -> bool:
    """Evaluate ONE Appendix-A condition matcher. FIRST match wins
    (caller iterates in YAML order). Unknown `kind` -> no match (a future
    matcher kind never crashes the offline classifier).
    """
    kind = rule.get("kind")

    if kind == "structural":
        pred = rule.get("predicate")
        if pred == "pt3_timeout_but_pt4_green":
            return _pt3_timeout_but_pt4_green(finput)
        if pred == "results_detail_http_404":
            return _results_detail_http_404(finput)
        return False

    if kind == "pt4_results":
        # The #145 class: a capability `red` while boot is green. Maps via
        # pt4, NOT a pt3 boot failure.
        pt3 = finput.pt3_boot or {}
        if rule.get("require_boot_green") and not pt3.get("ok"):
            return False
        pt4 = finput.pt4_smoke or {}
        results = pt4.get("results") or {}
        return results.get(rule.get("capability")) == rule.get("value")

    if kind == "log_substring":
        if not error_substring:
            return False
        return any(
            str(s).lower() in error_substring
            for s in (rule.get("any") or [])
        )

    if kind == "log_substring_all":
        if not error_substring:
            return False
        subs = rule.get("all") or []
        return bool(subs) and all(
            str(s).lower() in error_substring for s in subs
        )

    return False


def _coerce_class(value) -> FailureClass:
    """Map a DB string to the enum. ANY value not in the 6-member §6.1
    enum (a corrupt/typo'd seed row, an out-of-enum 7th value) degrades to
    `unknown` — the hard guarantee that no 7th value can leak.
    """
    try:
        return FailureClass(str(value))
    except ValueError:
        return FailureClass.UNKNOWN


# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------
def classify(
    finput: FInput,
    *,
    fingerprint_db_path: Optional[Path] = None,
) -> ClassificationResult:
    """Classify ONE capture bundle into exactly one §6.1 class or
    `unknown` (CONTRACT-2 Tier-2).

    F2 = Tier-2 ONLY. Order:
      1. Extract `error_substring` (CONTRACT-2 source precedence).
      2. Compute `fingerprint = sha256(error_substring + arch_family +
         engine_version)[:12]`.
      3. F3 SEAM: Tier-1 plugs in HERE, in front of Tier-2 (it will
         consult pt1.predicted_b_breakdown + pt3.actual.{...}). F2 has no
         Tier-1 data and does not implement it — fall straight through.
      4. Tier-2: exact-fingerprint table hit -> that class. Else first
         matching Appendix-A condition matcher -> its class. Else
         `unknown`.
      5. §6.1 routing: `benign-cold-start` + `unknown` -> should_file
         False; `unknown` -> review_queue True; `route_as_kv_calc_bug`
         HARD-False (F3 Tier-1 owns it).

    Never raises for an expected outcome (house style: structured result).
    """
    db = _load_db(
        Path(fingerprint_db_path) if fingerprint_db_path else _DEFAULT_DB
    )

    error_substring = _extract_error_substring(finput)
    arch_family = finput.arch_family
    engine_version = finput.engine_version
    fp = _fingerprint(error_substring, arch_family, engine_version)

    # ---- F3 SEAM -------------------------------------------------------
    # Tier-1 (the torch.cuda.OutOfMemoryError fast-path that emits a
    # predicted-vs-actual delta = candidate kv-calc bug) plugs in HERE, IN
    # FRONT of the Tier-2 block below, in STEP F3. It will read
    # pt1.predicted_b_breakdown + pt3.actual.{attempted_alloc_mib,
    # gpu_worker_reported_mib} (the additive [E] touch F2 must NOT do) and
    # be the ONLY path allowed to set route_as_kv_calc_bug=True (and only
    # when ALL THREE inputs are present). F2 implements NO Tier-1: it
    # falls straight through to Tier-2. `Tier.TIER1` exists in the enum
    # purely so F3 needs no enum change.

    # ---- Tier-2 --------------------------------------------------------
    matched_rule: Optional[str] = None
    tier = Tier.TIER2

    # (a) exact hash-keyed table (grown by maintainer-classified
    #     submissions; seeded empty — see YAML header).
    exact = db.get("exact_fingerprints") or {}
    if fp in exact:
        cls = _coerce_class(exact[fp])
        matched_rule = fp
    else:
        # (b) Appendix-A condition matchers — FIRST match wins.
        cls = None
        for rule in db.get("condition_matchers") or []:
            if _match_condition(rule, finput, error_substring):
                cls = _coerce_class(rule.get("class"))
                matched_rule = rule.get("id")
                break
        if cls is None:
            # (c) unmatched -> unknown -> maintainer review queue.
            cls = FailureClass.UNKNOWN
            tier = Tier.NONE_UNKNOWN

    # ---- §6.1 routing rules -------------------------------------------
    # exactly one class or `unknown` (guaranteed by _coerce_class +
    # FailureClass membership — no 7th value can leak).
    # `benign-cold-start` SUPPRESSED (not filed); `unknown` -> review
    # queue, not filed, never auto-files a kv-calc bug.
    should_file = cls not in _SUPPRESSED_NEVER_FILED
    review_queue = cls is FailureClass.UNKNOWN

    # HARD-WIRED False in F2. F3's Tier-1 is the ONLY code allowed to set
    # this True, and only for `genuine-oom` WITH all three Tier-1 inputs
    # present (pt1.predicted_b_breakdown + pt3.actual.attempted_alloc_mib
    # + pt3.actual.gpu_worker_reported_mib). F2 owns NEITHER the data nor
    # the gate — even a genuine-oom is should_file=True but
    # route_as_kv_calc_bug=False here (honest degrade: classified + filed
    # as a normal issue, never confidently-wrong as a kv-calc bug).
    route_as_kv_calc_bug = False

    return ClassificationResult(
        failure_class=cls,
        tier=tier,
        fingerprint=fp,
        should_file=should_file,
        route_as_kv_calc_bug=route_as_kv_calc_bug,
        review_queue=review_queue,
        error_substring=error_substring,
        matched_rule=matched_rule,
    )
