#!/usr/bin/env bash
#
# Test harness for ../scripts/maybe-synthesize.sh.
#
# Builds an isolated fixture .dev-diary/ for each case, invokes the
# script with a crafted Stop envelope on stdin, and asserts on output.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-maybe-synthesize.sh
#
# Exit code: 0 if all cases pass, 1 otherwise. Designed to be used as a
# Guard command in the autoresearch:fix workflow when modifying the
# synthesis hook.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/maybe-synthesize.sh"
SANDBOX="$(mktemp -d -t diary-synth-test.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0

reset() {
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/.dev-diary"
}

# write_events <session_id> <kind1> <kind2> ...
# Writes one JSONL line per kind, each 1 second apart starting from a
# fixed timestamp well in the past so "now"-touched markdown files are
# reliably newer than the session regardless of local timezone.
write_events() {
  local sid="$1"; shift
  local i=0
  for kind in "$@"; do
    local ts
    ts="$(date -u -j -v+${i}S -f "%Y-%m-%dT%H:%M:%SZ" "2025-01-15T10:00:00Z" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || date -u -d "2025-01-15T10:00:00Z + ${i} seconds" "+%Y-%m-%dT%H:%M:%SZ")"
    printf '{"ts":"%s","kind":"%s","session_id":"%s","cwd":"%s"}\n' \
      "$ts" "$kind" "$sid" "$SANDBOX" >> "$SANDBOX/.dev-diary/.events.jsonl"
    i=$((i+1))
  done
}

# envelope <session_id> <stop_hook_active>
envelope() {
  local sid="$1"
  local active="${2:-false}"
  printf '{"session_id":"%s","cwd":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}\n' \
    "$sid" "$SANDBOX" "$active"
}

# run_case <name> <expect: silent|block> <input> [extra env...]
run_case() {
  local name="$1"; shift
  local expect="$1"; shift
  local input="$1"; shift
  local out
  out="$(printf '%s' "$input" | env "$@" CLAUDE_PROJECT_DIR="$SANDBOX" "$SCRIPT" 2>&1)"
  if [[ "$expect" == "silent" ]]; then
    if [[ -z "$out" ]]; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected silent, got: $out"; FAIL=$((FAIL+1))
    fi
  else
    if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected block JSON, got: $out"; FAIL=$((FAIL+1))
    fi
  fi
}

# Case 1: no events.jsonl at all
reset
run_case "no events log" "silent" "$(envelope sess1)"

# Case 2: events exist but only 1 edit (below threshold)
reset
write_events sess2 edit
run_case "below threshold (1 edit)" "silent" "$(envelope sess2)"

# Case 3: events exist with 2 edits, no prior entry — should fire
reset
write_events sess3 prompt edit bash edit
run_case "2 edits, no prior entry → block" "block" "$(envelope sess3)"

# Case 4: stop_hook_active true — loop prevention
reset
write_events sess4 prompt edit bash edit edit
run_case "stop_hook_active true → silent" "silent" "$(envelope sess4 true)"

# Case 5: opt-out marker present
reset
write_events sess5 prompt edit edit edit
touch "$SANDBOX/.dev-diary/.no-auto-synth"
run_case "opt-out marker present" "silent" "$(envelope sess5)"

# Case 6: prior diary entry exists (mtime newer than session start)
reset
write_events sess6 prompt edit edit
touch "$SANDBOX/.dev-diary/2026-05-25-something.md"
run_case "prior entry exists → silent" "silent" "$(envelope sess6)"

# Case 7: events from a DIFFERENT session — current session has 0 edits
reset
write_events other-sess edit edit edit
run_case "all edits belong to other session → silent" "silent" "$(envelope sess7)"

# Case 8: empty envelope
reset
write_events sess8 edit edit edit
run_case "empty envelope → silent" "silent" ""

# Case 9: malformed envelope
reset
write_events sess9 edit edit edit
run_case "malformed envelope → silent" "silent" "not json"

# Case 10: DIARY_EDIT_THRESHOLD env var raises threshold above edit count
reset
write_events sess10 edit edit
run_case "threshold=3 with 2 edits → silent" "silent" "$(envelope sess10)" "DIARY_EDIT_THRESHOLD=3"

# Case 11: DIARY_EDIT_THRESHOLD env var lowers threshold to 1
reset
write_events sess11 edit
run_case "threshold=1 with 1 edit → block" "block" "$(envelope sess11)" "DIARY_EDIT_THRESHOLD=1"

# Case 12: Non-numeric DIARY_EDIT_THRESHOLD falls back to default 2.
# With 2 edits, default fires; with 1 edit, default suppresses.
reset
write_events sess12 edit edit
run_case "threshold=garbage with 2 edits → block (fallback to 2)" "block" \
  "$(envelope sess12)" "DIARY_EDIT_THRESHOLD=garbage"

reset
write_events sess12b edit
run_case "threshold=garbage with 1 edit → silent (fallback to 2)" "silent" \
  "$(envelope sess12b)" "DIARY_EDIT_THRESHOLD=garbage"

# Case 13: Empty DIARY_EDIT_THRESHOLD ("") falls back to default 2.
reset
write_events sess13 edit edit
run_case "threshold='' with 2 edits → block (fallback to 2)" "block" \
  "$(envelope sess13)" "DIARY_EDIT_THRESHOLD="

# Case 14: Corrupted line in events.jsonl doesn't poison the entire pass —
# valid events around the bad line should still be counted. Simulates a
# torn write from a crash mid-append.
reset
write_events sess14 edit
printf 'this is not json — torn write\n' >> "$SANDBOX/.dev-diary/.events.jsonl"
write_events sess14 edit
run_case "corrupted line surrounded by valid events → block" "block" \
  "$(envelope sess14)"

echo
echo "----"
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
