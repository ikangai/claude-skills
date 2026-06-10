# Local models (LM Studio)

How to run diary synthesis on a local model, which models measure well, and how to wire fully automatic local synthesis into the Stop hook.

## How it works

`scripts/synthesize-local.sh` is the events-only synthesis path: it filters one session out of `.dev-diary/.events.jsonl`, compacts the events to one readable line each, and sends them with the diary voice rules to an OpenAI-compatible chat-completions endpoint. The response contract is plain text: `SLUG: <slug>`, a blank line, then the entry — or `NO ENTRY` plus a reason line when the session doesn't clear the bar. The script strips `<think>…</think>` reasoning blocks, truncates chat-template leaks (`<|…`), sanitizes the slug, and writes `.dev-diary/YYYY-MM-DD-<slug>.md` (collision-safe with `-2`, `-3` suffixes).

The trade-off versus in-session synthesis: the local model sees *what* happened (files, commands, exit codes, prompts truncated to 500 chars) but not the conversation, so entries are thinner on reasoning and motive. Costs nothing and works offline. Local synthesis is the default path; in-session synthesis is the fallback when the local server is unavailable, and the higher-context option when an entry needs conversation-only reasoning (`DIARY_SYNTH=claude` opts the Stop hook back into it).

## Usage

```bash
scripts/synthesize-local.sh                          # latest session, auto-discovered model
scripts/synthesize-local.sh --session <id>           # specific session
scripts/synthesize-local.sh --model <model-id>       # specific model
scripts/synthesize-local.sh --dry-run                # show the prompt, no API call
scripts/synthesize-local.sh --stdout                 # print entry, write nothing
```

| Env var | Default | Meaning |
|---|---|---|
| `DIARY_LM_URL` | `http://localhost:1234/v1` | OpenAI-compatible base URL |
| `DIARY_LM_MODEL` | first non-embedding model served | model id (`--model` overrides) |
| `DIARY_LM_TEMP` | `0.2` | sampling temperature |
| `DIARY_LM_MAX_TOKENS` | `4096` | completion budget — reasoning models think inside this; below ~4096 they can return empty content |
| `DIARY_LM_TIMEOUT` | `300` | request timeout (s); the first call to an unloaded model includes LM Studio's JIT load (10s–2min) |

Exit codes: `0` entry written or model declined; `1` server/model failure (callers can fall back to in-session synthesis); `2` usage error.

## Automatic local synthesis (Stop hook)

This is the default. When the auto-synthesis conditions are met (edit threshold reached, no entry yet, no opt-out), `scripts/maybe-synthesize.sh` runs `synthesize-local.sh` directly instead of blocking Stop and nudging Claude. Sessions end silently and the entry appears in `.dev-diary/` — zero Claude tokens. If the local server is down or returns garbage, the hook falls back to the normal block directive, so the entry is never silently lost. Each attempt's output is written to `.dev-diary/.last-local-synth.log` — check it first when an expected entry didn't appear or the nudge fired despite a running server. Set `DIARY_SYNTH=claude` to skip the local attempt entirely and always nudge in-session Claude (the pre-2026-06 behavior).

Two cautions:

- **Hook timeout.** The maybe-synthesize hook needs `"timeout": 300` in `.claude/settings.json` (the hooks-setup snippet ships with that value): generation plus a JIT model load far exceeds the 5 seconds that suffices for a bare nudge.
- **Quality bar.** Events-only entries are grounded but thinner. Spot-check the first few with `tests/check-entry.sh <entry> <events>`; if quality disappoints, set `DIARY_SYNTH=claude` to return to nudge mode.

## Which model

Evaluated 2026-06-10 with `tests/eval/run-eval.sh` against the fixture suite in `tests/eval/fixtures/` (synthetic pivot/failure/correction sessions, a routine session that must be declined, and three real sessions from a working repo, 7–455 events) — 13 models screened, 5 finalists on the full suite, scored by the mechanical linter plus a sonnet judge pass. Full matrices, latencies, and failure modes: `tests/eval/results/REPORT.md`.

| Model | Verdict |
|---|---|
| `google/gemma-4-26b-a4b` | **Recommended default.** Combined mechanical 0.99, best prose per judge (7.0), the only finalist that correctly declined both routine and noise sessions. 14–164s/entry. |
| `qwen3.6-35b-a3b-configi-mlx` | **Fast alternative.** Perfect finals incl. a 455-event session in 70s; prose slightly flatter (6.7). Use when hook latency matters. |
| `openai/gpt-oss-20b` | Speed floor (5–23s) — but writes fluent filler instead of `NO ENTRY` on routine sessions and judges weakest on voice (5.3). |
| `zai-org/glm-4.7-flash` | Best faithfulness, structurally perfect on small/medium — but reasoning latency times out (300s) on large sessions. |
| `qwen/qwen3.6-27b`, `qwen3.5-27b-claude-distilled` | Fail to load (~45GB dense). |
| `nemotron-3-nano(/-omni)`, `qwen3-coder-30b`, `qwen3-vl-30b` | Errors on medium sessions and/or false entries on routine sessions. |

`synthesize-local.sh` prefers `google/gemma-4-26b-a4b` automatically when the server lists it (falling back to the first non-embedding model). To force a different model:

```bash
export DIARY_LM_MODEL="qwen3.6-35b-a3b-configi-mlx"
```

The sharpest quality discriminator was not prose — every model wrote a plausible pivot entry — but the *bar*: declining sessions that don't warrant an entry. If you try a new model, test that first (`tests/eval/run-eval.sh --models <id> --fixtures routine-no-entry.jsonl`).

## Re-running the evaluation

```bash
tests/eval/run-eval.sh                                  # all served models × all fixtures
tests/eval/run-eval.sh --models openai/gpt-oss-20b      # one model
tests/eval/run-eval.sh --fixtures pivot-canonical.jsonl --results /tmp/quick
```

The harness writes `scores.jsonl`, `summary.md`, and the generated entries (kept for judging) into the results directory. LM Studio serves one large model at a time; the harness runs sequentially and the first request per model includes its load time. Entries can additionally be judged by a stronger model on voice/narrative/faithfulness — the mechanical linter catches structure and grounding, not prose quality.
