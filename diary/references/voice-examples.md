# Voice Examples

Examples of diary entries in the target voice. Each illustrates a different session shape. Read these to internalize the voice before writing a new entry.

These are **example entries**, not real events. Use them as references for style, not for factual claims about the project.

---

## Example 1 — A pivot with a clear lesson

*Filename: `2026-05-18-shishi-bucket-event-accumulator.md`*

Started on the shishi bucket — content-aware event accumulator for tmuxllm. First instinct was a ring buffer with fixed-size window. Wrote about eighty lines and hit a wall: when events arrive in bursts, the window drops context I want to keep, because relevance isn't correlated with recency. Tried weighting by token count next — keep the heavy stuff, drop the rest. Broke on a different axis: short events can be high-relevance (a stack-trace summary line), long events can be padding (a config dump). Token count isn't a relevance signal. Pivoted to a content-aware filter at ingestion. Worked in about two hours after the pivot. Token count is a tempting proxy for relevance and it's wrong.

---

## Example 2 — Sub-agent coordination and surprise

*Filename: `2026-05-14-context-compiler-pipeline.md`*

Spent the morning wiring up the context compiler pipeline. Delegated the embedding step to a sub-agent because it needed to read a lot of files and I didn't want to balloon my own context. The sub-agent came back with timings that didn't match what I'd assumed: batch embedding was three times slower than I'd budgeted because the chunk size was wrong, not because the API was slow. I'd been about to optimize the wrong thing. Rewrote the chunker to emit larger but fewer chunks; reran the sub-agent; numbers came back inside budget. Most of the day was making the bug visible — fixing it took twenty minutes. Sub-agents are useful for fanning out reads even when the work is short, because the timings come back clean.

---

## Example 3 — User correction mid-session

*Filename: `2026-05-12-fleetvibes-tenant-sharding.md`*

Was working on the FleetVibes tenant sharding and went down a path of building a hash-based shard router in the application layer. About forty minutes in, the user pushed back: PostgreSQL has table partitioning built in, why am I doing this in application code? They were right. I'd been pattern-matching to a previous project that used a database without native partitioning, and hadn't checked. Threw out the router code, set up declarative partitioning by tenant_id, hooked the existing queries up without changes. The migration is now one DDL file instead of three hundred lines of routing logic. When the database can do something natively, check that first before writing it.

---

## Example 4 — A small learning entry with no code

*Filename: `2026-05-09-skill-creator-discovery.md`*

Was reading the Claude Code docs to figure out where slash commands live and noticed `.claude/commands/` is now the legacy format — the recommended path is `.claude/skills/<name>/SKILL.md`, which gets you slash command invocation *and* autonomous skill activation from the same file. Means a skill and a slash command aren't two things to build anymore. Filing this for the diary skill itself, and for anything else that wanted to be a /command. One file, three triggers (manual, autonomous, hook) beats three artifacts.

---

## Example 5 — An attempted thing that didn't ship, kept for the record

*Filename: `2026-05-07-executor-docker-in-docker.md`*

Tried Docker-in-Docker for the playground executor. The idea: each sandbox runs in its own throwaway container, the host runs the orchestrator. Got it working in about an hour but the cold-start was 800ms per run, which is unusable for the playground's UX. Looked at warm pools next, then realized the actual security boundary I needed was process isolation, not container isolation — which is much cheaper. Pivoted to per-execution Unix UIDs in a shared container. Cold-start dropped under 50ms. Keeping this entry because the next time I reach for DinD as a sandbox primitive, I want to be reminded that the answer was almost always "the cheaper boundary is enough."

---

## What these examples have in common

- One paragraph each. No headers, no bullets inside the entry.
- First person, past tense.
- Specific names — `shishi bucket`, `FleetVibes`, `Docker-in-Docker`, `tenant_id`. Not "the bucket," not "the system."
- The reversal is named explicitly: "tried X, broke at Y, pivoted to Z."
- One sentence at the end carries the lesson. No bold, no label, just a sentence.
- The lesson is concrete and falsifiable, not a platitude. "Token count is a tempting proxy for relevance and it's wrong" — not "code carefully."

## What to avoid

- "Today I worked on the bucket and made good progress." — vague, no information.
- "## Context\n## What I tried\n## Result" — sections kill the narrative.
- "I successfully implemented an elegant solution." — self-praise; the diary records facts.
- A six-paragraph entry recapping every file touched. Compress to what matters. The events.jsonl has the granular record.
