# Hooks Setup

The diary's capture side uses Claude Code hooks to append events to `.dev-diary/.events.jsonl` as the session runs. This document gives the exact configuration and explains each hook.

## Prerequisites

- `jq` on PATH. macOS: `brew install jq`. Debian/Ubuntu: `sudo apt-get install jq`.
- The skill installed at `.claude/skills/diary/` in the project. The capture script (`scripts/log-event.sh`) and the auto-synthesis script (`scripts/maybe-synthesize.sh`) must both be executable (`chmod +x`).

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
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/skills/diary/scripts/maybe-synthesize.sh\"",
            "timeout": 300
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
- **`Stop`** — runs two commands per turn end:
  - `log-event.sh stop` captures Claude's final message at the end of each turn (light record of the session's beats).
  - `maybe-synthesize.sh` checks whether the session has accumulated substantive work and no entry has been written yet; if so, it synthesizes the entry via the detected backend (a suitable local model, else headless Sonnet), or blocks Stop with a directive asking Claude to apply the synthesis workflow when synthesis fails or `DIARY_SYNTH=claude` is set. Its `timeout` is 300, not 5: local generation plus a JIT model load takes minutes, not seconds.

## Auto-synthesis via the Stop hook

`maybe-synthesize.sh` is what makes diary entries write themselves. By default it synthesizes directly: when the trigger conditions hold, it calls `synthesize-local.sh` with the backend detected for the project — a suitable local model (LM Studio) when one is served, else Sonnet via the headless claude CLI — and the session ends silently. The nudge path — blocking Stop and asking the in-session Claude to apply the synthesis workflow with full conversation context — remains as the fallback when synthesis fails, and as the explicit mode under `DIARY_SYNTH=claude`. Either way, the requirement that the user type `/diary` is gone and an entry is never silently lost.

The script fires when **all** of the following hold:

1. `.dev-diary/.events.jsonl` exists.
2. The Stop envelope's `session_id` is present.
3. The current session has at least `EDIT_THRESHOLD` `edit` events in the log (the substantive-work threshold; default **2**, overridable via the `DIARY_EDIT_THRESHOLD` env var — non-numeric values silently fall back to 2).
4. No `*.md` file in `.dev-diary/` has an mtime newer than the session's first event timestamp (i.e., no entry has been written for this session yet).
5. The envelope's `stop_hook_active` field is not `true` (loop prevention — see below).
6. `.dev-diary/.no-auto-synth` does not exist (per-project opt-out marker).
7. A working `stat` binary (BSD or GNU) is available — if neither variant works, the script bails silently rather than risk a false-positive nudge.

When all of these hold, the script first attempts local synthesis (the default — see below). If that path is disabled or fails, it emits JSON of the form `{"decision":"block","reason":"..."}` to stdout. Claude Code interprets that as a directive to keep the session alive and feed the reason back as a follow-up instruction. Claude then reads the events log, applies the bar from `SKILL.md` ("would a future agent benefit from knowing this beyond what the code itself records?"), and either writes the entry or briefly states that the session did not clear the bar.

**Loop prevention.** Once the Stop hook injects, Claude responds, and the next Stop event fires with `stop_hook_active: true`. The script sees that flag and exits silently, so the session actually stops. If Claude wrote an entry, the fresh `*.md` file is newer than the session start anyway, so future Stop checks would also be silent.

**Opting out per project.** Create `.dev-diary/.no-auto-synth` (any content, the existence of the file is the signal). Capture continues normally; the auto-synthesis nudge is suppressed. Useful for projects where you want the events log as audit trail but not the inline prose-writing turns.

**Tuning the threshold.** The default of 2 edits matches the canonical pivot-shaped session in `references/events-schema.md`. To override it without editing the script, set the `DIARY_EDIT_THRESHOLD` environment variable — either globally in your shell profile or per-hook via the `env` field in `settings.json`. Higher = fewer false-positive nudges, more likely to miss short sessions worth recording. Lower = more nudges, more turns spent on Claude deciding "this didn't clear the bar." `EDIT_THRESHOLD=2` at the top of the script stays as the in-code default.

**External synthesis (the default).** `maybe-synthesize.sh` writes the entry itself via `synthesize-local.sh` instead of nudging Claude. The backend is detected once per project on the first triggering Stop: `detect-synth.sh` probes LM Studio for a suitable model (backend `local`, zero Claude tokens) and falls back to `sonnet` (headless `claude -p --model sonnet`) when the server is down or serves no suitable model; the decision persists in `.dev-diary/.synth-config` (delete it or `detect-synth.sh --force` to re-detect). Any synthesis failure falls back to the block directive, and each attempt's output is logged to `.dev-diary/.last-local-synth.log` for post-hoc diagnosis. Set `DIARY_SYNTH=claude` in the hook's environment to skip external synthesis and always nudge in-session Claude; `DIARY_SYNTH=local|sonnet` forces a backend without detection. The maybe-synthesize hook needs `"timeout": 300` in `settings.json` (the snippet above ships with it): generation plus a JIT model load far exceeds 5 seconds. See `references/local-models.md` for detection details, model choice, and quality trade-offs.

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
