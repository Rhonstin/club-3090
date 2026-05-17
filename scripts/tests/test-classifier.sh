#!/usr/bin/env bash
set -euo pipefail

# test-classifier.sh — v0.8.0 [F] STEP F2 (club-3090 #147).
#
# Contract test for CONTRACT-2 Tier-2 + Appendix A: the §6.1 semantic-
# fingerprint classifier. The test IS the spec; the code is fixed to it.
# NO live Docker / GPU / network — fixture capture dirs are built in a tmp
# tree (byte-exact [E] schema, reused via F1's read_capture_bundle for
# realism) and classified.
#
# Coverage (every CONTRACT-2 / Appendix-A / §6.1 assertion as a
# failing-then-passing check):
#   * EACH Appendix A row maps to its STATED §6.1 class:
#       Cliff-2 OOM            -> genuine-oom
#       prefill-cliff GDN OOM  -> genuine-oom
#       #145 streaming dead    -> quant-unsupported (via pt4, boot green)
#       AWQ/quant mis-load     -> quant-unsupported
#       Genesis overlay drift  -> overlay-arch-drift
#       Ampere/FA3 SM90 kernel -> kernel-unsupported
#       cold-start then green  -> benign-cold-start (should_file=False)
#       served-name 404 ctrl   -> benign-cold-start (should_file=False)
#       unmatched              -> unknown (should_file=False + review_queue)
#   * route_as_kv_calc_bug is False for EVERY F2 path incl. genuine-oom
#     (Tier-1 is F3 — F2 must hard-wire False).
#   * output ALWAYS in the 6-enum ∪ unknown — an out-of-enum 7th DB value
#     degrades to `unknown` (no 7th value can leak).
#   * works with pt3.failure_log_excerpt ABSENT (today's shipped [E]
#     schema, bare pt3.failure) AND present (F3 forward-compat).
#   * tier seam: F2 only ever emits TIER2 / NONE_UNKNOWN, never TIER1.
#   * REAL on-disk .pull-captures/ bundle (a success/`partial`): classify
#     returns a valid enum and does NOT misclassify as a fileable failure.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
export PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}"

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root))

from scripts.lib.profiles.loop_input import read_capture_bundle  # noqa: E402
from scripts.lib.profiles.classifier import (  # noqa: E402
    FailureClass,
    Tier,
    classify,
)

ENUM_VALUES = {c.value for c in FailureClass}
failures: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"PASS: {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        failures.append(msg)


# ---------------------------------------------------------------------------
# Byte-exact [E] schema fixtures (mirror scripts/lib/profiles/capture.py),
# parsed back through F1's reader for realism (CONTRACT-1 boundary).
# ---------------------------------------------------------------------------
def mk_manifest(**over) -> dict:
    m = {
        "schema": 1,
        "slug": "Org/My-Model",
        "utc_ts": "20260517T000000Z",
        "submission_fingerprint": "deadbeef" * 8,
        "model": "Org/My-Model",
        "quant_label": "BFloat16",
        "arch_family": "Qwen3NextForCausalLM",
        "topology_class": "1x24576MiB",
        "engine_pin": "vllm/vllm-openai:nightly-abc123",
        "engine_version": "vllm/vllm-openai:nightly-abc123",
        "kv_calc_version": "kvcalc-v0.8.0",
        "selected_ctx": 32768,
        "kv_format": "fp8_e5m2",
        "smoke_capability_set": ["plain-chat", "streaming"],
        "topology_summary_canonical": "[(NVIDIA GeForce RTX 3090, 24576)]",
        "model_id": "Org/My-Model",
        "failure_class": None,
        "club3090_commit": "cafef00d",
        "outcome": "failed",
        "capture_points": ["gate", "download", "boot", "smoke"],
    }
    m.update(over)
    return m


def write_bundle(d: Path, *, manifest=None, pt3=None, pt4=None) -> Path:
    d.mkdir(parents=True, exist_ok=True)
    arts = {
        "manifest.json": manifest if manifest is not None else mk_manifest(),
        "pt1-gate.json": {
            "schema": 1, "point": "gate", "slug": "Org/My-Model",
            "confidence": "estimated-lower-bound",
            "raw_verdict": "fits-clean", "terminal": "confirm→proceed",
            "profile_like": "vllm/minimal", "hardware_sm": 8.6,
        },
        "pt2-download.json": {
            "point": "download", "ok": True, "files": ["model.safetensors"],
            "bytes": 123, "sha_verified": True, "failure": None,
        },
        "pt3-boot.json": pt3 if pt3 is not None else {
            "point": "boot", "ok": False, "seconds": 0.0,
            "failure": "server did not become ready before timeout",
        },
        "pt4-smoke.json": pt4 if pt4 is not None else {
            "point": "smoke",
            "smoke_capability_set": ["plain-chat", "streaming"],
            "results": {"plain-chat": "unsmoked", "streaming": "unsmoked"},
            "partial": True, "results_detail": {},
        },
    }
    for name, obj in arts.items():
        (d / name).write_text(json.dumps(obj, indent=2), encoding="utf-8")
    return d


tmp = Path(tempfile.mkdtemp())


def fi(name, **kw):
    return read_capture_bundle(write_bundle(tmp / name, **kw))


def boot_fail(failure=None, excerpt=None):
    pt3 = {"point": "boot", "ok": False, "seconds": 0.0,
           "failure": failure}
    if excerpt is not None:
        pt3["failure_log_excerpt"] = excerpt           # F3 forward-compat
        pt3["actual"] = {"attempted_alloc_mib": 1234,  # F2 must NOT read
                         "gpu_worker_reported_mib": 23456}
    return pt3


# ---------------------------------------------------------------------------
# Appendix A — every row maps to its STATED §6.1 class.
# ---------------------------------------------------------------------------
# Row 1: Cliff-2 accumulated-ctx OOM (~21-26K) — torch.cuda.OOM.
r = classify(fi("a1", pt3=boot_fail(
    failure="torch.cuda.OutOfMemoryError: CUDA out of memory. Tried to "
            "allocate 512.00 MiB")))
check(r.failure_class is FailureClass.GENUINE_OOM,
      f"Appendix-A Cliff-2 OOM -> genuine-oom (got {r.failure_class.value})")
check(r.route_as_kv_calc_bug is False,
      "genuine-oom route_as_kv_calc_bug=False in F2 (Tier-1 is F3)")
check(r.should_file is True,
      "genuine-oom should_file=True (classified+filed, not a kv-calc bug)")
check(r.tier is Tier.TIER2,
      f"genuine-oom decided by Tier-2 (got {r.tier.value}; never TIER1 "
      f"in F2)")

# Row 2: prefill-cliff OOM (~50-60K, DeltaNet GDN) — works with the F3
# forward-compat failure_log_excerpt PRESENT.
r = classify(fi("a2", pt3=boot_fail(
    failure="server did not become ready before timeout",
    excerpt="...gated_delta_net forward... torch.cuda.OutOfMemoryError: "
            "CUDA out of memory ...")))
check(r.failure_class is FailureClass.GENUINE_OOM,
      f"Appendix-A prefill-cliff GDN OOM -> genuine-oom "
      f"(got {r.failure_class.value})")
check(r.route_as_kv_calc_bug is False,
      "prefill-cliff genuine-oom route_as_kv_calc_bug=False (F2)")
check(r.error_substring and "torch.cuda" in r.error_substring,
      "F3 forward-compat: failure_log_excerpt used when PRESENT")

# Row 3: #145 qwen3_coder streaming dead — boot+plain-chat green,
# streaming red. Maps via pt4, NOT a boot failure.
r = classify(fi("a3",
    pt3={"point": "boot", "ok": True, "seconds": 80.0, "failure": None},
    pt4={"point": "smoke",
         "smoke_capability_set": ["plain-chat", "streaming"],
         "results": {"plain-chat": "green", "streaming": "red"},
         "partial": False,
         "results_detail": {"streaming": {"status": 200, "error": ""}}}))
check(r.failure_class is FailureClass.QUANT_UNSUPPORTED,
      f"Appendix-A #145 streaming-dead -> quant-unsupported (got "
      f"{r.failure_class.value})")
check(r.matched_rule == "streaming-dead-boot-green-145",
      "#145 matched via pt4_results rule (not a pt3 boot failure)")

# Row 4: AWQ/quant mis-load on derived (no --quantization).
r = classify(fi("a4", pt3=boot_fail(
    failure="ValueError: Model QuantConfig: the AWQ weight is not "
            "supported for this dtype")))
check(r.failure_class is FailureClass.QUANT_UNSUPPORTED,
      f"Appendix-A AWQ mis-load -> quant-unsupported (got "
      f"{r.failure_class.value})")

# Row 5: Genesis-required engine on clean image (overlay drift).
r = classify(fi("a5", pt3=boot_fail(
    failure="AttributeError: module 'vllm' has no attribute "
            "'genesis_patch' (patch not applied)")))
check(r.failure_class is FailureClass.OVERLAY_ARCH_DRIFT,
      f"Appendix-A Genesis overlay drift -> overlay-arch-drift (got "
      f"{r.failure_class.value})")

# Row 6: Ampere-unsupported kernel (FA3 / SM90-only path).
r = classify(fi("a6", pt3=boot_fail(
    failure="RuntimeError: FlashAttention-3 requires Hopper SM90; "
            "compute capability 8.6 not supported on this gpu")))
check(r.failure_class is FailureClass.KERNEL_UNSUPPORTED,
      f"Appendix-A Ampere/FA3 SM90 -> kernel-unsupported (got "
      f"{r.failure_class.value})")

# Row 7: first-request-after-boot cold start (slow, then green). pt3
# timeout but pt4 green -> benign-cold-start, SUPPRESSED (not filed).
r = classify(fi("a7",
    pt3={"point": "boot", "ok": False, "seconds": 0.0,
         "failure": "server did not become ready before timeout"},
    pt4={"point": "smoke",
         "smoke_capability_set": ["plain-chat"],
         "results": {"plain-chat": "green"},
         "partial": False, "results_detail": {}}))
check(r.failure_class is FailureClass.BENIGN_COLD_START,
      f"Appendix-A cold-start-then-green -> benign-cold-start (got "
      f"{r.failure_class.value})")
check(r.should_file is False,
      "benign-cold-start SUPPRESSED — should_file=False (§6.1 acceptance)")
check(r.route_as_kv_calc_bug is False and r.review_queue is False,
      "benign-cold-start never files / never review-queue / never kv-calc")

# Row 8: [E] bug #1 served-model-name 404 — historical negative control.
r = classify(fi("a8",
    pt3={"point": "boot", "ok": True, "seconds": 80.0, "failure": None},
    pt4={"point": "smoke",
         "smoke_capability_set": ["plain-chat"],
         "results": {"plain-chat": "red"},
         "partial": False,
         "results_detail": {"plain-chat": {"status": 404,
                                            "error": "model not found"}}}))
check(r.failure_class is FailureClass.BENIGN_COLD_START,
      f"Appendix-A served-name-404 negative control -> benign-cold-start "
      f"(got {r.failure_class.value})")
check(r.should_file is False,
      "negative-control 404 should_file=False (in-enum benign-cold-start)")

# Row 9: anything unmatched -> unknown -> review queue, never files.
r = classify(fi("a9", pt3=boot_fail(
    failure="some entirely novel boot error nobody has classified yet")))
check(r.failure_class is FailureClass.UNKNOWN,
      f"Appendix-A unmatched -> unknown (got {r.failure_class.value})")
check(r.should_file is False and r.review_queue is True,
      "unknown -> should_file=False + review_queue=True (maintainer queue)")
check(r.route_as_kv_calc_bug is False,
      "unknown NEVER auto-files a kv-calc bug (§6.1)")
check(r.tier is Tier.NONE_UNKNOWN,
      f"unmatched decided as NONE_UNKNOWN (got {r.tier.value})")

# ---------------------------------------------------------------------------
# Cross-cutting: pt3.failure_log_excerpt ABSENT (today's shipped [E]
# schema) classifies off the bare pt3.failure string.
# ---------------------------------------------------------------------------
r = classify(fi("noexcerpt", pt3={
    "point": "boot", "ok": False, "seconds": 0.0,
    "failure": "torch.cuda.OutOfMemoryError: CUDA out of memory"}))
check("failure_log_excerpt" not in (read_capture_bundle(
          write_bundle(tmp / "noexcerpt2", pt3={
              "point": "boot", "ok": False, "seconds": 0.0,
              "failure": "torch.cuda.OutOfMemoryError"})).pt3_boot),
      "fixture confirms pt3.failure_log_excerpt ABSENT (shipped [E] schema)")
check(r.failure_class is FailureClass.GENUINE_OOM,
      "classifies off bare pt3.failure when failure_log_excerpt ABSENT")

# ---------------------------------------------------------------------------
# Out-of-enum guard: no 7th value can ever leak. Point the classifier at a
# poisoned DB whose matcher class is an invalid 7th value -> must degrade
# to `unknown`, and EVERY result must be in the 6-enum.
# ---------------------------------------------------------------------------
poison = tmp / "poison.yml"
poison.write_text(
    "schema: 1\n"
    "exact_fingerprints: {}\n"
    "condition_matchers:\n"
    "  - id: poisoned\n"
    "    kind: log_substring\n"
    "    any: ['poison-signal']\n"
    "    class: not-a-real-class-7th-value\n",
    encoding="utf-8")
r = classify(fi("poisoned", pt3=boot_fail(
    failure="this contains a poison-signal token")),
    fingerprint_db_path=poison)
check(r.failure_class is FailureClass.UNKNOWN,
      f"out-of-enum 7th DB class degrades to `unknown` (got "
      f"{r.failure_class.value}) — no 7th value can leak")
check(r.failure_class.value in ENUM_VALUES,
      "poisoned-DB result still strictly in the 6-member §6.1 enum")

# Sweep every Appendix-A fixture: output ALWAYS ∈ the 6-enum.
for nm in ("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9"):
    rr = classify(read_capture_bundle(tmp / nm))
    check(rr.failure_class.value in ENUM_VALUES,
          f"{nm}: failure_class ∈ §6.1 6-enum ({rr.failure_class.value})")
    check(rr.tier is not Tier.TIER1,
          f"{nm}: F2 never emits TIER1 (Tier-1 is the F3 seam)")
    check(rr.route_as_kv_calc_bug is False,
          f"{nm}: route_as_kv_calc_bug HARD-False in F2 (F3 owns it)")

# ---------------------------------------------------------------------------
# REAL on-disk .pull-captures/ bundle (a success/`partial`): classify
# returns a valid enum and does NOT misclassify as a fileable failure.
# ---------------------------------------------------------------------------
real_root = root / ".pull-captures"
real_dirs: list[Path] = []
if real_root.is_dir():
    for slug_dir in sorted(real_root.iterdir()):
        if not slug_dir.is_dir() or slug_dir.name.startswith("_"):
            continue
        for ts_dir in sorted(slug_dir.iterdir()):
            if ts_dir.is_dir() and (ts_dir / "manifest.json").is_file():
                real_dirs.append(ts_dir)

if not real_dirs:
    print("SKIP: no real on-disk .pull-captures/ bundle (graceful)")
else:
    for rd in real_dirs:
        rfi = read_capture_bundle(rd)
        rr = classify(rfi)
        check(rr.failure_class.value in ENUM_VALUES,
              f"REAL {rd.name}: classify -> valid §6.1 enum "
              f"({rr.failure_class.value})")
        # The one real bundle is boot-ok + all caps green/unsmoked (no
        # red, no failure) — a success/`partial`. It must NOT be filed as
        # a failure and must NEVER route as a kv-calc bug.
        boot_ok = bool((rfi.pt3_boot or {}).get("ok"))
        no_red = not any(
            v == "red"
            for v in ((rfi.pt4_smoke or {}).get("results") or {}).values())
        if boot_ok and no_red:
            check(rr.route_as_kv_calc_bug is False,
                  f"REAL success/partial {rd.name}: never a kv-calc bug")
            check(rr.failure_class is not FailureClass.GENUINE_OOM,
                  f"REAL success/partial {rd.name}: NOT misclassified as "
                  f"genuine-oom")

# ---------------------------------------------------------------------------
if failures:
    print(f"\n{len(failures)} assertion(s) failed.", file=sys.stderr)
    sys.exit(1)
print("\nAll F2 §6.1 Tier-2 classifier (CONTRACT-2 / Appendix A) "
      "assertions passed.")
PY

echo "test-classifier.sh OK"
