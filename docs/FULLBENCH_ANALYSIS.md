# Full-suite benchmark analysis — 8 models × 3 runs × 8 packs (2026-06-04)

**Hardware:** 1× RTX 3090 24 GB  
**Suite:** benchlocal-cli `--full` — 150 scenarios / run (ToolCall-15, InstructFollow-15, StructOutput-15, DataExtract-15, ReasonMath-15, BugFind-15, HermesAgent-20, CLI-40)  
**Protocol:** 3 runs per model, averages reported. Temperature 0.6 / top_p 0.95 / top_k 20.  
**Source data:** `results/quality/overnight-20260603_213655/`

---

## Overall ranking

| Rank | Model | Avg /150 | % | HA-20 | CLI-40 | TPS | Ctx |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | byteshape IQ4_XS 35B-A3B + MTP | 110.3 | 73.5% | 11.3/20 | 17.0/40 | 115 | 262K |
| 2 | bartowski Qwen3.6-35B Q4_K_M | 109.3 | 72.9% | 12.3/20 | 15.7/40 | 140 | 131K |
| 3 | Qwen3.6-27B Q5_K_XL + MTP n=3 | 107.7 | 71.8% | 12.3/20 | 18.0/40 | 32 | 32K |
| 3 | Qwopus3.6-27B-v2 MTP n=2 | 107.7 | 71.8% | 14.0/20 | 20.0/40 | 42 | 102K |
| 3 | Carnice-V2-27B MTP n=2 | 107.7 | 71.8% | 12.3/20 | 18.0/40 | 40 | 65K |
| 6 | Gemma 4 26B-A4B Q4_K_M | 104.7 | 69.8% | 12.0/20 | 17.0/40 | 102 | 32K |
| 7 | Carnice I-Quality 35B-A3B | 95.3 | 63.5% | **16.0/20** | 6.7/40 | 139 | 131K |
| 8 | GLM-4.7-Flash Q5_K_L | 85.7 | 57.1% | 10.0/20 | 9.3/40 | 107 | 65K |

---

## Per-pack breakdown (avg across 3 runs)

| Model | TC/15 | IF/15 | SO/15 | DE/15 | RM/15 | BF/15 | HA/20 | CLI/40 | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| byteshape IQ4_XS | **15.0** | 14.7 | 14.0 | **13.0** | 12.7 | 12.7 | 11.3 | 17.0 | **110.3** |
| bartowski 35B | **15.0** | 14.7 | 14.0 | 12.0 | **13.0** | 12.7 | 12.3 | 15.7 | 109.3 |
| Qwen27-xl MTP n=3 | 14.0 | **15.0** | 14.0 | 8.0 | 12.3 | **14.0** | 12.3 | 18.0 | 107.7 |
| Qwopus-v2 MTP n=2 | 14.0 | 14.0 | 14.0 | 7.0 | 11.7 | 13.0 | 14.0 | **20.0** | 107.7 |
| Carnice-V2 MTP n=2 | 14.0 | 14.7 | 14.0 | 9.0 | 12.3 | 13.3 | 12.3 | 18.0 | 107.7 |
| Gemma 4 26B | 11.3 | 14.0 | 14.0 | 10.0 | **13.0** | 13.3 | 12.0 | 17.0 | 104.7 |
| Carnice I-Quality | 13.0 | 13.3 | 14.0 | 12.0 | 10.7 | 9.7 | **16.0** | 6.7 | 95.3 |
| GLM-4.7-Flash | 13.0 | 13.7 | 14.0 | 7.3 | 9.7 | 8.7 | 10.0 | 9.3 | 85.7 |

**Pack abbreviations:** TC=ToolCall, IF=InstructFollow, SO=StructOutput, DE=DataExtract, RM=ReasonMath, BF=BugFind, HA=HermesAgent, CLI=CLI-40

---

## Pack winners

| Pack | Winner | Score | Notes |
|---|---|---:|---|
| ToolCall-15 | bartowski 35B / byteshape (tie) | 15/15 (100%) | Both perfect |
| InstructFollow-15 | Qwen3.6-27B Q5_K_XL MTP n=3 | 15/15 (100%) | Only model to hit 100% |
| StructOutput-15 | All models | 14/15 (93%) | Near-universal ceiling |
| DataExtract-15 | byteshape IQ4_XS | 13/15 (87%) | Most consistent across runs |
| ReasonMath-15 | Gemma 4 26B / bartowski (tie) | 13/15 (87%) | Gemma math advantage |
| BugFind-15 | Qwen3.6-27B Q5_K_XL MTP n=3 | 14/15 (93%) | Clear leader |
| HermesAgent-20 | Carnice I-Quality 35B | 16/20 (80%) | Only model >14 |
| CLI-40 | Qwopus3.6-27B-v2 MTP n=2 | 20/40 (50%) | Perfect consistency, 3/3 runs |

---

## Key findings

### 1. The specialization trap: Carnice I-Quality

Carnice I-Quality 35B scored 16.0/20 on HermesAgent (80%) — the highest of any model. But CLI-40 averaged 6.7/40 (16.8%), consistent across all three runs. The Carnice fine-tune optimizes for HermesAgent protocol fidelity at the cost of general CLI execution competence.

This is the core finding of the overnight run. A model that looks dominant on one pack can rank 7th out of 8 on the full suite. hermesagent-20-only benchmarks hide this.

**Conclusion:** Carnice I-Quality is the right choice for HermesAgent-protocol workloads. It is not a general-purpose model.

### 2. byteshape IQ4_XS is the best all-rounder

4.19 bpw quantization, 262K context, 115 TPS. No individual pack win except DataExtract and ToolCall (tied). But the lowest floor of any model — never catastrophic on any pack. Full-suite winner at 73.5%.

The insight: at sufficient context (262K), the model can handle tasks that other models truncate. The quantization penalty is smaller than expected for general instruction-following.

### 3. CLI-40 is the decisive differentiator

CLI-40 has the largest spread of any pack: 6.7 (Carnice) to 20.0 (Qwopus), a 3× range. ToolCall-15 and StructOutput-15 spread from 11.3 to 15.0, a 1.3× range. Models that are useful for DevOps/automation workloads need to be evaluated on CLI competence, not just agent protocol packs.

### 4. GLM-4.7-Flash: narrow specialist

Interesting on memory recall and cron scenarios (as noted in hermesagent-20 analysis). But CLI-40: 9.3/40 (23%), BugFind: 8.7/15 (58%), ReasonMath: 9.7/15 (65%). Full-suite: 57.1%. The niche where GLM excels (scheduled tasks, memory-across-sessions) is real but narrow.

### 5. Gemma 4 26B: math engine with a context ceiling

Best or tied-best on ReasonMath (13/15 = 87%) and BugFind (13.3/15 = 89%). The hard constraint is 32K context — dense KV. For math-heavy and code-review tasks on contained inputs, Gemma 4 is the pick. For anything requiring long documents or multi-session context, it can't compete.

### 6. Qwopus v2: CLI + agent hybrid

Only model with a perfect CLI-40 run across all 3 runs (20/40 each time). Also 14/20 on HermesAgent in the hermesagent-20 standalone test. The trade-off: DataExtract 7/15 (47%) — weakest in the group there. Best choice when the workload mixes shell automation with agent protocol.

### 7. Qwen3.6-27B Q5_K_XL: the bug finder

14/15 on BugFind (93%), 15/15 on InstructFollow (100%). Weakest at DataExtract (8/15, 53%). MTP n=3 at 32 TPS is slow but produces the most precise code analysis output in the group. For code review / regression hunting workflows, this configuration stands out.

### 8. Variance

HermesAgent-20 was the highest-variance pack (agent framework non-determinism). CLI-40 was stable — most models had ≤1 scenario variance across 3 runs. ReasonMath and StructOutput were essentially deterministic.

---

## Task-based model selection

| Use case | Recommended model | Why |
|---|---|---|
| HermesAgent protocol workflows | Carnice I-Quality 35B | 80% HA, only model with safety clarification (HA-20) |
| CLI/shell automation | Qwopus3.6-27B-v2 MTP | 20/40 CLI, consistent across all runs |
| Code review / bug finding | Qwen3.6-27B Q5_K_XL MTP | 93% BugFind, 100% InstructFollow |
| Math / structured reasoning | Gemma 4 26B or bartowski 35B | 87% ReasonMath (watch 32K ctx limit) |
| Long-context all-rounder | byteshape IQ4_XS 35B-A3B | 73.5% overall, 262K ctx, 115 TPS |
| Max speed + general quality | bartowski Qwen3.6-35B Q4_K_M | 140 TPS, 72.9%, 131K ctx |
| Scheduled tasks / memory recall | GLM-4.7-Flash | Niche only — accept 57% full-suite |

---

## Run configuration

| Model | Image | Ctx | KV | Extra |
|---|---|---|---|---|
| Carnice I-Quality | mainline llama.cpp | 81920 | q4_0 | --jinja |
| Qwen3.6-27B Q5_K_XL | mainline llama.cpp | 32768 | q4_0 | --spec-type draft-mtp --spec-draft-n-max 3 |
| Qwopus3.6-27B-v2 MTP | mainline llama.cpp | 102400 | q4_0 | --spec-type draft-mtp --spec-draft-n-max 2 |
| Gemma 4 26B-A4B | ik-llama cu12 | 32768 | q4_0 | --reasoning off |
| Carnice-V2-27B MTP | mainline llama.cpp | 65536 | q4_0 | --spec-type draft-mtp --spec-draft-n-max 2 --reasoning off |
| bartowski Qwen3.6-35B | mainline llama.cpp | 131072 | q4_0 | --jinja |
| GLM-4.7-Flash | mainline llama.cpp | 65536 | q4_0 | --jinja |
| byteshape IQ4_XS 35B-A3B | ik-llama cu12 | --fit (262K) | q4_0 | -khad -vhad --multi-token-prediction --draft-max 2 |

---

## Relation to prior benchmarks

This run supersedes the hermesagent-20-only rankings from 2026-06-02/03. The hermesagent-20 scores here are consistent with earlier standalone results (±1-2 scenarios, expected variance). The overall ranking is a different picture because CLI-40 was not included in previous runs.

See `BENCHMARKS.md` for the full historical trace.
