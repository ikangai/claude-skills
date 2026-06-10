#!/usr/bin/env bash
#
# Test harness for ../scripts/synthesize-local.sh.
#
# Runs the script against a mock LM Studio server (tests/mock-lm-server.py,
# python3 stdlib — test-only dependency). Asserts on exit codes, written
# files, and the request bodies the script sends.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-synthesize-local.sh
#
# Exit code: 0 if all cases pass, 1 otherwise.

set -u

# Isolate from the machine's diary configuration — settings.json env blocks
# (e.g. DIARY_LM_MODEL pins) leak into test runs and break discovery cases.
unset DIARY_SYNTH DIARY_LM_URL DIARY_LM_MODEL DIARY_LM_TEMP \
  DIARY_LM_MAX_TOKENS DIARY_LM_TIMEOUT 2>/dev/null || true

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/synthesize-local.sh"
MOCK="$HERE/mock-lm-server.py"
SANDBOX="$(mktemp -d -t diary-synthlocal-test.XXXXXX)"
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

PASS=0
FAIL=0
TODAY="$(date +%Y-%m-%d)"

ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

EVENTS="$SANDBOX/events.jsonl"
OUT="$SANDBOX/out"

write_events() {
  cat > "$EVENTS" <<'EOF'
{"ts":"2026-05-18T14:30:02Z","kind":"prompt","session_id":"sess_a","cwd":"/proj","prompt":"add the alphaonly feature"}
{"ts":"2026-05-18T14:31:15Z","kind":"edit","session_id":"sess_a","cwd":"/proj","tool":"Write","file_path":"/proj/src/alpha.py"}
{"ts":"2026-05-18T15:30:02Z","kind":"prompt","session_id":"sess_b","cwd":"/proj","prompt":"add the shishi bucket implementation"}
{"ts":"2026-05-18T15:31:15Z","kind":"edit","session_id":"sess_b","cwd":"/proj","tool":"Write","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T15:33:48Z","kind":"bash","session_id":"sess_b","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":1,"description":"Run the bucket tests"}
{"ts":"2026-05-18T15:42:09Z","kind":"edit","session_id":"sess_b","cwd":"/proj","tool":"Edit","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T15:43:32Z","kind":"bash","session_id":"sess_b","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":0,"description":"Re-run the bucket tests"}
EOF
}

GOOD_BODY='Started on the shishi bucket. I wrote bucket.py around a ring buffer, watched pytest fail on burst input, and pivoted to a content-aware filter at ingestion. The second pytest run passed. Recency turned out to be a poor proxy for relevance, and I should have questioned it before writing eighty lines. The detour cost an hour but made the real constraint visible, which the next session will benefit from when it touches the accumulator again.'

# launch <content> [status] — (re)start the mock server, capture its port.
launch() {
  [[ -n "$SERVER_PID" ]] && { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
  : > "$SANDBOX/requests.log"
  : > "$SANDBOX/port.txt"
  MOCK_CONTENT="$1" MOCK_STATUS="${2:-200}" MOCK_LOG="$SANDBOX/requests.log" \
    python3 "$MOCK" > "$SANDBOX/port.txt" &
  SERVER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    PORT="$(head -1 "$SANDBOX/port.txt" 2>/dev/null)"
    [[ -n "$PORT" ]] && break
    sleep 0.1
  done
  if [[ -z "$PORT" ]]; then
    echo "could not start mock server" >&2
    exit 1
  fi
  BASE_URL="http://127.0.0.1:$PORT/v1"
}

reset_out() { rm -rf "$OUT"; mkdir -p "$OUT"; }

write_events

# --- 1: happy path writes a dated, slugged entry ---------------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
f="$OUT/$TODAY-ring-buffer-pivot.md"
if [[ $rc -eq 0 && -f "$f" ]] && grep -q "shishi bucket" "$f" && ! grep -q "^SLUG:" "$f"; then
  ok "happy path writes entry"
else
  bad "happy path writes entry" "rc=$rc out=$out files=$(ls "$OUT" 2>/dev/null)"
fi

# --- 2: the written entry passes the linter --------------------------------
if [[ -f "$f" ]]; then
  SESSION_EVENTS="$SANDBOX/sess_b.jsonl"
  grep sess_b "$EVENTS" > "$SESSION_EVENTS"
  if bash "$HERE/check-entry.sh" "$f" "$SESSION_EVENTS" >/dev/null 2>&1; then
    ok "entry passes linter"
  else
    bad "entry passes linter" "$(bash "$HERE/check-entry.sh" "$f" "$SESSION_EVENTS" 2>&1 | grep FAIL)"
  fi
else
  bad "entry passes linter" "no entry file from case 1"
fi

# --- 3: NO ENTRY decline writes nothing, exits 0 ----------------------------
reset_out
launch "NO ENTRY
Routine reading session, nothing a future agent needs."
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && [[ -z "$(ls "$OUT")" ]] && printf '%s' "$out" | grep -qi "no entry"; then
  ok "NO ENTRY declines cleanly"
else
  bad "NO ENTRY declines cleanly" "rc=$rc out=$out files=$(ls "$OUT")"
fi

# --- 4: <think> reasoning blocks are stripped -------------------------------
reset_out
launch "<think>
Let me reason about the events at length here.
</think>
SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
f="$OUT/$TODAY-ring-buffer-pivot.md"
if [[ $rc -eq 0 && -f "$f" ]] && ! grep -qi "think" "$f" && ! grep -q "reason about" "$f"; then
  ok "think tags stripped"
else
  bad "think tags stripped" "rc=$rc out=$out content=$(cat "$f" 2>/dev/null | head -3)"
fi

# --- 5: chat-template garbage after the entry is truncated ------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY
<|user|>thought I should add more here"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
f="$OUT/$TODAY-ring-buffer-pivot.md"
if [[ $rc -eq 0 && -f "$f" ]] && ! grep -q "<|" "$f"; then
  ok "template garbage truncated"
else
  bad "template garbage truncated" "rc=$rc content=$(cat "$f" 2>/dev/null | tail -2)"
fi

# --- 6: messy slug is sanitized ---------------------------------------------
reset_out
launch "SLUG: Ring Buffer PIVOT!!

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$OUT/$TODAY-ring-buffer-pivot.md" ]]; then
  ok "slug sanitized"
else
  bad "slug sanitized" "rc=$rc files=$(ls "$OUT" 2>/dev/null)"
fi

# --- 7: filename collision appends -2 ----------------------------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
echo "existing" > "$OUT/$TODAY-ring-buffer-pivot.md"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$OUT/$TODAY-ring-buffer-pivot-2.md" ]] \
  && [[ "$(cat "$OUT/$TODAY-ring-buffer-pivot.md")" == "existing" ]]; then
  ok "collision appends -2"
else
  bad "collision appends -2" "rc=$rc files=$(ls "$OUT" 2>/dev/null)"
fi

# --- 8: --session filters the prompt to that session -------------------------
if grep -q "shishi" "$SANDBOX/requests.log" && ! grep -q "alphaonly" "$SANDBOX/requests.log"; then
  ok "session filter excludes other sessions"
else
  bad "session filter excludes other sessions" "$(head -c 300 "$SANDBOX/requests.log")"
fi

# --- 9: default session is the latest in the log -----------------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q "shishi" "$SANDBOX/requests.log" && ! grep -q "alphaonly" "$SANDBOX/requests.log"; then
  ok "default session is latest"
else
  bad "default session is latest" "rc=$rc log=$(head -c 300 "$SANDBOX/requests.log")"
fi

# --- 10: model auto-discovery skips embedding models -------------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q '"model": *"mock-chat-model"' "$SANDBOX/requests.log"; then
  ok "model auto-discovery skips embeddings"
else
  bad "model auto-discovery skips embeddings" "rc=$rc log=$(head -c 300 "$SANDBOX/requests.log")"
fi

# --- 10b: discovery prefers the measured-best model when the server lists it --
reset_out
MOCK_MODELS="text-embedding-nomic-embed-text-v1.5,mock-chat-model,google/gemma-4-26b-a4b" \
  launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q '"model": *"google/gemma-4-26b-a4b"' "$SANDBOX/requests.log"; then
  ok "discovery prefers gemma when served (even when not first)"
else
  bad "discovery prefers gemma when served" "rc=$rc log=$(head -c 300 "$SANDBOX/requests.log")"
fi

# --- 11: API unreachable fails nonzero, writes nothing ------------------------
reset_out
out="$(DIARY_LM_URL="http://127.0.0.1:1/v1" DIARY_LM_MODEL=m DIARY_LM_TIMEOUT=3 \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -ne 0 && -z "$(ls "$OUT")" ]]; then
  ok "unreachable API fails nonzero"
else
  bad "unreachable API fails nonzero" "rc=$rc files=$(ls "$OUT")"
fi

# --- 12: empty content fails with a max-tokens hint ---------------------------
reset_out
launch ""
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -qi "max.tokens" && [[ -z "$(ls "$OUT")" ]]; then
  ok "empty content hints at max_tokens"
else
  bad "empty content hints at max_tokens" "rc=$rc out=$out"
fi

# --- 13: --dry-run prints the prompt and makes no HTTP call -------------------
reset_out
: > "$SANDBOX/requests.log"
out="$(DIARY_LM_URL="http://127.0.0.1:1/v1" DIARY_LM_MODEL=m \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" --dry-run 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q "shishi" && [[ -z "$(ls "$OUT")" ]]; then
  ok "dry-run prints prompt without calling API"
else
  bad "dry-run prints prompt without calling API" "rc=$rc out=$(printf '%s' "$out" | head -c 200)"
fi

# --- 14: --stdout prints the entry without writing a file ---------------------
reset_out
launch "SLUG: ring-buffer-pivot

$GOOD_BODY"
out="$(DIARY_LM_URL="$BASE_URL" DIARY_LM_MODEL=mock-chat-model \
  "$SCRIPT" --events "$EVENTS" --session sess_b --out "$OUT" --stdout 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q "shishi bucket" && [[ -z "$(ls "$OUT")" ]]; then
  ok "stdout mode writes no file"
else
  bad "stdout mode writes no file" "rc=$rc files=$(ls "$OUT")"
fi

# --- 15: missing events file is a usage error ---------------------------------
out="$("$SCRIPT" --events "$SANDBOX/nope.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 2 ]]; then
  ok "missing events file exits 2"
else
  bad "missing events file exits 2" "rc=$rc out=$out"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
