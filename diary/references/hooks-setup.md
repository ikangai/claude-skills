# Hooks Setup

The diary's capture side uses Claude Code hooks to append events to `.dev-diary/.events.jsonl` as the session runs. This document gives the exact configuration and explains each hook.

## Prerequisites

- `jq` on PATH. macOS: `brew install jq`. Debian/Ubuntu: `sudo apt-get install jq`.
- The skill installed at `.claude/skills/diary/` in the project. The capture script is at `.claude/skills/diary/scripts/log-event.sh` and must be executable (`chmod +x`).

## settings.json snippet

Add the following to the project's `.claude/settings.json` under the top-level `hooks` key. If the file doesn't exist yet, create it with this content. If it does and already has a `hooks` block, merge the arrays for each event name (do not overwrite — other hooks may already be installed).

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/log-event.sh\" edit",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/log-event.sh\" bash",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/log-event.sh\" prompt",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/log-event.sh\" subagent",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/log-event.sh\" stop",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## What each hook does

- **`PostToolUse` / `Write|Edit|MultiEdit`** — captures state-changing file edits. Records the tool name and file path. Skips the file contents (they're in the codebase already).
- **`PostToolUse` / `Bash`** — captures shell commands and their exit codes. Truncates long commands to 500 chars. The exit code is the most useful field; failures are the moments worth narrating later.
- **`UserPromptSubmit`** — captures user prompts (truncated to 500 chars). User feedback and course-corrections are part of the narrative.
- **`SubagentStop`** — captures the final message from any sub-agent task. Useful when delegating work and the sub-agent returns something the synthesis should know about.
- **`Stop`** — captures Claude's final message at the end of each turn. Light record of how the session's beats were paced. Optional; can be removed if too noisy.

There is deliberately no `SessionEnd` hook auto-triggering synthesis. Inline synthesis happens when the user types `/diary` — that's when full session context is still available. Auto-triggering at SessionEnd would either run in a stripped-context subprocess (poor prose) or fire after the main session is gone.

## Read-only operations are intentionally not captured

`Read`, `Grep`, `Glob`, and `LS` are reconnaissance, not narrative. They get filtered out by the `matcher` in `PostToolUse`. Capturing them would bury the events.jsonl in noise and dilute the signal during synthesis.

## Failure modes

The capture script is defensive and always exits 0. If `jq` is missing, it writes a minimal event with `"error": "jq_not_installed"` so the missing dependency is visible in the log without breaking the session. If the diary directory can't be created, it exits silently. A misconfigured hook should never block a Claude Code session.

## Verifying it works

1. After installing, start a Claude Code session in the project and make any small edit.
2. Run `ls .dev-diary/`. There should be a `.events.jsonl` file.
3. Run `tail -1 .dev-diary/.events.jsonl | jq .`. The most recent event should match the edit.

If `.dev-diary/` doesn't appear, the most likely cause is that `$CLAUDE_PROJECT_DIR` is unset in the hook context — check the Claude Code version (the variable is available from v2.1.9+) or replace the variable with the absolute project path in the hook command.

## Gitignore

Add this line to `.gitignore` so the diary doesn't get committed by default:

```
.dev-diary/
```

If/when the project is ready to commit the diary (e.g., open-sourcing the project and wanting the development history along with it), remove the line.
