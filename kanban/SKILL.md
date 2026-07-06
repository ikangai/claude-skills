---
name: kanban
description: Per-project visual kanban board for Claude Code, backed by a self-contained rwa (rewritable) HTML file at .kanban/board.html. Cards have status (todo/in_progress/review/done), priority, tags, assignee, and notes. Use this skill ambiently — whenever a project has a board, silently keep it in sync with the work: add cards for substantive new tasks, claim cards when starting work, move them on completion or pivot, assign to other agents/humans on handoff. Also invoke explicitly when the user says /kanban, references "the board", or asks what's being worked on. The skill drives a Bash CLI — init/add/claim/move/note/assign/list — so reads and writes are atomic and structured. The board file also opens directly in any modern browser; the human drags cards and presses ⌘S to commit.
---

# Kanban

## Overview

A per-project kanban board that doubles as a human-readable HTML file. The board lives at `.kanban/board.html` and is a [rewritable](https://github.com/ikangai/rewritable) container — a single self-contained `.html` file that renders, stores, and rewrites itself in place. Cards are JSON inside the document; the runtime renders them as draggable column cards. The human opens the file in a browser to see the board, drag cards between columns, and press ⌘S to persist; Claude operates the same data through a small Bash CLI.

Two surfaces, one file, same source of truth.

### When to invoke

The skill runs in two modes: **explicit** (user asks) and **ambient** (you operate the board as a side-effect of doing the work). The board is for work that takes more than a few minutes and that the user or another agent might come back to — both modes share that bar.

**Explicit triggers:**

- **The user says `/kanban`** with no further detail → run `kanban list` and report the board state.
- **The user references "the board", "my kanban", "what's on the board", "what am I working on"** → invoke `kanban list`.
- **The user asks who's working on what** → `kanban list --status=in_progress`.

**Ambient triggers** (no permission needed when the project already has a `.kanban/board.html`):

- **A substantive new task appears in the conversation** → `add.sh` then `claim.sh --model=<you>` in one step. Acknowledge with one line: "Added & claimed `<id>`." See [Ambient management](#ambient-management) for what counts as substantive.
- **You start work that's already on the board** → `claim.sh <id> --model=<you>` (stamps your model and starts the effort clock). If it's already claimed by another agent (exit 2), surface the conflict instead of silently retrying.
- **You finish the work on a card** → `move.sh <id> review` (or `done` if the user has already accepted it), adding `--tokens=<n>` if you know the token count. Don't leave finished work in `in_progress`.
- **You pivot, hit a wall, or hand off** → `note.sh` for the why, then `move.sh ... todo` or `assign.sh ... <other>` as appropriate.
- **Starting a session in a multi-instance setup** (worktrees, multiple terminals) → `kanban list --status=in_progress` first to avoid stepping on another agent's work.

**Don't invoke** for trivial one-shot questions, code-review feedback, or anything that won't outlive the session — those aren't board material. Also don't auto-init: if a project has no `.kanban/` directory yet, mention it once when substantive work appears ("There's no board here — want me to `kanban init`?") and wait for the go-ahead.

### How agents and humans share the board

- **Claude operates the board through the CLI** scripts in this skill's `scripts/` directory. Each script writes the `.kanban/board.html` file atomically.
- **The human opens `.kanban/board.html` in a browser** to see the visual board, drag cards between columns, and ⌘S to commit. The board reconciles the file on every load, so a reload — or the `↻ sync from file` button — shows the latest CLI edits (uncommitted local drags are preserved). Live auto-refresh without a reload is best-effort: it works once the human has pressed ⌘S, or when the board is served over http(s), but not on a fresh `file://` open, where Chrome blocks `fetch()` of `file://` URLs (see `references/browser-side.md`).
- **Multi-instance setup**: each Claude instance has its own assignee identity. Set `KANBAN_AGENT_NAME=alpha` (or `beta`, `review`, etc.) in each worktree's shell to get friendly names; otherwise the skill falls back to a short hash of `$CLAUDE_SESSION_ID`.

## The CLI surface

All scripts live in `scripts/` inside this skill directory. Invoke them via `bash` with the absolute path. The scripts read `$CLAUDE_PROJECT_DIR` (or the current working directory as a fallback) to locate `.kanban/board.html`.

### `init.sh` — bootstrap the board

```bash
bash $CLAUDE_SKILL_DIR/scripts/init.sh
```

Creates `.kanban/board.html` from a fresh rwa container and adds `.kanban/` to `.gitignore`. Idempotent — running again on an existing board is a no-op. Requires Node.js ≥ 20.16 (uses `npx rewritable@latest new`).

### `upgrade.sh` — rebuild an existing board on the current seed

```bash
bash $CLAUDE_SKILL_DIR/scripts/upgrade.sh [path/to/board.html] [--force]
```

Deployed boards never pick up seed fixes on their own — the CLI splices only the cards JSON, so a board's runtime and body stay whatever generation they were created from. `upgrade.sh` reads the cards out of an existing board, rebuilds it from the current seed (fresh container, new document UUID so stale browser IndexedDB can't shadow the new body), splices the cards back in, verifies the round-trip, and atomically replaces the file, leaving a timestamped `.bak-` backup beside it. Defaults to `$CLAUDE_PROJECT_DIR/.kanban/board.html`; already-current boards are a no-op unless `--force`. Run it when a board misbehaves in ways the current seed has already fixed.

### `add.sh` — create a card

```bash
bash $CLAUDE_SKILL_DIR/scripts/add.sh "Refactor auth to use middleware pattern" \
  --priority=high \
  --tags=auth,refactor \
  --description="Current auth uses inline checks; consolidate into express middleware"
```

Required: the title (positional). Optional flags: `--priority` (high|medium|low|none, default `none`), `--tags` (comma-separated), `--description`, `--id` (override the auto-generated id).

Prints the new card id on stdout. Default id is `YYYY-MM-DD-<slug>` where slug is derived from the title. Status defaults to `todo`.

### `claim.sh` — claim a card

```bash
bash $CLAUDE_SKILL_DIR/scripts/claim.sh <card-id> [--agent=<name>] [--model=<name>] [--no-move] [--force]
```

Sets `assigned_to` + `claimed_at` and (unless `--no-move`) moves status to `in_progress`. Agent identity resolves from: `--agent` flag → `$KANBAN_AGENT_NAME` env var → 8-char hash of `$CLAUDE_SESSION_ID` → literal `agent`.

`--model=<name>` stamps the model working the card — free-form, so any vendor fits (`--model="Opus 4.8"`, `Sonnet`, `GPT-5`, `Gemini`, `local:qwen`). Falls back to `$KANBAN_MODEL` if the flag is omitted. **When you claim a card, pass your own model** (or export `KANBAN_MODEL` once per session) so the board records who did the work. Moving the card to `in_progress` also starts its effort clock (see below).

Exit code 2 if the card is already claimed by a different agent (use `--force` to take over). Use this exit-code check to detect cross-agent contention before doing duplicate work.

### `move.sh` — change a card's status

```bash
bash $CLAUDE_SKILL_DIR/scripts/move.sh <card-id> <status> [--tokens=<n>]
```

Status is one of `todo`, `in_progress`, `review`, `done`. Moving to `todo` clears the assignment so another agent can pick it up; moving to `done` preserves it so credit is visible.

`--tokens=<n>` records the total tokens the task needed (absolute count, not additive) — stamp it on the move to `review`/`done` when you know the figure, e.g. `move.sh <id> done --tokens=42100`.

**Effort is tracked automatically.** Each status change banks or starts the card's `in_progress` clock, so `effort_seconds` accumulates the active time a card spends being worked — across pauses in review and back — without any flag. The board and `kanban list` show `model / effort / tokens` per card (a running clock is flagged live). You don't manage effort by hand; just move cards honestly and pass `--model` / `--tokens` when you have them. See `references/card-schema.md` → *Effort accounting*.

### `note.sh` — log a note on a card

```bash
bash $CLAUDE_SKILL_DIR/scripts/note.sh <card-id> "Picked express, not koa — smaller surface."
```

Appends a timestamped, agent-stamped note. Use for material decisions, dead-ends, or anything a future agent picking up the card should know. Don't use for routine commentary.

### `assign.sh` — hand a card to someone else

```bash
bash $CLAUDE_SKILL_DIR/scripts/assign.sh <card-id> <agent-name> [--move=<status>]
```

Sets `assigned_to` to an arbitrary name (free-form string, no user directory). Use for explicit handoff to *another* agent or human — distinct from `claim.sh`, which is "I'm taking this." Does not change status by default; pass `--move=review` (or other status) when the handoff also implies a column change, e.g. assigning to a human for review.

### `list.sh` — show the board

```bash
bash $CLAUDE_SKILL_DIR/scripts/list.sh                    # all cards, grouped by column
bash $CLAUDE_SKILL_DIR/scripts/list.sh --status=todo      # one column
bash $CLAUDE_SKILL_DIR/scripts/list.sh --agent=alpha      # filter by assignee
bash $CLAUDE_SKILL_DIR/scripts/list.sh --json             # raw JSON
```

Default output is a compact text view suitable for terminal reading. `--json` is for programmatic use (filter cards yourself, count things, etc.). All filters compose.

## Ambient management

The board should reflect the work without being asked. When a project has a `.kanban/board.html`, operate it as a passive side-effect of normal conversation — the same way you'd run tests or save files. The user shouldn't have to direct each operation, and you shouldn't pause to ask permission for routine updates.

The cost of an update is one terse line ("Added `2026-05-20-refactor-auth`."); the cost of a missed update is a stale board the user can't trust. Lean toward updating.

### When to create a card

Auto-add when the user describes work that is all three of:

- **Substantive** — more than a few minutes of effort, more than a one-file change, or requires research.
- **Named** — has a clear deliverable you could point to ("the auth refactor", not "let me think about auth").
- **Persistent** — likely to outlive this single response.

Skip when work is one-shot ("what does this function do?"), trivial ("rename this variable"), or part of your own loop (running tests, reading files to plan).

If intent is genuinely ambiguous — "explore options for X", "look into Y a bit" — ask once: "Want this on the board?" Don't add silently for work that may not happen.

When the card is for work you're about to start, `add` then immediately `claim` it in the same step. Don't leave a freshly-created card in `todo` if you're picking it up right now — that's two state changes for one event.

### When to change a card's status

- **`todo` → `in_progress`**: when you start work. Use `claim.sh`, not `move.sh` — claim sets the assignment in the same operation.
- **`in_progress` → `review`**: when implementation is complete and the user typically validates this kind of work. Most coding tasks land here, not `done`.
- **`in_progress` → `done`**: when the user has already accepted the result ("looks good", "ship it") or for trivial cards where review would be theatre.
- **`review` → `done`**: when the user accepts what was in review.
- **`review` → `in_progress`**: when the user kicks back with changes.
- **`in_progress` → `todo`**: when you're abandoning the approach but the work itself is still wanted. `move.sh ... todo` clears the assignment so another agent can pick it up. Pair with `note.sh` explaining the pivot.

### When to add a note

Notes are for things a future reader — you in a week, or another agent picking up the card — wouldn't know from the code alone:

- A non-obvious technical decision and why ("picked express, not koa — smaller surface").
- A dead-end and what was learned ("tried Y, didn't work because Z, pivoting to W").
- A constraint you discovered ("rate-limited at 100rps, needs throttling").
- Handoff context for the next agent ("backend done; blocked on schema sign-off from the data team").

Don't note routine progress ("read X", "ran tests"). The card's status already communicates that work is happening.

### When to assign to someone else

`claim.sh` is the "I'm taking this" verb. `assign.sh` is the "X is taking this" verb — explicit handoff to another agent or human. Use `assign.sh` (not `claim --agent=`) when the user says any of:

- "Let alpha take this" / "this is beta's"
- "Hand this off to <name>" / "<name> should pick this up"
- "This needs <name>'s eyes" / "for review by <name>" (pair with `--move=review`)

**On who you can assign to:** the skill has no user directory — `assigned_to` is a free-form string. Practical rules:

- Use names that actually appear in the conversation. Don't invent assignees.
- Match the casing of existing assignees on the board. If `alpha` exists, don't create `Alpha`. Check `kanban list --json` if unsure.
- For humans without a known handle, ask once: "Who should I assign this to?" Or move the card back to `todo` (clears assignment) if the human will figure it out from the board.
- The browser renders whatever string you set as a chip — so `martin`, `alpha`, `human:reviewer`, `data-team` all render fine.

### Voice and elegance

- **One line per update.** "Added `<id>`." "Moved to review." "Assigned to alpha." Never restate the title or description — the user already typed them and can see the board.
- **Batch related updates.** Three cards from one user instruction → one acknowledgement: "Added 3 cards: `a`, `b`, `c`." Same for moves.
- **Stay silent on coupled operations.** Creating + immediately claiming is one event; one line. Moving + assigning on a single handoff is one event; one line.
- **Surface conflicts proactively.** If `claim.sh` exits 2, say so once and ask: take over with `--force`, or pick a different card?
- **Don't backfill the board.** Already-completed work doesn't get retroactive cards unless the user asks.
- **Respect "don't track this."** Honor explicit opt-outs.
- **The board is not a tracker for *you*** — it's a tracker for the project. Trivial bookkeeping (read this file, run this test) doesn't go on the board.

## Card schema

For the full card JSON shape (fields, defaults, allowed values), see `references/card-schema.md`.

## Browser side

For how the file works as a browser app (drag-and-drop, ⌘S commit, the rwa runtime layer), and what the human sees when they open `.kanban/board.html` directly, see `references/browser-side.md`.

## Prior diary integration

If the [diary skill](https://github.com/ikangai/claude-skills/tree/main/diary) is also installed on the project (`.dev-diary/` exists), diary entries can reference cards by id, and `kanban list` output can mention recent diary entries that touched the same area. v0 doesn't enforce this — it's a convention to maintain by hand.
