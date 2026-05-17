"""v0.8.0 Pull-Emit-Derived `[E]` — STEP E3: capability-aware derived smoke
+ the 4 §6 capture-point artifact emitters + the §6.2/§6.3 manifest.

CONTRACT-4 (the brief's locked E3 spec, capture half). `[E]` **emits** these;
`[F]` (the Loop — §6.1 classifier / §6.2 inbound-trust / §6.3 dedup /
consensus / promotion) **consumes** them and is explicitly OUT of scope here.

This module owns ONLY:
  * `smoke_derived()`  — the capability-aware DERIVED smoke prober
                         (CONTRACT-4 "Capability-smoke set for DERIVED
                         models" — the conservative floor);
  * `emit_capture()`   — write the 4 §6 capture-point artifacts (pt1 gate /
                         pt2 download / pt3 boot / pt4 smoke) + a top-level
                         `manifest.json`, schema **v1**, redacted via the
                         `report.sh --redact` convention.

CAPTURE-POINT 5 (override-accepted force-capture) is the ONE additive E4
extension to this module (`emit_override_capture()` — §5.3 / CONTRACT-4
pt5). It is emitted ONLY on the post-`[C1]` override-accepted path E4
wires; the E3 pt1-4 + manifest emitters below are byte-behaviour-preserving
(`test-pullemit-capture.sh` stays green — it asserts pt5 is NOT written by
`emit_capture()`; pt5 is a SEPARATE function E4 invokes only when
`einput.is_override_accepted`). NO `run_pull()` wiring here (that is E4).
NO §6.1 failure classification (`failure_class` is left null — that is
`[F]`'s job). NO docs (E5). NO real on-rig boot (E5).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from .downloader import sanitize_slug

SCHEMA = 1

# ---------------------------------------------------------------------------
# CONTRACT-4 capability-smoke set for DERIVED models.
#
# A derived generic profile declares no capabilities, so the conservative
# floor is: plain-chat ALWAYS + streaming ALWAYS (cheap; catches the #145
# class — a model can boot + answer plain chat while streaming/tools/etc are
# silently dead). The remaining capabilities are smoked ONLY if `der`'s
# config.json POSITIVELY declares them; otherwise recorded "unsmoked" and
# the anchor is `partial` (per §6.2: an anchor with un-smoked capabilities
# is `partial` and cannot graduate to Tier-1 for those capabilities).
# ---------------------------------------------------------------------------
FLOOR_CAPS = ("plain-chat", "streaming")
OPTIONAL_CAPS = (
    "tool-call",
    "reasoning-streaming",
    "structured-output",
    "vision",
    "long-context",
)


@dataclass
class SmokeResult:
    smoke_capability_set: list[str] = field(default_factory=list)
    # {<cap>: "green" | "red" | "unsmoked"}
    results: dict[str, str] = field(default_factory=dict)
    partial: bool = False
    # ADDITIVE (E3-fix): per-capability failure diagnostic for `red` probes
    # — {<cap>: {"status": int|None, "error": str}}. Populated ONLY for
    # capabilities that probed `red`; absent for green/unsmoked caps. This
    # is consumed by the §6.1 classifier `[F]` will build + on-rig E5
    # diagnosis. It does NOT alter the locked `results`/`partial`/
    # `smoke_capability_set` shape (CONTRACT-4 + [F] recon depend on those).
    results_detail: dict[str, dict] = field(default_factory=dict)


def _config_declares(der: Any, cap: str) -> bool:
    """Does `der`'s config.json POSITIVELY declare `cap`?

    A derived generic-dense model surfaces config.json signals on
    `der.profile`. We read ONLY positive declarations (never infer a
    capability from absence). The recognised positive signals, conservative
    by design (unknown -> not declared -> "unsmoked" -> partial):

      tool-call           config.json declares a tool/function-calling
                          chat-template or `tool_use`/`tools` support, OR
                          the deriver surfaced a positive tool flag.
      reasoning-streaming config declares a reasoning/thinking parser
                          (`reasoning`/`thinking` config block).
      structured-output   config declares guided/structured-output support.
      vision              an image/vision config block, a *VL/*Vision
                          architecture, or a positive vision flag.
      long-context        config declares a context window beyond the
                          plain-floor (e.g. `max_position_embeddings` /
                          `rope_scaling`) AND the runtime selected a large
                          max_model_len — derived defers this unless the
                          model itself positively declares it.

    `der.profile` may carry a raw config dict under `config`/`_config`
    (whatever the deriver/orchestrator attaches); we look there + at the
    surfaced `arch`. We NEVER mutate the deriver and NEVER guess.
    """
    prof = getattr(der, "profile", None) or {}
    cfg = prof.get("config") or prof.get("_config") or {}
    arch = str(prof.get("arch") or "").lower()

    def has(*keys: str) -> bool:
        return any(k in cfg and cfg.get(k) for k in keys)

    if cap == "tool-call":
        return bool(
            prof.get("supports_tool_call") is True
            or has("tool_use", "tools", "function_calling")
            or (isinstance(cfg.get("chat_template"), str)
                and "tool" in cfg["chat_template"].lower())
        )
    if cap == "reasoning-streaming":
        return bool(
            prof.get("supports_reasoning") is True
            or has("reasoning", "thinking", "reasoning_parser")
        )
    if cap == "structured-output":
        return bool(
            prof.get("supports_structured_output") is True
            or has("guided_decoding", "structured_outputs", "grammar")
        )
    if cap == "vision":
        return bool(
            prof.get("supports_vision") is True
            or has("vision_config", "image_token_id", "vision_tower")
            or arch.endswith(("vl", "vision"))
            or "vl" in arch
            or "vision" in arch
        )
    if cap == "long-context":
        return bool(
            prof.get("supports_long_context") is True
            or has("rope_scaling")
        )
    return False


def _resolve_served_model_name(einput, compose_meta: Optional[dict]) -> str:
    """The model name the probe MUST send in the OpenAI `model` field — it
    has to be the EXACT value `generate_from_profile` emitted for
    `--served-model-name`, or vLLM 404s the request (the on-rig E5 defect:
    a healthy booted server, but `model:"derived"` is an unknown served
    name -> HTTP 404 -> every floor probe `red`).

    Authoritative source priority (CONTRACT-4 / brief):
      (a) `compose_meta['served_model_name']` — the literal value the
          generator emitted (preferred when the smoke path has it);
      (b) `sanitize_slug(einput.slug)` — the SAME function
          `generate_compose._sanitize_slug` mirrors, so it is identical to
          what `--served-model-name` carries. No third derivation.
    """
    if compose_meta:
        smn = compose_meta.get("served_model_name")
        if isinstance(smn, str) and smn:
            return smn
    return sanitize_slug(einput.slug)


def smoke_derived(
    einput,
    endpoint: str,
    *,
    client: Optional[Any] = None,
    compose_meta: Optional[dict] = None,
) -> SmokeResult:
    """Capability-aware DERIVED smoke prober (CONTRACT-4).

    The DERIVED floor: **plain-chat ALWAYS + streaming ALWAYS** (cheap;
    catches the #145 class). `tool-call` / `reasoning-streaming` /
    `structured-output` / `vision` / `long-context` are probed ONLY if
    `der`'s config.json positively declares them; otherwise recorded
    `"unsmoked"`. `partial = any(v == "unsmoked")` — per §6.2 an anchor
    with un-smoked capabilities is `partial` and cannot graduate to Tier-1
    for those capabilities.

    The OpenAI `model` field sent to the server is the RESOLVED
    served-model-name (see `_resolve_served_model_name`) — NOT the literal
    `"derived"` (which vLLM 404s; the on-rig E5 red-smoke-on-healthy-boot
    defect). `compose_meta` (optional; the dict
    `generate_from_profile` returns, carrying `served_model_name`) is used
    when available, else `sanitize_slug(einput.slug)` (identical to the
    emitted `--served-model-name`).

    `client` is INJECTABLE: default = the real OpenAI-compatible probe
    against `endpoint`; E3 tests pass a fixture client so there is NO live
    server in CI. A client must provide:
      .probe(capability, endpoint, model_name) -> bool
          | (bool, status:int|None, error:str)
      (truthy / a True first element == green; the optional 2nd/3rd
      carry the HTTP status + a short error snippet for the additive
      `results_detail` failure capture). A legacy bare-bool client is
      still accepted (no detail recorded for it).
    """
    if client is None:
        client = _HttpSmokeClient()

    model_name = _resolve_served_model_name(einput, compose_meta)

    der = einput.der
    probe_set: list[str] = list(FLOOR_CAPS)
    for cap in OPTIONAL_CAPS:
        if _config_declares(der, cap):
            probe_set.append(cap)

    results: dict[str, str] = {}
    results_detail: dict[str, dict] = {}
    # FLOOR + declared caps -> actually probed; everything in OPTIONAL_CAPS
    # not declared -> "unsmoked" (recorded, drives `partial`).
    for cap in FLOOR_CAPS + OPTIONAL_CAPS:
        if cap not in probe_set:
            results[cap] = "unsmoked"
            continue
        status: Optional[int] = None
        error: str = ""
        try:
            raw = client.probe(cap, endpoint, model_name)
        except TypeError:
            # Legacy fixture/client with the old 2-arg signature — keep the
            # injected-fixture seam working (E3 tests inject a fake client).
            try:
                raw = client.probe(cap, endpoint)
            except Exception as exc:
                raw, status, error = False, None, repr(exc)
        except Exception as exc:
            raw, status, error = False, None, repr(exc)

        if isinstance(raw, tuple):
            ok = bool(raw[0])
            if len(raw) > 1 and raw[1] is not None:
                status = int(raw[1])
            if len(raw) > 2 and raw[2]:
                error = str(raw[2])
        else:
            ok = bool(raw)

        if ok:
            results[cap] = "green"
        else:
            results[cap] = "red"
            # ADDITIVE: a `red` carries the HTTP status + a short, redacted
            # error snippet so [F]'s §6.1 classifier + on-rig E5 diagnosis
            # have something to reason over (today pt4 records only the
            # bare verdict).
            results_detail[cap] = {
                "status": status,
                "error": _redact_text(error)[:240] if error else "",
            }

    partial = any(v == "unsmoked" for v in results.values())
    return SmokeResult(
        smoke_capability_set=sorted(probe_set),
        results=results,
        partial=partial,
        results_detail=results_detail,
    )


class _HttpSmokeClient:
    """Real probe client (NOT exercised in E3 CI — a fixture client is
    injected; the live server is E5 on-rig). Codifies the minimal
    OpenAI-compatible probe per capability so E5 has nothing to invent."""

    def _build_body(self, capability: str, model_name: str) -> dict:
        """Construct the OpenAI /chat/completions probe body. The `model`
        field MUST be the resolved served-model-name (NOT the literal
        `"derived"` — vLLM validates it against `--served-model-name` and
        404s an unknown name; that was the on-rig E5 defect). Factored out
        so a UNIT test can assert the request shape with NO network."""
        body: dict = {
            "model": model_name,
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 8,
        }
        if capability == "streaming":
            body["stream"] = True
        return body

    def probe(  # pragma: no cover - E5
        self, capability: str, endpoint: str, model_name: str
    ) -> tuple[bool, Optional[int], str]:
        import urllib.error
        import urllib.request

        url = f"{endpoint}/chat/completions"
        body = self._build_body(capability, model_name)
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                ok = resp.status == 200
                return (ok, resp.status, "" if ok else f"HTTP {resp.status}")
        except urllib.error.HTTPError as exc:
            snippet = ""
            try:
                snippet = exc.read().decode("utf-8", "replace")[:240]
            except Exception:
                snippet = str(exc)
            return (False, exc.code, f"HTTP {exc.code}: {snippet}")
        except (urllib.error.URLError, OSError) as exc:
            return (False, None, repr(exc))


# ---------------------------------------------------------------------------
# Redaction — REUSE the `report.sh --redact` convention (do NOT reinvent).
#
# report.sh's `redact()` (scripts/report.sh:66-80) is a bash sed pipeline; it
# is not independently importable, so E3 reuses the SAME convention by
# applying the IDENTICAL sed expression set, driven by the SAME env keys
# (USER / hostname / HF token). Kept in lock-step with report.sh:66-80 — if
# that block changes, this must change with it. No path/token/host leak.
# ---------------------------------------------------------------------------
def _redact_text(text: str) -> str:
    user = os.environ.get("USER") or ""
    try:
        host = subprocess.run(
            ["hostname", "-s"], capture_output=True, text=True, check=False
        ).stdout.strip()
    except Exception:  # pragma: no cover - hostname always present on rig
        host = ""

    # The EXACT report.sh:66-80 expression set (verbatim convention reuse).
    sed_exprs: list[str] = []
    if user:
        sed_exprs += ["-e", f"s|/home/{re.escape(user)}|~|g"]
    sed_exprs += ["-e", "s|/root|~|g"]
    if host:
        sed_exprs += ["-e", f"s|{re.escape(host)}|<HOST>|g"]
    if user:
        sed_exprs += ["-e", f"s|{re.escape(user)}|<USER>|g"]
    sed_exprs += [
        "-e", 's|HF_TOKEN=[^ "]*|HF_TOKEN=<REDACTED>|g',
        "-e", 's|HUGGING_FACE_HUB_TOKEN=[^ "]*|HUGGING_FACE_HUB_TOKEN=<REDACTED>|g',
        "-e", 's|api_key=[^ "]*|api_key=<REDACTED>|gi',
        "-e", r's|hf_[A-Za-z0-9]\{30,\}|hf_<REDACTED>|g',
    ]
    # Hardening BEYOND report.sh's home/root convention (additive, never
    # weaker): the CONTRACT-4 schema carries only slugs / verdicts /
    # relative filenames — it must NEVER carry an absolute internal host
    # path. report.sh only collapses ~/  + /root; a capture artifact is
    # consumed by [F]/cross-rig so ANY absolute internal mount path
    # (/opt/* /mnt/* /data/*) is scrubbed to <PATH> as a defence in depth
    # (the "don't leak internal paths in public artifacts" stack rule).
    sed_exprs += [
        "-e", r's|/opt/[A-Za-z0-9._/-]*|<PATH>|g',
        "-e", r's|/mnt/[A-Za-z0-9._/-]*|<PATH>|g',
        "-e", r's|/data/[A-Za-z0-9._/-]*|<PATH>|g',
    ]
    try:
        proc = subprocess.run(
            ["sed", *sed_exprs],
            input=text, capture_output=True, text=True, check=True,
        )
        return proc.stdout
    except Exception:  # pragma: no cover - sed is POSIX-ubiquitous
        return text


# ---------------------------------------------------------------------------
# F3/G6-A-ii′ — the `pt3.actual` parse helper (capture-time, [E]-owned).
#
# Both inputs are regexed out of the SAME already-captured + redacted
# `failure_log_excerpt` (the booter's bounded `docker compose logs
# --no-color` text). `--no-color` is MANDATORY upstream (ANSI escapes
# corrupt these regexes) — see booter.capture_failure_log.
#
#   attempted_alloc_mib      — the torch.cuda.OutOfMemoryError traceback's
#                              "Tried to allocate <N> {MiB|GiB|KiB|B}" figure
#                              (the size the allocation that OOM'd asked for).
#   gpu_worker_reported_mib  — the gpu_worker.py measured-peak line
#                              ("... peak ... <N> {MiB|GiB} ..." emitted by
#                              vLLM's GPU worker memory profiler).
#
# Either is `None` when not found — NEVER fabricate a number (the §1
# confidently-wrong rule; the F3 routing gate then honest-degrades). This
# helper is `[E]`-owned (CONTRACT-1: classifier.py only READS pt3.actual).
# ---------------------------------------------------------------------------
_ALLOC_UNIT_TO_MIB = {
    "b": 1.0 / (1024.0 * 1024.0),
    "kib": 1.0 / 1024.0,
    "kb": 1.0 / 1024.0,
    "mib": 1.0,
    "mb": 1.0,
    "gib": 1024.0,
    "gb": 1024.0,
}

# "Tried to allocate 512.00 MiB" / "Tried to allocate 2.50 GiB" etc.
# (the CLASSIC torch.cuda.OutOfMemoryError traceback phrasing).
_RE_ATTEMPTED_ALLOC = re.compile(
    r"tried to allocate\s+([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|KB|MiB|MB|GiB|GB)",
    re.IGNORECASE,
)
# vLLM gpu_worker peak line, tolerant of phrasing:
#   "gpu_worker.py ... peak memory ... 22880.00 MiB"
#   "GPU memory peak: 22.34 GiB"
#   "Maximum memory usage ... 22880 MiB"
_RE_GPU_WORKER_PEAK = re.compile(
    r"(?:gpu[_ ]?worker|peak memory|memory peak|maximum memory|"
    r"peak gpu memory|max memory)[^0-9\n]*?"
    r"([0-9]+(?:\.[0-9]+)?)\s*(MiB|MB|GiB|GB)",
    re.IGNORECASE,
)

# ── F8-fix: real modern vLLM v0.21.0+ KV-cache-too-large phrasing ──────────
# The on-rig F8 validator induced a GENUINE vLLM KV-cache-too-large failure;
# the captured nightly (bf610c2f / v0.20.2rc1.dev371, the v0.21.0+ memory-
# profiler regime) does NOT raise `torch.cuda.OutOfMemoryError` for this very
# common kv-calc-relevant case. It raises a CLEAN `ValueError` from
# `_check_enough_kv_cache_memory` with this VERBATIM shape (see
# `/opt/ai/f8-real-vllm-oom.log` lines 42 + 74/97):
#
#   ValueError: To serve at least one request with the models's max seq len
#   (2000000), (22.89 GiB KV cache is needed, which is larger than the
#   available KV cache memory (20.89 GiB). ...
#   INFO ... [gpu_worker.py:462] Available KV cache memory: 20.89 GiB
#
# The CLASSIC `_RE_ATTEMPTED_ALLOC` ("tried to allocate") + `_RE_GPU_WORKER_
# PEAK` ("peak memory") regexes match NEITHER line, so this real, common
# failure was silently parsed `{None, None}` and Tier-1 never routed.
#
# These NEW sibling regexes are tried AFTER the classic ones (first match
# wins; classic torch OOM is never regressed). Mapping (F8-fix spec):
#   attempted_alloc_mib  <- the "(N GiB|MiB) KV cache is needed" figure
#                           (the FIRST number in the ValueError; the KV the
#                           engine actually needed -> 22.89 GiB).
#   gpu_worker_reported_mib <- the standalone gpu_worker.py line
#                           "Available KV cache memory: N GiB" (preferred),
#                           ELSE the ValueError parenthetical
#                           "available KV cache memory (N GiB)" (the SECOND
#                           number -> 20.89 GiB). Both are the SAME measured-
#                           available figure; prefer the explicit gpu_worker
#                           line when present.
#
# "<N> GiB KV cache is needed" — the engine-needed KV size (attempted side).
_RE_KV_NEEDED = re.compile(
    r"([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|KB|MiB|MB|GiB|GB)\s+kv cache is needed",
    re.IGNORECASE,
)
# The explicit gpu_worker.py measured-available line (PREFERRED source for
# gpu_worker_reported_mib): "[gpu_worker.py:462] Available KV cache memory:
# 20.89 GiB".
_RE_KV_AVAILABLE_GPU_WORKER = re.compile(
    r"gpu_worker[^\n]*?available kv cache memory[:\s]+"
    r"([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|KB|MiB|MB|GiB|GB)",
    re.IGNORECASE,
)
# Fallback: the available figure inside the ValueError parenthetical —
# "available KV cache memory (20.89 GiB)".
_RE_KV_AVAILABLE_VALUEERROR = re.compile(
    r"available kv cache memory\s*\(\s*"
    r"([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|KB|MiB|MB|GiB|GB)\s*\)",
    re.IGNORECASE,
)


def _to_mib(value: str, unit: str) -> Optional[int]:
    try:
        factor = _ALLOC_UNIT_TO_MIB.get(unit.lower())
        if factor is None:
            return None
        return int(round(float(value) * factor))
    except (TypeError, ValueError):
        return None


def _parse_pt3_actual(excerpt: Optional[str]) -> dict:
    """Regex the two Tier-1 actual-side inputs out of the redacted excerpt.

    Returns the structured first-class `{attempted_alloc_mib:int|None,
    gpu_worker_reported_mib:int|None}` object (both `None` when not found —
    never fabricated). The OOM-signature gate itself is `[F]`'s job
    (classifier.py Tier-1); this only extracts the numbers `[E]` measured.
    """
    attempted: Optional[int] = None
    gpu_worker: Optional[int] = None
    if excerpt:
        # --- attempted_alloc_mib: classic torch OOM FIRST, then the real
        #     modern vLLM v0.21.0+ "<N> GiB KV cache is needed" phrasing
        #     (first match wins; classic path never regressed). ----------
        m = _RE_ATTEMPTED_ALLOC.search(excerpt)
        if m:
            attempted = _to_mib(m.group(1), m.group(2))
        else:
            mk = _RE_KV_NEEDED.search(excerpt)
            if mk:
                attempted = _to_mib(mk.group(1), mk.group(2))

        # --- gpu_worker_reported_mib: classic "peak memory" FIRST; else
        #     the explicit gpu_worker.py "Available KV cache memory: N GiB"
        #     line (PREFERRED), else the ValueError's parenthetical
        #     "available KV cache memory (N GiB)" fallback. ---------------
        g = _RE_GPU_WORKER_PEAK.search(excerpt)
        if g:
            gpu_worker = _to_mib(g.group(1), g.group(2))
        else:
            ga = _RE_KV_AVAILABLE_GPU_WORKER.search(excerpt)
            if ga:
                gpu_worker = _to_mib(ga.group(1), ga.group(2))
            else:
                gv = _RE_KV_AVAILABLE_VALUEERROR.search(excerpt)
                if gv:
                    gpu_worker = _to_mib(gv.group(1), gv.group(2))
    return {
        "attempted_alloc_mib": attempted,
        "gpu_worker_reported_mib": gpu_worker,
    }


def _write_redacted_json(path: Path, obj: dict) -> None:
    raw = json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False)
    path.write_text(_redact_text(raw) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# §6.2 submission_fingerprint + manifest helpers.
# ---------------------------------------------------------------------------
def _fingerprint(parts: list[str]) -> str:
    h = hashlib.sha256()
    h.update("\x1f".join(str(p) for p in parts).encode("utf-8"))
    return h.hexdigest()


def _arch_family(der: Any) -> Optional[str]:
    prof = getattr(der, "profile", None) or {}
    return prof.get("arch") or prof.get("family")


def _quant_label(der: Any) -> Optional[str]:
    prof = getattr(der, "profile", None) or {}
    return prof.get("weight_format")


def _topology_class(einput) -> str:
    """A coarse, deterministic class for §6.2/§6.3 (NOT the canonical
    summary — that is `topology_summary_canonical`). N GPUs × VRAM-bucket."""
    n = len(einput.selected_gpu_vram_mib or [])
    vram = min(einput.selected_gpu_vram_mib) if einput.selected_gpu_vram_mib else 0
    return f"{n}x{vram}MiB"


# ---------------------------------------------------------------------------
# THE 4 §6 capture-point emitters + manifest.
# ---------------------------------------------------------------------------
def emit_capture(
    einput,
    *,
    confidence,
    raw_verdict,
    profile_like: str,
    download_result,
    boot_result,
    smoke_result: SmokeResult,
    compose_meta: dict,
    kv_calc_version: str,
    repo_root: Path,
    ts: Optional[str] = None,
    predicted_b_breakdown=None,
    failure_log_excerpt: Optional[str] = None,
) -> dict:
    """Write the 4 §6 capture-point artifacts (pt1 gate / pt2 download /
    pt3 boot / pt4 smoke) + a top-level `manifest.json`, schema v1, JSON,
    redacted via the `report.sh --redact` convention, under:

        <repo>/.pull-captures/<slug-sanitized>/<utc-ts>/

    Returns `{paths:{...}, dir:str, manifest:{...}}`. CONTRACT-4 EXACTLY:
      pt1 gate     {schema, point, slug, confidence, raw_verdict, terminal,
                    profile_like, hardware_sm, predicted_b_breakdown}
      pt2 download {point, ok, files, bytes, sha_verified, failure}
      pt3 boot     {point, ok, seconds, failure
                    [, failure_log_excerpt, actual]  -- only when NOT ok}
      pt4 smoke    {point, smoke_capability_set, results, partial}

    CAPTURE-POINT 5 (override-accepted force-capture) is OUT of E3 scope —
    NOT emitted here (E4 wires it). `failure_class` is left **null** — E3
    must NOT classify (§6.1 = `[F]`'s job).

    F3/G6-A — the 3-part additive `[E]` touch (CONTRACT-2 G6-(A); all
    additive, every existing key byte-preserved):

      * A-i `predicted_b_breakdown` (kw-only, default `None`): the `[B]`
        kv-calc GB breakdown that produced the verdict
        (`res.diagnostics["b_breakdown"]` == `raw_verdict()["breakdown_gb"]`,
        `pull.py:638`). Persisted into **pt1** for ALL post-`[B]` captures
        (C1: previously on disk only in pt5/override). The key is ALWAYS
        present in pt1 (value `None` when the caller passes nothing) — pt1
        already emits a fixed key set, so an always-present additive key
        keeps that shape; no EXISTING pt1 key's value or bytes change
        (JSON is `sort_keys=True`: a new key inserts its own line, it never
        mutates an existing key's serialization). F1's `read_capture_bundle`
        + F2's classifier were built to tolerate this exact key
        absent-or-present.

      * A-ii `failure_log_excerpt` (kw-only, default `None`): the bounded,
        `_redact_text`-scrubbed `docker compose logs --no-color` excerpt the
        booter captured BEFORE teardown (C2: the in-container vLLM OOM
        traceback + the gpu_worker peak line live there, NOT in compose-up
        stderr). Written into **pt3 ONLY when `not ok`** — so the success
        path pt3 is byte-identical to today (NO new keys at all when boot
        ok); a failure pt3 gains `failure_log_excerpt`.

      * A-ii′ `pt3.actual`: emitted HERE at capture time (NOT in
        classifier.py — `[F]` stays a pure bundle reader, CONTRACT-1). When
        pt3 is `not ok` and we have an excerpt, `_parse_pt3_actual()`
        regexes `attempted_alloc_mib` (the OOM traceback "Tried to allocate"
        line) and `gpu_worker_reported_mib` (the gpu_worker peak line) out
        of that SAME captured excerpt into the structured first-class
        `pt3.actual = {attempted_alloc_mib:int|None,
        gpu_worker_reported_mib:int|None}`. classifier.py only READS this.
    """
    san = sanitize_slug(einput.slug)
    stamp = ts or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = Path(repo_root) / ".pull-captures" / san / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- pt1: pre-download gate verdict --------------------------------
    # F3/G6-A-i: `predicted_b_breakdown` is ALWAYS present (None when the
    # caller passes nothing) — pt1 emits a fixed key set, so this additive
    # key keeps that shape. No EXISTING key value/bytes change.
    pt1 = {
        "schema": SCHEMA,
        "point": "gate",
        "slug": einput.slug,
        "confidence": str(getattr(confidence, "name", confidence)),
        "raw_verdict": raw_verdict,
        "terminal": einput.terminal,
        "profile_like": profile_like,
        "hardware_sm": einput.hardware_sm,
        "predicted_b_breakdown": predicted_b_breakdown,
    }

    # ---- pt2: download (the E2 DownloadResult shape) -------------------
    pt2 = {
        "point": "download",
        "ok": bool(getattr(download_result, "ok", False)),
        "files": list(getattr(download_result, "files", []) or []),
        "bytes": int(getattr(download_result, "bytes", 0) or 0),
        "sha_verified": bool(getattr(download_result, "sha_verified", False)),
        "failure": getattr(download_result, "failure", None),
    }

    # ---- pt3: boot -----------------------------------------------------
    # The 4 LOCKED keys are byte-behaviour-unchanged. F3/G6-A-ii + A-ii′:
    # `failure_log_excerpt` (the booter's bounded redacted
    # `docker compose logs --no-color` excerpt) and the structured
    # `actual.{attempted_alloc_mib,gpu_worker_reported_mib}` are added
    # **ONLY when boot is NOT ok** — so the success-path pt3 is byte-
    # identical to today (no new keys at all); a failure pt3 gains them.
    pt3 = {
        "point": "boot",
        "ok": bool(getattr(boot_result, "ok", False)),
        "seconds": float(getattr(boot_result, "seconds", 0.0) or 0.0),
        "failure": getattr(boot_result, "failure", None),
    }
    if not pt3["ok"]:
        # Prefer the explicitly-passed excerpt; else the booter may have
        # stashed it on the BootResult (additive attribute, default None).
        excerpt = failure_log_excerpt
        if excerpt is None:
            excerpt = getattr(boot_result, "failure_log_excerpt", None)
        excerpt_red = (
            _redact_text(str(excerpt)) if excerpt else None
        )
        pt3["failure_log_excerpt"] = excerpt_red
        pt3["actual"] = _parse_pt3_actual(excerpt_red)

    # ---- pt4: post-boot capability-aware smoke ------------------------
    # `point` / `smoke_capability_set` / `results` / `partial` are the
    # LOCKED CONTRACT-4 shape (byte-behaviour-unchanged — [F] §6.1 recon
    # depends on them). `results_detail` is ADDITIVE only: per-`red`-cap
    # HTTP-status + redacted error snippet so [F]'s classifier + on-rig E5
    # diagnosis are not blind to WHY a probe went red (the on-rig defect:
    # only `red` was recorded, no 404 status).
    pt4 = {
        "point": "smoke",
        "smoke_capability_set": list(smoke_result.smoke_capability_set),
        "results": dict(smoke_result.results),
        "partial": bool(smoke_result.partial),
        "results_detail": {
            k: dict(v)
            for k, v in (
                getattr(smoke_result, "results_detail", {}) or {}
            ).items()
        },
    }

    # ---- manifest: §6.2 consensus-key inputs as FIRST-CLASS fields -----
    # (Codex-r5 High-2 — [F] must reason OVER them; a hash is opaque.)
    model = einput.slug
    quant_label = _quant_label(einput.der)
    arch_family = _arch_family(einput.der)
    topology_class = _topology_class(einput)
    engine_pin = compose_meta.get("resolved_image") or compose_meta.get(
        "engine_pin"
    )
    engine_version = engine_pin
    selected_ctx = compose_meta.get("max_model_len")
    kv_format = compose_meta.get("kv_format")
    smoke_capability_set = list(smoke_result.smoke_capability_set)
    topology_summary_canonical = einput.topology_summary

    # Honest 3-state manifest outcome, derived PURELY from structured truth
    # already in scope (pt2 download `ok`, pt3 boot `ok`, the locked
    # `smoke_result.results`/`.partial`) — no new fields, no re-derivation,
    # no model/network. Precedence is strict: failed > partial > ok.
    #   - "failed"  : a REAL stage failure — download not ok, OR boot not ok,
    #                  OR ANY *smoked* capability went "red". (A stage
    #                  hard-fail dominates even when smoke is absent.)
    #   - "partial" : NOT failed AND `smoke_result.partial` is True — every
    #                  smoked cap green but ≥1 cap "unsmoked". Per §6.2 this
    #                  is a capability-scoped SUCCESS (it merely cannot
    #                  graduate to Tier-1 for those caps); it is NOT a
    #                  failure. The floor-green/optionals-unsmoked
    #                  generic-dense case (e.g. Qwen2.5-0.5B) lands HERE.
    #   - "ok"      : NOT failed AND NOT partial — everything attempted, all
    #                  green, nothing unsmoked.
    # NOTE: this 3-state is the honest INTERIM only — the final anchor-status
    # taxonomy is owned by the future `[F]` Loop phase (§6.1 classifier /
    # §6.2 consensus). `[E]` emits honest structured truth; `[F]` classifies.
    _failed = (
        not pt2["ok"]
        or not pt3["ok"]
        or any(v == "red" for v in smoke_result.results.values())
    )
    if _failed:
        outcome = "failed"
    elif smoke_result.partial:
        outcome = "partial"
    else:
        outcome = "ok"
    submission_fingerprint = _fingerprint([
        model,
        einput.club3090_commit,
        topology_summary_canonical,
        str(quant_label),
        kv_calc_version,
        str(engine_version),
        stamp,
        outcome,
    ])

    manifest = {
        "schema": SCHEMA,
        "slug": einput.slug,
        "utc_ts": stamp,
        # §6.2 stage-2 hash (quick correlation).
        "submission_fingerprint": submission_fingerprint,
        # §6.2 consensus-key inputs — FIRST-CLASS (not only hashed).
        "model": model,
        "quant_label": quant_label,
        "arch_family": arch_family,
        "topology_class": topology_class,
        "engine_pin": engine_pin,
        "engine_version": engine_version,
        "kv_calc_version": kv_calc_version,
        "selected_ctx": selected_ctx,
        "kv_format": kv_format,
        "smoke_capability_set": smoke_capability_set,
        # §6.2 verbatim — sorted (gpu_name, vram_mib) serialization.
        "topology_summary_canonical": topology_summary_canonical,
        # §6.3 dedup-key inputs — FIRST-CLASS too. `[E]` emits the inputs;
        # `[F]` computes/uses the key. `failure_class` is left **null**:
        # that is §6.1 classifier = `[F]`'s job; E3 must NOT classify.
        "model_id": model,
        "failure_class": None,
        "club3090_commit": einput.club3090_commit,
        "outcome": outcome,
        "capture_points": ["gate", "download", "boot", "smoke"],
    }

    paths = {
        "gate": str(out_dir / "pt1-gate.json"),
        "download": str(out_dir / "pt2-download.json"),
        "boot": str(out_dir / "pt3-boot.json"),
        "smoke": str(out_dir / "pt4-smoke.json"),
        "manifest": str(out_dir / "manifest.json"),
    }
    _write_redacted_json(Path(paths["gate"]), pt1)
    _write_redacted_json(Path(paths["download"]), pt2)
    _write_redacted_json(Path(paths["boot"]), pt3)
    _write_redacted_json(Path(paths["smoke"]), pt4)
    _write_redacted_json(Path(paths["manifest"]), manifest)

    return {"paths": paths, "dir": str(out_dir), "manifest": manifest}


# ---------------------------------------------------------------------------
# CAPTURE-POINT 5 — override-accepted force-capture (CONTRACT-4 pt5 / §5.3).
#
# ADDITIVE E4 extension (NOT invoked by emit_capture(); a SEPARATE function
# E4 calls ONLY on the post-`[C1]` override-accepted path, i.e. when
# `einput.is_override_accepted` is True). E3's pt1-4 + manifest emitters
# above are byte-behaviour-preserving — `test-pullemit-capture.sh` continues
# to assert `emit_capture()` writes ONLY pt1-4 + manifest and NO override
# artifact. pt5 is written into the SAME `<repo>/.pull-captures/<slug>/<ts>/`
# directory, redacted via the SAME convention, schema-less per CONTRACT-4
# pt5's literal field list.
#
# CONTRACT-4 pt5 / §5.3 — emit EXACTLY:
#   { point:"override_capture",
#     predicted_b_breakdown:{ the full [B] kv-calc GB breakdown that
#                             produced the verdict },
#     actual:{ boot_peak_mib:int|null, gpu_worker_reported_mib:int|null },
#     predicted_vs_actual_delta_mib:int|null,
#     exit_error_summary:str|null,
#     calibration_signal_not_validated:true }
# The `true` flag is MANDATORY + LITERAL — §5.3: a forced low-confidence
# download is a calibration SIGNAL, never recorded as fit-validated. `actual`
# may be null (boot never reached allocation) — then `exit_error_summary`
# carries why; the artifact is STILL emitted regardless.
# ---------------------------------------------------------------------------
def emit_override_capture(
    einput,
    *,
    predicted_b_breakdown,
    boot_peak_mib: Optional[int] = None,
    gpu_worker_reported_mib: Optional[int] = None,
    exit_error_summary: Optional[str] = None,
    repo_root: Path,
    ts: str,
) -> str:
    """Write the §5.3 / CONTRACT-4 pt5 override-accepted force-capture
    artifact into the SAME capture directory `emit_capture()` used (keyed by
    the SAME sanitized-slug + `ts`). Returns the written path.

    `predicted_b_breakdown` is the full `[B]` kv-calc GB breakdown that
    produced the verdict (E4 passes `res.diagnostics['b_breakdown']`).
    `actual` is `null` iff BOTH `boot_peak_mib` and
    `gpu_worker_reported_mib` are None (boot never reached allocation) — in
    that case `predicted_vs_actual_delta_mib` is also `null` and
    `exit_error_summary` carries why. `calibration_signal_not_validated` is
    ALWAYS the literal `True` (mandatory; §5.3).
    """
    san = sanitize_slug(einput.slug)
    out_dir = Path(repo_root) / ".pull-captures" / san / ts
    out_dir.mkdir(parents=True, exist_ok=True)

    have_actual = (
        boot_peak_mib is not None or gpu_worker_reported_mib is not None
    )
    if have_actual:
        actual: Optional[dict] = {
            "boot_peak_mib": (
                int(boot_peak_mib) if boot_peak_mib is not None else None
            ),
            "gpu_worker_reported_mib": (
                int(gpu_worker_reported_mib)
                if gpu_worker_reported_mib is not None
                else None
            ),
        }
    else:
        # boot never reached allocation -> actual is null; the WHY lives in
        # exit_error_summary (CONTRACT-4 pt5).
        actual = None

    # predicted_vs_actual_delta_mib: only computable when we have a measured
    # peak AND the prediction carries a comparable MiB figure; else null.
    delta: Optional[int] = None
    if actual is not None and boot_peak_mib is not None:
        pred_mib = _predicted_total_mib(predicted_b_breakdown)
        if pred_mib is not None:
            delta = int(boot_peak_mib) - int(pred_mib)

    pt5 = {
        "point": "override_capture",
        "predicted_b_breakdown": predicted_b_breakdown,
        "actual": actual,
        "predicted_vs_actual_delta_mib": delta,
        "exit_error_summary": exit_error_summary,
        # MANDATORY + LITERAL — never "fit validated" (§5.3).
        "calibration_signal_not_validated": True,
    }
    path = out_dir / "pt5-override-capture.json"
    _write_redacted_json(path, pt5)
    return str(path)


def _predicted_total_mib(breakdown) -> Optional[int]:
    """Best-effort MiB total of the `[B]` GB breakdown (for the
    predicted-vs-actual delta). The `[B]` breakdown is a `{component: GB}`
    dict (`kv.raw_verdict()['breakdown_gb']`); sum numeric components and
    convert GB -> MiB. Returns None if it is not a usable numeric mapping
    (delta stays null — never fabricate a number)."""
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
