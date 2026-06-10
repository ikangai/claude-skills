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

# Isolate from the machine's diary configuration — settings.json env blocks
# (e.g. DIARY_SYNTH or DIARY_LM_MODEL) leak into test runs.
unset DIARY_SYNTH DIARY_EDIT_THRESHOLD DIARY_LM_URL DIARY_LM_MODEL \
  DIARY_LM_TEMP DIARY_LM_MAX_TOKENS DIARY_LM_TIMEOUT \
  DIARY_SUITABLE_MODELS DIARY_CLAUDE_BIN DIARY_CLAUDE_MODEL 2>/dev/null || true

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/maybe-synthesize.sh"
SANDBOX="$(mktemp -d -t diary-synth-test.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# Claude CLI stub for the sonnet-backend cases — lives outside $SANDBOX
# because reset() wipes that directory between cases.
SANDBOX_STUB_DIR="$(mktemp -d -t diary-synth-stub.XXXXXX)"
trap 'rm -rf "$SANDBOX" "$SANDBOX_STUB_DIR"' EXIT
cat > "$SANDBOX_STUB_DIR/claude-stub" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'SLUG: sonnet-stub-entry\n\nStarted on the stub work. I edited the files, ran the commands, and the second run passed after the first one failed. The fix was in the configuration rather than the handler, which I only saw after rereading the failing output. Configuration defaults deserve the first look when behavior differs between runs.\n'
EOF
chmod +x "$SANDBOX_STUB_DIR/claude-stub"

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

# Trigger-logic cases below pin DIARY_SYNTH=claude: the default mode is
# "local", which would hit whatever server answers at the default URL and
# make these cases depend on the machine's LM Studio state. The local-mode
# default itself is covered by cases 15–18.

# Case 3: events exist with 2 edits, no prior entry — should fire
reset
write_events sess3 prompt edit bash edit
run_case "2 edits, no prior entry → block" "block" "$(envelope sess3)" "DIARY_SYNTH=claude"

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
run_case "threshold=1 with 1 edit → block" "block" "$(envelope sess11)" \
  "DIARY_EDIT_THRESHOLD=1" "DIARY_SYNTH=claude"

# Case 12: Non-numeric DIARY_EDIT_THRESHOLD falls back to default 2.
# With 2 edits, default fires; with 1 edit, default suppresses.
reset
write_events sess12 edit edit
run_case "threshold=garbage with 2 edits → block (fallback to 2)" "block" \
  "$(envelope sess12)" "DIARY_EDIT_THRESHOLD=garbage" "DIARY_SYNTH=claude"

reset
write_events sess12b edit
run_case "threshold=garbage with 1 edit → silent (fallback to 2)" "silent" \
  "$(envelope sess12b)" "DIARY_EDIT_THRESHOLD=garbage"

# Case 13: Empty DIARY_EDIT_THRESHOLD ("") falls back to default 2.
reset
write_events sess13 edit edit
run_case "threshold='' with 2 edits → block (fallback to 2)" "block" \
  "$(envelope sess13)" "DIARY_EDIT_THRESHOLD=" "DIARY_SYNTH=claude"

# Case 14: Corrupted line in events.jsonl doesn't poison the entire pass —
# valid events around the bad line should still be counted. Simulates a
# torn write from a crash mid-append.
reset
write_events sess14 edit
printf 'this is not json — torn write\n' >> "$SANDBOX/.dev-diary/.events.jsonl"
write_events sess14 edit
run_case "corrupted line surrounded by valid events → block" "block" \
  "$(envelope sess14)" "DIARY_SYNTH=claude"

# Case 15: DIARY_SYNTH=local with a reachable model server — the hook runs
# local synthesis itself: silent (no block directive) and an entry appears.
reset
write_events sess15 prompt edit bash edit
: > "$SANDBOX/port.txt"
MOCK_CONTENT='SLUG: local-mode-entry

Started on the bucket work. I edited the files, ran the commands, and the second run passed after the first one failed. The fix was in the configuration rather than the handler, which I only saw after rereading the failing output. Configuration defaults deserve the first look when behavior differs between runs.' \
  python3 "$(dirname "$0")/mock-lm-server.py" > "$SANDBOX/port.txt" &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null; rm -rf "$SANDBOX" "$SANDBOX_STUB_DIR"' EXIT
MOCK_PORT=""
for _ in $(seq 1 20); do
  MOCK_PORT="$(head -1 "$SANDBOX/port.txt" 2>/dev/null)"
  [[ -n "$MOCK_PORT" ]] && break
  sleep 0.1
done
run_case "DIARY_SYNTH=local with live server → silent" "silent" "$(envelope sess15)" \
  "DIARY_SYNTH=local" "DIARY_LM_URL=http://127.0.0.1:$MOCK_PORT/v1" "DIARY_LM_MODEL=mock-chat-model"
if ls "$SANDBOX/.dev-diary/"*-local-mode-entry.md >/dev/null 2>&1; then
  echo "PASS: DIARY_SYNTH=local wrote the entry"; PASS=$((PASS+1))
else
  echo "FAIL: DIARY_SYNTH=local wrote the entry — $(ls "$SANDBOX/.dev-diary" 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# Case 16: DIARY_SYNTH unset — first run triggers detection. The pinned
# DIARY_LM_MODEL is served by the mock, so detection writes a "local"
# config and the hook synthesizes locally, all in one Stop.
reset
write_events sess16 prompt edit bash edit
run_case "DIARY_SYNTH unset, live server → silent (detect → local)" "silent" "$(envelope sess16)" \
  -u DIARY_SYNTH "DIARY_LM_URL=http://127.0.0.1:$MOCK_PORT/v1" "DIARY_LM_MODEL=mock-chat-model"
if ls "$SANDBOX/.dev-diary/"*-local-mode-entry.md >/dev/null 2>&1 \
  && [[ "$(jq -r '.backend' "$SANDBOX/.dev-diary/.synth-config" 2>/dev/null)" == "local" ]]; then
  echo "PASS: detection wrote a local config and the entry"; PASS=$((PASS+1))
else
  echo "FAIL: detection wrote a local config and the entry — $(ls -a "$SANDBOX/.dev-diary" 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# Case 17: DIARY_SYNTH=claude opts out of local synthesis — block directive
# even though the server is alive, and no entry file appears.
reset
write_events sess17 prompt edit bash edit
run_case "DIARY_SYNTH=claude, live server → block (opt-out)" "block" "$(envelope sess17)" \
  "DIARY_SYNTH=claude" "DIARY_LM_URL=http://127.0.0.1:$MOCK_PORT/v1" "DIARY_LM_MODEL=mock-chat-model"
if ls "$SANDBOX/.dev-diary/"*.md >/dev/null 2>&1; then
  echo "FAIL: DIARY_SYNTH=claude must not write an entry — $(ls "$SANDBOX/.dev-diary" 2>/dev/null)"; FAIL=$((FAIL+1))
else
  echo "PASS: DIARY_SYNTH=claude wrote no entry"; PASS=$((PASS+1))
fi
kill "$MOCK_PID" 2>/dev/null

# Case 18: server unreachable on first run — detection picks sonnet; with
# the claude CLI also unavailable (DIARY_CLAUDE_BIN points nowhere, so the
# test never spends real tokens), synthesis fails and the hook falls back
# to the block directive. The entry is never lost.
reset
write_events sess18 prompt edit bash edit
run_case "first run, server down, no claude CLI → block fallback" "block" "$(envelope sess18)" \
  -u DIARY_SYNTH "DIARY_LM_URL=http://127.0.0.1:1/v1" "DIARY_LM_TIMEOUT=3" \
  "DIARY_CLAUDE_BIN=/nonexistent/claude"
if [[ "$(jq -r '.backend' "$SANDBOX/.dev-diary/.synth-config" 2>/dev/null)" == "sonnet" ]]; then
  echo "PASS: detection persisted the sonnet decision"; PASS=$((PASS+1))
else
  echo "FAIL: detection persisted the sonnet decision — $(cat "$SANDBOX/.dev-diary/.synth-config" 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# A claude CLI stub for the sonnet-backend cases: swallows the prompt on
# stdin, prints a valid SLUG + entry. Keeps the tests offline and free.
STUB="$SANDBOX_STUB_DIR/claude-stub"

# Case 19: first run, server down, claude CLI present (stub) — the full
# fallback chain: detect → sonnet → entry written via the stub, silent.
reset
write_events sess19 prompt edit bash edit
run_case "first run, server down, stub claude → silent (sonnet)" "silent" "$(envelope sess19)" \
  -u DIARY_SYNTH "DIARY_LM_URL=http://127.0.0.1:1/v1" "DIARY_LM_TIMEOUT=3" \
  "DIARY_CLAUDE_BIN=$STUB"
if ls "$SANDBOX/.dev-diary/"*-sonnet-stub-entry.md >/dev/null 2>&1 \
  && [[ "$(jq -r '.backend' "$SANDBOX/.dev-diary/.synth-config" 2>/dev/null)" == "sonnet" ]]; then
  echo "PASS: sonnet backend wrote the entry"; PASS=$((PASS+1))
else
  echo "FAIL: sonnet backend wrote the entry — $(ls -a "$SANDBOX/.dev-diary" 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# Case 20: explicit DIARY_SYNTH=sonnet skips detection entirely — entry via
# the stub, and no .synth-config is created.
reset
write_events sess20 prompt edit bash edit
run_case "DIARY_SYNTH=sonnet, stub claude → silent, no detection" "silent" "$(envelope sess20)" \
  "DIARY_SYNTH=sonnet" "DIARY_CLAUDE_BIN=$STUB"
if ls "$SANDBOX/.dev-diary/"*-sonnet-stub-entry.md >/dev/null 2>&1 \
  && [[ ! -f "$SANDBOX/.dev-diary/.synth-config" ]]; then
  echo "PASS: explicit sonnet wrote the entry without a config"; PASS=$((PASS+1))
else
  echo "FAIL: explicit sonnet wrote the entry without a config — $(ls -a "$SANDBOX/.dev-diary" 2>/dev/null)"; FAIL=$((FAIL+1))
fi

echo
echo "----"
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
