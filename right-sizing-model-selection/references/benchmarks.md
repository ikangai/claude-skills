# Public benchmarks as routing priors

Researched and adversarially verified 2026-06-10 (12/12 load-bearing claims cross-checked
against independent sources). Machine-readable orderings: `benchmark-priors.json` (consumed
by `scripts/kb prior`).

## How benchmarks fit the evidence hierarchy

```
local KB record (n>=2)  >  fresh probe  >  family-transfer from KB  >  benchmark prior  >  provenance/load-state
```

Benchmarks are **population evidence**: measured on someone else's task distribution,
harness, and build of the model. They are good for three things and three things only:

1. **Ordering probe candidates** when the KB is empty for a task type (`kb prior --task-type X`).
2. **First-guess tier calibration** for genuinely new task shapes.
3. **Divergence detection**: when a model's local result is drastically below its benchmark
   profile, suspect your integration — chat template, max_tokens vs reasoning budget,
   sampling params — before concluding the model is weak. Measured case: GLM-4.7-Flash
   benches SWE 59.2 / AIME 91.6 publicly but scored 0.0 locally — the LM Studio chat
   template leaks; the model isn't broken, the path is.

A benchmark prior never skips the probe. The METR RCT (16 experienced devs, 246 real
issues) found developers *believed* AI made them 20% faster while being measured 19%
*slower* — benchmark/perception-to-real-task transfer is weak; your probe on your task is
the only signal that binds.

## Rankings snapshot (2026-06-10)

### Agentic coding — SWE-bench Verified (% resolved)

| Model | Score | Notes |
|---|---|---|
| Claude Fable 5 | 95.0 | near saturation; SWE-bench **Pro** discriminates: fable 80.3 vs opus-4.8 69.2 |
| Claude Opus 4.8 | 88.6 | |
| Claude Sonnet 4.6 | 79.6 | |
| Qwen3.6-27B | 77.2 | official build, thinking mode — **fails to load locally** (45GB) |
| Qwen3.6-35B-A3B | 73.4 | local copies are community MLX builds — discount |
| Claude Haiku 4.5 | 73.3 | |
| gpt-oss-20b | 60.7 | high reasoning effort (37.4 low / 53.2 medium) |
| GLM-4.7-Flash | 59.2 | broken locally (template) |
| Qwen3-Coder-30B | 51.6 | disputed (OpenHands scaffold, reproducibility questions) — but locally KB-passing on extraction/codegen probes |

### Reasoning / knowledge

| Model | GPQA Diamond | AIME 2025/26 | MMLU-Pro |
|---|---|---|---|
| Claude Opus 4.8 | 93.6 | USAMO'26 96.7 | — |
| Claude Sonnet 4.6 | 89.9 | 95.6 (contamination flagged) | — |
| Qwen3.6-27B | 87.8 | 94.1 | 86.2 |
| Qwen3.6-35B-A3B | 86.0 | 92.7 | 85.2 |
| Gemma 4 26B-A4B | 82.3 | 88.3 | 82.6 |
| GLM-4.7-Flash | 75.2 | 91.6 | — |
| Nemotron 3 Nano | 73.0 | 89.1 (99.2 w/ tools) | 78.3 |
| Claude Haiku 4.5 | 73.0 | 80.7 no-tools | ~77 (low conf) |
| gpt-oss-20b | 71.5 (high effort) | 91.7 | MMLU 85.3 (not Pro) |

GPQA is saturated at the top (current frontier scores ≥90 on only 198 questions;
researchers describe progress as asymptotic) — use MMLU-Pro or LiveBench to
discriminate strong models; treat small GPQA gaps as noise.

### Human preference — LMArena Elo (overall / WebDev / creative)

| Model | Overall | Code (WebDev) | Creative |
|---|---|---|---|
| claude-opus-4-8(-thinking) | 1479–1482 | 1545–1552 | 1454–1475 |
| claude-sonnet-4-6 | 1470 | 1522 | 1449 |
| gemma-4-26b-a4b | 1438 | 1360 | 1403 |
| claude-haiku-4-5 | 1411 | 1324 | 1387 |
| glm-4.7-flash | 1368 | — | 1312 |
| gpt-oss-20b | 1318 (med conf) | — | — |

~100 Elo ≈ 64% win rate. Caveats: style bias (length + markdown dominate votes), the
Leaderboard-Illusion critique (private-variant gaming), and hosted variants (qwen3.6-max,
-plus) are NOT the local builds.

### Instruction following

IFEval and IFBench are **different scales** — never cross-compare (qwen3.6-plus IFEval
94.3 vs fable IFBench 63.5 says nothing about relative quality). Sparse coverage for our
inventory; treat format-compliance as probe-measured, not benchmark-known.

## Per-task-type benchmark validity (what predicts what)

| Task type | Best public proxy | Trust level |
|---|---|---|
| codegen-complex (repo/agentic) | SWE-bench Verified (discount 2–5pts memorization), SWE-bench Pro, Terminal-Bench | good, harness-sensitive |
| codegen-simple | LiveCodeBench (post-cutoff window) | good |
| reasoning | MMLU-Pro, LiveBench Reasoning/Math, AIME | good (GPQA saturated) |
| qa-factual | MMLU-Pro, MMMLU (multilingual) | moderate |
| translation | WMT (human ESA protocol only) | sparse coverage |
| creative | LMArena Creative, EQ-Bench longform | weak (style bias) |
| analysis/synthesis | LMArena overall + MMLU-Pro | weak |
| classification, extraction, summarization | none trustworthy — IFEval/LiveBench-IF weak proxies | **probe-only territory** |
| proofreading | GEC F0.5 (minimal-edit) — strong chat models over-rewrite | inverted: restraint task |
| code-review | none mature (2026 survey: fragmented) | probe-only territory |

## Cross-cutting caveats (why the probe stays mandatory)

- **Harness sensitivity**: Opus 4.7 SWE-bench = 87.6 (Anthropic harness) vs 82.0 (minimal
  harness). Never mix harnesses in one comparison column.
- **Version drift**: Terminal-Bench 2.1 ≠ 2.0 ≠ 1.0 task sets; LiveCodeBench windows differ.
- **Build gap**: published numbers are full-precision official releases at vendor-chosen
  reasoning effort; your local quantized/MLX/community build can be far weaker (and
  reasoning-effort defaults differ).
- **Contamination/memorization**: SWE-bench Illusion — SOTA models reproduce buggy file
  paths from issue text alone 76% of the time; AIME 2025 contamination flagged by Anthropic.
- **One general factor**: ~80% of benchmark variance is a single capability factor
  (observational scaling laws) — benchmarks mostly rank *general* strength; task-specific
  fit (restraint in proofreading, schema discipline, format compliance) is exactly what
  they miss and what the local KB captures.

## Refreshing this file

Numbers go stale with every model release. To refresh: re-run the research workflow
(`tests/results/benchmark-research.json` documents the area split), verify load-bearing
claims against primary sources, update this file + `benchmark-priors.json`, bump both
`updated` fields, and re-run `tests/scenarios/` GREEN checks.
