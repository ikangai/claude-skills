---
name: diary
description: Maintains a per-project development diary capturing the narrative of how code got built — what was tried, what broke, where direction changed, what was learned. Use this skill when the user invokes /diary to synthesize a session into an entry, when a notable pivot or learning moment occurs mid-session that should be captured before context fades, or when starting work in an area where prior diary entries in .dev-diary/ might provide useful context. Entries are first-person markdown in .dev-diary/ at project root; raw session events accumulate in .dev-diary/.events.jsonl via Claude Code hooks.
---

# Diary

## Overview

Maintain a development diary for the current project. The diary captures *how* things got built — the narrative behind decisions, the things that were tried and abandoned, the moments work changed direction. Entries are first-person prose, the way a developer would write in a notebook at the end of a working day.

The diary serves three audiences: future-Claude resuming work and needing context for prior decisions; other agents picking up the project and needing to learn what's been tried; humans retracing how the codebase came to be.

The diary is per-project and lives in `.dev-diary/` at the project root, gitignored by default. Narrative entries are written by this skill. Raw session events are captured automatically by Claude Code hooks to `.dev-diary/.events.jsonl` — the audit trail; the markdown entries are the narrative.

## When to invoke

Invoke this skill in three situations:

1. **The user types `/diary`.** Synthesize a diary entry from the current session.
2. **A significant pivot or learning moment occurs mid-session.** When direction changes notably or a surprising lesson emerges that would be lost by session end, capture it as a short entry without waiting for the user to ask. Examples: realizing the initial approach is wrong and rewriting, discovering a library behaves differently than expected, the user correcting course after several wrong attempts.
3. **Starting work on an unfamiliar area.** Check `.dev-diary/` for entries relevant to the area before beginning. Read what's there. Surface relevant findings briefly to the user before proceeding.

Do **not** invoke for routine, uneventful work. Successful test runs, mechanical edits matching established patterns, and execution of well-trodden paths do not warrant entries. The bar is: *would a future agent benefit from knowing this, beyond what the code itself records?* If no, skip.

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

When invoked to write an entry:

1. **Read the raw events for this session.** Open `.dev-diary/.events.jsonl` and read events from the current session. The session ID is in the hook envelope; if running without that context, use the most recent events (the file is append-only and chronological). The events tell you *what* happened with timestamps; the conversation context tells you *why* and *how*. Use both. For the events.jsonl schema, see `references/events-schema.md`.

2. **Decide whether this session warrants an entry.** Apply the bar from "When to invoke." If the session was routine — reading files, answering questions, no substantive code change or decision — tell the user briefly that the session didn't produce diary-worthy content and write nothing. A diary with no entry is better than a diary with filler.

3. **Choose a slug.** Two to five lowercase words separated by hyphens, naming the substance of the work. Good: `shishi-bucket-event-accumulator`, `executor-uid-isolation-pivot`. Bad: `session-update`, `progress`, `work-done`.

4. **Construct the filename:** `.dev-diary/YYYY-MM-DD-<slug>.md`. Use today's date. If a file with that name exists, append `-2`, `-3`, etc.

5. **Write the entry.** Apply the voice rules. Walk the work chronologically. Surface reversals and decisions explicitly. End with one short lesson sentence only if genuinely earned.

6. **Save the file and tell the user briefly.** One sentence: "Wrote `.dev-diary/2026-05-18-shishi-bucket-event-accumulator.md`." No further commentary.

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

## Capture side: hooks

The capture side runs as Claude Code hooks defined in `.claude/settings.json`. They append normalized events to `.events.jsonl` as the session proceeds. The capture script is `scripts/log-event.sh` (inside this skill directory) and handles all event kinds.

For the hook configuration and install steps, see `references/hooks-setup.md`.

The capture side is independent of synthesis. Even if `/diary` is never invoked, the events log accumulates and stays available for later reconstruction.
