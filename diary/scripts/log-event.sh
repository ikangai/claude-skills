#!/usr/bin/env bash
#
# log-event.sh — append a normalized event to .dev-diary/.events.jsonl
#
# Invoked from Claude Code hooks. Reads the hook JSON envelope from stdin
# and writes one normalized JSON line to the events log. Always exits 0
# so a misconfigured hook never breaks the Claude Code session.
#
# Usage (from .claude/settings.json):
#   .claude/skills/diary/scripts/log-event.sh <kind>
#
# Where <kind> is one of:
#   edit          (PostToolUse matcher: Write|Edit|MultiEdit)
#   bash          (PostToolUse matcher: Bash)
#   prompt        (UserPromptSubmit)
#   subagent      (SubagentStop)
#   session_end   (SessionEnd)
#   stop          (Stop)
#
# Dependencies: jq, date, mkdir (all standard on macOS and Linux).

set -u

KIND="${1:-unknown}"
DIARY_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.dev-diary"
LOG="$DIARY_DIR/.events.jsonl"

# Ensure the diary directory exists. Silently no-op if mkdir fails.
mkdir -p "$DIARY_DIR" 2>/dev/null || exit 0

# If jq isn't on PATH, write a minimal event and bail out.
if ! command -v jq >/dev/null 2>&1; then
  TS_FALLBACK="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  printf '{"ts":"%s","kind":"%s","error":"jq_not_installed"}\n' \
    "$TS_FALLBACK" "$KIND" >> "$LOG" 2>/dev/null
  exit 0
fi

# Read hook input from stdin; fall back to "{}" if empty.
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && INPUT="{}"

# Validate input is JSON; if not, wrap as a single field.
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  INPUT=$(jq -nc --arg raw "$INPUT" '{raw_input: $raw}')
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build the normalized event, pulling kind-specific fields.
EVENT="$(printf '%s' "$INPUT" | jq -c \
  --arg ts "$TS" \
  --arg kind "$KIND" \
  '
  def trunc($n): if . == null then null elif (tostring | length) > $n then (tostring | .[0:$n] + "…") else tostring end;

  ({
    ts: $ts,
    kind: $kind,
    session_id: .session_id,
    cwd: .cwd
  } + (
    if $kind == "edit" then
      {
        tool: .tool_name,
        file_path: .tool_input.file_path
      }
    elif $kind == "bash" then
      {
        command: (.tool_input.command | trunc(500)),
        exit_code: .tool_response.exit_code,
        description: .tool_input.description
      }
    elif $kind == "prompt" then
      {
        prompt: ((.prompt // .user_prompt // "") | trunc(500))
      }
    elif $kind == "subagent" then
      {
        last_message: ((.last_assistant_message // "") | trunc(500))
      }
    elif $kind == "stop" then
      {
        last_message: ((.last_assistant_message // "") | trunc(500))
      }
    else
      {}
    end
  )) | with_entries(select(.value != null and .value != ""))
  ' 2>/dev/null)"

# If jq produced nothing usable, emit a minimal event.
if [[ -z "$EVENT" ]]; then
  EVENT="$(jq -nc --arg ts "$TS" --arg kind "$KIND" '{ts: $ts, kind: $kind, error: "jq_parse_failed"}')"
fi

printf '%s\n' "$EVENT" >> "$LOG" 2>/dev/null

exit 0
