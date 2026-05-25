#!/usr/bin/env bash
#
# maybe-synthesize.sh — Stop hook that nudges Claude to write a diary entry
# when the current session has accumulated substantive work and no entry
# has been written for it yet.
#
# The script does NOT synthesize anything itself. It only decides whether
# the in-session Claude should be asked to apply the diary skill's
# synthesis workflow before stopping. The actual prose-writing happens
# inside the still-live session, where the full conversation context is
# available — preserving the principle that originally argued against any
# kind of automatic synthesis.
#
# Invocation (from .claude/settings.json under Stop):
#   .claude/skills/diary/scripts/maybe-synthesize.sh
#
# Loop prevention:
#   If the hook envelope's stop_hook_active field is true, a previous Stop
#   already injected a directive — we exit 0 so the session can actually
#   stop. Claude wrote (or chose not to write) the entry on the previous
#   turn.
#
# Opt-out:
#   Create .dev-diary/.no-auto-synth to disable automatic synthesis without
#   removing the hook from settings.json.
#
# Trigger conditions (all must hold):
#   - .dev-diary/.events.jsonl exists
#   - .dev-diary/.no-auto-synth does not exist (opt-out marker)
#   - Hook envelope parses as JSON and contains a session_id
#   - Envelope's stop_hook_active flag is not true (loop prevention)
#   - At least EDIT_THRESHOLD `edit` events exist for this session_id
#   - A working stat (BSD or GNU) is available
#   - No *.md file in .dev-diary/ has mtime newer than the session's first
#     event (i.e., no entry has been written for this session yet)
#
# Dependencies: jq, date, stat (BSD or GNU). All standard on macOS and Linux.
#
# Always exits 0. A misconfigured hook must never block a Claude Code
# session.

set -u

# Edit threshold — minimum number of edit events in the current session
# before this hook nudges Claude to synthesize. Default 2 matches the
# canonical pivot-shaped session in references/events-schema.md. Override
# via the DIARY_EDIT_THRESHOLD env var without editing the script.
# Non-numeric overrides fall back to the default rather than crash — the
# script's contract is "always exits 0, never breaks a session."
EDIT_THRESHOLD="${DIARY_EDIT_THRESHOLD:-2}"
[[ "$EDIT_THRESHOLD" =~ ^[0-9]+$ ]] || EDIT_THRESHOLD=2

DIARY_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.dev-diary"
LOG="$DIARY_DIR/.events.jsonl"

# Nothing captured yet — nothing to synthesize.
[[ -f "$LOG" ]] || exit 0

# User opted out for this project.
[[ -f "$DIARY_DIR/.no-auto-synth" ]] && exit 0

# Need jq for envelope parsing and event filtering.
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Validate input as JSON; if not, bail rather than guess.
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# Loop prevention: don't re-inject if the previous Stop was already blocked
# by a hook.
STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
[[ "$STOP_HOOK_ACTIVE" == "true" ]] && exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
[[ -z "$SESSION_ID" ]] && exit 0

# Single jq pass over the events log: filter to this session, count edits,
# and grab the earliest timestamp. Output is tab-separated: "<count>\t<ts>".
#
# Reads each line as raw text and uses `try fromjson catch empty` so a single
# corrupted line in the log doesn't poison the entire pass. The log is
# append-only and can in theory get torn writes if the OS crashes mid-append —
# we don't want that to permanently disable auto-synthesis.
SESSION_INFO="$(jq -Rrs --arg sid "$SESSION_ID" '
  split("\n")
  | map(try fromjson catch empty)
  | [.[] | select(.session_id == $sid)] as $all
  | ([$all[] | select(.kind == "edit")] | length) as $edits
  | ($all[0].ts // "") as $start
  | "\($edits)\t\($start)"
' "$LOG" 2>/dev/null)"
EDIT_COUNT="${SESSION_INFO%%	*}"
SESSION_START="${SESSION_INFO#*	}"

[[ "${EDIT_COUNT:-0}" -lt "$EDIT_THRESHOLD" ]] && exit 0
[[ -z "$SESSION_START" ]] && exit 0

# Convert session_start (ISO 8601 UTC) to epoch seconds. Try BSD date first
# (macOS), then GNU date (Linux). Bail silently if neither parses it.
SESSION_EPOCH="$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$SESSION_START" "+%s" 2>/dev/null \
  || date -u -d "$SESSION_START" "+%s" 2>/dev/null)"
[[ -z "$SESSION_EPOCH" ]] && exit 0

# Probe which stat variant works on this system. BSD (macOS) accepts -f,
# GNU (Linux) accepts -c. If neither works, we cannot reliably decide
# whether an entry has been written, so we exit silently rather than risk
# nagging Claude to re-write an entry that already exists.
if stat -f %m "$LOG" >/dev/null 2>&1; then
  USE_BSD_STAT=1
elif stat -c %Y "$LOG" >/dev/null 2>&1; then
  USE_BSD_STAT=0
else
  exit 0
fi

# If any markdown entry in .dev-diary/ has an mtime newer than session_start,
# assume the entry for this session has already been written.
ENTRY_EXISTS=0
shopt -s nullglob 2>/dev/null || true
for f in "$DIARY_DIR"/*.md; do
  if [[ "$USE_BSD_STAT" -eq 1 ]]; then
    mtime="$(stat -f %m "$f" 2>/dev/null)"
  else
    mtime="$(stat -c %Y "$f" 2>/dev/null)"
  fi
  [[ -z "$mtime" ]] && continue
  if (( mtime > SESSION_EPOCH )); then
    ENTRY_EXISTS=1
    break
  fi
done
[[ "$ENTRY_EXISTS" -eq 1 ]] && exit 0

# All conditions met — block Stop and inject a synthesis directive.
jq -nc --arg edits "$EDIT_COUNT" '{
  decision: "block",
  reason: (
    "Auto-synthesis trigger: this session has " + $edits + " file edits captured in .dev-diary/.events.jsonl and no diary entry has been written for it yet. " +
    "Apply the diary skill before stopping. Read events for this session from .dev-diary/.events.jsonl, then apply the bar from SKILL.md (\"would a future agent benefit from this beyond what the code itself records?\"). " +
    "If the work clears the bar, write the entry to .dev-diary/YYYY-MM-DD-<slug>.md following the voice and structure rules in SKILL.md. " +
    "If it does not clear the bar, briefly say so in one sentence and stop. " +
    "Do not ask the user whether to write — just decide and act. The user can disable this trigger by creating .dev-diary/.no-auto-synth."
  )
}'

exit 0
