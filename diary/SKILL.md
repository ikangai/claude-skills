---
name: diary
description: Maintains a per-project development diary capturing the narrative of how code got built — what was tried, what broke, where direction changed, what was learned. Use this skill when the user invokes /diary to synthesize a session into an entry, when a Stop-hook directive arrives at end-of-turn asking for auto-synthesis, when a notable pivot or learning moment occurs mid-session that should be captured before context fades, when starting work in an area where prior diary entries in .dev-diary/ might provide useful context, or when the user wants entries synthesized in-session by Claude instead of the default local model (LM Studio, offline, zero token cost). Entries are first-person markdown in .dev-diary/ at project root; raw session events accumulate in .dev-diary/.events.jsonl via Claude Code hooks, and a Stop hook synthesizes entries automatically via the local model when the session has accumulated substantive work, falling back to an in-session nudge when the local server is unavailable.
---

# Diary

## Overview

Maintain a development diary for the current project. The diary captures *how* things got built — the narrative behind decisions, the things that were tried and abandoned, the moments work changed direction. Entries are first-person prose, the way a developer would write in a notebook at the end of a working day.

The diary serves three audiences: future-Claude resuming work and needing context for prior decisions; other agents picking up the project and needing to learn what's been tried; humans retracing how the codebase came to be.

The diary is per-project and lives in `.dev-diary/` at the project root, gitignored by default. Narrative entries are written by this skill. Raw session events are captured automatically by Claude Code hooks to `.dev-diary/.events.jsonl` — the audit trail; the markdown entries are the narrative.

## When to invoke

Invoke this skill in four situations:

1. **The user types `/diary`.** Synthesize a diary entry from the current session, using the local model first (see "Synthesis workflow").
2. **The Stop hook injects an auto-synthesis directive.** At end-of-turn, `scripts/maybe-synthesize.sh` checks whether the session has accumulated substantive work (file edits at or above the threshold — default 2, configurable via the `DIARY_EDIT_THRESHOLD` env var — with no entry written yet and no opt-out marker present). When all conditions hold, the hook synthesizes the entry itself via the detected backend — a suitable local model (LM Studio) when one is available, else Sonnet via the headless claude CLI — and the session ends silently. Only when synthesis fails — or `DIARY_SYNTH=claude` is set — does the hook block Stop and feed back a directive asking you to apply the synthesis workflow. Treat that directive exactly like a manual `/diary` invocation — read the events, apply the bar, and either write the entry or briefly say it does not clear the bar. Do not ask the user; just decide and act.
3. **A significant pivot or learning moment occurs mid-session.** When direction changes notably or a surprising lesson emerges that would be lost by session end, capture it as a short entry without waiting for the user to ask. Examples: realizing the initial approach is wrong and rewriting, discovering a library behaves differently than expected, the user correcting course after several wrong attempts.
4. **Starting work on an unfamiliar area.** Check `.dev-diary/` for entries relevant to the area before beginning. Read what's there. Surface relevant findings briefly to the user before proceeding.

Do **not** invoke for routine, uneventful work. Successful test runs, mechanical edits matching established patterns, and execution of well-trodden paths do not warrant entries. The bar is: *would a future agent benefit from knowing this, beyond what the code itself records?* If no, skip — including when the Stop hook nudges you. The hook's only signal is "edits happened"; you are the one who applies the bar. A one-sentence "this session didn't clear the bar — no entry written" reply is the correct response when the work was routine.

## Voice and structure of entries

Entries are first-person prose. Chronological narrative. No headers within an entry. No bullet lists. The structure is carried by the verbs — *tried*, *broke*, *pivoted*, *learned* — not by section labels.

Style rules:

- First person, past tense. "I tried..." / "I rewrote..." / "The user pushed back when..."
- Concrete and specific. Name the file, the function, the library, the actual error. Avoid abstractions like "the system."
- Document reversals explicitly. The most valuable content is the moment work changed direction and why.
- End with one short beat for the lesson, if one was earned. Not "Lessons Learned: ..." — just a sentence stating what carries forward.

Avoid:

- Section headers inside an entry (the entry is one flowing piece).
- Bullet or numbered lists.
- Self-evaluative adjectives ("elegant solution," "clean refactor"). The diary records facts and reasoning, not praise.
- Vague summary sentences ("Made good progress on X"). Either say what happened concretely or omit.

Example of the target voice:

> Started on the shishi bucket — content-aware event accumulator for tmuxllm. First instinct was a ring buffer with fixed-size window. Wrote about eighty lines and hit a wall: when events arrive in bursts, the window drops context I want to keep, because relevance isn't correlated with recency. Tried weighting by token count next — keep the heavy stuff, drop the rest. Broke on a different axis: short events can be high-relevance (a stack-trace summary line), long events can be padding (a config dump). Token count isn't a relevance signal. Pivoted to a content-aware filter at ingestion. Worked in about two hours after the pivot. Token count is a tempting proxy for relevance and it's wrong.

For more examples covering different session shapes (pivots, sub-agent coordination, user pushback, learning moments), see `references/voice-examples.md`.

## Synthesis workflow

When invoked to write an entry, try the local model first:

0. **Run external synthesis.** From the skill's base directory, run `scripts/detect-synth.sh` (instant no-op when `.dev-diary/.synth-config` already holds the project's detected backend), then `scripts/synthesize-local.sh` (backend and model come from that config; it defaults to the latest session in the events log, which during a live session is the current one). Three outcomes: the script writes an entry and prints its path — validate it with `tests/check-entry.sh <entry> .dev-diary/.events.jsonl` and, if the linter passes, report the path to the user and stop here; the model declines with "NO ENTRY" — relay that in one sentence and stop; the script fails (exit 1: server down, claude CLI missing, empty output) or the linter reports failures — delete any failed entry file and fall back to in-session synthesis, steps 1–6 below. One exception: if the local entry is sound but misses a decisive *why* that only the live conversation holds (a pivot's reason, a user correction), amend it with a targeted edit rather than rewriting.

When falling back to in-session synthesis:

1. **Read the raw events for this session.** Open `.dev-diary/.events.jsonl` and read events from the current session. The session ID is in the hook envelope; if running without that context, use the most recent events (the file is append-only and chronological). The events tell you *what* happened with timestamps; the conversation context tells you *why* and *how*. Use both. For the events.jsonl schema, see `references/events-schema.md`.

2. **Decide whether this session warrants an entry.** Apply the bar from "When to invoke." If the session was routine — reading files, answering questions, no substantive code change or decision — tell the user briefly that the session didn't produce diary-worthy content and write nothing. A diary with no entry is better than a diary with filler.

3. **Choose a slug.** Two to five lowercase words separated by hyphens, naming the substance of the work. Good: `shishi-bucket-event-accumulator`, `executor-uid-isolation-pivot`. Bad: `session-update`, `progress`, `work-done`.

4. **Construct the filename:** `.dev-diary/YYYY-MM-DD-<slug>.md`. Use today's date. If a file with that name exists, append `-2`, `-3`, etc.

5. **Write the entry.** Apply the voice rules. Walk the work chronologically. Surface reversals and decisions explicitly. End with one short lesson sentence only if genuinely earned.

6. **Save the file and tell the user briefly.** One sentence: "Wrote `.dev-diary/2026-05-18-shishi-bucket-event-accumulator.md`." No further commentary.

## Local synthesis (LM Studio)

Synthesis can also run on a local model instead of in-session. `scripts/synthesize-local.sh` reads one session's events from `.dev-diary/.events.jsonl`, asks an OpenAI-compatible server (LM Studio, default `http://localhost:1234/v1`) to write the entry in the diary voice, and writes the dated, slugged file. It applies the same bar — the model may decline with "NO ENTRY" for routine sessions.

External synthesis is the default path — for the Stop hook's auto-synthesis and for manual `/diary` invocations alike. On a project's first synthesis, `scripts/detect-synth.sh` probes LM Studio for a suitable model (the eval-proven ones, see `references/local-models.md`): found, the backend is `local` — zero Claude tokens, works offline; server down or nothing suitable, the backend is `sonnet` — headless `claude -p --model sonnet`. The decision persists in `.dev-diary/.synth-config`; delete it or run `detect-synth.sh --force` to re-detect after installing LM Studio or downloading a suitable model. The trade-off: both backends see only the events, not the conversation, so entries are thinner on the *why* behind decisions; in-session synthesis remains the fallback whenever synthesis fails, and the higher-context option when an entry needs conversation-only reasoning. Set `DIARY_SYNTH=claude` to opt the Stop hook back into in-session synthesis, or `DIARY_SYNTH=local`/`sonnet` to force a backend without detection.

```bash
scripts/detect-synth.sh                      # first-run probe; no-op once .synth-config exists
scripts/synthesize-local.sh                  # latest session; backend + model from .synth-config
scripts/synthesize-local.sh --session ID --model openai/gpt-oss-20b
scripts/synthesize-local.sh --backend sonnet # force headless claude -p --model sonnet
```

Configuration via env vars (`DIARY_LM_URL`, `DIARY_LM_MODEL`, `DIARY_LM_MAX_TOKENS`, …), measured model quality, and the recommended default model (`google/gemma-4-26b-a4b`, preferred automatically when the server lists it) are documented in `references/local-models.md`. After a local synthesis, `tests/check-entry.sh <entry> <events>` validates the entry against the voice rules and the events — regenerate or fix if it reports failures.

## Reading prior entries

When the user begins work on something that might have prior context in the diary:

1. List `.dev-diary/` (skip `.events.jsonl` and `README.md`).
2. Filename slugs are the first filter — they describe what each entry is about.
3. For entries that look potentially relevant, read them.
4. Surface relevant findings briefly before starting work: "There's a prior entry on this from May 15; the first approach was X, pivoted to Y because of Z. Worth keeping in mind."

Do not read every entry every session. The diary accumulates over months — full reads become impractical. Use filename slugs and targeted grep instead.

## File layout

```
.dev-diary/
├── YYYY-MM-DD-<slug>.md       # narrative entries, one per session that produced work
├── .events.jsonl              # append-only raw event log (from hooks)
└── README.md                  # explains the layout to humans
```

The `.dev-diary/` directory belongs in `.gitignore` by default. The user can opt into committing it later.

## Capture and auto-trigger sides: hooks

Two halves of the skill run as Claude Code hooks defined in `.claude/settings.json`:

- **Capture.** `scripts/log-event.sh` runs on `PostToolUse` (Write/Edit/MultiEdit and Bash), `UserPromptSubmit`, `SubagentStop`, and `Stop`. It appends normalized events to `.dev-diary/.events.jsonl` as the session proceeds. Read-only operations (Read/Grep/Glob/LS) are deliberately excluded as noise.
- **Auto-trigger.** `scripts/maybe-synthesize.sh` runs as a second command on the `Stop` hook. It inspects the events log for the current session, and if the conditions are met (edits at or above the configured threshold, no entry yet, no opt-out, not already in a Stop-hook loop), it writes the entry via the detected backend (`synthesize-local.sh` — LM Studio, or Sonnet through the claude CLI; `detect-synth.sh` decides once per project on first run). If synthesis fails, or `DIARY_SYNTH=claude` is set, it instead emits a JSON directive that blocks Stop and asks the in-session Claude to apply the synthesis workflow with full live conversation context.

For the hook configuration, install steps, conditions, threshold tuning, and the per-project `.dev-diary/.no-auto-synth` opt-out marker, see `references/hooks-setup.md`.

The capture side is independent of synthesis. Even if both `/diary` is never invoked AND auto-synthesis is opted out, the events log accumulates and stays available for later reconstruction.
