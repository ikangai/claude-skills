# Events Schema

Format of `.dev-diary/.events.jsonl`. One JSON object per line, append-only, chronological. Written by `scripts/log-event.sh` from Claude Code hooks.

## Common fields

Every event has at minimum:

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string | ISO 8601 UTC timestamp, e.g. `2026-05-18T14:32:11Z` |
| `kind` | string | Event kind. One of: `edit`, `bash`, `prompt`, `subagent`, `stop` |
| `session_id` | string | Claude Code session ID (matches the active session) |
| `cwd` | string | Working directory at event time |

Fields are omitted when empty rather than written as `null` or `""`. A field's presence carries information.

## Kind-specific fields

### `edit`

Fires after `Write`, `Edit`, or `MultiEdit` tool calls. Captures what file changed, not the content (the content is in the codebase).

| Field | Type | Description |
|-------|------|-------------|
| `tool` | string | `Write`, `Edit`, or `MultiEdit` |
| `file_path` | string | Absolute path to the file that was edited |

### `bash`

Fires after `Bash` tool calls. The most useful field for the narrative is `exit_code` — failed commands are usually the moments worth retelling.

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | The shell command, truncated to 500 chars |
| `exit_code` | number | Exit code of the command |
| `description` | string | The description Claude attached to the bash call |

### `prompt`

Fires when the user submits a prompt. Captures user feedback, corrections, and direction.

| Field | Type | Description |
|-------|------|-------------|
| `prompt` | string | The user's prompt text, truncated to 500 chars |

### `subagent`

Fires when a sub-agent task completes. Captures the final message from the sub-agent.

| Field | Type | Description |
|-------|------|-------------|
| `last_message` | string | The sub-agent's final message, truncated to 500 chars |

### `stop`

Fires when the main agent finishes a turn. Captures the final message of the turn.

| Field | Type | Description |
|-------|------|-------------|
| `last_message` | string | Claude's final message of the turn, truncated to 500 chars |

## Error events

If the capture script fails to parse or process a hook payload, it writes a minimal event with an `error` field:

```json
{"ts":"2026-05-18T14:32:11Z","kind":"edit","error":"jq_not_installed"}
```

Known error values:

- `jq_not_installed` — `jq` is missing from PATH. Install it to get full event detail.
- `jq_parse_failed` — jq processed input but produced empty output. Rare; usually indicates a hook payload shape change.

Error events still count as events at that timestamp and kind. They're useful as anomaly markers during synthesis ("something happened, but the details didn't make it into the log").

## Reading events during synthesis

To read events for the current session, filter by `session_id`. The session ID is available in the hook envelope when the `/diary` skill is invoked from a hook, or via the `$CLAUDE_SESSION_ID` environment variable in the active session.

Example: read all events from the current session using jq:

```bash
jq -c --arg sid "$CLAUDE_SESSION_ID" 'select(.session_id == $sid)' .dev-diary/.events.jsonl
```

If `$CLAUDE_SESSION_ID` is unavailable, the most recent events in the file are almost certainly from the active session — the file is append-only and chronological. Use the last N events or the last group with a single `session_id`.

## Example session

A short session that resulted in one pivot:

```json
{"ts":"2026-05-18T14:30:02Z","kind":"prompt","session_id":"sess_x","cwd":"/proj","prompt":"add the shishi bucket implementation"}
{"ts":"2026-05-18T14:31:15Z","kind":"edit","session_id":"sess_x","cwd":"/proj","tool":"Write","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T14:33:48Z","kind":"bash","session_id":"sess_x","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":1,"description":"Run the bucket tests"}
{"ts":"2026-05-18T14:35:21Z","kind":"prompt","session_id":"sess_x","cwd":"/proj","prompt":"the ring buffer drops too much, can we weight by relevance"}
{"ts":"2026-05-18T14:42:09Z","kind":"edit","session_id":"sess_x","cwd":"/proj","tool":"Edit","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T14:43:32Z","kind":"bash","session_id":"sess_x","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":0,"description":"Re-run the bucket tests"}
{"ts":"2026-05-18T14:45:00Z","kind":"prompt","session_id":"sess_x","cwd":"/proj","prompt":"/diary"}
```

Reading this, the shape of the session is visible: prompt → edit → test failure → user steered to relevance weighting → edit → test pass → /diary. The synthesis turns this into the narrative entry.
