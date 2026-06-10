#!/usr/bin/env bash
#
# Test harness for ../tests/eval/run-eval.sh — the model evaluation runner.
#
# Uses the mock LM Studio server so no real model is needed. Asserts on the
# scores.jsonl rows and summary.md the harness produces.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-run-eval.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS="$HERE/eval/run-eval.sh"
MOCK="$HERE/mock-lm-server.py"
FIXTURES="$HERE/eval/fixtures"
SANDBOX="$(mktemp -d -t diary-eval-test.XXXXXX)"
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

GOOD_CONTENT='SLUG: ring-buffer-pivot

Started on the shishi bucket. I wrote bucket.py around a ring buffer, watched pytest fail on burst input, and pivoted to a content-aware filter at ingestion. The second pytest run passed. Recency turned out to be a poor proxy for relevance, and I should have questioned it before writing eighty lines. The detour cost an hour but made the real constraint visible, which the next session will benefit from when it touches the accumulator again.'

launch() { # launch <content>
  [[ -n "$SERVER_PID" ]] && { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
  : > "$SANDBOX/port.txt"
  MOCK_CONTENT="$1" python3 "$MOCK" > "$SANDBOX/port.txt" &
  SERVER_PID=$!
  PORT=""
  for _ in $(seq 1 20); do
    PORT="$(head -1 "$SANDBOX/port.txt" 2>/dev/null)"
    [[ -n "$PORT" ]] && break
    sleep 0.1
  done
  [[ -z "$PORT" ]] && { echo "mock server failed to start" >&2; exit 1; }
  BASE_URL="http://127.0.0.1:$PORT/v1"
}

# --- 1: entry fixture, good content -> outcome=entry, score 1 ---------------
R="$SANDBOX/r1"
launch "$GOOD_CONTENT"
DIARY_LM_URL="$BASE_URL" bash "$HARNESS" --models mock-chat-model \
  --fixtures pivot-canonical.jsonl --results "$R" >/dev/null 2>&1
row="$(cat "$R/scores.jsonl" 2>/dev/null | head -1)"
if printf '%s' "$row" | jq -e '.outcome == "entry" and .score == 1 and .model == "mock-chat-model"' >/dev/null 2>&1; then
  ok "entry fixture scores 1.0"
else
  bad "entry fixture scores 1.0" "row=$row"
fi
if [[ -f "$R/summary.md" ]] && grep -q "mock-chat-model" "$R/summary.md"; then
  ok "summary.md written"
else
  bad "summary.md written" "$(ls "$R" 2>/dev/null)"
fi

# --- 2: no_entry fixture, declining mock -> outcome=declined, score 1 -------
R="$SANDBOX/r2"
launch "NO ENTRY
Routine session, nothing to record."
DIARY_LM_URL="$BASE_URL" bash "$HARNESS" --models mock-chat-model \
  --fixtures routine-no-entry.jsonl --results "$R" >/dev/null 2>&1
row="$(cat "$R/scores.jsonl" 2>/dev/null | head -1)"
if printf '%s' "$row" | jq -e '.outcome == "declined" and .score == 1' >/dev/null 2>&1; then
  ok "correct decline scores 1.0"
else
  bad "correct decline scores 1.0" "row=$row"
fi

# --- 3: no_entry fixture, entry-producing mock -> score 0 -------------------
R="$SANDBOX/r3"
launch "$GOOD_CONTENT"
DIARY_LM_URL="$BASE_URL" bash "$HARNESS" --models mock-chat-model \
  --fixtures routine-no-entry.jsonl --results "$R" >/dev/null 2>&1
row="$(cat "$R/scores.jsonl" 2>/dev/null | head -1)"
if printf '%s' "$row" | jq -e '.outcome == "entry" and .score == 0' >/dev/null 2>&1; then
  ok "false entry on routine session scores 0"
else
  bad "false entry on routine session scores 0" "row=$row"
fi

# --- 4: unreachable server -> outcome=error, harness still completes ---------
R="$SANDBOX/r4"
DIARY_LM_URL="http://127.0.0.1:1/v1" DIARY_LM_TIMEOUT=3 bash "$HARNESS" \
  --models mock-chat-model --fixtures pivot-canonical.jsonl --results "$R" >/dev/null 2>&1
row="$(cat "$R/scores.jsonl" 2>/dev/null | head -1)"
if printf '%s' "$row" | jq -e '.outcome == "error" and .score == 0' >/dev/null 2>&1 && [[ -f "$R/summary.md" ]]; then
  ok "error recorded, harness completes"
else
  bad "error recorded, harness completes" "row=$row files=$(ls "$R" 2>/dev/null)"
fi

# --- 5: two fixtures produce two rows and a mean in the summary --------------
R="$SANDBOX/r5"
launch "$GOOD_CONTENT"
DIARY_LM_URL="$BASE_URL" bash "$HARNESS" --models mock-chat-model \
  --fixtures pivot-canonical.jsonl,user-correction.jsonl --results "$R" >/dev/null 2>&1
n="$(wc -l < "$R/scores.jsonl" 2>/dev/null | tr -d ' ')"
if [[ "$n" == "2" ]] && grep -qi "mean" "$R/summary.md"; then
  ok "two fixtures, two rows, mean column"
else
  bad "two fixtures, two rows, mean column" "rows=$n"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
