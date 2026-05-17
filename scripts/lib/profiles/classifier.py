"""v0.8.0 Loop `[F]` — STEP F2+F3: the §6.1 two-tier failure classifier.

CONTRACT-2 (the LOCKED brief — `/opt/ai/docs/v0.8.0-loop-brief.md`
"## CONTRACT 2" + "## Appendix A"; source-of-truth design §6.1
`/opt/ai/docs/v0.8.x-design.md`). F1 (`loop_input.py`) produced the
validated `FInput`; this module CONSUMES it and emits exactly one §6.1
class or `unknown`.

Two tiers (F2 shipped Tier-2; F3 added Tier-1 IN FRONT):
  * **Tier-1 (F3)** — the `torch.cuda.OutOfMemoryError` regex fast-path:
    on the definitive OOM signature -> always `genuine-oom`, decided by
    `Tier.TIER1`, with the predicted-vs-actual delta and the
    kv-calc-bug routing gate. It reads ONLY the structured `[E]` fields
    F3's additive `[E]` touch persists (pt1.predicted_b_breakdown,
    pt3.failure_log_excerpt → error_substring, pt3.actual.{...}, or the
    richer pt5 by A-iii precedence) — NEVER raw logs (CONTRACT-1:
    classifier.py is a pure bundle reader). Tier-1 is the ONLY path
    allowed to set `route_as_kv_calc_bug=True`, and ONLY when
    `failure_class==genuine-oom` AND `predicted_b_breakdown` AND
    `attempted_alloc_mib` AND `gpu_worker_reported_mib` are ALL present
    (else `genuine-oom` is still classified+filed, but
    `route_as_kv_calc_bug=False` — honest degrade, never a
    confidently-wrong kv-calc-bug filing).
  * **Tier-2 (F2)** — the semantic-fingerprint DB + Appendix-A seed
    matchers. Reached ONLY when Tier-1 finds no OOM signature (Tier-1
    returns `None` -> fall straight through; F2 behaviour byte-unchanged).
    Tier-2 NEVER sets `route_as_kv_calc_bug` (hard-False there).

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
import re
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
                             -> None; Tier-1 OOM fast-path -> the literal
                             "tier1-oom-fastpath").
    `predicted_vs_actual_delta_mib`
                           — F3 Tier-1 ONLY: the candidate kv-calc-bug
                             signal = actual_peak_mib - predicted_total_mib
                             (gpu_worker measured peak minus the summed [B]
                             predicted breakdown), or None when Tier-1 did
                             not fire / inputs incomplete. NEVER fabricated.
    `tier1_inputs`         — F3 Tier-1 ONLY: the resolved
                             {predicted_b_breakdown, attempted_alloc_mib,
                             gpu_worker_reported_mib, source} triple
                             (source ∈ {pt5, pt3+pt1, None}). `None` when
                             Tier-1 did not fire.
    """

    failure_class: FailureClass
    tier: Tier
    fingerprint: str
    should_file: bool
    route_as_kv_calc_bug: bool
    review_queue: bool
    error_substring: str
    matched_rule: Optional[str] = None
    # F3 Tier-1 additive telemetry (default None so every existing F2
    # construction + assertion is byte-unaffected — F2 never sets these).
    predicted_vs_actual_delta_mib: Optional[int] = None
    tier1_inputs: Optional[dict] = None


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


# ---------------------------------------------------------------------------
# F3 — §6.1 Tier-1 rule fast-path (CONTRACT-2 A-i/A-ii/A-ii′/A-iii).
#
# Tier-1 plugs IN FRONT of Tier-2. It ONLY handles the definitive OOM
# fast-path; ANYTHING else (no OOM signature) returns None and falls
# straight through to F2's unchanged Tier-2 (no F2 regression).
#
# §6.1 verbatim: "regex for the definitive OOM signature
# (torch.cuda.OutOfMemoryError during weight/KV allocation). Match ->
# extract attempted-allocation size from traceback + gpu_worker.py measured
# peak -> diff vs kv-calc predicted -> emit predicted-vs-actual delta =
# candidate kv-calc bug."
#
# classifier.py is a PURE bundle reader (CONTRACT-1): it reads the
# structured `pt3.actual` / `pt1.predicted_b_breakdown` / `pt5` fields `[E]`
# emitted — it NEVER parses raw logs (the regex below is only the OOM
# *signature* detector on the already-redacted excerpt; the numbers come
# from `[E]`'s `pt3.actual`).
#
# Routing gate (CONTRACT-2 A-ii′ + §11, verbatim): set
# route_as_kv_calc_bug=True ONLY when failure_class==genuine-oom AND
# predicted_b_breakdown AND attempted_alloc_mib AND gpu_worker_reported_mib
# are ALL present; else classify normally (genuine-oom) but
# route_as_kv_calc_bug=False (honest degrade — never a confidently-wrong
# kv-calc-bug filing).
#
# A-iii input precedence (verbatim):
#   pt5 structured fields
#     > (pt3 failure_log_excerpt + pt3.actual + pt1 predicted_b_breakdown)
#       > pt3.failure bare string
# ---------------------------------------------------------------------------

# The definitive OOM signature. `torch.cuda.OutOfMemoryError` is the
# CLASSIC weight/KV-allocation OOM vLLM/torch raises; tolerate the common
# phrasings.
#
# F8-fix: the on-rig F8 validator proved the CLASSIC-only signature MISSES
# the very common modern vLLM v0.21.0+ kv-calc-relevant failure: vLLM
# nightly (bf610c2f) raises a CLEAN `ValueError` from
# `_check_enough_kv_cache_memory` — NOT `torch.cuda.OutOfMemoryError` —
# whenever the requested max_model_len's KV cache exceeds the measured-
# available KV memory (see `/opt/ai/f8-real-vllm-oom.log` line 74/97):
#
#   ValueError: To serve at least one request with the models's max seq len
#   (2000000), (22.89 GiB KV cache is needed, which is larger than the
#   available KV cache memory (20.89 GiB). ...
#
# plus the historically-seen older vLLM phrasing
# "No available memory for the cache blocks". Both are a GENUINE OOM (the
# request cannot be served on the available memory) and are exactly the
# kv-calc-bug-relevant class Tier-1 must route. Widen the signature
# ADDITIVELY (the classic torch path is the FIRST alternative — never
# regressed; the new alternatives only ADD coverage).
_RE_OOM_SIGNATURE = re.compile(
    r"torch\.cuda\.outofmemoryerror"
    r"|cuda out of memory"
    r"|cuda error: out of memory"
    r"|outofmemoryerror: cuda"
    # F8-fix: real modern vLLM v0.21.0+ KV-cache-too-large ValueError.
    r"|kv cache is needed, which is larger than the available kv cache"
    r" memory"
    # F8-fix: older vLLM "no KV blocks fit" phrasing (defensive).
    r"|no available memory for the cache blocks",
    re.IGNORECASE,
)


def _predicted_total_mib(breakdown) -> Optional[int]:
    """Sum a `[B]` `{component: GB}` breakdown -> MiB total (the predicted
    side of the delta). None when not a usable numeric mapping — NEVER
    fabricate (the §1 confidently-wrong rule). Mirrors
    `capture._predicted_total_mib` (same convention; kept local so the
    classifier has no import-time dependency on capture.py).
    """
    if not isinstance(breakdown, dict) or not breakdown:
        return None
    total_gb = 0.0
    saw = False
    for v in breakdown.values():
        if isinstance(v, (int, float)):
            total_gb += float(v)
            saw = True
    if not saw:
        return None
    return int(round(total_gb * 1024.0))


def _resolve_tier1_inputs(finput: FInput) -> dict:
    """Resolve the THREE Tier-1 inputs by the A-iii precedence
    (pt5 > pt3-triple). Returns a dict ALWAYS carrying the keys
    `predicted_b_breakdown`, `attempted_alloc_mib`,
    `gpu_worker_reported_mib`, `source` (each value may be None).

    `source`:
      "pt5"      — taken from the override-accepted pt5 (richest); its
                   `actual.{boot_peak_mib,gpu_worker_reported_mib}` is the
                   measured side, `predicted_b_breakdown` the predicted.
                   pt5's measured "attempted alloc" proxy is `boot_peak_mib`
                   (the peak the forced low-confidence boot actually hit).
      "pt3+pt1"  — the normal-path triple: pt1.predicted_b_breakdown +
                   pt3.actual.{attempted_alloc_mib,gpu_worker_reported_mib}.
      None       — neither source carried usable structured fields.
    """
    # --- (1) pt5 structured fields win when present (A-iii) -------------
    pt5 = finput.pt5_override
    if isinstance(pt5, dict):
        pred = pt5.get("predicted_b_breakdown")
        actual = pt5.get("actual")
        if isinstance(actual, dict):
            return {
                "predicted_b_breakdown": pred,
                # pt5's measured "attempted/used" side is boot_peak_mib.
                "attempted_alloc_mib": actual.get("boot_peak_mib"),
                "gpu_worker_reported_mib": actual.get(
                    "gpu_worker_reported_mib"
                ),
                "source": "pt5",
            }

    # --- (2) the normal-path triple: pt3.actual + pt1.predicted --------
    pt3 = finput.pt3_boot or {}
    pt1 = finput.pt1_gate or {}
    actual = pt3.get("actual")
    if isinstance(actual, dict) or pt1.get("predicted_b_breakdown") is not None:
        a = actual if isinstance(actual, dict) else {}
        return {
            "predicted_b_breakdown": pt1.get("predicted_b_breakdown"),
            "attempted_alloc_mib": a.get("attempted_alloc_mib"),
            "gpu_worker_reported_mib": a.get("gpu_worker_reported_mib"),
            "source": "pt3+pt1",
        }

    return {
        "predicted_b_breakdown": None,
        "attempted_alloc_mib": None,
        "gpu_worker_reported_mib": None,
        "source": None,
    }


def _tier1_oom_fastpath(
    finput: FInput, error_substring: str
) -> Optional[ClassificationResult]:
    """The §6.1 Tier-1 fast-path. Returns a `ClassificationResult` IFF the
    definitive OOM signature is present (always `genuine-oom`); else `None`
    -> the caller falls through to the unchanged Tier-2.

    A-iii precedence for the OOM-signature SOURCE: the pt3
    `failure_log_excerpt` (already in `error_substring` via
    `_extract_error_substring`'s precedence chain) else the pt3 `failure`
    bare string. The NUMBERS are read from the structured `pt3.actual` /
    `pt1.predicted_b_breakdown` / `pt5` fields (`_resolve_tier1_inputs`) —
    classifier.py never parses raw logs (CONTRACT-1).

    F8-fix: the OOM-SIGNATURE DETECTION scans the FULL (lowercased)
    pt3.failure_log_excerpt / pt3.failure / pt5.exit_error_summary — NOT
    the 240-char-capped `error_substring`. The on-rig F8 validator proved
    real modern vLLM v0.21.0+ emits ~110 chars of `gpu_worker.py` +
    `EngineCore`/`ValueError:` log prefix BEFORE the diagnostic phrase
    `KV cache is needed, which is larger than the available KV cache
    memory`, so that phrase falls PAST the `_ERROR_SUBSTRING_CAP`
    truncation and the (even widened) signature regex would never see it
    when scanned against `error_substring`. `error_substring` itself
    (the fingerprint + telemetry value) stays 240-capped and BYTE-
    UNCHANGED; only the Tier-1 signature *detection surface* is widened
    to the full excerpt. Tier-2 is byte-unaffected (it still keys on the
    capped `error_substring`).
    """
    pt3 = finput.pt3_boot or {}
    pt5 = finput.pt5_override

    # OOM-signature DETECTION surface (A-iii precedence + F8-fix): the FULL
    # untruncated excerpt text. Precedence mirrors `_extract_error_substring`
    # (pt3.failure_log_excerpt > pt3.failure) PLUS the pt5 exit summary.
    # Lowercased only (the signature regex is case-insensitive anyway; this
    # keeps it cheap + deterministic). The capped `error_substring` is still
    # ALSO scanned so any future signal that lands within 240 chars (and
    # nowhere else) is not lost — union of both surfaces, never narrower.
    full_excerpt = pt3.get("failure_log_excerpt") or pt3.get("failure") or ""
    sig_parts = [error_substring or "", str(full_excerpt).lower()]
    if isinstance(pt5, dict) and pt5.get("exit_error_summary"):
        sig_parts.append(str(pt5["exit_error_summary"]).lower())
    sig_text = " ".join(p for p in sig_parts if p)
    if not _RE_OOM_SIGNATURE.search(sig_text):
        return None  # not the OOM fast-path -> fall through to Tier-2.

    # Definitive OOM -> genuine-oom (Tier-1).
    cls = FailureClass.GENUINE_OOM
    inputs = _resolve_tier1_inputs(finput)

    pred_mib = _predicted_total_mib(inputs.get("predicted_b_breakdown"))
    attempted = inputs.get("attempted_alloc_mib")
    gpu_worker = inputs.get("gpu_worker_reported_mib")

    # Routing gate (CONTRACT-2 A-ii′ + §11): ALL THREE present.
    all_three_present = (
        inputs.get("predicted_b_breakdown") is not None
        and attempted is not None
        and gpu_worker is not None
    )
    route_as_kv_calc_bug = bool(all_three_present)

    # predicted-vs-actual delta = measured gpu_worker peak - predicted
    # total. Only when BOTH sides are usable numbers (never fabricate).
    delta: Optional[int] = None
    if gpu_worker is not None and pred_mib is not None:
        try:
            delta = int(gpu_worker) - int(pred_mib)
        except (TypeError, ValueError):
            delta = None

    # §6.1 routing: genuine-oom is a real, fileable failure (should_file
    # True) regardless of the kv-calc-bug gate. The kv-calc-bug signal is
    # the ADDITIONAL routing on top, gated on all-3-present (honest degrade
    # otherwise: classified + filed as a normal issue, never a
    # confidently-wrong kv-calc bug).
    fp = _fingerprint(
        error_substring, finput.arch_family, finput.engine_version
    )
    return ClassificationResult(
        failure_class=cls,
        tier=Tier.TIER1,
        fingerprint=fp,
        should_file=cls not in _SUPPRESSED_NEVER_FILED,
        route_as_kv_calc_bug=route_as_kv_calc_bug,
        review_queue=False,
        error_substring=error_substring,
        matched_rule="tier1-oom-fastpath",
        predicted_vs_actual_delta_mib=delta,
        tier1_inputs=inputs,
    )


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

    # ---- F3 Tier-1 (IN FRONT of Tier-2) --------------------------------
    # The §6.1 Tier-1 rule fast-path: regex the definitive OOM signature;
    # on a match -> always `genuine-oom`, decided by Tier.TIER1, with the
    # predicted-vs-actual delta + the all-3-present kv-calc-bug routing
    # gate (CONTRACT-2 A-ii′ + §11). It reads ONLY the structured `[E]`
    # fields (pt5 > pt3.actual+pt1.predicted_b_breakdown, A-iii precedence)
    # — never raw logs (CONTRACT-1: classifier.py is a pure bundle reader).
    # NO OOM signature -> `None` -> fall straight through to the unchanged
    # Tier-2 block below (no F2 regression).
    t1 = _tier1_oom_fastpath(finput, error_substring)
    if t1 is not None:
        return t1

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
