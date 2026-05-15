# Changelog

Auto-generated from commit subjects by [git-cliff](https://git-cliff.org/) on tag
push. Click any commit SHA below to see the full message body (why / how /
validation data) — those live in `git log`, not here. Don't hand-edit; the file
is regenerated on every tag.

**Versioning:** SemVer in `0.x` — treat any minor bump as potentially breaking
until `1.0`. Past CalVer tags (`v2026.05.09`, `v2026.05.10`) are preserved for
history; SemVer takes over from `v0.3.0` onward.

| CalVer tag | SemVer equivalent | Date |
|---|---|---|
| `v2026.05.09` | (≈ v0.1.0) | 2026-05-09 — first tagged release |
| `v2026.05.10` | (≈ v0.2.0) | 2026-05-10 — stack reorg + Gemma 4 INT8 PTH unblock |

---

## v0.7.3 — 2026-05-15


### ✨ Features

- feat(report): surface kv-calc calibration verdict ([#143](https://github.com/noonghunna/club-3090/pull/143) by @noonghunna)
- feat(kv-calc): model v0.7.3 MoE architectures ([39e1873](https://github.com/noonghunna/club-3090/commit/39e18733aa8f14c83a1f76d5bed23156fda61568))
- feat(gemma-4-26b-a4b): AWQ + MTP n=4 — +12% narr / +49% code over no-MTP baseline ([6dc9a0d](https://github.com/noonghunna/club-3090/commit/6dc9a0dce1b4ecef787e50808a8a15439cabe209))
- feat(qwen-35b-a3b): preview-MTP compose + bench row — MTP measured SLOWER on MoE ([e1d44bd](https://github.com/noonghunna/club-3090/commit/e1d44bd732cef0757b8d3f0f872b5b0a1a4fe5cc))
- feat(vllm-pr41800): vendor truncate_prompt_tokens overlay across all pre-fix engines (closes #139) ([1d7aad1](https://github.com/noonghunna/club-3090/commit/1d7aad112c097709d954750ab0e725a785ad062a))
- feat(gemma-4-26b-a4b): AWQ path via vLLM PR #40886 overlay ([0053444](https://github.com/noonghunna/club-3090/commit/0053444e84f80ce9f3fb910435c8d627591f59ed))
- feat(estate): add parallel boot mode ([99328b4](https://github.com/noonghunna/club-3090/commit/99328b4cda7ec9efc723a001295525a6d1f86e2a))
- feat(moe): add dual-card composes for Gemma 26B-A4B + Qwen 35B-A3B preview ([2d1b1dc](https://github.com/noonghunna/club-3090/commit/2d1b1dc347c3897f8b902f7ab60c8bd9c97abbeb))
- feat(moe): wire Gemma 4 26B-A4B + Qwen 3.6 35B-A3B composes through fits() ([f7f6f44](https://github.com/noonghunna/club-3090/commit/f7f6f444b9e937396c3de70df7dd6a5b957be80b))
- feat(profiles): split engine-pin policy by Genesis dependency ([15eda8a](https://github.com/noonghunna/club-3090/commit/15eda8a823dd273ee9b238369cba365021b61a29))
- feat(profiles): add Gemma 4 26B-A4B ModelProfile + num_global_kv_heads field ([abf0e32](https://github.com/noonghunna/club-3090/commit/abf0e327f9b877f989fe16c88bda1a457c144e0a))
- feat(profiles): add Qwen 3.6 35B-A3B ModelProfile (MoE schema extensions) ([9378714](https://github.com/noonghunna/club-3090/commit/937871492ae08b58b041a1fded41ab793f0c8549))


### 🐛 Bug fixes

- fix(gpu-mode): mode_off tears down estate-managed instances ([9cd854d](https://github.com/noonghunna/club-3090/commit/9cd854dbcb9b8b215876e0f88443c269072b93b9))
- fix(qwen3.6-27b): route non-TQ3 composes to vllm-nightly-clean ([3b2d940](https://github.com/noonghunna/club-3090/commit/3b2d940d26ec2ffe6daf631e77986898c1d2849d))
- fix(gemma-4-31b): route default/bf16 composes to vllm-nightly-clean ([cf0451a](https://github.com/noonghunna/club-3090/commit/cf0451a7ad5c56bd7b63327aac7178df70cba1fb))
- fix(engines): vllm-nightly-mtp anchors to 01d4d1ad (Sander v7.72.2 PROD pin) ([87f0a0c](https://github.com/noonghunna/club-3090/commit/87f0a0c528473a225f06997bdcb9b79fefa13b04))


### 📝 Documentation

- docs(soak-test): clarify PASS verdict semantics — closes #140 ([9a039d8](https://github.com/noonghunna/club-3090/commit/9a039d8c922d3141102e8244d5468e8de46c6674))
- docs(UPSTREAM): add PR #41800 truncate_prompt_tokens row ([273c017](https://github.com/noonghunna/club-3090/commit/273c017646087fe508626be7ecea5e2106be54be))
- docs(README): add v0.7.3 MoE models to Supported Models table ([e49c939](https://github.com/noonghunna/club-3090/commit/e49c9397481b5fba226323b59c4fa37bdc2aeeab))
- docs(BENCHMARKS): Gemma 4 26B-A4B AWQ first row + AutoRound row demoted ([92b69bd](https://github.com/noonghunna/club-3090/commit/92b69bd220ce8360d2dfd5fdcf89d26ee2264791))
- docs(BENCHMARKS): add v0.7.3 MoE preview section ([bdfb939](https://github.com/noonghunna/club-3090/commit/bdfb939edd98c3872439a7a05dcde13cce7ccaa2))
- docs(HARDWARE): add note on PCIe Gen 3 + older CPU TP=2 headwind ([8cf38b0](https://github.com/noonghunna/club-3090/commit/8cf38b05906e3954405af3db09a822ac87a25ae5))
- docs(KERNEL_MATRIX): add KV Cache Impact subsection ([1a233cd](https://github.com/noonghunna/club-3090/commit/1a233cd9fd05a6ec51adfadae79813bc80cea4b0))
- docs: add KERNEL_MATRIX.md (attention backend + engine support matrix) ([97195fe](https://github.com/noonghunna/club-3090/commit/97195fe443770bc8adc883755fd3baf9933df874))
- docs(kv-math): extend k_v_tensors=N notation to sliding-KV formulas ([b1c68b4](https://github.com/noonghunna/club-3090/commit/b1c68b4fe3211af3442cd3bb7e9fd011e30e5554))
- docs(kv-math): tighten k_v_tensors notation across all 4 formulas ([54d8bf0](https://github.com/noonghunna/club-3090/commit/54d8bf0b3e2b322dbd67e6939ff9f9995c642437))
- docs(kv-math): third-pass Grok polish ([67de3ec](https://github.com/noonghunna/club-3090/commit/67de3eca3eb4b75b43fd0f83d2ed304976b3f1b5))
- docs(kv-math): second-pass Grok polish ([78f94ca](https://github.com/noonghunna/club-3090/commit/78f94cacf006064f68d945122907d30be8723eec))
- docs(kv-math): address Grok review feedback ([3114399](https://github.com/noonghunna/club-3090/commit/31143999837639b5a7d492d2f2b64e164787bcfe))
- docs(kv-math): config-verify Qwen 35B-A3B + Gemma 26B-A4B MoE sections ([6ec6a67](https://github.com/noonghunna/club-3090/commit/6ec6a6761f36cca44ea819434be7205bcb6fdbc6))


### 🧹 Maintenance

- test(launch): align engine pin expectations ([127f4f6](https://github.com/noonghunna/club-3090/commit/127f4f6d8fe104a954b7865a4d7550017a1c629b))



[Pin: `git checkout v0.7.3`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.7.2...v0.7.3)
## v0.7.2 — 2026-05-15


### ✨ Features

- feat(launch): add hardware topology advisor ([d116ba9](https://github.com/noonghunna/club-3090/commit/d116ba9ba3442482e0005bab9067d304b40e5e24))



[Pin: `git checkout v0.7.2`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.7.1...v0.7.2)
## v0.7.1 — 2026-05-15


### ✨ Features

- feat(bench): surface prompt processing throughput ([2a148d7](https://github.com/noonghunna/club-3090/commit/2a148d702b9415129d4c4ec9d3e7d30765927aa4))
- feat(llamacpp): expose batch tuning knobs ([02249ab](https://github.com/noonghunna/club-3090/commit/02249ab1939f354ac062d343efefe32677203174))


### 🐛 Bug fixes

- fix(ci): simplify vllm image workflow, drop smoke-gate (#135) ([ce2617e](https://github.com/noonghunna/club-3090/commit/ce2617e0bc0f56d42caf64e96847d966380be80c))


### 📝 Documentation

- docs(upstream): PR #42102 closed-as-slop; local overlay permanent ([57eb269](https://github.com/noonghunna/club-3090/commit/57eb269cd70935fc3069b85e46ead8f0f0af13dc))



[Pin: `git checkout v0.7.1`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.7.0...v0.7.1)
## v0.7.0 — 2026-05-14


### ✨ Features

- feat(scripts): add diagnose-profile triage ([c2adb39](https://github.com/noonghunna/club-3090/commit/c2adb3970dbdcb3bf227cfc7a1ac58a2de3930a4))
- feat(compose): use profile-sourced vllm image pins ([e6e33ab](https://github.com/noonghunna/club-3090/commit/e6e33ab37235cdfa2d47987e16e00d617564e55d))
- feat(launch): export profile vllm pins ([c306383](https://github.com/noonghunna/club-3090/commit/c3063838bfde3f7811db3edbb9541814aea8f09d))
- feat(profiles): resolve vllm nightly pins ([40f1ef7](https://github.com/noonghunna/club-3090/commit/40f1ef78f8e3ab80a5424ce196c7715df85a0d1a))
- feat(launch): add estate planner orchestration ([c9b153f](https://github.com/noonghunna/club-3090/commit/c9b153f91f3dd4a076395008ad3bfecdd226a452))
- feat(launch): validate single-model profiles ([a142b1c](https://github.com/noonghunna/club-3090/commit/a142b1ce1085c78e8752fa52718af66f7a49f237))
- feat(compat): add profile validator and estate self-test ([6581ccc](https://github.com/noonghunna/club-3090/commit/6581ccca9e8613594dba876ba2472e78d48c9eed))
- feat(compose): accept ESTATE_GPUS and ESTATE_PORT overrides ([a57596e](https://github.com/noonghunna/club-3090/commit/a57596e0764babc6fe91e96af8b6dd746da45e09))
- feat(profiles): ship v0.7.0 data layer ([69825d7](https://github.com/noonghunna/club-3090/commit/69825d7dae0fe1387a04879b31e0d225143b3684))


### 🐛 Bug fixes

- fix(tools): resolve profile image pins in audit ([98535dc](https://github.com/noonghunna/club-3090/commit/98535dc81453e54be03a1f5915bb2367ebab5c27))
- fix(tools): bump engine nightly profiles ([d1acde0](https://github.com/noonghunna/club-3090/commit/d1acde0b28eccb123338d2a9d94e4ef6ff75cc4b))
- fix(ci): keep vllm base arg in image metadata ([1abe65f](https://github.com/noonghunna/club-3090/commit/1abe65fe2810be594d6890ce0f26a3f0a554075f))
- fix(launch): persist estate source of truth ([52e4347](https://github.com/noonghunna/club-3090/commit/52e43470c6ee111dfa97be81e13e229ede715073))


### 📝 Documentation

- docs: document profile-sourced vllm pins ([86445be](https://github.com/noonghunna/club-3090/commit/86445be3e8c24ad829d45c4f1702a0bccf27e4dc))
- docs: document club vllm image pin ([2ae8303](https://github.com/noonghunna/club-3090/commit/2ae8303833497f20d4079a12226ca23c83f71337))
- docs: expand KV_MATH + add ADDING_MODELS workflow ([1f8aaa2](https://github.com/noonghunna/club-3090/commit/1f8aaa2acc72a7cff763fa81ae938d552fffffb2))
- docs(hardware): clarify 3090 stock TDP varies by board SKU ([0d59f94](https://github.com/noonghunna/club-3090/commit/0d59f949e472095e3ecb83ce133eb103d10588d9))


### 🧹 Maintenance

- chore(vllm): use club3090 image in composes ([aebc4f3](https://github.com/noonghunna/club-3090/commit/aebc4f321c3536943bfbd554d2c21ed6824742f9))
- chore(ci): build club vllm image ([e88a2a8](https://github.com/noonghunna/club-3090/commit/e88a2a8d21efd3556739fcb0fb1a26327b7d38cd))
- refactor(kv-calc): consume profile data ([9ccde62](https://github.com/noonghunna/club-3090/commit/9ccde62abe360bfb9170fc88102623dc5e87597e))


### 🧹 Other

- Revert "chore(vllm): use club3090 image in composes" ([c7c40bd](https://github.com/noonghunna/club-3090/commit/c7c40bdf1232ec2a2f8e5b1d98249df33026f46b))



[Pin: `git checkout v0.7.0`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.6.3...v0.7.0)
## v0.6.3 — 2026-05-14


### ✨ Features

- feat: unify dual-card composes with NVLink auto-detection ([e00626a](https://github.com/noonghunna/club-3090/commit/e00626a50e92fe44855c410b86ae3f33ace82f29))


### 🐛 Bug fixes

- fix(scripts): report.sh shows human-readable version via git describe ([0f0a9c8](https://github.com/noonghunna/club-3090/commit/0f0a9c84c513392d889dbf51d05c5edb1f4ba649))


### 📝 Documentation

- docs: cross-rig data — eddie 3090/3090Ti power-cap + alanspires 6×3090 VFIO ([e41323f](https://github.com/noonghunna/club-3090/commit/e41323ffa9c471c6f4d9b771bbb94ff784235342))


### 🧹 Other

- Merge PR #128: unify dual-card composes with NVLink auto-detection ([#128](https://github.com/noonghunna/club-3090/pull/128) by @noonghunna)



[Pin: `git checkout v0.6.3`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.6.2...v0.6.3)
## v0.6.2 — 2026-05-14


### 🐛 Bug fixes

- fix(launch): project TP greater than four ([98f0406](https://github.com/noonghunna/club-3090/commit/98f0406d0f265767b4a6712a1eba293b1e2dc889))



[Pin: `git checkout v0.6.2`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.6.1...v0.6.2)
## v0.6.1 — 2026-05-14


### ✨ Features

- feat(launch): add hardware-aware launcher ([5882bbe](https://github.com/noonghunna/club-3090/commit/5882bbef6f5ed7e8ceea450fa3a6b167a1bf4926))
- feat(tools): extend kv-calc.py to multi-model (Qwen 3.6 + Gemma 4 31B) ([0d48dac](https://github.com/noonghunna/club-3090/commit/0d48dac818ba889f74b74df1c454bb961a123c37))


### 📝 Documentation

- docs: update launch.sh references for v0.6.1 wizard flow ([e299e70](https://github.com/noonghunna/club-3090/commit/e299e70451c8d146214a6560e582d0e174dd0ebc))


### 🧹 Other

- Merge codex/v0.6.1-launch into master ([056dcb6](https://github.com/noonghunna/club-3090/commit/056dcb643914fee6169b02b89cb420b038c29b0f))



[Pin: `git checkout v0.6.1`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.6.0...v0.6.1)
## v0.6.0 — 2026-05-13


### ✨ Features

- feat(scripts): add hardware-aware setup picker ([12a33fb](https://github.com/noonghunna/club-3090/commit/12a33fbdd1b6422429521f887d9f21c2e3da793d))


### 🐛 Bug fixes

- fix(launch): exit cleanly on stdin EOF in wizard prompts ([e05f196](https://github.com/noonghunna/club-3090/commit/e05f1969bcf57547a17cd963a1f21435de80815b))



[Pin: `git checkout v0.6.0`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.5.4...v0.6.0)
## v0.5.4 — 2026-05-13


### 🐛 Bug fixes

- fix(scripts): make submit-bench issue-first ([22bf2e9](https://github.com/noonghunna/club-3090/commit/22bf2e9398c7907aae6b62809bde30e111e4a700))



[Pin: `git checkout v0.5.4`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.5.3...v0.5.4)
## v0.5.3 — 2026-05-13


### ✨ Features

- feat(scripts): add submit-bench flow ([ef77032](https://github.com/noonghunna/club-3090/commit/ef770322f43724f612a80393f547e5da218b5bf7))



[Pin: `git checkout v0.5.3`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.5.2...v0.5.3)
## v0.5.2 — 2026-05-13


### 🎯 New models + serving paths

- Add hardware-aware compose preflight ([2698552](https://github.com/noonghunna/club-3090/commit/26985527f75d8da2a32a8a2f985989d5dcf9e89a))



[Pin: `git checkout v0.5.2`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.5.1...v0.5.2)
## v0.5.1 — 2026-05-13


### 🐛 Bug fixes

- fix(qwen): PR #35936 overlay — sidecar pattern to resolve Genesis RO-mount conflict ([6617e1e](https://github.com/noonghunna/club-3090/commit/6617e1e090a6f52708aaf83821a92b612c4ad869))


### 📝 Documentation

- docs: clarify MODEL_DIR — second drive / HF cache / Windows-WSL ([1678ca0](https://github.com/noonghunna/club-3090/commit/1678ca0c8ba43ea09fad9073639a48337f2ff163))
- docs(upstream): correct stale vllm#40807 row + add #40798/#42215 row ([14ffe45](https://github.com/noonghunna/club-3090/commit/14ffe45667fb0aa292839be05ae3ad0d139d3a04))



[Pin: `git checkout v0.5.1`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.5.0...v0.5.1)
## v0.5.0 — 2026-05-12


### ✨ Features

- feat(qwen): ship froggeric chat-template fixes as default-on ([84498d4](https://github.com/noonghunna/club-3090/commit/84498d47aaf7a2fdb7c0203d53bb64414a64b6c1))
- feat(vllm): add PR #35936 required-tool fallback overlay ([28b16b5](https://github.com/noonghunna/club-3090/commit/28b16b5dc9d602a8e1c4b8d5496aa82cbca7f95d))
- feat(qwen-tq3): add CLUB3090_TQ_K1_SKIP_MTP layer-filter for PR #40914 K+1 dispatch ([6b2a7d5](https://github.com/noonghunna/club-3090/commit/6b2a7d553b6164bb4854e80fc0acdf8dcec18a87))


### 🎯 New models + serving paths

- compose(tq3-mtp-genesis): pin to Genesis v7.72.2 known-good vLLM nightly ([570fa71](https://github.com/noonghunna/club-3090/commit/570fa71240a12ab642693c0570851611e933f8c4))


### 📊 Benchmarks + cross-rig data

- bench(matrix): @ygafarov first heterogeneous Ampere + Blackwell eGPU dual ([1770931](https://github.com/noonghunna/club-3090/commit/1770931729a354bad319c8b58bdee143fe6ebce2))


### 📝 Documentation

- docs(dtype-matrix): more polish — RDNA naming, FP8 maturity caveats, AMD detection ([62b3b45](https://github.com/noonghunna/club-3090/commit/62b3b455a9ea5146cbf5576febd0c8b25a8c0fa1))
- docs(dtype-matrix): polish nuances + add Intel and AMD vendor sections ([3d4548c](https://github.com/noonghunna/club-3090/commit/3d4548c50422da07c16fcba2a59d6f42f268355b))
- docs(dtype-matrix): per-arch hardware accelerator matrix for compose optimization ([9c6d3cf](https://github.com/noonghunna/club-3090/commit/9c6d3cfba1de9d9079d6eafc9ff68c352cac7197))
- docs(faq): add 'INT8 PTH doesn't scale at concurrency — is that a bug?' ([df53287](https://github.com/noonghunna/club-3090/commit/df53287b1c26ec83be8a30eec24baf2bddc993eb))
- docs(tq3-mtp): writeup + charts for the Genesis-backed TQ3+MTP path ([c2b1c93](https://github.com/noonghunna/club-3090/commit/c2b1c93872f84fa9afa3bbe41360dc42be28c066))
- docs(qwen-tq3): close round-4 — #40914 not shippable, route to nomtp + Genesis ([9fba037](https://github.com/noonghunna/club-3090/commit/9fba03788e30151f9bf8c85f279260696954d094))
- docs(qwen-tq3): re-tombstone tq3-mtp.yml after round-3 MTP-skip validation ([063d3e9](https://github.com/noonghunna/club-3090/commit/063d3e943ce8da9cc69bd30c68b87426aca6202e))


### 🧹 Maintenance

- refactor(qwen): rename int8-tq3 → tq3-* family + add no-MTP + Genesis variants ([6182922](https://github.com/noonghunna/club-3090/commit/6182922225dfeee1c28084d1ff917bfd25539520))



[Pin: `git checkout v0.5.0`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.4.0...v0.5.0)
## v0.4.0 — 2026-05-11


### ✨ Features

- feat(rebench-report): close 9 gaps — TL;DR + rig + timings + reproducer + delta + discuss variant ([be7f9aa](https://github.com/noonghunna/club-3090/commit/be7f9aa143e9942bbc331e219542b529e4156512))
- feat(rebench): add REPORT.md synthesizer + container/boot/GPU captures ([18355f4](https://github.com/noonghunna/club-3090/commit/18355f41f68699d76dd50452b32d505119f399d0))
- feat(rebench): halve default soak to 10 sessions × 5 turns (~15-20 min) ([3406894](https://github.com/noonghunna/club-3090/commit/340689427f971dc16856b9d069ff32d4c280da28))
- feat(rebench): one-shot canonical 5-step bench orchestrator ([94a2522](https://github.com/noonghunna/club-3090/commit/94a2522417d514674db78c590c4b899bb3eb9d36))


### 🐛 Bug fixes

- fix(switch): GPU memory pre-flight + widen RUNNING_PATTERN ([4866913](https://github.com/noonghunna/club-3090/commit/4866913a10002e8a3e6d2a2df7e6fda07fb1f953))
- fix(rebench-report): parse aider upstream_per_exercise as dict (not list) ([7c4b310](https://github.com/noonghunna/club-3090/commit/7c4b310cca0c62a55a9603cdd31540763e82191a))


### 📊 Benchmarks + cross-rig data

- bench(head-to-head): matched-config rebench + Qwen INT8 PTH KV compose ([755e519](https://github.com/noonghunna/club-3090/commit/755e5199ffd029336000fbfb80dc342e42c8c6d5))


### 📝 Documentation

- docs(gemma-4-31b): document TQ3 Ampere FA2 head_dim wall + vendor #40108 overlay ([f8c7066](https://github.com/noonghunna/club-3090/commit/f8c706699ca8ae9630c7fda58e23a21183241175))
- docs(benchmarks): Qwen 3.6 27B vs Gemma 4 31B head-to-head on dual 3090 ([edda3b3](https://github.com/noonghunna/club-3090/commit/edda3b3ecac7d460b34081e307ffd843a414b83e))


### 🧹 Maintenance

- chore(composes): bump Qwen pins → 1acd67a7, drop obsolete patch_tolist_cudagraph ([16a1374](https://github.com/noonghunna/club-3090/commit/16a1374053f979363fe4634a73ddd9c90db6061c))
- chore(cliff): skip auto-regen bot commits in changelog parser ([a258e49](https://github.com/noonghunna/club-3090/commit/a258e496bf926892c3a33e6f2f5ee2efb87a9d71))



[Pin: `git checkout v0.4.0`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.3.3...v0.4.0)
## v0.3.3 — 2026-05-10


### 🧹 Maintenance

- chore(changelog): subject-only rendering (drop commit body verbosity) ([eeb946b](https://github.com/noonghunna/club-3090/commit/eeb946b0a7b90462a968c800ecceb2e519b0e7fd))



[Pin: `git checkout v0.3.3`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.3.2...v0.3.3)
## v0.3.2 — 2026-05-10


### ✨ Features

- feat(quality-test): auto-set BENCHLOCAL_HERMES_RESOLVE_LOCALHOST=1 for localhost URLs ([83bf73d](https://github.com/noonghunna/club-3090/commit/83bf73d3ec464f6a366c074a3d43f203ff1e3444))


### 🧹 Maintenance

- chore: trigger v0.3.2 release workflow (GitHub deduped previous tag push) ([255c743](https://github.com/noonghunna/club-3090/commit/255c743dff59149ef83a06a4e63b0e74153c61cb))
- chore(changelog): automate CHANGELOG + release notes from commits via cliff (Option A) ([64b0474](https://github.com/noonghunna/club-3090/commit/64b0474a628d5a91222446d90b4974b14ab3237f))



[Pin: `git checkout v0.3.2`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.3.1...v0.3.2)
## v0.3.1 — 2026-05-10


### 🐛 Bug fixes

- fix(soak-helper): capture `delta.reasoning` alongside `delta.reasoning_content` ([88eb67a](https://github.com/noonghunna/club-3090/commit/88eb67aa18263a5706268a06d66784987ec69069))


### 📝 Documentation

- docs(changelog): v0.3.1 entry for soak-helper delta.reasoning capture ([9db8b26](https://github.com/noonghunna/club-3090/commit/9db8b2603ca2e9638b533f76e9fbc1aa7bf936a3))



[Pin: `git checkout v0.3.1`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v0.3.0...v0.3.1)
## v0.3.0 — 2026-05-10


### ✨ Features

- feat(power-cap-sweep): --include-commit flag stamps club-3090 git SHA in report header (closes #112) ([7d91ac7](https://github.com/noonghunna/club-3090/commit/7d91ac75e05eb01c81a30b35d2aa1290d5dc4b7f))
- feat(qwen3.6-27b): thinking OFF by default across all 21 composes ([29d17ed](https://github.com/noonghunna/club-3090/commit/29d17ed82d5a62191e96284f557686c4baa1cea7))
- feat(setup): interactive MODEL_DIR prompt for fresh TTY users ([3909c2d](https://github.com/noonghunna/club-3090/commit/3909c2d6b826d40a382fe3554cfe068a81145657))


### 🐛 Bug fixes

- fix(qwen3.6-27b): use --default-chat-template-kwargs (not --chat-template-kwargs) ([534d29f](https://github.com/noonghunna/club-3090/commit/534d29f1b1da3ff5f34035e01b496db1c565a81b))
- fix: 4 stale refs missed in 2026-05-10 reorg push (caught by RobH589 #116) ([cf7f195](https://github.com/noonghunna/club-3090/commit/cf7f1959fdd002b4c354aa14ec5ae983aa971c9d))


### 📝 Documentation

- docs(benchmarks): aider-polyglot-30 — Qwen 27B 20/30 (66.7%) > Gemma 4 31B 17/30 (56.7%) ([e08988e](https://github.com/noonghunna/club-3090/commit/e08988e6140ea5afc7be46434f0bd1aa0c02096d))
- docs(recipes): use \$MODEL_DIR placeholder + sensible cross-rig default ([cc3a717](https://github.com/noonghunna/club-3090/commit/cc3a7175243abe43f21a1eb69ca0015b5a10f7f8))
- docs: use \$MODEL_DIR placeholder, not the dev rig's /mnt/models/huggingface/ ([fbf3431](https://github.com/noonghunna/club-3090/commit/fbf343129ccc48d242178a0d5b57d6def7d5651d))


### 🧹 Other

- release: SemVer adoption + v0.3.0 changelog entry ([7080f1f](https://github.com/noonghunna/club-3090/commit/7080f1f89b674a0cc5becd361623a0ab6abdd53d))



[Pin: `git checkout v0.3.0`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v2026.05.10...v0.3.0)
## v2026.05.10 — 2026-05-10


### ✨ Features

- feat(gemma-4-31b): INT8 PTH KV unblocks 262K + AWQ + DFlash compose family ([403b16f](https://github.com/noonghunna/club-3090/commit/403b16f303253430bf58b606da7490d8253b7ef7))


### 🎯 New models + serving paths

- compose: parametrize VLLM_ENFORCE_EAGER, KV_CACHE_DTYPE, P40/P82/PN54 across all variants (#110) ([#110](https://github.com/noonghunna/club-3090/pull/110) by @easel)
- composes: refresh Quality lines with --full sandboxed (8-pack) results ([9dea0eb](https://github.com/noonghunna/club-3090/commit/9dea0ebb7beb72845a6264664bf5da1bc5c65b9f))
- composes: add --full Quality lines on Qwen3.6-27B + Gemma 4 31B duals ([26ff0e5](https://github.com/noonghunna/club-3090/commit/26ff0e58643dae75904f4b1ea4705a5fa32007bc))


### 🐛 Bug fixes

- fix: BIND_HOST opt-in + localhost script fixes (#109) ([#109](https://github.com/noonghunna/club-3090/pull/109) by @easel)


### 📝 Documentation

- docs: WSL2 budget formula + Cliff 3 (DeltaNet SSM-state non-cacheable) ([6e12700](https://github.com/noonghunna/club-3090/commit/6e12700f9a91c92c3c28c35d25be798745016ee0))


### 🛠️ Scripts + tooling

- quality-test.sh: --sandboxed-only passthrough ([7020d96](https://github.com/noonghunna/club-3090/commit/7020d965bdbcc1b4d3bfeadd0c85b030488c1dfd))
- quality-test.sh: --help, --pack passthrough, align with benchlocal-cli v0.5 ([1be02d2](https://github.com/noonghunna/club-3090/commit/1be02d22719e78913470e6ee98a17a2b2d46f152))
- ci: replace Release Drafter with git-cliff for commit-based release notes ([7002e6b](https://github.com/noonghunna/club-3090/commit/7002e6b550fe357859e34bb6ff15d1e9ae493de4))


### 🧹 Other

- reorg: services/ consolidation + gpu-mode under git + ComfyUI + pin tracker + path updates ([00366a5](https://github.com/noonghunna/club-3090/commit/00366a58d761ca797581c1411b06c4f6ab98654c))
- encourage-soak: template dropdown + script ergonomics + report reminder + Notes convention ([c298b60](https://github.com/noonghunna/club-3090/commit/c298b60f762309d3829a0ce3a45b17ac3ca9224a))
- BENCHMARKS: add @ygafarov Strix-Halo + oculink-eGPU x4-PCIe single-3090 row (#113) ([a589058](https://github.com/noonghunna/club-3090/commit/a5890587610404d69819512a32290d87deeb5460))



[Pin: `git checkout v2026.05.10`] · [Full diff](https://github.com/noonghunna/club-3090/compare/v2026.05.09...v2026.05.10)
## v2026.05.09 — 2026-05-09


### ⚠️ Cliffs, gotchas, regressions

- Merge v7.69-cliff2-test: ship Cliff 2 closure recipes (Balanced MTP + Max-context) ([15b84df](https://github.com/noonghunna/club-3090/commit/15b84df717d1a7b193946a1cb8de0945d7f2693d))
- v7.69 + #35975 + Codex P103 gate fix — Cliff 2 closure recipes ([f6613c8](https://github.com/noonghunna/club-3090/commit/f6613c869abd6260825cf3fde17956a867316d43))
- docs + charts: v7.66 + Cliff 1 mech B closed across all 4 TQ3 composes ([ae4846f](https://github.com/noonghunna/club-3090/commit/ae4846fd6345ee414b933a6aa272ee1fdf8c3adc))
- PN30 dst-shaped temp fix: close DS conv state regression class on long-text ([9af1a52](https://github.com/noonghunna/club-3090/commit/9af1a5245adf6ac740b9e2baa7ac515379e158f4))
- PN25 v3: close Cliff 1 mech B (club-3090#16) on long-text via setup-time Genesis backport ([a62ad78](https://github.com/noonghunna/club-3090/commit/a62ad78a4e8a7ce62aec4d11ae967382b188df46))
- walk back: Cliff 1 mech B reproduces on real IDE-agent prompts (club-3090#16) ([b62b6b1](https://github.com/noonghunna/club-3090/commit/b62b6b1de46cab098718d6f671b12480d687ab4c))
- Ship verified Cliff 1 closure on long-text 205K + long-vision 192K ([287de1c](https://github.com/noonghunna/club-3090/commit/287de1c6e8f1500dd9144dce9a9b9fbf601d7d67))
- Cliff 1 P104 + P101 anchor fix outcomes (built on cliff1-fa-clamp branch) ([e6570a7](https://github.com/noonghunna/club-3090/commit/e6570a7d1139c6bf61c91569f55a4844971a7ecb))
- Cliff 1 dual-mechanism: P101+P103 cross-rig test reveals FFN buffer cliff ([573a377](https://github.com/noonghunna/club-3090/commit/573a377690a760f7fed29b80b7633b5526af2095))
- Cliff 1 root cause revised: FA2 softmax_lse sized by max_seqlen ([2d6b69d](https://github.com/noonghunna/club-3090/commit/2d6b69dd50eaa4764f12d6c30cc7d91c4355881b))


### ✨ Features

- feat(preflight): compose-dependency + HF_TOKEN + KV-format checks (#37, #47, #219) ([b6c8708](https://github.com/noonghunna/club-3090/commit/b6c870820978fe641771e631700e11e17bf475d2))
- feat(tools): kv-calc.py — predict per-card VRAM budget for Qwen3.6-27B (#226) ([4e89c6a](https://github.com/noonghunna/club-3090/commit/4e89c6aa40856126ab5803159ad69211a03a1a9a))
- feat(bounded-thinking): Phase 3 grammar A/B complete; DeepSeek scratchpad is the new recommended grammar ([b956c85](https://github.com/noonghunna/club-3090/commit/b956c85477f0f4e9dd00e20c0dfc68bc30ad20b4))
- feat(report.sh): --stress + --soak flags, --full now the canonical "everything" pass ([8a29b95](https://github.com/noonghunna/club-3090/commit/8a29b95da10f7ab45151fba866aa526f2a1796c2))
- feat(qwen3.6-27b/vllm): add dual4 + dual4-dflash composes (TP=4, 4×3090, #44) ([#44](https://github.com/noonghunna/club-3090/pull/44) by @Whamp)
- feat(grammar-eval): land harness for Holiday tagline grammar A/B ([7be8ecc](https://github.com/noonghunna/club-3090/commit/7be8ecc9e0977ae2d27397811a1cbb24b51b4b68))
- feat(soak-test): continuous-mode v2 fixtures + reproduces Cliff 2 at 25K accumulated context ([8d5bfd8](https://github.com/noonghunna/club-3090/commit/8d5bfd85f99a6a7c2c91cf70241c1e46c56ae957))
- feat(scripts): add soak-test.sh — runtime VRAM accretion validation (closes gap from #41) ([563a39e](https://github.com/noonghunna/club-3090/commit/563a39e0d3e7acbc15bb3c743d81cdcbef442dd4))
- feat: detect repo drift in preflight + add scripts/update.sh ([43fe2a4](https://github.com/noonghunna/club-3090/commit/43fe2a4e20ac8eb5c3f406f25ca0588a0989fb21))
- feat(launch/switch): register vllm/dual-nvlink as a known variant ([75de7c9](https://github.com/noonghunna/club-3090/commit/75de7c95dbcbc0c2c87f8130960340d204956224))
- feat(preflight): warn when Genesis tree out of sync with setup.sh's declared pin ([d552ed9](https://github.com/noonghunna/club-3090/commit/d552ed92166a07ce5fc3c289d9b42745f8479da5))
- feat(scripts/report.sh): capture per-GPU PCIe lane width + Gen + bus ID ([535be29](https://github.com/noonghunna/club-3090/commit/535be29df4520095bdb07cfe093031ca076f65b2))
- feat(scripts/report.sh): capture container-internal Python/CUDA versions ([e491e07](https://github.com/noonghunna/club-3090/commit/e491e07972275e2155421182a7f2df830170cd21))
- feat(scripts): add report.sh — paste-ready triage report ([31982f0](https://github.com/noonghunna/club-3090/commit/31982f0e6b029498b7244273217d448250aeeb20))
- push long-text/bounded-thinking back to 185K + 0.975; long-vision stays 140K + 0.95 ([df91d64](https://github.com/noonghunna/club-3090/commit/df91d641c443e1dd308cde8cc06175655dcfcd8e))
- feat(vllm): structured-CoT bounded-thinking compose (cross-rig port) ([3d151b9](https://github.com/noonghunna/club-3090/commit/3d151b9edc2621cfa45a7f38f8f5c05962fe924e))
- Push verified ceilings: long-text 218K, long-vision 198K ([f3e5b52](https://github.com/noonghunna/club-3090/commit/f3e5b5217c93d1476062caf5c94c1bfe93029dba))
- Verify 256K single-prompt prefill on dual.yml (Sandermage cross-rig) ([5270d94](https://github.com/noonghunna/club-3090/commit/5270d9400adfa07687ebd1beaa24cb812b10f1ea))


### 🎯 New models + serving paths

- composes: formalize Status enum + Caveats field (100% coverage) ([e1137d6](https://github.com/noonghunna/club-3090/commit/e1137d6889bbb6c7d7ddb584c942488f654c3b86))
- composes: rename dual4 → multi4 to align topology prefix with MULTI_CARD.md framing ([d33e6f8](https://github.com/noonghunna/club-3090/commit/d33e6f82da84e3e402bd2f1e0904c56cbcdb656a))
- composes: complete profile-schema header rollout (8 more composes) ([fca643d](https://github.com/noonghunna/club-3090/commit/fca643d6437bfc79522da57278a7001d1b268887))
- compose: extend VLLM_ENFORCE_EAGER hook to dual / dual-nvlink / dual4 + HARDWARE.md docs ([5ec40c6](https://github.com/noonghunna/club-3090/commit/5ec40c65ffd47b805026a9e65023a3bfe0a1dbd4))
- compose: VLLM_ENFORCE_EAGER env hook + WSL2 .env docs ([#99](https://github.com/noonghunna/club-3090/pull/99) by @easel)
- Add dual-nvlink-dflash-noviz compose variant (NVLink + DFlash N=5, 200K ctx, no vision) ([63ab224](https://github.com/noonghunna/club-3090/commit/63ab224c570516f158eee13cde22afcd9a4ba944))
- Add docker-compose.dual-nvlink-dflash.yml (#92) ([#92](https://github.com/noonghunna/club-3090/pull/92) by @danbedford)
- composes: PYTORCH_CUDA_ALLOC_CONF env-override knob + WSL2 boot-crash docs (#84) ([#84](https://github.com/noonghunna/club-3090/pull/84) by @easel)
- Add Gemma 4 + DFlash compose (vLLM PR #41703 Codex-rebased overlay) (#81) ([#81](https://github.com/noonghunna/club-3090/pull/81) by @noonghunna)
- composes: env-override knobs MAX_MODEL_LEN + GPU_MEMORY_UTILIZATION (#79) ([#79](https://github.com/noonghunna/club-3090/pull/79) by @noonghunna)
- add Gemma 4 31B + Google MTP drafter (first Ampere data) (#68) ([#68](https://github.com/noonghunna/club-3090/pull/68) by @noonghunna)
- Add dual NVLINK Docker Compose setup for Qwen3.6-27B ([1350450](https://github.com/noonghunna/club-3090/commit/135045002464a440381c8f77d4385a0045e754de))
- Add llama.cpp compose + perf chart + Q3_K_XL bench data ([39692c9](https://github.com/noonghunna/club-3090/commit/39692c98e5f2ea963da8274815b24fb3da70ecfd))
- Add long-vision + long-text composes (formalize R3' / R3''' bench rows) ([b641719](https://github.com/noonghunna/club-3090/commit/b641719eb815de978f01ddb6c2caed978cb45408))


### 🐛 Bug fixes

- fix: verify-full.sh broken pipe + llama-cpp DISABLE_THINKING env hook ([8f103f3](https://github.com/noonghunna/club-3090/commit/8f103f33ec8ed42c293e12b6bb39e73f736b1946))
- fix(preflight): catch missing llama.cpp GGUF before container boot (#63) ([#63](https://github.com/noonghunna/club-3090/pull/63) by @noonghunna)
- fix: remove thinking prompt from Carnice chat template + JSON tool format ([3729144](https://github.com/noonghunna/club-3090/commit/3729144107c587be2576171bad039aa453afceb2))
- fix: missing pipe in DUAL_CARD table row ([a28ba38](https://github.com/noonghunna/club-3090/commit/a28ba387dcdf3b6bb735872109e86062a5a5eb71))
- fix(soak): flag silent-empty turns (HTTP 200 + 0 tokens) as warnings ([f32d8a6](https://github.com/noonghunna/club-3090/commit/f32d8a69721059537557dcaeaaf522732798339a))
- fix: 3 issues from community feedback ([2f8ed19](https://github.com/noonghunna/club-3090/commit/2f8ed197ce8fb1ec1ce91a1d7647847bbca996f8))
- fix(soak-test, switch): calibration + boot-progress UX from first cross-rig runs ([8e9cf70](https://github.com/noonghunna/club-3090/commit/8e9cf70d9997d04336ead0eb7664cac608b64b3c))
- fix(dual-nvlink): rename to avoid collision + vendored Marlin path ([147f2e3](https://github.com/noonghunna/club-3090/commit/147f2e33ee8e8c021ab70f000928927326e9b4e8))
- fix(default compose): swap P65 (cudagraph workaround) → P67 (proper Triton kernel fix) ([620d918](https://github.com/noonghunna/club-3090/commit/620d918db3c0a346ae245ffaf78b7ecf0d789f70))
- fix(long-text-no-mtp): drop P65 + P85 — missed in a26e30b ([22e6549](https://github.com/noonghunna/club-3090/commit/22e654989b5658b09af989508584ce635826398e))
- fix(composes): drop GENESIS_ENABLE_P65 + P85 — out of sync with v7.69 dispatcher v2 ([a26e30b](https://github.com/noonghunna/club-3090/commit/a26e30b279d5dacbdaf7489c5dfb8d1203219166))
- fix(setup.sh): auto-clone vllm-src Marlin patched fork (was manual step) ([2e934ad](https://github.com/noonghunna/club-3090/commit/2e934ad18ad70d98e2e314ca3a96759935393949))
- fix(docs): replace dead luce-spec/llama-cpp-dflash links with Luce-Org/lucebox-hub ([e9c658c](https://github.com/noonghunna/club-3090/commit/e9c658cbc6ca453e9502b20a6fa6e682b2e5f752))
- fix(scripts): register vllm/long-text-no-mtp in switch.sh + launch.sh ([1f09a05](https://github.com/noonghunna/club-3090/commit/1f09a059d59138288bf630881c6870dacc91d9ed))
- fix(dflash): close the docs+setup gap that hit @lolren on club-3090#18 ([eb54cf4](https://github.com/noonghunna/club-3090/commit/eb54cf4e68da057a884b8d5fa8d26c8fd04969a0))
- fix(verify): drop tail buffer on Genesis check 2 anchor (refines 95b0905) ([f2c1433](https://github.com/noonghunna/club-3090/commit/f2c143326ea710cd1b724407dff5367930f14534))
- fix(verify+docs): close two items from troymroberts cross-rig validation (#25) ([95b0905](https://github.com/noonghunna/club-3090/commit/95b090567c646e7bbfcada5a05ec622dc9936ca2))
- fix(launch): pass per-variant URL + CONTAINER to verify-full.sh (#20) ([77ca576](https://github.com/noonghunna/club-3090/commit/77ca5767f5bf27ba0774edf1ded301c826d66277))
- fix(docs): bump curl smoke-test max_tokens 30 → 200 (#14) ([2f8bade](https://github.com/noonghunna/club-3090/commit/2f8bade82c53886f2525e0a5cb0efe748b1135e9))
- fix(vllm): fail fast when Genesis patches volume is empty (#13) ([0df8f74](https://github.com/noonghunna/club-3090/commit/0df8f743192809dbdcda942887b625b0f48699f2))
- fix: address open issues #1, #4, #7 ([ebacba1](https://github.com/noonghunna/club-3090/commit/ebacba1efd052fa3eda7ee3b05f2f8479a2fb2ff))


### 📊 Benchmarks + cross-rig data

- results: re-bench dual.yml + dual-dflash + dual-dflash-noviz on v0.20 ([0bdcb69](https://github.com/noonghunna/club-3090/commit/0bdcb69fa3e446442c8bc744dcb588e1697cba55))
- results: dual-turbo re-bench with corrected env vars (PN22 / PN26 naming fix) ([077228e](https://github.com/noonghunna/club-3090/commit/077228e81b06aebca3401fc03456f4a3eb55e227))


### 📝 Documentation

- docs: add Discord invite to README + FAQ + issue template ([c18257f](https://github.com/noonghunna/club-3090/commit/c18257f4399e0e7a5ee6bc38e80b10ff97ed2a8e))
- docs: refresh 4090 cross-rig knee with @laurimyllari's richer 38-cap sweep ([20ca297](https://github.com/noonghunna/club-3090/commit/20ca29737897df1d52c7c31ad6674a9d08aca54e))
- AGENTS.md: codify why patches/cache stay engine-level (not under a topology) ([9fbce96](https://github.com/noonghunna/club-3090/commit/9fbce961202965aeccd6851799b7abbdc806d355))
- AGENTS.md: capture compose naming + profile schema + experimental-compose conventions ([62e636c](https://github.com/noonghunna/club-3090/commit/62e636c0525156e6a98faaf318ce50c85a44de6b))
- docs+composes: align Gemma 4 compose names to Qwen's <topology>-<feature>.yml convention ([fe86b48](https://github.com/noonghunna/club-3090/commit/fe86b48c2134df8b333ff8445f40a7c6205aad0b))
- docs: surface Gemma 4 31B + add at-a-glance profile schemas to canonical composes ([4d7356a](https://github.com/noonghunna/club-3090/commit/4d7356aac69fbe46e87cf44083ee84965287ca19))
- docs: add Community projects section pointing at VykosX/club-3090-server ([cd48764](https://github.com/noonghunna/club-3090/commit/cd487648c9bc42c9807ec458b09e21d2ce238a5e))
- docs: laptop EC-managed power + TQ3 vs fp8 KV naming-trap; verify-stress: auto-bump curl timeout under VLLM_ENFORCE_EAGER ([fe23eff](https://github.com/noonghunna/club-3090/commit/fe23eff8f0dcac9647dffa198959b89e42e9fe33))
- docs + compose: ship Phase 2 INT8 PTH validation results — 262K Gemma 4 unblocked ([1e1886a](https://github.com/noonghunna/club-3090/commit/1e1886a3a95825f387bcc33badba3a52409e7778))
- docs(hardware): add Qwen3.6-35B-A3B (MoE) 3090 power-cap charts + comparison ([ec27d75](https://github.com/noonghunna/club-3090/commit/ec27d7594eadcad6a343fe4b4e3246f195b87eef))
- docs(img): reposition freq-cap chart annotations to clear right margin ([2f7eb44](https://github.com/noonghunna/club-3090/commit/2f7eb44a15b1383e90cfd8b8245193a9363cd255))
- docs(hardware): add 5090 clock-lock chart + Blackwell freq-cap section ([119a5fa](https://github.com/noonghunna/club-3090/commit/119a5fa00db659ac5283540d70cea65257c4cbaa))
- docs(hardware): regen 3090 power-cap charts with SM clock + plateau evidence ([9f77be7](https://github.com/noonghunna/club-3090/commit/9f77be791bced574965276d8271eaa28dc58f5a9))
- docs(hardware): reconcile 230W vs 290W vs 330W sweet-spot story ([a7a1d59](https://github.com/noonghunna/club-3090/commit/a7a1d591d5154fb8c0822738ff66536f85ae9fb0))
- docs(hardware): @apnar prefill-heavy 5090 sweep — proves per-workload power ceiling ([d5ef8c8](https://github.com/noonghunna/club-3090/commit/d5ef8c89d09c35b37ce10b6a85db63d374ebcf17))
- docs(hardware): correct 3090 cooling class — air, not water ([1f94478](https://github.com/noonghunna/club-3090/commit/1f94478179f9fe4d1daff644a1cf1eb5f06cc0cc))
- docs(hardware): embed 3090 + Qwen3.6 + llama.cpp power-cap chart ([42afdbb](https://github.com/noonghunna/club-3090/commit/42afdbbff8ac552f716c9d61383b9a80e9f8280b))
- docs(hardware): embed 4090 + Qwen3.6 + llama.cpp power-cap chart ([e70258c](https://github.com/noonghunna/club-3090/commit/e70258c47f6a134f5f4f503a06e074f1a7d54758))
- docs(hardware): embed 5090 + Gemma 4 power-cap efficiency chart ([8b1d51a](https://github.com/noonghunna/club-3090/commit/8b1d51ab3c5b4d976cea1f1c5c74ba8c1f3b4a42))
- docs(engines): more honest vLLM GGUF status ([2d9aa14](https://github.com/noonghunna/club-3090/commit/2d9aa1483ccdc446a6e3609e86eb4010c08474fe))
- docs(engines): fix 12 corrupted table separators from ik_llama.cpp column add ([8f5b924](https://github.com/noonghunna/club-3090/commit/8f5b92491a44e06873c9c8a252b6602589550043))
- docs(engines): add ik_llama.cpp as 5th column to comparison matrix ([0959206](https://github.com/noonghunna/club-3090/commit/09592065f5261f17d55efc2e053690552d148fbb))
- docs(hardware): add 5090 + Gemma 4 + MTP cross-rig anchor rows (apnar disc #86) ([bef5701](https://github.com/noonghunna/club-3090/commit/bef57012a725fe8c5f0975ff531508826c5eb45e))
- docs: add INFERENCE_ENGINES.md feature matrix (vLLM/llama.cpp/SGLang/ktransformers) ([dfceccb](https://github.com/noonghunna/club-3090/commit/dfceccbf5577c8fb44d1a746b2808803ca659a46))
- docs: codify canonical power-cap-sweep command for cross-rig anchors ([886b619](https://github.com/noonghunna/club-3090/commit/886b619cc45d3a5f26adeebb3ec78508ce856388))
- docs: BENCHMARKS rows + CHANGELOG entry for danbedford NVLink+DFlash variants ([b893d60](https://github.com/noonghunna/club-3090/commit/b893d60f43a02aea8b4032003004d855eb97980e))
- docs(benchmarks): @apnar 5090 Gemma 4 MTP + DFlash rows (disc #67) ([98b0601](https://github.com/noonghunna/club-3090/commit/98b0601b6888b86116312f2b9df38e9f871b7521))
- docs(benchmarks): three cross-rig rows from 2026-05-07 reports ([76aacdc](https://github.com/noonghunna/club-3090/commit/76aacdc22043e224e6a080f23dccad4146d01cf5))
- docs(benchmarks): add @aaronlockhartdev patched-P2P driver row (#91, disc #70) ([4eea837](https://github.com/noonghunna/club-3090/commit/4eea837da808bf7f6bfd2c944bc7c19fecb79726))
- docs(upstream): note we filed cross-rig validation on vLLM PR #40391 ([e46f1e8](https://github.com/noonghunna/club-3090/commit/e46f1e8e03de6b0d882a95581fd73163594796d6))
- docs(gemma-4): int8_per_token_head on Ampere — Codex investigation verdict ([1c2c156](https://github.com/noonghunna/club-3090/commit/1c2c156003550b5b1b004c329461f7d7ba2588bb))
- docs: surface host-build contributor flow + power-cap-sweep in README + CONTRIBUTING ([9aa6cb2](https://github.com/noonghunna/club-3090/commit/9aa6cb2b0e93c8b45d33b00b368532d7055086ca))
- docs(benchmarks): add @lamentofhighborne 1× 3090 llama.cpp MTP row (#85) ([68dbfaf](https://github.com/noonghunna/club-3090/commit/68dbfafe94148806a97025c1758bd6864454c1af))
- docs(hardware): add @apnar's 5090 power-cap anchor + compute-saturation note ([60d4df6](https://github.com/noonghunna/club-3090/commit/60d4df6ce7a960c7ff6a38c78c6be85a55e4608c))
- docs(upstream): correct Gemma 4 per-token-head KV row — upstream PR exists ([eb9f955](https://github.com/noonghunna/club-3090/commit/eb9f9552832931d4cc5e2bdd0a9d21f18f739e80))
- docs(gemma-4): document fp8 + int8 KV exploration on Ampere — both blocked ([bb07eb5](https://github.com/noonghunna/club-3090/commit/bb07eb59aec1c70f1748a43be51acbaccc1e2364))
- docs(gemma-4): empirical ctx ceilings + PR #41745 merge status ([1038e5f](https://github.com/noonghunna/club-3090/commit/1038e5fc77f72f28c0900cf53a947e90f008b002))
- docs(power): add cooling caveat — 388W stock requires liquid cooling ([b15c5e1](https://github.com/noonghunna/club-3090/commit/b15c5e1f33bee67ed17c9301e630f54af6d81827))
- docs(power): revise default cap 230W → 330W per @syangsao cross-rig data ([2fe017f](https://github.com/noonghunna/club-3090/commit/2fe017f88dee7036184c6ee0e048c91c59754cea))
- docs(benchmarks): correct V100 row VRAM 14.6→15.6 GB/card per @efschu ([d7bffec](https://github.com/noonghunna/club-3090/commit/d7bffeccb74e330f070cf3461019a387b6e766ff))
- docs(benchmarks): add @efschu 2× Tesla V100 16GB row (first sm_70 Volta data) ([9212c60](https://github.com/noonghunna/club-3090/commit/9212c606e07c0cb4f52ea5bcf259e987cb184630))
- docs(benchmarks): @danbedford 2× 3090 cross-rig matrix (6 benches, controlled PCIe vs NVLink) ([6e57215](https://github.com/noonghunna/club-3090/commit/6e572156883fe2d5a291922307346b526b930525))
- docs(benchmarks): add @laurimyllari 4090 single-card vllm/long-text row ([461c4d4](https://github.com/noonghunna/club-3090/commit/461c4d4d3d9cadbd88ad6bd39437958238ff7c62))
- docs(benchmarks): add @lolren 2× 3090 + Ryzen 5950X cross-rig rows (3 variants) ([34a2348](https://github.com/noonghunna/club-3090/commit/34a23486c4bc10b1a54c6eccdc6a793ddeff1fe7))
- docs(benchmarks): add @apriori dual-dflash row (EPYC 7302P + Arch + 2× 3090) ([344e595](https://github.com/noonghunna/club-3090/commit/344e595cb915f2168d48b26492624c5c555c4832))
- docs(upstream): track llama.cpp MTP PR #22673 + non-adoption rationale (#64) ([#64](https://github.com/noonghunna/club-3090/pull/64) by @noonghunna)
- docs(contributing): clarify issues-vs-discussions routing (#61) ([#61](https://github.com/noonghunna/club-3090/pull/61) by @noonghunna)
- docs: add Carnice BF16MTP to DUAL_CARD, vllm README, and CHANGELOG ([fbd3531](https://github.com/noonghunna/club-3090/commit/fbd3531960894e4f1dac1c29e55fdd99224c4f6c))
- docs(runtimes): tighten Proxmox section — native venv works (#49) ([a51202c](https://github.com/noonghunna/club-3090/commit/a51202c7b32e755afa2739d35574efa41fbcf17c))
- docs(hardware): note SM86 structural ~70% TG drop at 131K (cross-rig) ([eb5cd70](https://github.com/noonghunna/club-3090/commit/eb5cd708c3899953ecd9bb9852bd5825609b0799))
- docs: capture environmental footnotes — WSL2 TDR + Proxmox uvloop (#49, #50) ([224ca71](https://github.com/noonghunna/club-3090/commit/224ca71b1910d5ca4eb8f2379aa353c4ce0f3156))
- docs(cliffs): add rig-class caveat — "known good" is rig-specific (#49) ([53d5c6b](https://github.com/noonghunna/club-3090/commit/53d5c6b02f4dac7fab16f53aee37391ca77bc67c))
- docs(multi-card): topology-aware pair selection on awkward GPU counts (#49) ([8e60539](https://github.com/noonghunna/club-3090/commit/8e605397e05f00ee6eca2c825e49e6b2a02a7250))
- docs(benchmarks): walk back PFlash "shippable" framing — TTFT + NIAH ≠ full validation (#230, #231) ([ccac1ff](https://github.com/noonghunna/club-3090/commit/ccac1ff1751ce5b80c1d635e6e88d0a8294b0a6e))
- docs(benchmarks): PFlash long-context bench — 131K source ceiling on 1× 3090 (#230) ([ebca0c8](https://github.com/noonghunna/club-3090/commit/ebca0c8921293b156fffc338c3aee708621384ac))
- docs(benchmarks): K8V4 result + P2P-CNS finding on lucebox-hub dual-GPU (#229) ([e78eaa1](https://github.com/noonghunna/club-3090/commit/e78eaa1148af83566753d2ffb1c66fc1cbf2aba5))
- docs(benchmarks): add lucebox-hub DFlash dual-GPU bench — no-op on 24 GB cards (#229) ([cb089e1](https://github.com/noonghunna/club-3090/commit/cb089e1e36c3cc37db45da630331d0a5bfa10215))
- docs(benchmarks): add @JusefPol's 2× 3090 + NVLink dual-nvlink row (#29, #31) ([017d0d2](https://github.com/noonghunna/club-3090/commit/017d0d2c2009ddd15ec50395e1947d52562e4747))
- docs(lucebox): record PRs #78 + #80 — dual-GPU PFlash + DFlash split shipped (May 2026) ([dec0f22](https://github.com/noonghunna/club-3090/commit/dec0f22dac051c96b38a31b7245020f0736025c9))
- docs(sglang): refresh per-engine + comparison pages — DFlash + MTP native upstream as of May 2026 ([ecc2d74](https://github.com/noonghunna/club-3090/commit/ecc2d747aea7d7c0e06aaacae4e6bbbfbe1c3b40))
- docs(structured-cot): soften Phase 3 framing per Codex v2-prompt validation ([011d4cc](https://github.com/noonghunna/club-3090/commit/011d4cc37111dcb857338684faaa57a7bce2a717))
- docs(cliffs/hardware): ground Cliff 2 + TQ3 explanations in published literature ([9b370f5](https://github.com/noonghunna/club-3090/commit/9b370f5ab1ab24bfc0ff6a5a96022cdc3e093606))
- docs: cross-reference TQ3→fp8 KV swap from CLIFFS, DUAL_CARD, dual-turbo.yml + CHANGELOG record (#47) ([129a4f4](https://github.com/noonghunna/club-3090/commit/129a4f42f4e3a1eab64abcdf6a444937b566c353))
- docs(hardware): 20 GB Ampere TP=2 needs fp8_e5m2 KV, not TQ3 (#47) ([124f08c](https://github.com/noonghunna/club-3090/commit/124f08c7ceaf400965622c3038e851a1d62365b4))
- docs(benchmarks): add @snoby's 2× 4090 dual-dflash-noviz row (#46) ([fc4c061](https://github.com/noonghunna/club-3090/commit/fc4c061be1298124e2c144c7143b308eee4f57bb))
- docs: align bug-report + FAQ + MULTI_CARD with report.sh --full / --soak ([b859630](https://github.com/noonghunna/club-3090/commit/b85963033aa62465a0c75a911d7ce394be52a098))
- docs(benchmarks): add Rig column for cross-rig contributions ([d8e7f73](https://github.com/noonghunna/club-3090/commit/d8e7f73eb281ea62771b38458429d14271bd6427))
- docs: add BENCHMARKS.md + extend grammar harness for full-bench mode ([9043678](https://github.com/noonghunna/club-3090/commit/90436788fbf54258e98a206da4260d6fb94fbb40))
- docs+gates: PR template, soak-continuous gate, Phase 2 grammar A/B ([85a6ea8](https://github.com/noonghunna/club-3090/commit/85a6ea8c48d44558476f09d2bc5a1a6c9fa93d2f))
- docs: UPSTREAM tracker + SINGLE_CARD polish — close the cliff-2b research thread ([451b9f3](https://github.com/noonghunna/club-3090/commit/451b9f37ab645fb2c9b3540017518a6ea32179df))
- docs: surface Cliff 2b multi-turn envelope + WHY TP=2 / llama.cpp escape ([04764c5](https://github.com/noonghunna/club-3090/commit/04764c5f28c3c21ad0621d9693356a3712918514))
- docs(UPSTREAM): sync 3 upstream changes + add next-week revisit queue ([4327fd3](https://github.com/noonghunna/club-3090/commit/4327fd30247c87bda7bac43672635356bfa2847e))
- docs: surface scripts/update.sh + repo-drift detection ([bca5a06](https://github.com/noonghunna/club-3090/commit/bca5a063c964b0029189c46aeec6cdce6323b72a))
- docs(vllm-marlin-pad/README): add sanity-check procedure before image-bump syncs ([1bb85fa](https://github.com/noonghunna/club-3090/commit/1bb85fadb82f92b80216a6a1dfa4eff87e25b03d))
- docs: add MULTI_CARD.md for 3+ GPU users (derived, untested locally) ([75a64a6](https://github.com/noonghunna/club-3090/commit/75a64a694e0789d2ec3ed74c64eda96c789a2de8))
- docs(FAQ): add WSL2 RAM-constraint failure mode to troubleshooting ([3bf7da7](https://github.com/noonghunna/club-3090/commit/3bf7da7501e3bc0e909cf7eeb55acb425697e7e3))
- docs: surface triage ladder at issue-filing time + add at-a-glance table ([f55b0a7](https://github.com/noonghunna/club-3090/commit/f55b0a734f259f031da18e7d823ef7eb44dbbca5))
- docs(FAQ): add 5-step triage ladder before symptom-matching ([9560efd](https://github.com/noonghunna/club-3090/commit/9560efd1f7616bd91b3d753d5ffc961ad3d3641d))
- docs: add PFlash integration feasibility memo (Codex audit, 2026-05-02) ([90a83a3](https://github.com/noonghunna/club-3090/commit/90a83a3fb5e4a931380a3920b30047ab062a23a2))
- docs: route bug + bench templates through scripts/report.sh ([b9a1305](https://github.com/noonghunna/club-3090/commit/b9a13056cc04a45f828c4d6e3809ce2f5c979c60))
- docs(dual-card): substrate refs from v7.65/v7.66 → v7.69 ([95b2c3b](https://github.com/noonghunna/club-3090/commit/95b2c3b1fa36600f88815b90d66eda86e20eb22c))
- docs: full sync to v7.69 + Cliff 2 60K closure recipes ([f8c9c36](https://github.com/noonghunna/club-3090/commit/f8c9c365e06ffdfa0d938b0e7c6f6557a8e8f1f1))
- docs(UPSTREAM): track Pflash (Luce-Org prefill accelerator) — flagged by @troymroberts (#25) ([e0e1752](https://github.com/noonghunna/club-3090/commit/e0e1752b3a0299671a4c5fec610fa3e321caed95))
- docs(CLIFFS): note v7.68 cross-rig test outcome — 3 regressions, master stays on v7.66 ([ae1b92f](https://github.com/noonghunna/club-3090/commit/ae1b92fef33b3873464b45cfab30a73733064621))
- docs: Genesis #14/#15 fixes shipped on Sandermage dev (P38B/P15B/PN25 pending v7.65) ([60d7b02](https://github.com/noonghunna/club-3090/commit/60d7b02c55ae3c4b85d65977508068ab2e25ed27))
- docs(upstream): refresh tracker for v0.20 blockers, P38/FA varlen filings, v7.64 closures ([f633fdb](https://github.com/noonghunna/club-3090/commit/f633fdbe17d91ee6c56af3d7d20ea7e11e337bac))
- docs+composes: refresh long-text/long-vision/bounded-thinking headers + max_tokens guidance ([cc4f083](https://github.com/noonghunna/club-3090/commit/cc4f0835e6b0214b5775ffd3bb638a0b6e8cf0d7))
- docs + bounded-thinking: roll new context defaults across user-facing surfaces ([d803278](https://github.com/noonghunna/club-3090/commit/d803278ebc78028a58172a6a9cfc976c7bbbc0ea))
- docs(compose): document Cliff 1 mech B real-workload gap + escape hatches (#16) ([6bff99a](https://github.com/noonghunna/club-3090/commit/6bff99a3f2a2bc17caaf72c7e23b465799094d27))
- charts: add tweet-asset variant (single-card vLLM only, 2 bars) ([f754669](https://github.com/noonghunna/club-3090/commit/f754669562ea2be8f83215423a112b2f4b0af433))
- charts: combined width 18 + 2-line group labels + dual VRAM title says vLLM ([24c8a62](https://github.com/noonghunna/club-3090/commit/24c8a629fd7c632286ba99e8f5b8f166b41f9012))
- charts: fix layout overlap with Luce DFlash 7th bar ([1ce7dc4](https://github.com/noonghunna/club-3090/commit/1ce7dc4512a292c906c5f85df27e7851f879369f))
- docs+charts: add Luce DFlash bench + watch entry; cautions in single-card chart ([cf71feb](https://github.com/noonghunna/club-3090/commit/cf71feb3e809cf618930959c3f5a6198a81c4cbc))
- docs: demote 48K/tools-text/minimal to fallback; lead with long-* + llama.cpp ([48f93e5](https://github.com/noonghunna/club-3090/commit/48f93e550fc3232783b516e6d22bf484defb6f5b))
- docs: fix stale chart ref in HARDWARE.md + delete obsolete vram-budget.svg ([cc02699](https://github.com/noonghunna/club-3090/commit/cc026993da6b2bfb3dd3a2322970317524f6399d))
- docs: catch remaining stale 192K/205K refs in long-text.yml header ([f00f279](https://github.com/noonghunna/club-3090/commit/f00f279d381885e979b0e3e46428df5c40171fd8))
- docs: final cleanup pass on stale 192K/205K refs ([a1fc225](https://github.com/noonghunna/club-3090/commit/a1fc22556a26c7dbbdfe8995364361ccbb93a5ff))
- docs+scripts+charts: propagate new ceilings (long-vision 198K, long-text 218K) ([427d2f8](https://github.com/noonghunna/club-3090/commit/427d2f8aa9f47931ea2a5258b59936f32b1bb7fe))
- docs: record verified ceilings and bisection in CLIFFS + CHANGELOG ([26e5f65](https://github.com/noonghunna/club-3090/commit/26e5f65975eea982ae2babec8a2cbfb32e05ae5a))
- docs: note revised Cliff 1 diagnosis posted on Sandermage issue #11 ([8d8968b](https://github.com/noonghunna/club-3090/commit/8d8968b034e11af6ad76b2ffb952c76d7846b357))
- docs: link PN12 PR #13 + record independent validation pass ([5e38365](https://github.com/noonghunna/club-3090/commit/5e383657f988e320ab2e15e44d1a509e5f839d95))
- docs: revise Cliff 1 analysis (PN12 anchor drift was the real bug) ([13d325b](https://github.com/noonghunna/club-3090/commit/13d325b1eddf8062341c5723503516389548074a))
- Document Cliff 1 205K closure ([9f6182e](https://github.com/noonghunna/club-3090/commit/9f6182edc65691fe17e83df7cc88559db084e25a))
- changelog: link P101 PR #12 in 2026-04-30 entry ([90a03ce](https://github.com/noonghunna/club-3090/commit/90a03ce2775aa08c8e972df3c6eeaf23067ace1c))
- docs: link P101 PR #12 in UPSTREAM and CLIFFS ([d0d79b1](https://github.com/noonghunna/club-3090/commit/d0d79b1c25ab334f78f1ae4530f3f2ebbed91e76))
- CLIFFS.md: post-2026-04-30 architectural-wall conclusion ([8580dc6](https://github.com/noonghunna/club-3090/commit/8580dc612dfe4be605552671448b34777993a914))
- CLIFFS.md: refine clamp formula + implementation shape (ChatGPT review) ([da6393b](https://github.com/noonghunna/club-3090/commit/da6393bb79da167a018834dff71843cff2337853))
- Add docs/CLIFFS.md — comprehensive prefill-cliff synopsis ([b0eed46](https://github.com/noonghunna/club-3090/commit/b0eed46ff7e86f54c3ca6b19803cbd996a6f83fd))
- LLAMA_CPP.md: add structural explanation of why prefill cliffs don't fire ([17aff4c](https://github.com/noonghunna/club-3090/commit/17aff4ce05d14ed56515928d31caf7ccfce72c07))
- Add docs/UPSTREAM.md + AGENTS.md (consolidate upstream tracking) ([53d811d](https://github.com/noonghunna/club-3090/commit/53d811d82b0fc09b2f5ebf2aa557718a97d9c18b))
- Add docs/COMPARISONS.md — self-host vs cloud and other local options ([297a982](https://github.com/noonghunna/club-3090/commit/297a9821f5c2f0a0489bb86490d9a21055b1357c))
- Add docs/FAQ.md — common questions answered for tweet click-throughs ([1b9374b](https://github.com/noonghunna/club-3090/commit/1b9374b8b5fd47541d168241642cddec8c3b6f04))
- Add docs/EXAMPLES.md — client snippets + IDE / Open WebUI connection ([91b817f](https://github.com/noonghunna/club-3090/commit/91b817fa72d22d54bd9ab029711d8866b008763b))
- README: lead with two-routes framing (matches launch tweet) ([710def5](https://github.com/noonghunna/club-3090/commit/710def58e421aaa2629b19495bef1f1f3bdb76cb))


### 🔧 Pin bumps + upstream

- bump Genesis pin 753344b → fc89395 (v7.66 dev tip) ([7a7efbe](https://github.com/noonghunna/club-3090/commit/7a7efbea0dfd6694abe0bcfcbdb570d85fb9a884))
- v0.20 migration + Genesis v7.65 dev tip + cold-start cache + env-var alignment ([5aa97a2](https://github.com/noonghunna/club-3090/commit/5aa97a25d910012c1a614978665e57fee53934d0))
- Genesis v7.62.x + PN8 on FP8 paths (closes Cliff 1 on tools-text) ([51a4001](https://github.com/noonghunna/club-3090/commit/51a4001af78e7e3cc7d8a0f10fe276c8f10afee6))


### 🛠️ Scripts + tooling

- ci: add Release Drafter for CalVer release notes ([c49db50](https://github.com/noonghunna/club-3090/commit/c49db508e64bb2332822b15fe54239845de7f9a2))
- power-cap-sweep: also sum delta.reasoning (third field-path) ([1528b59](https://github.com/noonghunna/club-3090/commit/1528b591c3900fde4c5fffb6af137063053947b5))
- power-cap-sweep: sum delta.reasoning_content alongside delta.content ([71e5954](https://github.com/noonghunna/club-3090/commit/71e5954ea987ece658ecfa1f232ccf3506a41fbf))
- power-cap-sweep: clamp prefill calibration to model context window ([32f924c](https://github.com/noonghunna/club-3090/commit/32f924c1c4889f26113dcf0f3ae8677339a95a08))
- power-cap-sweep: plateau auto-detection + multi-mode chain docs ([fd11ae6](https://github.com/noonghunna/club-3090/commit/fd11ae64c5dfb29ae0941e29ce96364d85d490cd))
- power-cap-sweep: add SM/mem clock + throttle% + pstate sampling ([ab2796d](https://github.com/noonghunna/club-3090/commit/ab2796dd6eaba09086f03847fa4e8c6cd9d55852))
- power-cap-sweep: time-bounded prefill-heavy + decode-concurrent (Codex round 2) ([1ede998](https://github.com/noonghunna/club-3090/commit/1ede998ced854f970018380dbf829132b3f9fe5f))
- power-cap-sweep: time-bounded streaming bench (Codex Option A redesign) ([7877c04](https://github.com/noonghunna/club-3090/commit/7877c047b55eb80a2941e6da1490389ffbb5aff3))
- power-cap-sweep: 4 cross-card portability fixes ([652103f](https://github.com/noonghunna/club-3090/commit/652103f07405535bea9c1dd659ab3610e4f86443))
- power-cap-sweep: env-overridable bench shape for decode-single mode ([c638c30](https://github.com/noonghunna/club-3090/commit/c638c305873e2a6b109302b2cae1f99fcad5ce43))
- setup.sh: auto-create .env for WSL2 boot-crash workaround (#60) ([4861ee7](https://github.com/noonghunna/club-3090/commit/4861ee7b6bfb6e337de541e44cecc30e3343b9c4))
- power-cap-sweep: --concurrency-stretch N flag for probing headroom past plateau pick ([3991ecc](https://github.com/noonghunna/club-3090/commit/3991ecc5b945fad1eaba1165e7d9a85dc6d80701))
- power-cap-sweep: plateau-detection auto-calibration (saturate headroomy GPUs) ([29e7de5](https://github.com/noonghunna/club-3090/commit/29e7de5a90ea70807c32d33ab4ebca9814f74e55))
- report.sh: engine-aware Active container probes (vllm + llamacpp) ([6fa66d2](https://github.com/noonghunna/club-3090/commit/6fa66d2f97e23563f2c5f3e7965473f3b6672d31))
- report.sh: capture recently-exited containers' boot logs (#60) ([cd980f6](https://github.com/noonghunna/club-3090/commit/cd980f64b7e7276016eae9c4cd47557ed9211ee9))
- setup.sh: add gemma-4-31b model support (#89) ([dd3bccc](https://github.com/noonghunna/club-3090/commit/dd3bcccb05f3027ca7dda6cabca962d4b7a75c5c))
- power-cap-sweep: --concurrency auto for workload-calibrated sweeps (Codex) ([f811457](https://github.com/noonghunna/club-3090/commit/f811457fffaad61c834d6c2b2b32ecca66376fa2))
- power-cap-sweep: --bench-runs N for variance mitigation (Codex) ([f99fad3](https://github.com/noonghunna/club-3090/commit/f99fad3361a577e8360c4c7a1d36531d80216c97))
- power-cap-sweep: document decode-concurrent n=1 variance caveat ([18c74de](https://github.com/noonghunna/club-3090/commit/18c74def0a6b987eecac26883bb13b2f602fe791))
- power-cap-sweep: load-mode flag + concurrent/prefill modes (Codex iteration) ([f387622](https://github.com/noonghunna/club-3090/commit/f38762251b31333a4bde463c3c1af2796bcec28c))
- verify-stress: engine-aware diagnostic hints (closes #87) ([4f01abb](https://github.com/noonghunna/club-3090/commit/4f01abb2d5fb318ee8862db51b19045257f4a69a))
- power-cap-sweep: make CONTAINER optional for host engine builds (#85, #87) ([2bb3cf7](https://github.com/noonghunna/club-3090/commit/2bb3cf72170b57de56358ca4ce4893346ebbabf0))
- scripts(verify-full, soak-test): decouple from docker/vLLM assumptions (#85, #87) ([a8606e3](https://github.com/noonghunna/club-3090/commit/a8606e34398d1c207fcfb6e6c989c2f94e766296))
- power-cap-sweep: fix stale summary footer + add compute-saturation note ([8c26c4b](https://github.com/noonghunna/club-3090/commit/8c26c4b56af0414ff8c0a499076250c6c38cefe3))
- power-cap-sweep: reduce per-cap bench to ~30s for faster sweeps ([a413321](https://github.com/noonghunna/club-3090/commit/a413321ad95667b9c767a8e56ee267657cdc690d))
- power-cap-sweep: 10W default increment + under-load median power sampling ([6d70b72](https://github.com/noonghunna/club-3090/commit/6d70b7287084cfa40dfdcf7470a8234cf8b5dbba))
- power-cap-sweep: auto-derive cap range from card's min/max power limits ([e5c7a34](https://github.com/noonghunna/club-3090/commit/e5c7a34e91e8577f61133693878f1625f92e99fc))
- Add scripts/power-cap-sweep.sh — automated cross-rig power-cap A/B (#83) ([#83](https://github.com/noonghunna/club-3090/pull/83) by @noonghunna)
- scripts: auto-detect running container + port in verify / bench (closes #52 promise) ([29718ca](https://github.com/noonghunna/club-3090/commit/29718cac994a7060e994fc85b898ffbec8fd73c1))
- verify-stress: add 3 probes to cover the bug shapes we missed ([5e745c5](https://github.com/noonghunna/club-3090/commit/5e745c5c85547c028a86fe2bcf83376d61b6c8b5))
- Add scripts/health.sh — operational health check for running server ([e7780c5](https://github.com/noonghunna/club-3090/commit/e7780c556a55f98038b287fca9314a35c88ec1a5))
- Split verify-full.sh → verify-full.sh (fast functional) + verify-stress.sh (boundary) ([5060e22](https://github.com/noonghunna/club-3090/commit/5060e22a6c25320104edf10fe799b4c2c31a2296))


### 🧹 Maintenance

- restructure: promote topology to a directory level (single/dual/multi4) ([acd7ffb](https://github.com/noonghunna/club-3090/commit/acd7ffb67c07a1df4b34ec11a7ec52087f249d96))
- Drop vllm-gemma4-mtp overlay tree (merged upstream as #41745, validated) ([aa99173](https://github.com/noonghunna/club-3090/commit/aa99173e7ad9577e6d95032b67c596c254d4ee13))
- chore(gitignore): allow results/lucebox-*/ — evidence for BENCHMARKS lucebox row ([030f780](https://github.com/noonghunna/club-3090/commit/030f780f24d5c14777ccd8e19d2788c58b7afcd8))
- chore(tools): commit residency-instrument as research tool with framing README (#41, #217) ([ed05d1c](https://github.com/noonghunna/club-3090/commit/ed05d1c35ca804a369108e18915af9e5db5bc4a1))
- chore(results): commit grammar bench evidence + gitignore investigation artifacts (#217) ([d82e898](https://github.com/noonghunna/club-3090/commit/d82e89807aefbcdf9d6b1bcf1ed83ad5f9552617))
- refactor: vendor vllm#40361 Marlin patched files in-repo (drops /opt/ai/vllm-src/ host dep) ([d8b341f](https://github.com/noonghunna/club-3090/commit/d8b341fa8cea9a7dec47c26a5f3afc81fd7e08d2))
- chore: untrack docs/diagnostics/, gitignore the path ([3f18053](https://github.com/noonghunna/club-3090/commit/3f18053659f2f2997574ed6da7317f7e5872f20e))
- Remove no-genesis-mtp.yml (research artifact, not user-facing) ([f4a28b1](https://github.com/noonghunna/club-3090/commit/f4a28b19eb4466d504dcf4e7c532e0d4fac5e967))
- Remove fast-chat.yml; extend P68/P69 disable to default ([37a4895](https://github.com/noonghunna/club-3090/commit/37a4895f6dae510e42729c6502d23e83599894a8))
- Restructure docs around hardware axis: SINGLE_CARD.md + DUAL_CARD.md ([26ac811](https://github.com/noonghunna/club-3090/commit/26ac8118de51480e6c0ecce6c8dc0ceccabc93fb))
- Audit + reconcile dual-card compose headers, patches README, setup output ([0f33561](https://github.com/noonghunna/club-3090/commit/0f33561b6bd85f890cd36d5ada7bfb489e10c6d7))


### 🧹 Other

- benchmarks: add JDWarner #107 TB3 dual-eGPU + mixed-arch row ([fa9df49](https://github.com/noonghunna/club-3090/commit/fa9df49ef2cd55f088db94dba67b3533702e9baa))
- Rename gemma-mtp-fp8.yml → gemma-mtp-int8.yml to match Ampere reality ([160e8fc](https://github.com/noonghunna/club-3090/commit/160e8fce8b5158c9870e4714f8e05bf63fa9460f))
- Two regressions caught + reframe Phase 2 around INT8 PTH (Ampere reality) ([119f296](https://github.com/noonghunna/club-3090/commit/119f2965401c19132f9c654420b742c9eb684b63))
- gemma-mtp-fp8: vendor rebased PR #40391 + stacked tool-parser fixes (#42006 + #41991) ([f93d312](https://github.com/noonghunna/club-3090/commit/f93d31215e20b195e07d4c30d2ad854852c9b7dc))
- gemma-mtp: drop PR #41745 overlay + bump to post-merge nightly ([595be8f](https://github.com/noonghunna/club-3090/commit/595be8fb8eb0442916a3570494ec5b90fc3e33f3))
- llama.cpp: --reasoning-format none default (opencode unblock, #97) ([af00ab7](https://github.com/noonghunna/club-3090/commit/af00ab7bef911ed6127ac900ecc081f9e5293ddc))
- Set dual-nvlink-dflash-noviz --max-model-len default to 188000 ([89c6862](https://github.com/noonghunna/club-3090/commit/89c686288e482a5b3529afd3af01d86157232c51))
- patches: qwen3coder tool-parser deferred-commit sidecar (#72) ([2e00b6d](https://github.com/noonghunna/club-3090/commit/2e00b6d718ea3e30fb0a0a380eaff095c39c098f))
- TQ3 composes: propagate PN34 to remaining 4 (follow-up to #82 audit) ([ab69f65](https://github.com/noonghunna/club-3090/commit/ab69f656910aa00a77da5c06aea9cd9f03041750))
- vllm/default: also enable P98 (belt+suspenders with PN34, follow-up to #82) ([2c7efe6](https://github.com/noonghunna/club-3090/commit/2c7efe61086181dfd6777bd2c1a2e55e2957d2c5))
- vllm/default: add GENESIS_ENABLE_PN34_WORKSPACE_LOCK_RELAX=1 (#82) ([3167497](https://github.com/noonghunna/club-3090/commit/3167497fef643267e42df7009272bb6c062c13fe))
- add dual-nvlink-turbo variant (rebased on v7.72.2 master, sibling-table edits dropped) (#65) ([#65](https://github.com/noonghunna/club-3090/pull/65) by @noonghunna)
- release(v7.72.2-uplift): Genesis pin + vLLM pin + sidecar consolidation (#59) ([#59](https://github.com/noonghunna/club-3090/pull/59) by @noonghunna)
- carnice-bf16mtp: restore original template + qwen3_xml parser ([d57579c](https://github.com/noonghunna/club-3090/commit/d57579c31ae6b4a42d0bf604e0e86364a2e94b85))
- carnice-bf16mtp: JSON tool format + empty think block, no reasoning parser ([a350df7](https://github.com/noonghunna/club-3090/commit/a350df7c911b8c8935980e328a7b4c57f374c70b))
- carnice-bf16mtp: add HF model URL to header ([5da50ec](https://github.com/noonghunna/club-3090/commit/5da50ec8978d64ebcefbf11637921955a6edd0e7))
- carnice-bf16mtp: formal narrative + code bench results ([7fef94f](https://github.com/noonghunna/club-3090/commit/7fef94f600a906687d60f4c4a9da85e3659d9da7))
- carnice-bf16mtp: 2 streams at 262K confirmed + formal bench numbers ([66d42c7](https://github.com/noonghunna/club-3090/commit/66d42c7940cacd011ad2468fcb1320f5384766c0))
- carnice-bf16mtp: 65K context was config choice, not VRAM ceiling — bumped to 262K ([1cf0cb2](https://github.com/noonghunna/club-3090/commit/1cf0cb288e046af486f3ace1ef2295f4944989b2))
- Carnice-V2-27B + BF16 MTP overlay — new compose variant ([bc28542](https://github.com/noonghunna/club-3090/commit/bc28542c5571c929ecee3e6371f30457855e9618))
- extend PN25 v3 + PN30 dst-shaped temp fix to all 4 TQ3 composes ([b875624](https://github.com/noonghunna/club-3090/commit/b875624f2d9ea41d6ead3a8563f9ef37ffbdb59c))
- Genesis pin d89a089 → 753344b + cross-rig validation of Sander's PN30/PN31 ([2b5ab4d](https://github.com/noonghunna/club-3090/commit/2b5ab4d0cf761e895772290ecaf45573727a0553))
- cliffs: v0.20 unblock recipe + 50K-stress-PASSES finding ([9506561](https://github.com/noonghunna/club-3090/commit/9506561ba8fdc35ef515a17275a2c94a5bec1e69))
- cliffs: document P38 silently no-op'd on TurboQuant KV path ([91355b8](https://github.com/noonghunna/club-3090/commit/91355b8fd577fc172f3f6d2af035d06b5ce08ec7))
- long-text/long-vision/bounded-thinking: middle-ground recovery 130K → 175K / 120K → 140K ([383b5cc](https://github.com/noonghunna/club-3090/commit/383b5cc38197d2ffa68a001c1e0c4c60877d99fe))
- long-text/long-vision: enable P37 + back off context for activation headroom ([1a931b4](https://github.com/noonghunna/club-3090/commit/1a931b4042090f182266aa150fa0e31d15afdbd5))
- genesis: bump pin v7.62 → v7.64 + add compile-safe FFN sidecar (#16) ([53d0663](https://github.com/noonghunna/club-3090/commit/53d0663a50c91f0a929917ae6390303842508e9e))
- Add local FA max seqlen clamp sidecar ([9f06a0f](https://github.com/noonghunna/club-3090/commit/9f06a0fe79e8e4f55b438c2e2427b8738e72d1cf))
- Fix local PN12 activation pool anchor ([41eabac](https://github.com/noonghunna/club-3090/commit/41eabac17b0b8b558121e213be1498855be314d6))
- CLIFFS: document PN12-is-partial finding (full stack still hits wall) ([537875a](https://github.com/noonghunna/club-3090/commit/537875a7fd1235ef21006ef1c5f5c2d5aabee74a))
- Add genesis #11 row to UPSTREAM.md ([bb406f9](https://github.com/noonghunna/club-3090/commit/bb406f90f16d2c59a0512b060f7af3028140e02a))
- Add Max ctx column to TL;DR + perf-summary tables on both pages ([e94c2e7](https://github.com/noonghunna/club-3090/commit/e94c2e78c4176704f4dffe93137af6f9d56f201a))
- DUAL_CARD: promote perf chart to top, parallel to SINGLE_CARD ([19fb8e7](https://github.com/noonghunna/club-3090/commit/19fb8e730f5f009f73ceef0e31ced393a2f9b2c2))
- Disable P68/P69 on long-vision, long-text, dual-turbo too ([f0cbcc6](https://github.com/noonghunna/club-3090/commit/f0cbcc6a9c9333af4dfaf6a7267ff8a93767a157))
- Disable Genesis P68/P69 in shipped composes (silent-stop bugfix) ([aab8ff4](https://github.com/noonghunna/club-3090/commit/aab8ff4a0e1eddc4c53ab24ef31ff748c54f84c8))
- Split charts per GPU-count page; chart sources land in tools/charts/ ([3742244](https://github.com/noonghunna/club-3090/commit/3742244e4d98960732569551490a64c62a23d1d8))
- Move performance chart into docs/img/ alongside vram-budget-dual ([2e3ae0c](https://github.com/noonghunna/club-3090/commit/2e3ae0c7861b4a5f74bdec0bff1b8cdca399a837))
- UX polish: pre-flight checks + cards-first wizard + PNG embeds ([abc06c3](https://github.com/noonghunna/club-3090/commit/abc06c3e3317ab2472242f8410a0d105f3631a16))
- FAQ: add VS Code Copilot LLM Gateway entry ([f275bf5](https://github.com/noonghunna/club-3090/commit/f275bf502a9ac914f011d750c1f63486ce981436))
- Add CONTRIBUTING.md — what kind of PRs land cleanly ([0c261eb](https://github.com/noonghunna/club-3090/commit/0c261ebcdfaf8bd057195d007eee28dfc5922085))
- CHANGELOG: capture post-launch polish day in cross + per-model logs ([1cc6ee6](https://github.com/noonghunna/club-3090/commit/1cc6ee6e24f991bed4a63eb084c82bea0a17bf21))
- Add launch.sh wizard + switch.sh stateless variant switcher ([4b77ed5](https://github.com/noonghunna/club-3090/commit/4b77ed5eb1eee64bbf913a332f38a54746c17d05))
- Add per-card VRAM allocation diagram + reference from model README ([88523b3](https://github.com/noonghunna/club-3090/commit/88523b3d05985476ae5bcbaeee05aab4d091319e))
- Cite Kaitchup Qwen3.6-27B GGUF eval as quant-quality lens ([b7ef91f](https://github.com/noonghunna/club-3090/commit/b7ef91f9518d5b8f521d2b850570722322c4ea3b))
- Pin Genesis to exact tested commit + add .env.example + issue templates ([ec704e4](https://github.com/noonghunna/club-3090/commit/ec704e4e2e86d8ff2ec990d8d544427f3e957dcd))
- Dual-card re-bench on club-3090 substrate + fix dual-turbo mount path ([c701474](https://github.com/noonghunna/club-3090/commit/c70147426dd241e894186f40bb3207a53f43c8df))
- dual-turbo: switch kv-cache-dtype k8v4 → 3bit_nc to align with test findings ([3e1f5f6](https://github.com/noonghunna/club-3090/commit/3e1f5f61c0475474461008a71d54ca39ddc908b5))
- Pin Genesis version + fix MODEL_DIR defaults + clean stale headers ([7f00e52](https://github.com/noonghunna/club-3090/commit/7f00e5214072491637ba7b02cdec2c9e8135b445))
- Fix .gitignore + add the entire models/ tree (initial commit was incomplete) ([2511a98](https://github.com/noonghunna/club-3090/commit/2511a981109b983d05247a485db8bdf999c6d38e))
- Initial commit — club-3090: model-agnostic LLM serving recipes for RTX 3090 ([3fa3333](https://github.com/noonghunna/club-3090/commit/3fa33332ce12b042c171fc98ad21fe412c0f92a0))



[Pin: `git checkout v2026.05.09`]

