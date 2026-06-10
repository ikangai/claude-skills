# Model registry — tiers, traits, prompting notes

> The calibrated numbers in this file are the author's measurements on their own
> hardware and task suite — treat them as a worked example of what the knowledge
> base accumulates, not as your numbers. Your local inventory, quantizations, and
> tasks differ: probe and build your own `knowledge/kb.jsonl`.

Calibrated entries come from `knowledge/kb.jsonl` (run `scripts/kb query`); this file
holds the slower-moving facts. Update when the local inventory or pricing changes.
Public benchmark rankings and their validity per task type: `benchmarks.md`
(machine-readable orderings: `benchmark-priors.json`, served by `scripts/kb prior`).

## Claude tiers (via `claude -p` / Agent tool `model:` option)

| Tier | $/MTok in/out | Character | Prompting notes |
|---|---|---|---|
| fable | 10 / 50 | Strongest; long-horizon agentic work, subtle correctness | You are (probably) this model. Spend it on analysis, decomposition, adjudication — not bulk. |
| opus | 5 / 25 | Frontier reasoning, synthesis, code review | Handles ambiguity; states uncertainty honestly. |
| sonnet | 3 / 15 | Workhorse; solid reasoning, good writing, reliable JSON | Default judge for probes. Clear instruction + format suffices. |
| haiku | 1 / 5 | Fast pattern work: classify, extract, transform, proofread | Needs exact schema + edge-case decision rules + "output nothing but X". Confident — won't flag its own uncertainty; validate mechanically. |

Dispatch overhead (measured): each `claude -p` call adds ~9–27K input tokens of fixed
overhead (system prompt; varies with cache state) and roughly 4–15s wall clock.
Batch 20–50 items per call.

## Local models (LM Studio, `http://localhost:1234`, $0)

State check first: `scripts/llm --list` — only one large model stays loaded at a time;
`not loaded` means JIT-load delay (10s–2min) or a memory-guardrail failure
(27B+ dense models can demand >40GB and refuse to load — e.g. qwen3.6-27b).

| Model | Size/speed | Calibrated 2026-06-10 (benchmark, 0-10) | Prompting notes |
|---|---|---|---|
| openai/gpt-oss-20b | 20B, fast (~1-3s), 131K ctx | Strong: classification 10, translation 10, free-form summaries 10, logic puzzle 10, codegen 10, concurrency review 9. Weak: proofreading 3 (overcorrects), rigid output formats 6, analysis structure 5, extraction normalization 7.5 | Best local generalist. Doesn't normalize extracted values unless told (copies OCR garbage verbatim) — spell out normalization rules. |
| qwen/qwen3-coder-30b | 30B MoE, fast | Strong: invoice JSON extraction 10 (best local), classification 10, translation 10, codegen 10, logic puzzle 10. Weak: code review 5 (false positives), proofreading 4, creative 6 | Schema-strict extraction and code transforms. Demand a single fenced code block. |
| zai-org/glm-4.7-flash | flash-class, 202K ctx | **Unusable via OpenAI-compat API here**: reasoning consumes small max_tokens budgets (empty output); with large budgets it answers then leaks chat-template garbage (`<\|user\|>thought…`) | Don't route until the LM Studio chat template is fixed. If retrying: max_tokens ≥4K and strip everything after the first template token. |
| qwen/qwen3.6-27b | 27B dense | — | Dense 27B needs ~45GB to load — fails LM Studio's memory guardrail on most Macs. Use the hosted `or:qwen/qwen3.6-27b` instead. |
| nvidia/nemotron-3-nano | nano, very fast | Weak on almost everything: sentiment 3.3, topic 0, invoice 0, proofread 0 (empty); one pass: contact extraction 7.5 | Don't route graded work to it. |
| google/gemma-4-26b-a4b | 26B vlm | Vision-capable (unprobed locally); public: MMLU-Pro 82.6, LMArena Creative 1403 (best local prose per Arena) | Candidate for image tasks and creative drafts; probe first. |

Also downloaded but unprobed: `qwen/qwen3-vl-30b` (vision, qwen3-coder sibling),
`qwen3.6-35b-a3b-configi-mlx` and `-uncensored-wasserstein` (community builds — expect
quality below published Qwen3.6 numbers; prefer configi over uncensored finetunes),
`qwen3.6-27b-ud-mlx`, `qwen3.5-27b-claude-distilled`, `glm-4.7-flash-claude-distill`,
`nvidia/nemotron-3-nano-omni`. Run `scripts/llm --list` for the live inventory and
`kb prior` for benchmark-informed probe ordering.

Universal local-model rules:
- Temperature 0–0.2 for anything graded.
- One worked example anchors output format better than three paragraphs of rules.
- Re-state hard constraints at the END of the prompt (recency wins).
- They do not reliably say "I can't" — every batch needs mechanical validation.
- Output may include reasoning preamble; demand "output only X" and validate.

## OpenRouter (`or:` prefix via `scripts/llm`, needs OPENROUTER_API_KEY)

339-model catalog at market prices; curated shortlist with live pricing and rationale:
`openrouter-models.json` (kb/probe rank `or:` models by real blended $/MTok from it).
Refresh prices from the public endpoint: `curl https://openrouter.ai/api/v1/models`.

**Reasoning headroom:** thinking models (glm-4.7-flash, gpt-oss-*) count reasoning
tokens against `max_tokens`; tight output budgets get consumed by reasoning → empty
content. `scripts/llm` adds +2048 headroom to all `or:` calls (override:
`OR_REASONING_HEADROOM`). Empty output from an `or:` model = budget/integration
artifact first, capability conclusion last.

Calibrated/observed 2026-06-10:

| Model | Blended rank (haiku=1) | Calibrated (benchmark, 0-10) | Notes |
|---|---|---|---|
| or:deepseek/deepseek-v4-flash | 0.05 | proofread 10, translate 10, invoice 10, summarize-exec 10, taglines 9 — **best probe-first candidate** | 1M context; fast; barely any reasoning overhead. |
| or:openai/gpt-oss-120b | 0.04 | proofread 10, invoice 10, summarize-exec 10, translate 10, taglines 7 | Cheapest strong generalist; needs reasoning headroom (see above). |
| or:z-ai/glm-4.7-flash | 0.08 | invoice 10, translate 10, summarize-exec 9, proofread 9, taglines 8 — **hosted twin fix** for the locally-broken build | Heavy thinker: with headroom it's good but SLOW on creative/structured tasks (taglines took 147s); prefer deepseek/gpt-oss-120b when latency matters. |
| or:...:free variants | 0.0 | Blocked unless your OpenRouter privacy settings allow them (HTTP 404 guardrail/data-policy) | Free because prompts may train providers' models — enable in OpenRouter privacy settings only for non-sensitive work. |

Proofreading — where every local model failed (restraint task) — now has three
passing models below 1/10th of haiku's price. The ladder inversion is fixed by
the `or:` band, not by paying for Claude tiers.

Export `OPENROUTER_API_KEY` in your shell profile to enable `or:` routing.
Privacy rule: sensitive data routes local or Claude, never to the cheapest endpoint.

## Judge selection for probes

sonnet by default. Escalate the judge to opus when the criteria themselves require
expertise (concurrency correctness, security, legal nuance) — a judge can only cap
what it can detect. Never judge with the same model that produced the output.
