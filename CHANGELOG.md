# Changelog (cross-cutting)

Changes that span the entire stack — engine version pins, script behavior, repo structure. Per-model dated history lives in `models/<name>/CHANGELOG.md`.

## Versioning

club-3090 ships docker composes, system scripts, and patch bundles that downstream rigs run as-is — it's effectively software, not just rolling recipes. **SemVer** in `0.x` from `v0.3.0` onward; treat any minor bump as potentially breaking until `1.0`.

Past CalVer tags (preserved for history):

| CalVer tag | SemVer equivalent | Date |
|---|---|---|
| `v2026.05.09` | (≈ v0.1.0) | 2026-05-09 — first tagged release |
| `v2026.05.10` | (≈ v0.2.0) | 2026-05-10 — stack reorg + Gemma 4 INT8 PTH unblock |

CHANGELOG entries below 2026-05-10 use date-prose headings (pre-SemVer convention). New entries from `v0.3.0` use `## v0.X.Y (YYYY-MM-DD) — title`.

## v0.3.1 (2026-05-10) — soak-helper captures `delta.reasoning` (closes cross-rig silent-empty turn-5 mystery)

One-line patch behind a meaningful finding: vLLM nightly (`0.20.2rc1.dev9+`) emits the qwen3 reasoning parser's output under `delta.reasoning` (legacy field name), not `delta.reasoning_content` that `soak-helper.py` was watching. Result: any thinking-on response whose `<think>` block didn't close within `max_tokens` showed up as a silent-empty turn (`ttft_ms == t_ms`, `decode_tps = 0.0`, empty `content` + empty `reasoning_content`) — the model was generating correctly, the harness just couldn't see the wire.

This closes the cross-rig "silent-empty turn 5" pattern that was parked behind the Cliff 2b investigation. It was a harness measurement bug, not a model/rig issue.

Validation on JDWarner's exact repro request (#107 turn 5, math problem + `enable_thinking=true` + `max_tokens=2000`):

| | Before | After |
|---|---|---|
| `ttft_ms` | 22709 (== `t_ms`) | **234** |
| `decode_tps` | **0.0** | **88.985** |
| `reasoning_content` chars | 0 | 3959 |
| `completion_tokens` | 2000 | 2000 (unchanged) |

Validation soak (`qwen3.6-27b dual.yml`, fresh-mode, 20 sessions × 5 turns):

```
verdict              PASS
silent_empty         0 / 100 (0.0%)   ← was ~3-5/40 baseline
p50_decode_tps       90.22
p95_ttft_ms          1389
errors               0
max_growth_mib       0 / 200
```

**Patch** ([88eb67a](https://github.com/noonghunna/club-3090/commit/88eb67a)): `soak-helper.py` accumulates `delta.reasoning_content || delta.reasoning` (covers both vLLM streaming-output shapes, current and legacy). Three-line change inside `cmd_run`'s SSE chunk loop.

## v0.3.0 (2026-05-10) — Qwen thinking-off default, MODEL_DIR UX overhaul, docs cleanup, aider-polyglot bench rows

Eight commits since `v2026.05.10`. Headline: Qwen 3.6 27B now defaults `enable_thinking=false` server-side via `--default-chat-template-kwargs` across all 21 vLLM Qwen composes (closes the recurring "Qwen looks much slower than Gemma" agentic-bench skew). MODEL_DIR docs no longer bake the dev-rig path. New `--include-commit` flag on `power-cap-sweep.sh`.

**Compose change — Qwen 3.6 27B thinking OFF by default** ([534d29f](https://github.com/noonghunna/club-3090/commit/534d29f), [29d17ed](https://github.com/noonghunna/club-3090/commit/29d17ed)):
- All 17 vLLM Qwen 27B composes (single + dual + multi4 + nvlink variants + carnice + qwopus) gain `--default-chat-template-kwargs '{"enable_thinking": false}'` after `--reasoning-parser qwen3`. Server-side default — no per-request kwarg needed.
- llama.cpp single composes: `DISABLE_THINKING` default flipped 0 → 1; `concurrent.yml` gains `--chat-template-kwargs ${CHAT_TEMPLATE_KWARGS:-{"enable_thinking":false}}`.
- `bounded-thinking.yml` intentionally keeps thinking ON (its whole purpose is constrained CoT).
- Per-request override still works for users who want thinking on: `chat_template_kwargs: {enable_thinking: true}` in OpenAI request body.
- Empirical impact: aider-polyglot-30 bench went from 0/30 (1500s timeout, hidden CoT eats budget) → 20/30 (66.7%) on the same hardware once thinking defaulted off.
- Note: 29d17ed used the wrong flag name (`--chat-template-kwargs`); 534d29f corrected to `--default-chat-template-kwargs` after vLLM nightly source confirmed the actual CLI option (referenced in upstream PR #37739).

**MODEL_DIR UX overhaul** (closes club-3090#116 — RobH589's "downloads landing in root of drive" report):
- `cf7f195` — fixed 4 stale refs missed in the 2026-05-10 reorg push (preflight.sh hf-download hint, README.md example, compose header Q5_K_XL→Q3_K_XL stale comment).
- `fbf3431` — replaced the dev-rig path `/mnt/models/huggingface/...` with `$MODEL_DIR/...` placeholders across `models/qwen3.6-27b/llama-cpp/README.md`, `docs/engines/LLAMA_CPP.md`, the compose header, and the `preflight.sh` hint. Cross-rig users no longer see our path baked into instructions.
- `cc3a717` — recipe scripts (`single-card-default.sh`, `single-card-max-ctx.sh`) default `MODEL_PATH` to `${MODEL_DIR:-$HOME/models}/qwen3.6-27b-gguf/...`.
- `3909c2d` — `setup.sh` now **prompts interactively** when `MODEL_DIR` isn't set and stdin is a TTY: pick `<repo>/models-cache`, `$HOME/models`, or custom path; optionally persist to `.env` (gitignored). CI / scripted runs (no TTY) get the silent fallback unchanged.

**`power-cap-sweep.sh` — `--include-commit` flag** ([7d91ac7](https://github.com/noonghunna/club-3090/commit/7d91ac7), closes [#112](https://github.com/noonghunna/club-3090/issues/112)):
- Off by default. When set, stamps the club-3090 git short SHA in the report header next to the date. Useful for cross-rig sweep correlation per @laurimyllari's request.
- Suppresses the field entirely (no "n/a") when run from a non-clone — closes the curl-pipe-from-docs UX hole.

**BENCHMARKS.md — Aider Polyglot 30 quality bench** ([e08988e](https://github.com/noonghunna/club-3090/commit/e08988e)):
- New "Quality benches — Aider Polyglot 30" section with cross-model rows: Qwen 3.6 27B `dual.yml` 20/30 (66.7%) vs Gemma 4 31B `dual.yml` 17/30 (56.7%).
- Documents the thinking-on/thinking-off Qwen failure mode + per-language breakdown.
- Run via [`benchlocal-cli`](https://github.com/noonghunna/benchlocal-cli)'s `aider-polyglot-30` pack.

**cliff.toml + CHANGELOG meta**: switched from CalVer rolling-stack framing to SemVer software framing. Past CalVer tags preserved for history.

---

## 2026-05-10 — Stack reorg: services consolidation, gpu-mode under git, ComfyUI in services/, pin tracker 🧹

(This entry covers `v2026.05.10` — see SemVer mapping above.)


The rig had grown organically across three home dirs (`/opt/ai/compose/`, `/opt/ai/github/`, `/home/wasif/`), three repos (single-3090, dual-3090, club-3090), and ad-hoc paths under `/opt/ai/vllm-src/`, `/opt/ai/vendor/`, `/home/wasif/lucebox-hub/`, `/home/wasif/llama.cpp*`. Disk-out on `/` (97% used) forced a clean-up; rather than just prune, we consolidated the layout while we were at it.

**What landed in this repo:**

- **`services/` is now the canonical home for supporting services.** Five services migrated in from `/opt/ai/compose/`: `ollama/`, `openwebui/`, `litellm/`, `qdrant/`, `searxng/`. Same `docker-compose.yml` files, no functional change. `services/litellm/config.yaml` rewritten — added explicit routes for the current primaries (`qwen3.6-27b-autoround` → :8010, `gemma-4-31b-autoround` → :8030) and removed the `* → ollama/*` wildcard.
- **`services/comfyui/`** also migrated in (was at `/opt/ai/compose/comfyui/`). Wired into `gpu-mode` properly with full mutex against vLLM/SGLang.
- **`scripts/gpu-mode.sh`** moved into the repo (was a loose `/opt/ai/gpu-mode.sh` outside any git tree). Symlinked at `/usr/local/bin/gpu-mode`. New since the move:
  - 5 Gemma 4 31B modes: `gemma`, `gemma-dflash`, `gemma-int8`, `gemma-dflash-int8`, `gemma-awq`
  - 1 ComfyUI mode (mutex with all LLM serving)
  - 2 maintenance subcommands: `prune` (safe — image prune only), `prune-all` (+ build cache, keep-storage 5GB)
  - `gpu-mode status` now shows Docker disk usage, `/var/lib/docker` size, `/tmp` size — surfaces growth without needing to remember `docker system df`
  - `--env-file <repo>/.env` is now passed through `compose_at()` so `MODEL_DIR` resolves correctly regardless of which compose dir we cd into. Fixes the recurring "MODEL_DIR not set, defaulting to ../../../../../models-cache" warnings.
  - `stderr` no longer swallowed by `compose_at()` (real errors now surface)
  - Cross-model VRAM mutex: every Qwen mode `stop_all_gemma` + `stop_comfyui` and vice-versa
  - Ollama dropped from `SERVICES=()` array (no longer auto-started in chat mode); defensive `stop_service ollama` retained in every mode for cleanup
- **`scripts/maintenance/`** new dir for stack-hygiene tools (separates from operational scripts):
  - `list-image-pins.sh` — engine-agnostic pin auditor. Scans every compose for its `image:` line, groups by `<repo>:<tag>`, flags pin-drift (multiple tags pinned for the same repo), ranks composes by patch surface (highest = most expensive to migrate when the engine bumps).
- **`docs/UPSTREAM.md` "Pinned images" section** — table of every pinned image, why each pin exists, retirement candidate criteria. Live snapshot via `scripts/maintenance/list-image-pins.sh`. First entries: 3 distinct vLLM nightlies (Qwen 27B baseline, Gemma 4 base/AWQ/INT8, Gemma 4 DFlash) + 1 llama.cpp:server-cuda.
- **`docs/NIGHTLY_BUMP_RUNBOOK.md`** new — 7-step procedure for bumping pinned engine images (scope → branch → patch survival → boot → verify-full + verify-stress → bench delta → land → retirement). Engine-specific notes for vLLM (nightly hash format, volatile internals like `gpu_model_runner.py`), llama.cpp (capture digest if reproducibility matters), SGLang (variant tag conventions).
- **Path updates from the engine + model reorg.** All references to:
  - `/opt/ai/vllm-src/` → `/opt/ai/engines/vllm/primary/` (in `setup.sh`, `INTERNALS.md`, several compose+patch READMEs, `docs/{HARDWARE,FAQ,DUAL_CARD,UPSTREAM}.md`, `models/qwen3.6-27b/CHANGELOG.md`)
  - `/mnt/models/gguf/qwen3.6-27b/` → `/mnt/models/huggingface/qwen3.6-27b-gguf/` (in `models/qwen3.6-27b/llama-cpp/{compose/single/*.yml, recipes/*.sh, README.md}`, `docs/engines/LLAMA_CPP.md`)
  - `/home/wasif/lucebox-hub/` → `/opt/ai/engines/llama.cpp/refs/luce-dflash/` (in `vllm-gemma4-dflash/README.md`)

**Why now:** the disk-out on `/` (down to ~9.5 GB free, 97% used) made it impossible to pull a fresh nightly during ongoing work. Pruning got us back to 60% used; the reorg turned that recovery into a layout we can keep clean. End state: `/` at 42% (139G→117G used), `/mnt/models` at 80% (758G→741G used). The bigger win is structural — every artifact has one canonical home now, and the directory naming makes the format/role obvious.

**External impact:** none for cross-rig users. All paths inside `setup.sh` and the composes are either inside this repo or under `/mnt/models/` (which `setup.sh` controls via `$MODEL_DIR`). The reorg of the dev rig itself (engines, scripts, /home/wasif) is rig-local and not visible from outside.

## 2026-05-09 — Compose convention formalization + cliff CI + Discord launch

Continuation of the cross-rig contributor flow built earlier in the week. The compose tree had grown organically and was overdue a unification pass on naming, profile shape, and status semantics. Plus the first community-facing surface (Discord) and the release-notes pipeline.

**Compose convention:**
- **Topology promoted to a directory level** (`acdc7ffb`): the previous flat `compose/<variant>.yml` layout becomes `compose/<topology>/<variant>.yml`. Directories: `single/`, `dual/`, `multi4/` (renamed from `dual4/` to align with `MULTI_CARD.md` framing — `d33e6f8`).
- **Profile schema** rolled out across all composes (`fca643d`, `4d7356a`): every compose header now declares Model / Topology / Drafter / KV / Vision / Max ctx / Genesis / Status / Quality / Best for as a structured at-a-glance block. `AGENTS.md` (`62e636c`) codifies the schema + naming rules + experimental-compose conventions.
- **Status enum + Caveats field formalized** (`e1137d6`): every compose now declares `Status: ✅ Production / 🧪 Experimental / ⚠️ Workaround / 🔄 Deprecated` plus a Caveats field. 100% coverage achieved.
- **Quality lines** added on Qwen3.6-27B + Gemma 4 31B duals (`26ff0e5`, `9dea0eb`) — `--full` sandboxed (8-pack) measurements visible in compose headers.
- **`compose: parametrize VLLM_ENFORCE_EAGER, KV_CACHE_DTYPE, P40/P82/PN54 across all variants`** (`af9fb0c`, [#110](https://github.com/noonghunna/club-3090/pull/110) by @easel) — env-override knobs for the most common cross-rig tuning levers.

**Community + ops:**
- **Discord invite** added to README + FAQ + issue template (`c18257f`).
- **`encourage-soak`** template dropdown + script ergonomics + report reminder + Notes convention (`c298b60`).
- **Community projects section** in README pointing at `VykosX/club-3090-server` (`cd48764`).

**Release notes pipeline:**
- Initially added Release Drafter for CalVer release notes (`c49db50`); replaced same day with **`git-cliff` for commit-based release notes** (`7002e6b`). `cliff.toml` defines 10 categories (Cliffs/gotchas, Features, New models, Bug fixes, Benchmarks, Documentation, Pin bumps, Scripts/tooling, Maintenance, Other) with conventional-commits parsing + per-PR author attribution. CI workflow (`.github/workflows/release.yml`) runs on `v[0-9]+.[0-9]+.[0-9]+` tag push and publishes a GitHub Release. **Tag-and-push is what triggers it** — `git tag v0.1.0 && git push --tags` produces the first proper release-page notes.

**Other:**
- BIND_HOST opt-in + localhost script fixes (`73c3184`, [#109](https://github.com/noonghunna/club-3090/pull/109) by @easel) — composes default to `127.0.0.1` binding; `BIND_HOST=0.0.0.0` env var opens up to the LAN explicitly.
- BENCHMARKS.md row added: `@ygafarov` Strix-Halo + oculink-eGPU x4-PCIe single-3090 (`a589058`, [#113](https://github.com/noonghunna/club-3090/issues/113)).
- `quality-test.sh` aligned with benchlocal-cli v0.5 (`1be02d2`, `7020d96` adds `--sandboxed-only` passthrough).

## 2026-05-08 — Gemma 4 31B INT8-PTH KV unblocks 262K context on Ampere

Two regressions caught + reframed Phase 2 around what Ampere actually supports.

- **PR #41745 (Gemma 4 MTP "assistant" drafter) merged upstream** (`595be8f`). Dropped the local `vllm-gemma4-mtp` overlay tree (`aa99173`); the canonical `gemma-mtp` compose now uses the post-merge nightly directly. Validated.
- **`gemma-mtp-fp8.yml` → `gemma-mtp-int8.yml`** (`160e8fc`). Reframed Phase 2 around **INT8 PTH KV** (per-token-head, vendored from rebased PR #40391 stacked with tool-parser fixes #42006 + #41991, commit `f93d312`). Reason: Ampere has no native FP8 tensor cores; the FP8-KV nomenclature was misleading us toward configs that fall back to BF16 anyway. INT8 PTH delivers what FP8-KV was supposed to: smaller KV pool, more context.
- **Phase 2 INT8 PTH validation results shipped** (`1e1886a`): **262K Gemma 4 unblocked** on dual 3090 TP=2 + INT8 PTH KV. verify-stress 91K passes; bench at extended ctx documented.
- Compose-level: `power-cap-sweep` learned to clamp prefill calibration to the model context window (`32f924c`), and to sum `delta.reasoning_content` alongside `delta.content` for reasoning-model bench accuracy (`71e5954`).

## 2026-05-07 — Power-cap-sweep + HARDWARE.md cross-rig data campaign 📊

Heavy contributor week. The power-cap-sweep tool went from "useful" to "the canonical instrument for cross-rig efficiency-knee data" — multiple iterations from Codex review rounds, plateau auto-detection, multi-mode chain.

**`scripts/power-cap-sweep.sh` evolution** (Codex collab + cross-rig portability fixes):
- Added 2026-05-07 (`83d5d97`, [#83](https://github.com/noonghunna/club-3090/pull/83)). Same-day iterations: load-mode flag + concurrent/prefill modes (`f387622`), `--bench-runs N` for variance mitigation (`f99fad3`), `--concurrency auto` for workload-calibrated sweeps (`f811457`), time-bounded streaming bench redesign (`7877c04`, `1ede998`), 4 cross-card portability fixes (`652103f`), env-overridable bench shape for decode-single mode (`c638c30`), SM/mem clock + throttle% + pstate sampling (`ab2796d`), plateau auto-detection (`29e7de5`, `fd11ae6`), `--concurrency-stretch N` flag for probing past plateau pick (`3991ecc`).
- **Canonical command codified** (`886b619`) — every cross-rig anchor uses the same flags so numbers are comparable across submissions.
- **Made CONTAINER optional** for host engine builds (`2bb3cf7`, [#85](https://github.com/noonghunna/club-3090/pull/85), [#87](https://github.com/noonghunna/club-3090/issues/87)) — host-llama.cpp contributors no longer need a container to participate.
- **`verify-full + soak-test decoupled from docker/vLLM assumptions`** (`a8606e3`, [#85](https://github.com/noonghunna/club-3090/pull/85), [#87](https://github.com/noonghunna/club-3090/issues/87)) — host-build contributor flow now end-to-end.
- **`verify-stress` engine-aware diagnostic hints** (`4f01abb`, closes [#87](https://github.com/noonghunna/club-3090/issues/87)).

**HARDWARE.md power-cap charts campaign:**
- Embedded power-cap efficiency charts for **3090 + Qwen3.6 + llama.cpp** (`42afdbb`), **4090 + Qwen3.6 + llama.cpp** (`e70258c`), **5090 + Gemma 4** (`8b1d51a`).
- **3090 air-cooled vs water-cooled correction** (`1f94478`) — earlier doc misclassified our cooling.
- **5090 prefill-heavy sweep from `@apnar`** (`d5ef8c8`, disc [#67](https://github.com/noonghunna/club-3090/discussions/67)) — proves per-workload power ceiling differs (decode vs prefill saturate at different caps).
- **`a7a1d59`: 230W vs 290W vs 330W sweet-spot story reconciled** — single doc covering all three commonly-cited 3090 numbers + the workloads each is the answer for.
- **Plateau evidence + multi-mode chain docs** (`9f77be7`, `fd11ae6`).
- **5090 clock-lock chart + Blackwell freq-cap section** (`119a5fa`).

**Cross-rig benchmark rows added:**
- `@apnar` 5090 Gemma 4 MTP + DFlash (`98b0601`, disc [#67](https://github.com/noonghunna/club-3090/discussions/67))
- `@apnar` 5090 + Gemma 4 + MTP cross-rig anchor (`bef5701`)
- `@lamentofhighborne` 1× 3090 llama.cpp MTP (`68dbfaf`, [#85](https://github.com/noonghunna/club-3090/pull/85))
- `@aaronlockhartdev` patched-P2P driver row (`4eea837`, [#91](https://github.com/noonghunna/club-3090/issues/91), disc [#70](https://github.com/noonghunna/club-3090/discussions/70))
- Three more cross-rig rows from 2026-05-07 reports (`76aacdc`)
- `@danbedford` NVLink + DFlash variants (`0d199a1` [#92](https://github.com/noonghunna/club-3090/pull/92), `b893d60`)

**Engine landscape docs:**
- **`docs/INFERENCE_ENGINES.md` feature matrix** (`dfceccb`): vLLM / llama.cpp / SGLang / ktransformers / **ik_llama.cpp** (added later as 5th column, `0959206`). 12 corrupted table separators fixed in follow-up (`8f5b924`). More honest vLLM GGUF status (`2d9aa14`).
- **opencode unblock** (`af00ab7`, [#97](https://github.com/noonghunna/club-3090/issues/97)): llama.cpp `--reasoning-format none` is now default for compatibility with IDE agents.

**Tool / sidecar:**
- `qwen3coder tool-parser deferred-commit sidecar` (`2e00b6d`, [#72](https://github.com/noonghunna/club-3090/issues/72) by @troymroberts) — closes the same root-cause class as alexpolo1 #104.

**Compose:**
- `dual-nvlink-dflash-noviz` variant added (`63ab224`, NVLink + DFlash N=5 + 200K + no vision; `--max-model-len` default tuned to 188000 in `89c6862`).
- `setup.sh`: Gemma 4 31B model support added (`dd3bccc`, [#89](https://github.com/noonghunna/club-3090/issues/89)).
- `setup.sh`: auto-create `.env` for WSL2 boot-crash workaround (`4861ee7`, [#60](https://github.com/noonghunna/club-3090/issues/60)).

**Reports + ops:**
- `report.sh`: capture recently-exited containers' boot logs (`cd980f6`, [#60](https://github.com/noonghunna/club-3090/issues/60)).
- `report.sh`: engine-aware Active container probes (vllm + llamacpp) (`6fa66d2`).

## 2026-05-06 — `PYTORCH_CUDA_ALLOC_CONF` exposed as override knob (boot-crash workaround)

A single-card RTX 3090 Ti rig on WSL2 (driver 596.36) hit `RuntimeError: CUDA driver error: device not ready` from `gptq_marlin_repack` immediately after weight load on the v7.72.2-uplift nightly pin. Bisect (default → minimal-no-Genesis → minimal + `CUDA_LAUNCH_BLOCKING=1`) ruled out Genesis, spec-decode, TQ3 KV, async-residual error, and TDR (registry already extended + Windows rebooted). Setting `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` resolves the crash. Same env-var workaround as JusefPol's NVLink boot-crash report (PR #31), already hardcoded in the `dual-nvlink*.yml` composes.

**Changes:**
- All 14 single-card and PCIe dual-card composes: `PYTORCH_CUDA_ALLOC_CONF=...` → `${PYTORCH_CUDA_ALLOC_CONF:-...}` env-override knob (defaults preserved). Pattern matches existing `MAX_MODEL_LEN` / `GPU_MEMORY_UTILIZATION` overrides from #79.
- `dual-nvlink.yml` / `dual-nvlink-turbo.yml`: untouched (their existing JusefPol-driven default already has `expandable_segments` off).
- `.env.example`: documented the override under "vLLM tuning knobs".
- `docs/HARDWARE.md`: new `### Fix — disable PyTorch expandable_segments` subsection with stack trace, what we ruled out, the override recipe, and a single observation about weight-load time (32 sec → 13 sec on this rig — uncontrolled, not a measured benchmark).
- `docs/FAQ.md`: WSL2 question now cross-links to both the TDR and `expandable_segments` fix subsections.

The exact failing call hasn't been isolated; the `cuMemMap` virtual-memory API used by `expandable_segments:True` is the suspected culprit since both known occurrences respond to the same workaround, but we haven't proven which call returns `cudaErrorNotReady`.

**Override:** drop `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` into a `.env` next to the compose, then `docker compose up -d` as usual.

## 2026-05-05 — v7.72.2-uplift: Genesis pin bump + sidecar consolidation + cross-rig PN59 finding ⭐

Sander shipped Genesis [v7.72.2](https://github.com/Sandermage/genesis-vllm-patches/blob/main/CHANGELOG.md) on 2026-05-05 with 7 new patches (PN59-PN67), the v7.72.1 P68 xgrammar-incompat fix (closes [#57](https://github.com/noonghunna/club-3090/issues/57)), and v7.72.2 PN70 schema-subset filter. Branch `v7.72.2-uplift` aligns club-3090 with the new release.

**Pin bumps:**
- `scripts/setup.sh` `GENESIS_PIN`: `2db18df` (v7.69) → `7b9fd319` (v7.72.2)
- All 16 composes' vLLM image: `nightly-7a1eb8ac2ec...` → `nightly-01d4d1ad375...` (Sander's PROD-validated pin, allowlist entry #2)

**Sidecar consolidation** — 6 local sidecars deleted from `models/qwen3.6-27b/vllm/patches/`, all confirmed redundant on v7.72.2:

| Retired sidecar | Genesis native that supersedes |
|---|---|
| `patch_inputs_embeds_optional.py` | PN35 (vllm#35975 backport, default-on since v7.69) |
| `patch_pn30_dst_shaped_temp_fix.py` | PN30 v7.68 dst-shaped temp |
| `patch_pn25_genesis_register_fix.py` | PN25 opaque-op pool |
| `patch_tolist_cudagraph.py` | P78 TQ tolist capture-guard (Sander's v7.72 CHANGELOG retires this) |
| `patch_workspace_lock_disable.py` | PN34 workspace-lock relax |
| `patch_pr40798_workspace.py` | (research artifact, no compose ever mounted it) |

The 7 Genesis-loaded composes (`docker-compose.yml`, `dual-turbo.yml`, `long-text.yml`, `long-text-no-mtp.yml`, `long-vision.yml`, `bounded-thinking.yml`, `tools-text.yml`) had their volume mounts and entrypoint shell invocations cleaned up; `GENESIS_ENABLE_PN59_STREAMING_GDN=1` was added to all 7 for consistency.

`dual/docker-compose.yml` is intentionally left **Genesis-free** as a debugging fallback for cross-engine bisect — useful when isolating "is this a Genesis bug or upstream vLLM bug" during silent-empty / OOM triage.

**Bench results** (dual-turbo, 2× 3090):

| Metric | v7.69 baseline | v7.72.2 + new vLLM pin | Δ |
|---|---:|---:|---:|
| Narrative wall TPS | 81.57 | 81.21 | flat (within CV) |
| Code wall TPS | 108.77 | 108.20 | flat (within CV) |
| MTP AL | 3.47 | 3.46 | flat |
| **VRAM/card** | **22.1 GB** | **20.0 GB** | **−2.1 GB** ⭐ |
| Code CV | 2.1% | **0.9%** | tighter |
| All verify-full checks | pass | **pass (8/8)** | ✓ |

The 2 GB VRAM headroom recovery is the headline — PN35 (~64 MiB GPU + ~64 MiB pinned CPU per site × 2 sites) plus the cumulative effect of Sander's audit-pass cleanups. On 24 GB cards this is a real ~9% headroom gain.

**Phase C cross-rig PN59 finding** — single-card 24 GB Cliff 2b is **unchanged** despite v7.72.2's PN59 streaming-GDN orchestrator. Diagnosis showed PN59's eligibility check rejects calls with non-None `chunk_indices`/`chunk_offsets`, which vLLM's mandatory `--max-num-batched-tokens 4128` always populates on 24 GB single-card configs. PN59 falls back to `_vanilla_path` which OOMs at the exact `chunk_o.py:161 torch.empty_like(v)` site PN59 was advertised to eliminate. Filed as [Sandermage/genesis-vllm-patches#22](https://github.com/Sandermage/genesis-vllm-patches/issues/22) with concrete reproducer + 4 fix proposals; cross-link from [club-3090 disc #19](https://github.com/noonghunna/club-3090/discussions/19#discussioncomment-16815715).

**v7.72.1 closes [#57](https://github.com/noonghunna/club-3090/issues/57)** (lex's xgrammar-patternProperties fire on long-prompt agentic IDE traffic). P68 now auto-skips `tool_choice` upgrade on dirty catalogs; PN70 (opt-in via `GENESIS_ENABLE_PN70_TOOL_SCHEMA_FILTER=1`) is the companion option-3 path. Issue closed 2026-05-05.

**Reading order on this branch:**
1. `models/qwen3.6-27b/vllm/patches/README.md` — what's still load-bearing vs superseded
2. BENCHMARKS.md `dual-turbo.yml` 2026-05-05 row — measured uplift numbers
3. [Sandermage/genesis-vllm-patches#22](https://github.com/Sandermage/genesis-vllm-patches/issues/22) — open Genesis issue with the PN59 finding

---

## 2026-05-04 PM — KV format choice is per-VRAM-class, not just per-engine-config (#47) ⭐

Cross-rig validation by [@efschu](https://github.com/noonghunna/club-3090/issues/47) on 2× modded 3080 (20 GB / card) surfaced that **`dual-turbo.yml`'s shipped `turboquant_3bit_nc` KV trips Cliff 2 at 90K on 20 GB Ampere even though the same compose works at 262K on 2× 3090 (24 GB)**. Override to `--kv-cache-dtype fp8_e5m2` and the full window opens — verify-stress 7/7 PASS including the 91K needle, full 257,851-token auto-discovery needle test PASS at 90% depth, bench 82.4 narr / 107.9 code TPS.

The mechanism: TQ3 KV trades 0.375 bytes/cached-token (smallest KV pool → most concurrency) against a higher activation peak during the DeltaNet GDN forward (~1 GB/card more pressure than fp8). On 24 GB / 3090 the budget absorbs the activation peak. On 20 GB the trade flips — there isn't enough activation headroom after TP=2 split, and Cliff 2 fires at single-prompt 90K.

**Repo lesson recorded:** the variant matrix is per-card-budget × KV-format-tradeoff aware. Shipped defaults are tuned for 24 GB / 3090; users on different VRAM classes may need to override `--kv-cache-dtype` to relocate the activation/pool balance for their hardware.

**Files updated:**
- `docs/HARDWARE.md` — "Note for sub-24 GB cards" section extended with the TQ3→fp8_e5m2 swap rule, byte math, attribution to @efschu, cross-link to #47
- `docs/CLIFFS.md` — new subsection "KV format choice tunes the boundary" under Cliff 2 root-cause explanation; generalizes from the specific 20 GB finding to the principle
- `docs/DUAL_CARD.md` — `dual-turbo` picker row gets an inline pointer to the override
- `models/qwen3.6-27b/vllm/compose/dual/turbo.yml` — inline comment near the `--kv-cache-dtype turboquant_3bit_nc` line so users overriding via env or fork have the rationale at hand

This is a **hardware-class lesson, not a bug fix**. The `dual-turbo.yml` defaults are correct for the canonical hardware. The override path is now discoverable from every doc surface a user would land on when hitting the symptom.

Future related work: `scripts/setup.sh` could pre-flight detect VRAM class and surface KV-format guidance before compose boot. Tracked in #219 (compose-dependency preflight) — likely worth an env override knob (`KV_FORMAT=fp8_e5m2 bash scripts/switch.sh vllm/dual-turbo`) once the preflight lands.

## 2026-05-04 — bounded-thinking Phase 3 grammar A/B complete; DeepSeek scratchpad is the new recommended grammar ⭐

After the Phase 3 5-grammar A/B at full HE+ 164 + LCB v6 50 (n=214), `bounded-thinking.yml` is updated to recommend the **DeepSeek scratchpad grammar** (PLAN/NOTE×0-15/VERDICT FSM at `tools/grammar-eval/deepseek-scratchpad.gbnf`) as the new default. Phase 3 result: **93.9% HE+ / 66.0% LCB v6 / 87.4% combined**, mean 541 think tokens. The defensible framing: DeepSeek doesn't lose combined accuracy vs the andthattoo G/A/E baseline (+0.47pp = 1 problem on n=214, below noise) and gains +4pp on LCB v6 (= 2 problems on n=50, design signal not statistical proof). The "+1 net win" framing is too strong; the real evidence is per-LCB improvement at preserved HE+ accuracy.

The compose itself is unchanged engine-side — same vLLM image, same Genesis stack, same TQ3 KV, same MTP n=3, same `enable_in_reasoning` flag. Only the recommended grammar in the docstring + the on-disk grammar files in `tools/grammar-eval/` change. The grammar is selected client-side via `extra_body={"structured_outputs": {"grammar": ...}}`.

**Three grammars are now validated and available** (all live in `tools/grammar-eval/`):

- **DeepSeek scratchpad** (new default) — 87.4% combined, best on LCB v6
- **andthattoo G/A/E** (the originally-published technique we ported) — 86.9% combined, ~4× tighter think budget (134 vs 541 tokens). Available via [`andthattoo/structured-cot`](https://github.com/andthattoo/structured-cot/blob/main/grammars/fsm_grammar.gbnf). Pick this for cost-bounded deployments.
- **Holiday tagline** — 86.4% combined, 24-token extreme-compression. Wins LCB by 4pp over andthattoo too. Pick this for tagging/classification/log-triage.

**We ship one compose, not three.** Combined-accuracy spread across the three grammars is within noise (0.5pp over 214 problems), so creating three sibling composes would have been paradox-of-choice without statistical justification. The compose is grammar-agnostic — choice happens at the client.

Phase 3 also recontextualized Phase 2's n=30 finding: **PROMPT_TERSE loses on the long tail at scale** (82.2% combined, −10 net vs the FSM-enforced grammars at 214 problems). The right framing isn't "prompting never helps" — PT still rescues HE/151 and ties DeepSeek on the 6-problem prior-regression cluster, so it's competitive on the rigid-FSM-fail class. The defensible claim is *prompt-only shaping lacks the long-tail reliability needed across the full distribution*. Phase 1 reproducibility is exact (HE+ Δ +4.3pp, LCB Δ +24.0pp — both match Phase 1's published numbers).

**Files updated:**
- `models/qwen3.6-27b/vllm/compose/single/bounded-thinking.yml` — docstring rewritten to recommend DeepSeek scratchpad; references all three available grammars + Phase 3 results
- `tools/grammar-eval/deepseek-scratchpad.gbnf` (NEW; landed earlier in Phase 2)
- `docs/STRUCTURED_COT.md` — Phase 3 final results, three-grammar decision table, single-compose-with-default-grammar rationale
- `docs/SINGLE_CARD.md`, `docs/CLIFFS.md`, `docs/EXAMPLES.md`, `docs/UPSTREAM.md`, `BENCHMARKS.md` — refreshed to reflect Phase 3 numbers and the single shipped compose
- `tools/grammar-eval/smoke-test.py` — `--boot` default unchanged, but boots `vllm/bounded-thinking` (canonical name retained)

This wraps active research on bounded-thinking. Reopen if upstream FSM-regress cluster behavior changes (Genesis pin bump, vLLM grammar engine swap, model-family change), or if a user-driven workload demands the Holiday or andthattoo grammar as a default sibling compose.

**Bug fix bundled in this commit:** `tools/grammar-eval/subset-bench.py` `--full --include-lcb` mode now correctly threads dataset kind through `run_condition` so LCB problems use `mod.run_tests_livecodebench` instead of HE+ assertion-based testing. Without this, the Phase 3 LCB shard crashed with `KeyError: 'prompt'` on the HE→LCB transition (which is how we discovered it). Phase 3 LCB results recovered by re-running LCB-only on GPU 0 after the fix.

## 2026-05-03 PM — docs reflect Cliff 2b accumulated-context envelope ⭐

Updates docs to surface the corrected operating envelope after today's full validation matrix (see prior entry "soak-test v2 continuous fixtures + Cliff 2 reproduction at 25K accumulated context").

- **`docs/SINGLE_CARD.md`** — adds top-of-page ⚠️ section: single-card vLLM is **not safe** for accumulating-context multi-turn agent traffic on Qwen3.6-27B (hermes/openhands/Cline/OpenCode/OpenClaw etc.). Routing tree: 2× 3090 → `vllm/dual`; 1× 3090 → `llamacpp/default`. The "One limitation to know" section split into Cliff 2a (single-prompt, mostly closed) and Cliff 2b (multi-turn, NOT closed).
- **`docs/CLIFFS.md`** — TL;DR table extended from 2 cliffs to 3 (Cliff 2a + Cliff 2b separated). Two new subsections: **"Why TP=2 escapes"** (per-card live-tensor halving via head sharding — concrete byte math) and **"Why llama.cpp escapes"** (different kernels + ggml flat allocator + no JIT). Mechanism-level explanation for why our two recommended escape paths actually work, not just empirical that they do.
- **`docs/FAQ.md`** — new entry under Troubleshooting: *"My hermes / openhands / OpenCode / Cline / OpenClaw / Cursor session OOMs after a few turns. What do I do?"* Lists every dead-end mitigation we tested today (mem-util, MTP-off, max-num-batched-tokens, TRITON_CACHE_AUTOTUNING, expandable_segments, empty_cache) so users don't burn time tuning what we already ruled out. Routing recommendations + soak-test reproduction command.

Active issues responded to with the corrected envelope: [#41](https://github.com/noonghunna/club-3090/issues/41) (GuiPerPT), [#42](https://github.com/noonghunna/club-3090/issues/42) (HoodOG1, OpenCode), [#43](https://github.com/noonghunna/club-3090/issues/43) (stiggy2k16, OpenClaw). PR [#44](https://github.com/noonghunna/club-3090/pull/44) (Whamp's TP=4 baseline) reviewed with rig-report ask + optional v2 soak.

Genesis sidecar fix (streaming refactor of `chunk_gated_delta_rule_fwd` to reduce simultaneous live-tensor set) being filed with Sandermage. ETA 2-4 weeks if accepted.

## 2026-05-03 PM — grammar-eval harness lands; Holiday tagline grammar phase-1 smoke ✅

[Holiday_Purpose_3166's tagline grammar from r/LocalLLaMA](https://www.reddit.com/r/LocalLLaMA/comments/1sx7w55/) translated for vLLM/xgrammar and validated end-to-end against `vllm/bounded-thinking`. Different design philosophy from our shipped `andthattoo/structured-cot` GOAL/APPROACH/EDGE — 5 short fields (`Q=verb / M=method / K=keywords / R=result-keywords / V=verdict`) where K and R hold 1-5 comma-separated free tokens, giving the model a pressure-relief valve that the rigid 3-line shape lacks.

**Hypothesis being tested:** the K/R free-token-list fields rescue some/all of the 6 known HE+ FSM-regress problems (HE/97, 101, 108, 129, 137, 151) where our current grammar over-compresses and FREE wins. Phase-1 smoke (5 prompts × tagline-grammar) all PASS — translation valid, applies on xgrammar via `extra_body.structured_outputs.grammar`. Phase-2 30-prompt subset bench is unblocked, pending compute time.

**Files added:**
- `tools/grammar-eval/holiday-tagline.gbnf` — translated grammar (xgrammar-compatible)
- `tools/grammar-eval/TRANSLATION.md` — translation decisions + Phase-1 smoke results
- `tools/grammar-eval/smoke-test.py` — Phase-1 runner
- `tools/grammar-eval/subset-bench.py` — Phase-2 30-prompt HE+ A/B harness (FREE vs current vs Holiday vs PROMPT_TERSE)
- `tools/grammar-eval/README.md` — harness overview + run instructions

**Active experiment** noted in [`docs/STRUCTURED_COT.md`](docs/STRUCTURED_COT.md) "FSM-regress cases are real" section. Implementation by Codex against `docs/diagnostics/grammar-eval-codex-brief.md` (gitignored). Companion design-exercise prompt for refining the grammar further is at `docs/diagnostics/grammar-design-llm-prompt.md` (gitignored, can be passed to ChatGPT/DeepSeek/Gemini for fresh design ideas).

## 2026-05-03 PM — soak-test v2 continuous fixtures + Cliff 2 reproduction at 25K accumulated context ⭐⭐

`SOAK_MODE=continuous` env knob added to `scripts/soak-test.sh` — opt-in mode where each session is a single multi-turn agentic-coding conversation that ramps to ~22-25K accumulated context by turn 5. Mirrors the hermes/openhands workload pattern that bit @GuiPerPT in [club-3090#41](https://github.com/noonghunna/club-3090/issues/41) and that v1 fresh-mode fixtures (reset conversation each turn) couldn't reproduce.

**Major finding from first cross-rig run:** Cliff 2 (`chunk_gated_delta_rule → chunk_fwd_o → torch.empty_like(v)`) **fires at ~25K accumulated context, not just at 50-60K single prompts.** Both shipping single-card configs OOM under v2 continuous traffic on Qwen3.6-27B AutoRound INT4 + vLLM `0.20.1rc1.dev16` + Genesis `2db18df`/v7.69 + RTX 3090:

| Config | Boot baseline | Max VRAM | Growth | OOM at | Verdict |
|---|---|---|---|---|---|
| `vllm/long-vision` 145K + 0.95 | 21778 MiB | 23818 MiB | +2040 MiB | session 1 turn 5 (~26K ctx) | **FAIL** |
| `vllm/long-text` 180K + 0.93 | 22434 MiB | 23736 MiB | +3240 MiB | session 1 turn 4 (~21K ctx) | **FAIL** |

Both crash with byte-identical stack trace to GuiPerPT's #41 report (`Tried to allocate 38-50 MiB / ~32 MiB free`). Reproducing via fresh mode requires a 60K+ single prompt; reproducing via continuous mode requires only ~21-26K cumulative context across 4-5 multi-turn requests. **Fundamentally re-shapes the operating envelope** — not a long-vision-specific issue, not a 0.95-vs-0.93 calibration issue. Both shipping single-card variants are unsafe for hermes/openhands traffic.

**Practical implications for users:**

- **For multi-turn agent workloads (hermes, openhands, OpenCode multi-turn, Cline with retained context):** route to `vllm/dual.yml` (TP=2 splits activation peaks) or `llamacpp/default` (different memory regime, no Cliff 2). Single-card vLLM long-* variants are not safe for sustained agentic coding.
- **For single-shot vLLM single-card workloads (fresh chat, RAG with reset-each-query, 1-2 tool calls):** long-text and long-vision still work — the issue is sustained context accumulation, not basic operation.
- **For the upper-bound on safe single-card multi-turn context:** somewhere between fresh-mode safe (cleared by long-text on the v1 soak) and continuous-mode unsafe (~21K). Need calibration runs at intermediate accumulated-context sizes to find the boundary.

**Implementation:**
- `soak-helper.py` — adds 5 ramping turn shapes (small chat → tool inspection → grep → run_command → final fix), `init-session`, `request-continuous`, `ingest` commands. State persists in `state-s{N}.json` per session. Synthesizes plausible Python code / grep / pytest filler tool results so context grows even when the model doesn't emit a real tool_call.
- `cmd_run` extended to capture `content`, `reasoning_content`, and accumulated `tool_calls` from streaming chunks (was metrics-only in v1).
- `soak-test.sh` — `SOAK_MODE=fresh` (default, v1 backward-compat) or `continuous`. Continuous mode requires `SOAK_TURNS=5` (turn shapes are a designed ramp). Per-session state dir at `results/<run>/states/`.

**Methodology trade-off documented:** v1 fresh mode catches raw VRAM accretion class; v2 continuous mode catches context-accumulation class. They're complementary — both worth running before shipping a new config.

## 2026-05-03 PM — soak-test calibration + switch.sh boot-progress UX

First cross-rig soak runs surfaced three calibration issues fixed in the same commit batch:

**Calibration fixes:**
- **Baseline timing**: brief said capture warm baseline "after first turn" — but turn 3 ships a 12K-char tool-result paste that fills the prefix cache (~1000 MiB jump), making baseline-after-turn-1 false-positive on every healthy config. Fixed by capturing baseline at **end of session 1**, after all 5 turn shapes have run once and cache fill has completed. From there, sessions 2-N measure real accretion. Validated on long-text and long-vision (both PASS with 0 MiB growth from corrected baseline).
- **`decode_tps=2e9` artifact**: thinking-mode requests where vLLM bundles all reasoning into the terminal chunk produce `wall ≈ ttft` (no streaming content delta visible until the end). Old code computed `decode_tps = completion_tokens / (wall - ttft)` with `wall - ttft ≈ 0`, yielding ~2 billion TPS. Fixed: detect `wall - ttft < 100ms` or `ttft is None` and report `decode_tps = 0` (filterable).
- **TPS retention metric pollution**: `tps_retention = last_5_median / first_5_median` was being skewed up by the 2e9 outliers in early sessions. Added defensive filter `0 < t <= 500` for "realistic" decode TPS values across all summary computations.

**Cross-rig results:**

| Config | Boot baseline | Max VRAM | Growth | TPS retention | Verdict |
|---|---|---|---|---|---|
| `vllm/long-text` 180K + 0.93 | 23316 MiB | 23316 MiB | 0 MiB | 83.8% | PASS |
| `vllm/long-vision` 145K + 0.95 | 22778 MiB | 22778 MiB | 0 MiB | 98.0% | PASS |

**Methodology limitation surfaced**: long-vision under our synthetic 5-turn fixtures is soak-clean — but the [#41 hermes/openhands case](https://github.com/noonghunna/club-3090/issues/41) remains real-world reproducible. Our fixtures reset the conversation each turn; hermes accumulates context across turns. To catch the #41 class, v2 fixtures need session = single conversation with growing prefix. v1 catches a different class (raw VRAM accretion across requests) and discriminates that correctly.

**`switch.sh` boot-progress UX** (filed as a UX gap when @noonghunna's first long-text boot crashed silently for 8s before timing out at 600s):
- `wait_ready` now does crash detection — `docker inspect -f '{{.State.Running}}'` between polls. If container died, dump last 30 log lines + exit 1 immediately. Converts "silent 600s wait on a dead container" into "5s + actual error".
- `wait_ready` also surfaces boot-stage markers from docker logs: "Resolved architecture", "Loading weights", "Compilation finished", "Capturing CUDA graphs", "Application startup complete". Validated end-to-end on long-vision boot — visible progress at 60s/68s/80s/120s/176s/196s instead of 30s-pulse silence.

## 2026-05-03 — `scripts/soak-test.sh` ships v1

Adds a third validation primitive — `bash scripts/soak-test.sh` — that catches runtime VRAM accretion and multi-turn-agent-traffic OOMs that the existing two scripts don't surface. Companion to verify-full + verify-stress:

| Script | Question | Time | Catches |
|---|---|---|---|
| `verify-full.sh` | Does it boot + serve correctly? | ~2 min | Patch failures, tool-call regressions |
| `verify-stress.sh` | Do the **known cliffs** fire under one-shot stress? | ~5-10 min | Boot-time + single-large-prompt OOMs |
| **`soak-test.sh`** (new) | Does runtime accretion / multi-turn traffic fire OOM? | ~10-30 min | The class that bit [#41](https://github.com/noonghunna/club-3090/issues/41) |

Auto-detects container + endpoint, runs `SOAK_SESSIONS=20` × `SOAK_TURNS=5` synthetic agent shapes (small chat → tool call → large tool result → code completion → reasoning-heavy), watches VRAM growth between turns, and fails when post-warm-baseline growth exceeds `SOAK_MAX_GROWTH_MIB=200` OR engine-dead errors fire OR decode-TPS retention drops below 80%. Outputs CSV turn-log, GPU snapshots, baseline.json, and a summary.md with verdict + recommendation. Read-only against the running deployment; not part of `launch.sh` (slow + opt-in by design).

Implementation by Codex against `docs/diagnostics/soak-test-codex-brief.md`. Validated locally via mock-data PASS/FAIL/INCONCLUSIVE paths and a synthetic replay of #41's 1.2 GiB growth pattern (correctly produces `FAIL: VRAM grew 1165 MiB > 200 MiB threshold`). Live cross-rig validation pending — run on long-vision (expected FAIL pre-fix), long-text + minimal + dual (expected PASS).

## 2026-05-03 — repo-drift detection + `scripts/update.sh`

Catches the most common stale-setup pattern: user cloned weeks ago, master moved (Genesis pin bumps, compose changes, vendored patch updates), they re-run their compose, hit a stale config, file an issue we already solved on master.

- **`preflight_repo_drift`** — new function in `scripts/preflight.sh`, wired into both `launch.sh` and `switch.sh` alongside the existing `preflight_genesis_pin`. Soft-warns on boot when local HEAD is behind `origin/master`, with commit count + last-fetch age + the one-line fix. Skips silently on non-master / forks / `PREFLIGHT_NO_FETCH=1`. 5s fetch timeout so flaky networks don't block boot.
- **`scripts/update.sh`** — one-shot upgrade path. Refuses on dirty trees (preserves any local edits), refuses on non-master branches, then `git pull --ff-only origin master` + re-runs `setup.sh` to re-pin Genesis and re-vendor patches. Doesn't auto-restart the container — tells the user to `bash scripts/switch.sh <variant>` so they can A/B old-vs-new before bringing the new variant up. `--dry-run` and `--force` for the edge cases.

JusefPol's PR #31 (`vllm/dual-nvlink` variant) also landed today — community-experimental opt-in for users with NVLink bridges installed (`bash scripts/switch.sh vllm/dual-nvlink`, port 8014). Not in the launch wizard menu by default to avoid silently booting NVLink configs on PCIe-only rigs.

## 2026-05-02 PM — Genesis pin v7.69 master cutover + Cliff 2 60K closure ⭐⭐

Master Genesis pin bump `fc89395` (v7.66) → `2db18df` (v7.69 dev tip) in `scripts/setup.sh`. All three v7.66/v7.68 cross-rig regressions we surfaced (PN30 part3 drift-markers, P103 worker self-install, PN32 v1) landed in v7.69. Three local sidecars retired (`patch_pn25_genesis_register_fix.py`, `patch_pn30_dst_shaped_temp_fix.py`, `patch_workspace_lock_disable.py`); one new local backport added (`patch_inputs_embeds_optional.py` = vllm#35975).

**Cliff 2 closure:** combined v7.69 (PN32 + P103 worker self-install) + #35975 backport closes the **60K single-prompt envelope** on TQ3 + MTP K=3 at 24 GB. Two shippable single-card variants:

| Variant | Compose | Ctx | mem-util | MTP | 60K result |
|---|---|---|---|---|---|
| Balanced MTP ⭐ | `long-text.yml` | 180K | 0.93 | K=3 | PASS 623s |
| Max-context | `long-text-no-mtp.yml` (NEW) | 200K | 0.95 | off | PASS 537s |

Per-model deep dive: [models/qwen3.6-27b/CHANGELOG.md](models/qwen3.6-27b/CHANGELOG.md). Stack synthesis: [docs/CLIFFS.md](docs/CLIFFS.md). Upstream tracking: [docs/UPSTREAM.md](docs/UPSTREAM.md).

## 2026-04-30 PM — Bounded-thinking compose ships (structured-CoT cross-rig port)

[andthattoo/structured-cot](https://github.com/andthattoo/structured-cot) showed GBNF-grammar-bounded `<think>` blocks compress reasoning ~22-43× on coding benchmarks with no accuracy loss, on Qwen3.6-35B-A3B MoE Q4_K_M / 1× H100 / llama.cpp. We ported the technique to our stack — Qwen3.6-27B AutoRound INT4 dense / 1× RTX 3090 / vLLM nightly + MTP n=3 + TQ3 KV — and re-benched on the full HumanEval+ 164 + LiveCodeBench v6 50.

**Headline measured (max_tokens=4096, greedy):**
- HumanEval+ 164: FSM **92.7%** vs FREE **88.4%** pass@1 (+4.3pp), **30.7×** think compression
- LiveCodeBench v6 50: FSM **66.0%** vs FREE **42.0%** pass@1 (+24.0pp), **26.2×** think compression

The +Δpp accuracy gain partly reflects FSM dodging the `max_tokens=4096` truncation trap rather than pure reasoning gain — see [`docs/STRUCTURED_COT.md`](docs/STRUCTURED_COT.md) "Honest caveats" for the full picture.

**Three port surprises worth keeping:**
1. vLLM dev205+ defaults `StructuredOutputsConfig.enable_in_reasoning=False` — grammar mask only fires post-`</think>` unless overridden. The new `bounded-thinking.yml` compose sets `--structured-outputs-config.enable_in_reasoning true`.
2. Legacy `extra_body={"guided_grammar": ...}` is silently dropped on dev205+. Use `extra_body={"structured_outputs": {"grammar": ...}}`.
3. Qwen3.6 chat template auto-prefixes `<think>\n`. Drop the leading literal from upstream grammars when porting.

**Files added:**
- `models/qwen3.6-27b/vllm/compose/single/bounded-thinking.yml` — sister of long-text with the flag baked in
- `docs/STRUCTURED_COT.md` — public writeup with bench, usage, caveats
- `models/qwen3.6-27b/vllm/diagnostics/structured-cot-bench.md` — internal diagnostics with full setup details and port findings

**Files updated:**
- `scripts/launch.sh` wizard + `scripts/switch.sh` variant map
- `models/qwen3.6-27b/README.md` — bounded-thinking added to recommended single-card list + Genesis patch surface
- `models/qwen3.6-27b/vllm/README.md` — compose menu
- `docs/SINGLE_CARD.md` — TL;DR table now four rows

**Credit:** [andthattoo](https://github.com/andthattoo) for the technique, the grammar files, and the eval harness. We did the cross-rig port (one-line API patch + the `enable_in_reasoning` flag dance) and re-benched on a smaller dense model with a different quant + spec-decode stack.

## 2026-04-29 — Remove `no-genesis-mtp.yml` (research artifact, not user-facing)

`no-genesis-mtp.yml` was a control variant we used to A/B-test whether MTP-without-Genesis worked (it does — Genesis isn't strictly required for fp8+MTP). Useful for our internal upstream-bug-isolation workflow, but no real reason for end users to pick it over `tools-text.yml` (fp8 + MTP + Genesis bugfixes + 75K, strictly better) or `minimal.yml` (no Genesis at all, simplest stack). Wizard already didn't surface it. Removed from `switch.sh` variant map, sibling compose "see also" tables, patches/README, and engines/VLLM.md.

## 2026-04-30 PM — Cliff 1 mech B closes at 205K (PN12 anchor drift was the real bug)

**The real problem was anchor drift in PN12, not pool surface.** Earlier 2026-04-30 we'd built P104 + P101 anchor fix and concluded TQ3 + single-card + MTP hit an "architectural wall" because Cliff 1 mech B fired at 205K and 175K with identical signatures. Hypothesis: PN12 only pools `SiluAndMul` output, leaving the larger `gate_up_proj` allocation upstream — needs extension. **That hypothesis was wrong.**

Investigation found PN12 was silently no-op'd on dev205+: its anchor expected `@CustomOp.register("silu_and_mul_with_clamp")` immediately after `SiluAndMul`, but upstream now has `MulAndSilu` in that slot. Genesis `apply_all` reported "PN12 applied" while the live `vllm/model_executor/layers/activation.py` retained the vanilla body — same anchor-drift class as P101. We had no direct evidence PN12 was applying; we'd inferred it from the OOM signature.

**Local repair via two sidecars in `models/qwen3.6-27b/vllm/patches/`:**
- `patch_pn12_ffn_pool_anchor.py` — class-scoped anchor fix that actually patches `SiluAndMul.forward_cuda` with PN12's pooled-output body, env-gated by the existing `GENESIS_ENABLE_PN12_FFN_INTERMEDIATE_POOL=1`.
- `patch_fa_max_seqlen_clamp.py` — local P104 sidecar (Genesis pin doesn't ship P104 yet).

Both wired into `single/long-text.yml` after `apply_all`.

**Verified on RTX 3090 single-card (2026-04-30 PM):**
- `--max-model-len 205000`, `--max-num-batched-tokens 4128`, `--num-gpu-blocks-override 50`, MTP n=3
- P101 + P103 + PN12 (anchor-repaired) + PN13 + P104 (sidecar) all enabled
- `verify-stress.sh` tool-prefill: 643 chars, finish=stop ← was failing 138 MiB allocate / 130 MiB free
- `verify-full.sh`: all 8 checks passed
- MTP acceptance length: 2.38

**Lesson:** for any Genesis text-patch on a fresh upstream pin, grep the live file for the patch marker before drawing implementation conclusions. We now have two consecutive bisections (P101, then PN12) where anchor drift masqueraded as design problems and ate substantial debugging time. Anchor health verification belongs ahead of implementation analysis.

**Sandermage's PN12 design intent was correct all along** — pooling `SiluAndMul` output is sufficient for Cliff 1 mech B. No `gate_up_proj` extension needed. The bug was patch-application infrastructure, not algorithmic.

**PN12 anchor fix opened as [Sandermage PR #13](https://github.com/Sandermage/genesis-vllm-patches/pull/13)** (same narrow scope as P101 PR #12). Independent retest from a fresh container boot reproduced closure: verify-stress 671 chars / finish=stop, verify-full all 8 pass, MTP AL 2.45, VRAM 22.6/24 GB.

**Bisection of upward ceilings (commit f3e5b52):**
- `long-text.yml`: 205K → **218K** at 0.985 mem-util (vision off). Engine ceiling at 0.985 is vLLM-reported 218784. Verified by verify-stress + verify-full, MTP AL 2.66.
- `long-vision.yml`: 192K → **198K** at 0.98 mem-util (vision on). Engine ceiling at 0.98 is vLLM-reported 198144. 0.985 + vision reopens Cliff 1 (more goes to KV at the cost of activation budget; vision tower's persistent ~1 GB allocation makes this fragile).
- `--num-gpu-blocks-override 50` no longer needed at 0.985 — anchor-fixed PN12 cuts allocator churn enough that natural activation budget at higher mem-util is sufficient on text-only path.
- 0.99 mem-util ruled out — hardware reserves ~440 MiB (24 GB → 23.56 GiB visible to vLLM), so vLLM's 0.99 startup check fails.

**Decisions pending:**
- Whether to flip the default `docker-compose.yml` (currently 48K + vision) to one of these higher-ctx variants, or keep 48K as the conservative production path.
- Whether P104 stays held until Sandermage responds on issue #11, or gets PR'd alongside #12 + #13 now that two anchor-drift fixes are already in his queue (P104 is new functionality, different scoping decision than anchor fixes).

Full diagnostic: [`models/qwen3.6-27b/vllm/diagnostics/cliff1-attack.md`](models/qwen3.6-27b/vllm/diagnostics/cliff1-attack.md). Branch `cliff1-fa-clamp` carries the change.

## 2026-04-30 (AM) — Built P104 (FA max_seqlen_k clamp) + P101 anchor fix (superseded by PM update)

Codex agent (5h session) built and shipped two Genesis contributions on local branch `club-3090-cliff1-prep`:

**P104 (new)** — FA max_seqlen_k runtime clamp. Env-gated `GENESIS_ENABLE_FA_MAX_SEQLEN_CLAMP=1`, runtime-only (skips under cudagraph capture), never under-clamps below `max(cu_seqlens_k diff)`. Closes Cliff 1 mechanism A (FA2 softmax_lse cap-leak) wherever FA2 dominates. ~260 lines, follows Genesis text-patch infrastructure exactly. PR-ready for Sandermage's repo.

**P101 anchor drift fix** — discovered P101 was silently no-op'd on vLLM dev205+. Upstream replaced `_arange_cache[...]` slicing with inline `torch.arange(...)`; P101's text-replace anchor still expected the old form. apply_all reported "applied" misleadingly while file content was unchanged. Anyone running Genesis v7.62.x with `GENESIS_ENABLE_P101=1` on dev205+ has been getting a no-op. Fix updates anchor to match new upstream form. Opened as [Sandermage PR #12](https://github.com/Sandermage/genesis-vllm-patches/pull/12).

**Empirical findings at this stage (later corrected — see PM update above):** with the partial stack we observed identical 138 MiB / 130 MiB OOM at 205K and 175K and concluded the cliff was architectural. The PM session showed PN12 wasn't actually applying; once repaired, the cliff closes at 205K.

## 2026-04-29 (PM) — Cliff 1 dual-mechanism discovery (P101+P103 cross-rig test)

While preparing to write our own Cliff 1 fix, discovered Sandermage already has **P101** (TQ continuation 64-token slicing, vllm#41123 selective backport) and **P103** (FLA Cliff 2 chunked fwd_h+fwd_o orchestrator) in Genesis tree — both opt-in, default-OFF, and we'd never enabled either. Tested them on long-vision/long-text on RTX 3090.

**Result:** P101 + P103 don't fully close Cliff 1 — they reroute around one mechanism but expose another. Cliff 1 has TWO mechanisms:
1. **FA2 softmax_lse** (cap-leak, what ChatGPT/DeepSeek pointed at) — fires when continuation prefill goes through FA2 path
2. **FFN intermediate buffer** (`max_num_batched_tokens × intermediate_size = 4128 × 17408 × 2 bytes = 138 MiB`) — fires when activation budget is tight, regardless of whether FA2 is on the path

P101 reroutes around mechanism 1 (continuation prefill → TQ decode kernel) but exposes mechanism 2. The dominant cliff under tight budget is whichever has the larger allocation. Vision tower's ~500 MiB pressure is the swing factor.

Posted findings to [Sandermage/genesis-vllm-patches#11](https://github.com/Sandermage/genesis-vllm-patches/issues/11#issuecomment-4348299741) — the FA2 clamp ask remains valuable for tools-text/long-text-no-vision but won't fully unlock long-vision (FFN buffer mechanism). Updated [CLIFFS.md](docs/CLIFFS.md) with the dual-mechanism diagnosis. Default 48K + tools-text 75K stay correct; no shipped config changes.

## 2026-04-29 — Add `docs/CLIFFS.md` — full prefill-cliff synopsis

Single comprehensive document consolidating everything we know about Cliff 1 and Cliff 2: TL;DR table, empirical bisection (with stack traces), root-cause walk-through (FA2 `softmax_lse` cap-leak for Cliff 1, fla.ops GDN intermediate buffer for Cliff 2), why earlier "FFN intermediate buffer" framing was wrong, why mem-util doesn't help (coupling with max-ctx), why PN8 closes Cliff 1 on `tools-text.yml` but not on TQ3 paths, why llama.cpp dodges both structurally, alternative attention backends evaluated, who-can-fix-it landscape with timelines, what we could do at any difficulty level (trivial → out of scope), recommended path forward, and re-test triggers. Cross-linked from FAQ and README. Replaces scattered cliff explanations with one canonical reference.

## 2026-04-29 — Cliff 1 root cause REVISED (FA2 softmax_lse pre-allocation, not FFN buffer)

Bisected long-vision config space (192K / 128K / 96K / 86K @ 0.98 and 0.92 mem-util) to find Cliff-1-safe ceiling. Surprising result: **at fixed mem-util, lowering max-ctx changes nothing** because vLLM allocates the maximum KV pool the budget allows regardless of max-ctx (max-ctx only caps single-seq depth). And at fixed max-ctx, lowering mem-util forces the engine ceiling down too (the two knobs are coupled).

Bisected with second-opinion synthesis from ChatGPT + DeepSeek + manual vLLM source review:

**Real root cause of Cliff 1:** `softmax_lse` in FlashAttention 2's varlen kernel is allocated as `[num_seqs, num_heads, max_seqlen]` — sized by the `max_seqlen` *parameter*, not the actual `cu_seqlens`. vLLM passes `attn_metadata.max_seq_len`, which during cudagraph capture gets set to `max_model_len`. So a 25K-token tool prefill at `max-model-len=192K` allocates softmax_lse for 192K, eating activation headroom. The 50–138 MiB OOM allocations we'd been observing are downstream of this leak. Empirical OOM site: `_vllm_fa2_C.varlen_fwd` in `flash_attn_varlen_func`. Upstream root cause: [Dao-AILab/flash-attention#1011](https://github.com/Dao-AILab/flash-attention/issues/1011) (open since 2024). vLLM cap-leak path: [vllm#40961](https://github.com/vllm-project/vllm/pull/40961).

Earlier characterization as "FFN intermediate buffer at 138 MiB" was wrong — empirical site is FA2 not the FFN. Updated `docs/FAQ.md` "What's a prefill cliff?" entry, `docs/SINGLE_CARD.md` "Cliff 1 still fires" caveat, `docs/UPSTREAM.md` (added FA2 #1011 row, vllm#40961, vllm#40069 tracker, noted vllm#25543 removed `max_seq_len_to_capture` so the commonly-suggested mitigation doesn't apply on V1 nightly), and the `qwen36_27b_prefill_cliffs.md` memory entry.

**Practical implication: no new variant ships.** The current default (48K + 0.92 + TQ3 + vision) stays the prefill-safe ceiling at this stack class — pushing higher requires the upstream fix at FA repo, not config tuning. `tools-text.yml` (75K + FP8 + PN8 closes Cliff 1) remains the IDE-agent path.

## 2026-04-29 — Verified Sandermage's 256K single-prompt claim on dual.yml

Cross-rig verification of [Sandermage's 2026-04-29 claim](https://github.com/noonghunna/qwen36-27b-single-3090/issues/1#issuecomment-4342925976) that 256K single-prompt prefill works on `dual.yml`-class TP=2 setups. He measured 262 104 tokens @ 311s on 2× A5000 (~843 tok/s prefill).

Our run on 2× 3090 (`dual.yml`: 262K + fp8_e5m2 + 0.92 mem-util + 2 streams + max-num-batched-tokens=8192):

| Metric | Value |
|---|---|
| Prompt tokens | 236 939 (~90% of 262K max) |
| Wall time | 284s |
| Prefill throughput | ~834 tok/s |
| Per-card peak VRAM | 23.5 GB / 24 GB |
| finish_reason | stop |
| OOM? | No |

**Conclusion:** Cliff 2 (DeltaNet GDN forward OOM, fires on single-card at 50-60K single prompts) **does NOT fire on dual TP=2** — activation memory splits across cards under tensor parallelism. Same SM 8.6 architecture as A5000, throughput within ~1% of Sandermage's measurement, as expected. UPSTREAM.md + DUAL_CARD.md updated to reflect verified status.

We didn't push to the full 262K (per-card VRAM was already 23.5 GB at 237K, leaving ~500 MiB headroom). Sandermage ran at 0.90 mem-util, we ran at 0.92 — a config tweak would unlock the last 10%.

## 2026-04-29 — Add `docs/UPSTREAM.md` + `AGENTS.md` (consolidate upstream tracking)

- **`docs/UPSTREAM.md`** (new) — single source of truth for every upstream issue / PR we depend on, have filed, or use as workaround context. Categorized by upstream (vLLM, Genesis, fla-org, FlashQLA, llama.cpp, transformers, SGLang). Status emoji per row (🟢/🔵/🟡/🟠/🔴/⚫/✅/❌) + what-it-unblocks + local workaround. Replaces scattered cross-references in CHANGELOG / INTERNALS / FAQ / per-compose comment headers.
- **`AGENTS.md`** (new, repo root) — concise AI-coding-agent guidance. Includes the rule "before filing or referencing an upstream issue, check + update `docs/UPSTREAM.md`" so the tracker stays the canonical place. Also captures the Genesis-opt-in vetting rule from today's P68/P69 bisection (behavioral mitigations need streaming + large-prompt repro before shipping default-on).
- Cross-links from `README.md`, `CONTRIBUTING.md`, and `models/qwen3.6-27b/INTERNALS.md` "See also" sections updated to point at both new files.
- Convention going forward: file an upstream issue → add row to `UPSTREAM.md` → cross-link from any code/doc that depends on the workaround → update the row when status changes (don't delete; mark ✅/❌ for historical context).

## 2026-04-29 — Remove `fast-chat.yml` + extend P68/P69 disable to all Genesis-loading composes

- **`docker-compose.fast-chat.yml`** — deleted. Post-PN8, `fast-chat.yml` (20K, fp8, vision) and `docker-compose.yml` (48K, TQ3, vision) had effectively the same TPS (52/67 vs 50/67), so fast-chat's only remaining differentiator was "smaller context = ~3s faster boot." Not worth a maintained variant when 20K is also actively bad for IDE-agent users (Copilot Gateway tool-schema preamble alone hits 20K).
- **P68/P69 disable extended to every Genesis-loading compose** — `docker-compose.yml`, `long-vision.yml`, `long-text.yml`, `dual-turbo.yml` all had P68 + P69 enabled and would hit the same silent-stop bug on long agent prompts. Now disabled across the board with consistent inline comments. P64 and PN8 (where appropriate) stay enabled — they're targeted bugfixes, not behavioral overrides.
- `scripts/switch.sh` — dropped `vllm/fast-chat` from the variant map.
- `scripts/launch.sh` — wizard's vLLM workload list shortened from 6 → 5 entries.
- `docs/SINGLE_CARD.md`, `docs/FAQ.md`, `docs/engines/VLLM.md`, model README, vllm/README, patches/README, all sibling compose YAML "see also" tables — references removed or updated to point to `docker-compose.yml` (default) or `tools-text.yml` instead.
- Old CHANGELOG entries that mention `fast-chat.yml` are kept as-is (append-only history).

## 2026-04-29 — Disable Genesis P68/P69 in shipped composes (silent-stop bugfix)

- **`tools-text.yml`** + **`fast-chat.yml`** — `GENESIS_ENABLE_P68_AUTO_FORCE_TOOL` and `GENESIS_ENABLE_P69_LONG_CTX_TOOL_REMINDER` are now commented out (default-off). Caused silent finish_reason=stop with empty content + no tool_calls on greetings and clarifying questions when the prompt exceeded 8000 chars (the patches' threshold). Affected every realistic IDE-agent setup (Cline, Cursor, OpenCode, Copilot Gateway).
- **Bisected via cross-rig data on club-3090 issue #2** (HoodOG1 + tenitram). State A (all 4 env vars on) reproduced the silent stop. State B (P68 off, P69 on) still broken — model loops on "I cannot respond with plain text" then stops mid-reasoning. State D (both P68 and P69 off) — clean: greeting → "Hello! How can I help you today?", tool request → clean `read_file` call.
- **P64 and PN8 stay enabled** — both are real targeted bugfixes (P64 = qwen3coder MTP streaming early-return fix from kotori-yan vllm#39598 backport; PN8 = FP8+MTP draft online-quant memory savings, vllm#40849 backport). Neither overrides user intent.
- Mechanism: `vllm/_genesis/middleware/long_ctx_tool_adherence.py:227` — P68 silently sets `request.tool_choice = "required"` when prompt > 8000 chars; P69 appends "must use a tool" text to the user message. Either alone makes "hi there" + tools fail. Together they're worse.
- Threshold of 8000 chars is too low for IDE agents (typical context: 20-50K). We may file an upstream issue with Sandermage suggesting either raising the default or making opt-in+threshold mandatory-explicit.

## 2026-04-29 — UX polish: pre-flight checks + cards-first wizard + PNG embeds + per-page chart split

- **`scripts/preflight.sh`** (new) — sourceable library of `preflight_docker`, `preflight_gpu [min]`, `preflight_disk <path> <gb>`, `preflight_gpu_idle`, `preflight_running`. Each prints actionable `Fix:` hints on failure rather than a cryptic mid-run crash.
- **`scripts/setup.sh`** — runs pre-flight before any work: docker present, GPU detected, ≥25 GB free at `MODEL_DIR` (override via `PREFLIGHT_DISK_GB`). Catches the most common first-run footguns (no docker, no nvidia driver, full disk).
- **`scripts/launch.sh`** — runs pre-flight, plus inverts the wizard: now asks **cards → workload → auto-pick engine** instead of engine-first. New users can answer "how many GPUs do I have" and "what do I want to do" but rarely "vLLM or llama.cpp" — the engine falls out of the workload pick, with a one-paragraph explanation of why we chose it. `--engine vllm|llamacpp` overrides still work; `--no-preflight` skips the checks.
- **Embedded charts switched from SVG → PNG** in markdown (`README.md`, `docs/SINGLE_CARD.md`, `docs/DUAL_CARD.md`, `models/qwen3.6-27b/README.md`). Clicking an SVG on GitHub opens the raw XML; clicking a PNG opens a normal viewable image. Both files (.svg + .png at retina resolution) ship in the repo — SVG remains the editable source, PNG is what the docs link to. Convention: re-export PNG when SVG changes.
- **Charts split per GPU-count page.** SINGLE_CARD.md and DUAL_CARD.md now embed scoped charts (only their card count), instead of the combined diagrams which show both halves. Top-level README.md and the model README still show the combined views. New files in `docs/img/`: `performance-single.{svg,png}` (6 single configs), `performance-dual.{svg,png}` (4 dual configs), `vram-budget-single.{svg,png}`, `vram-budget-combined.{svg,png}` (renamed from `vram-budget-dual` which was actually combined). The `vram-budget-dual.{svg,png}` filename is reclaimed for genuinely-dual content.
- **`tools/charts/gen-perf.py`** + **`tools/charts/gen-vram.py`** (new) — matplotlib source for all chart files, idempotent re-generation. Run `python3 tools/charts/gen-perf.py` and `python3 tools/charts/gen-vram.py` after editing data. Use uv to bring matplotlib (`uv run --with matplotlib --with numpy python3 ...`).

## 2026-04-29 — Genesis bumped to v7.62.x + PN8 enabled on FP8 paths

- **`scripts/setup.sh`** — `GENESIS_PIN` bumped from `bf667c7` (v7.54) → `917519b` (v7.62.x release, 2026-04-29). Includes Sandermage's PN8 (MTP draft online-quant propagation, backport of vllm#40849), PN11 (Quentin-M streaming tool-call IndexError fix vllm#41142), per-GPU profile auto-recommendations, and TurboQuant k8v4 unlocked on hybrid GDN via P4+P98.
- **PN8 enabled on FP8 paths only** (`single/tools-text.yml` + `docker-compose.fast-chat.yml`). Cross-rig validation on 3090 measured ~800-900 MiB freed at boot, **Cliff 1 closes on `tools-text.yml`** (25K-token tool prefill no longer OOMs). TPS cost is real but small (~−5% narr / −7% code).
- **PN8 deliberately NOT enabled** on TQ3 paths (`docker-compose.yml` default 48K, `long-vision.yml`, `long-text.yml`). Tested 2026-04-29:
  - Default 48K + 0.92: PN8 is no-op (KV pool unchanged, plenty of activation headroom already)
  - long-vision 192K + 0.98: PN8 grows KV pool by 230 MiB and lifts engine ceiling 192K → 198K, but does NOT close Cliff 1 (the 138 MiB allocate is an FFN intermediate-buffer activation peak, not draft-model footprint)
  - long-text 205K + 0.98: PN8 has no effect (engine ceiling at 206K is gated by attention-block-size divisor, not KV)
- **PN8 not applied on dual-card configs** — `dual.yml` is intentionally Genesis-less (per its header), and adding Genesis structurally for one patch isn't worth it given dual.yml has no current cliff to close.
- Cross-rig data shared with Sandermage on [single-3090 #1](https://github.com/noonghunna/qwen36-27b-single-3090/issues/1#issuecomment-4343317153).

## 2026-04-28 (post-launch) — wizard + switcher + health + examples + FAQ + VRAM diagram + Kaitchup citation

Polish pass after the launch tweet went live. All click-through paths now lead somewhere useful instead of "find the right yml file":

- **`scripts/launch.sh`** — interactive wizard. Asks engine → cards → workload, maps to variant, calls switch.sh, runs verify-full. Also accepts `--variant <name>` to skip the wizard, or partial flags (`--engine vllm --cards 1`) and prompts for the rest.
- **`scripts/switch.sh`** — stateless variant switcher. `--list` shows all 13 variants; `<variant>` brings down whatever's running (auto-discovers via docker labels) and brings up the new one, waits for `/v1/models`. `--down` stops without booting.
- **`scripts/health.sh`** — operational health probe. Different lens from verify-full: probes runtime state (KV cache %, recent MTP AL, recent gen TPS, container uptime, VRAM bars, last 5 errors). `--watch` refreshes every 5s. Auto-detects vLLM vs llama.cpp from `/v1/models` response.
- **`docs/EXAMPLES.md`** — one-stop client reference: curl sanity test, Python via openai SDK (chat / streaming / tool calls / vision / reasoning mode), Python via raw `requests` (no SDK), TypeScript / Node, plus connection settings for Open WebUI / Cline / Cursor / LiteLLM. Calls out the Cliff-1 risk for tool-using IDE clients.
- **`docs/FAQ.md`** — ~22 common questions absorbing repeat issue-tracker traffic: 4090/5090 support, NVLink, AMD/Intel/Apple, why both engines, why not Ollama/LM Studio, why MTP not EAGLE, why not GGUF on vLLM, why AutoRound, TPS expectations, what cliffs are, what `vllm#40914` will fix.
- **`docs/img/vram-budget-dual.svg`** + **`.png`** — per-card VRAM allocation diagram across 7 configs (3 single-card, 4 dual-card). Embedded in `models/qwen3.6-27b/README.md` after the variant tables. Visualizes the TP=2 unlock — each card holds half the weights and half the KV, which is why 262K + vision + 2 streams fits on dual but not single.
- **`models/qwen3.6-27b/llama-cpp/README.md`** — quant table marks UD-Q3_K_XL ⭐ as our default with citation to Benjamin Marie's [Kaitchup eval](https://kaitchup.substack.com/p/summary-of-qwen36-gguf-evals-updating). Independent third-party validation of the quant pick (their H100 sweep, our 3090 speed lens — complementary).
- **README** — TL;DR rewritten to lead with the two-routes frame (vLLM dual = max TPS, llama.cpp single = max robustness). Quick-start replaces "cd into compose dir + docker compose up" with `bash scripts/launch.sh`.

## 2026-04-28 — Genesis pin + .env.example + issue templates + perf chart + llama.cpp compose

- **`scripts/setup.sh`** — `GENESIS_PIN` switched from tag `v7.51-stable-2026-04-27` to commit `bf667c7` (Genesis HEAD as of 2026-04-27, semver "v7.54"). This is the exact tree our published TPS numbers were measured against; pinning to commit removes the doc-vs-runtime mismatch.
- **`.env.example`** added at repo root — documents `MODEL_DIR`, `HF_TOKEN`, `CUDA_VISIBLE_DEVICES`, `MEM_UTIL`, `MAX_MODEL_LEN`, `GENESIS_PIN`, `SKIP_GENESIS`, `URL`, `WARMUPS`, `RUNS` with defaults.
- **`.github/ISSUE_TEMPLATE/`** — bug-report template (requires `docker logs --tail 100`, `verify-full.sh` output, `nvidia-smi`, GPU config, compose variant, repo commit) + numbers-from-your-rig template (structured cross-rig TPS contributions). Q&A redirected to GitHub Discussions via `config.yml`.
- **`docs/img/performance.svg`** + **`docs/img/performance.png`** — TPS bar chart across 10 single + dual configs, embedded in top-level README.
- **`models/qwen3.6-27b/llama-cpp/compose/`** — two new docker compose files using `ghcr.io/ggml-org/llama.cpp:server-cuda`:
  - `docker-compose.yml` — single slot, 262K ctx, q4_0 KV, vision on (showcase)
  - `single/concurrent.yml` — 4 parallel slots, 192K ctx pool, vision on
- **First measured TPS for UD-Q3_K_XL on this stack:** 21.22 narr / 20.79 code @ 262K + vision (single 3090, q4_0 KV). Lower than 2026-04-23's 28.5 measurement on Q4_K_M — investigating mainline llama.cpp regression between commits `9ab47e7d8` and current `0d0764dfd`. ngram-mod path measured at 22.04 / 26.11 (+25% on code).

## 2026-04-28 — Repo created (consolidating + superseding old single + dual repos)

`club-3090` was created to replace two predecessor repos:

- `noonghunna/qwen36-27b-single-3090` — single-card Qwen3.6-27B recipe
- `noonghunna/qwen36-dual-3090` — dual-card Qwen3.6-27B recipe

Reasons for consolidation:
- **Engine-first organization** — most users decide "vLLM or llama.cpp" before "1 card or 2"; the new structure reflects that.
- **Model-agnostic scaffolding** — when we add Qwen3.5-27B / GLM-4.6 / Llama-3.x quants in the future, they slot into `models/<name>/` without restructuring.
- **Single source of truth** — one issue tracker, one Twitter/Reddit/HN URL, no confusion about where to file or read.

**Old repos** remain readable (not deleted, not archived yet) for:
- Existing issue threads that are still active (e.g., the prefill-OOM investigation in single-3090 #1)
- External links from Medium articles, Reddit posts, Twitter
- Historical context for users who landed there via search

The old repo READMEs now have prominent "moved to" banners pointing here. New issues should be filed against `noonghunna/club-3090`.

## See also

- `models/qwen3.6-27b/CHANGELOG.md` — model-specific history (was previously split across two repos; now in one timeline)
- Engine version pins are tracked in the per-engine compose / recipe files. Bumping a pinned vLLM nightly is a per-model change documented in the model's CHANGELOG.
