---
name: kanban
description: Per-project visual kanban board for Claude Code, backed by a self-contained rwa (rewritable) HTML file at .kanban/board.html. Cards have status (todo/in_progress/review/done), priority, tags, assignee, and notes. Use this skill when the user invokes /kanban, when starting work and the user references "the board" or "the kanban", when needing to know what other agents are working on, or when a piece of work warrants becoming a card. The skill drives a small Bash CLI surface — init/add/claim/move/note/list — so reads and writes are atomic and structured. The board file also opens directly in any modern browser; the human drags cards and presses ⌘S to commit.
---

# Kanban

## Overview

A per-project kanban board that doubles as a human-readable HTML file. The board lives at `.kanban/board.html` and is a [rewritable](https://github.com/ikangai/rewritable) container — a single self-contained `.html` file that renders, stores, and rewrites itself in place. Cards are JSON inside the document; the runtime renders them as draggable column cards. The human opens the file in a browser to see the board, drag cards between columns, and press ⌘S to persist; Claude operates the same data through a small Bash CLI.

Two surfaces, one file, same source of truth.

### When to invoke

- **The user says `/kanban`** with no further detail → run `kanban list` and report the board state.
- **The user references "the board", "my kanban", "what's on the board", "what am I working on"** → invoke `kanban list`.
- **The user gives a task that's substantive enough to track** (a feature, a bug, a refactor, a non-trivial investigation) → propose adding it as a card via `kanban add`. Confirm before adding unless the user said "add it to the board" or similar.
- **The user starts work in a multi-instance setup** (worktrees, multiple terminals) → `kanban list --status=in_progress` to see what other agents are already doing; consider what to claim.
- **Mid-session, a task you're working on is real enough to be on the board** → ask the user "should I add this to the board?" before adding.

Do not invoke for trivial one-shot questions, code-review feedback, or anything that won't outlive the session. The board is for work that takes more than a few minutes and that the user (or another agent) might come back to.

### How agents and humans share the board

- **Claude operates the board through the CLI** scripts in this skill's `scripts/` directory. Each script writes the `.kanban/board.html` file atomically.
- **The human opens `.kanban/board.html` in a browser** to see the visual board, drag cards between columns, and ⌘S to commit. The browser polls the file every ~2.5s for changes; CLI edits flow into open tabs automatically (see `references/browser-side.md`).
- **Multi-instance setup**: each Claude instance has its own assignee identity. Set `KANBAN_AGENT_NAME=alpha` (or `beta`, `review`, etc.) in each worktree's shell to get friendly names; otherwise the skill falls back to a short hash of `$CLAUDE_SESSION_ID`.

## The CLI surface

All scripts live in `scripts/` inside this skill directory. Invoke them via `bash` with the absolute path. The scripts read `$CLAUDE_PROJECT_DIR` (or the current working directory as a fallback) to locate `.kanban/board.html`.

### `init.sh` — bootstrap the board

```bash
bash $CLAUDE_SKILL_DIR/scripts/init.sh
```

Creates `.kanban/board.html` from a fresh rwa container and adds `.kanban/` to `.gitignore`. Idempotent — running again on an existing board is a no-op. Requires Node.js ≥ 20.16 (uses `npx rewritable@latest new`).

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
bash $CLAUDE_SKILL_DIR/scripts/claim.sh <card-id> [--agent=<name>] [--no-move] [--force]
```

Sets `assigned_to` + `claimed_at` and (unless `--no-move`) moves status to `in_progress`. Agent identity resolves from: `--agent` flag → `$KANBAN_AGENT_NAME` env var → 8-char hash of `$CLAUDE_SESSION_ID` → literal `agent`.

Exit code 2 if the card is already claimed by a different agent (use `--force` to take over). Use this exit-code check to detect cross-agent contention before doing duplicate work.

### `move.sh` — change a card's status

```bash
bash $CLAUDE_SKILL_DIR/scripts/move.sh <card-id> <status>
```

Status is one of `todo`, `in_progress`, `review`, `done`. Moving to `todo` clears the assignment so another agent can pick it up; moving to `done` preserves it so credit is visible.

### `note.sh` — log a note on a card

```bash
bash $CLAUDE_SKILL_DIR/scripts/note.sh <card-id> "Picked express, not koa — smaller surface."
```

Appends a timestamped, agent-stamped note. Use for material decisions, dead-ends, or anything a future agent picking up the card should know. Don't use for routine commentary.

### `list.sh` — show the board

```bash
bash $CLAUDE_SKILL_DIR/scripts/list.sh                    # all cards, grouped by column
bash $CLAUDE_SKILL_DIR/scripts/list.sh --status=todo      # one column
bash $CLAUDE_SKILL_DIR/scripts/list.sh --agent=alpha      # filter by assignee
bash $CLAUDE_SKILL_DIR/scripts/list.sh --json             # raw JSON
```

Default output is a compact text view suitable for terminal reading. `--json` is for programmatic use (filter cards yourself, count things, etc.). All filters compose.

## Voice and conventions

When invoking the skill conversationally:

- **Be terse on success.** "Added card `2026-05-20-refactor-auth`." or "Moved to in_progress." — one line per operation. Don't restate parameters back.
- **Surface conflicts proactively.** If `claim.sh` exits 2 (already claimed), don't silently retry. Tell the user: "That's already claimed by `beta`. Want me to take over (`--force`), or pick a different card?"
- **Don't auto-create cards aggressively.** Treat card creation like a small commit — propose first, confirm, then add. The exception is when the user says "add it to the board" or "track this" or similar explicit go-ahead.
- **When the user pivots or finishes**, log it. Finishing the work the card represents → `move.sh ... done`. Hitting a dead-end and changing approach → `note.sh ... "tried X, didn't work because Y, pivoting"`. Cards without these accumulations decay into stale status.
- **The board is not a tracker for you** — it's a tracker for the project. Trivial bookkeeping (read this file, run this test) doesn't go on the board.

## Card schema

For the full card JSON shape (fields, defaults, allowed values), see `references/card-schema.md`.

## Browser side

For how the file works as a browser app (drag-and-drop, ⌘S commit, the rwa runtime layer), and what the human sees when they open `.kanban/board.html` directly, see `references/browser-side.md`.

## Prior diary integration

If the [diary skill](https://github.com/ikangai/claude-skills/tree/main/diary) is also installed on the project (`.dev-diary/` exists), diary entries can reference cards by id, and `kanban list` output can mention recent diary entries that touched the same area. v0 doesn't enforce this — it's a convention to maintain by hand.
