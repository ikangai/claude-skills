# Card schema

A card is a JSON object inside the `kanban-cards` array. The CLI scripts create, read, and modify these objects; the browser-side renderer reads the same array and renders the columns. There is no separate database.

## Shape

```json
{
  "id": "2026-05-20-refactor-auth-to-use-middleware",
  "title": "Refactor auth to use middleware pattern",
  "description": "Current auth uses inline checks; consolidate into express middleware",
  "status": "in_progress",
  "priority": "high",
  "tags": ["auth", "refactor"],
  "assigned_to": "alpha",
  "claimed_at": "2026-05-20T09:55:27Z",
  "model": "Sonnet",
  "tokens": 42100,
  "effort_seconds": 1620,
  "effort_started_at": null,
  "notes": [
    { "ts": "2026-05-20T10:12:04Z", "by": "alpha", "text": "Picked express, not koa. Smaller surface area." }
  ],
  "subtasks": [],
  "created_at": "2026-05-20T09:55:18Z"
}
```

## Fields

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `id` | string | yes | (auto) | Unique within the board. Default `YYYY-MM-DD-<slug>`. Override via `add.sh --id=…`. |
| `title` | string | yes | — | What the card is about, in one short line. |
| `description` | string | no | — | Multi-line context, intent, links. Rendered in the card detail. |
| `status` | enum | yes | `todo` | One of `todo`, `in_progress`, `review`, `done`. |
| `priority` | enum | no | `none` | One of `high`, `medium`, `low`, `none`. Drives the left-border color. |
| `tags` | string[] | no | `[]` | Free-form labels. Shown as chips on the card. |
| `assigned_to` | string \| null | no | `null` | Agent identity. Set by `claim.sh` (self) or `assign.sh` (other). |
| `claimed_at` | ISO timestamp \| null | no | `null` | When the current claim or assignment was made. |
| `model` | string \| null | no | `null` | The model that worked the card — free-form so any vendor fits (`Sonnet`, `Opus 4.8`, `GPT-5`, `Gemini`, `local:qwen`). Set by `claim.sh --model=` or `$KANBAN_MODEL`. |
| `tokens` | int \| null | no | `null` | Total tokens the task needed. Absolute count (not additive). Set via `move.sh --tokens=`, typically on the move to review/done. |
| `effort_seconds` | int | no | `0` | Banked wall-clock the card has spent in the `in_progress` column, summed across every stint. Accounted automatically. See [Effort accounting](#effort-accounting). |
| `effort_started_at` | ISO timestamp \| null | no | `null` | When the *current* in_progress stint began; `null` whenever the card is not in_progress. The live clock. |
| `notes` | Note[] | no | `[]` | Append-only log; see schema below. |
| `subtasks` | string[] | no | `[]` | Reserved for v1; v0 leaves this empty. |
| `created_at` | ISO timestamp | yes | (auto) | UTC, set on creation. |

### Note shape

```json
{ "ts": "2026-05-20T10:12:04Z", "by": "alpha", "text": "…" }
```

| Field | Type | Notes |
|-------|------|-------|
| `ts` | ISO timestamp | UTC, set on append. |
| `by` | string | Same agent-identity resolution as `assigned_to`. May be empty when no identity is available. |
| `text` | string | Free-form. Material decisions, dead-ends, pivots. |

## Status semantics

- **`todo`** — claimable. `move.sh … todo` clears `assigned_to` and `claimed_at` so anyone can pick it up.
- **`in_progress`** — actively being worked. `claim.sh` moves a card here by default. Conflicts on claim (different agent already assigned) exit 2.
- **`review`** — work is done from Claude's perspective; the human should glance and approve, comment, or kick back to `in_progress`. The assignment is preserved so it's visible who produced the work.
- **`done`** — finished and accepted. Assignment is preserved so credit is visible.

## Effort accounting

`effort_seconds` measures **active** time — the wall-clock a card spends in the `in_progress` column, not the raw span from claim to done. A card that's claimed Monday and finished Friday but only worked for 30 minutes reads `30m`, not four days.

Two fields carry it. The clock **starts** when a card enters `in_progress` (`effort_started_at` is stamped) and **banks** when it leaves (`effort_seconds += now − effort_started_at`, then `effort_started_at` is cleared). Moving through review and back to in_progress resumes it; the stints add up. Transitions that don't touch `in_progress` (e.g. `todo → review`, `review → done`) leave the clock alone.

The total effort shown anywhere is `effort_seconds + (now − effort_started_at)` when the clock is running, so a card actively in progress shows a live figure (the board and `list.sh` mark a running clock — a blue chip in the browser, a trailing `*` in the terminal).

This logic lives in one place per surface so the CLI and browser never disagree: `apply_effort_transition` in `scripts/rwa_splice.py` (fired by any status-changing `update`, so `move`, `claim`, and `assign --move` all account identically) and its mirror `applyEffortTransition` in `seeds/kanban-body.html` (fired when a human drags a card, and preserved through the file↔browser reconcile).

## Id format

The default `YYYY-MM-DD-<slug>` format gives:

- Chronological ordering when sorting by id.
- Human-readable references (`2026-05-20-flaky-test-investigation`) that survive being copy-pasted into commit messages, diary entries, or chat.
- Stable uniqueness within a project — the date-prefix makes accidental collisions on the same day rare, and collisions across days impossible by construction.

If you need to override (because two cards started the same day with the same slug), pass `--id=2026-05-20-flaky-test-investigation-2` or similar.

## Why JSON inside HTML

Every alternative considered (a separate `.json` sidecar, SQLite, a server) violated the rwa premise: the file should be the database, the runtime, and what you share. Embedding the cards array as `<script type="application/json" id="kanban-cards">…</script>` inside the document body keeps the rwa contract — one self-contained `.html` you can email, USB-stick, or commit to git — while giving Claude a clean JSON region to splice without parsing HTML.

The trade-off is that `</script>`, backticks, `${`, and backslashes inside card text need careful escaping when the JSON is written. The CLI handles this; see `scripts/rwa_splice.py` for the two layers of escape (JSON-internal `</` → `<\/` to protect the inner script tag, then `escapeTL` to protect the outer template literal). The browser sees clean JSON, the CLI reads it back identically, and the file on disk never produces a parse error.
