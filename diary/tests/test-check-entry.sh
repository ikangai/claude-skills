#!/usr/bin/env bash
#
# Test harness for ../tests/check-entry.sh — the diary entry linter.
#
# Builds a sandbox with an entry file (and optionally an events file),
# invokes the linter, and asserts on exit code and reported check names.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-check-entry.sh
#
# Exit code: 0 if all cases pass, 1 otherwise.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-entry.sh"
SANDBOX="$(mktemp -d -t diary-lint-test.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0

EVENTS="$SANDBOX/events.jsonl"
ENTRY="$SANDBOX/entry.md"

write_events() {
  cat > "$EVENTS" <<'EOF'
{"ts":"2026-05-18T14:30:02Z","kind":"prompt","session_id":"sess_x","cwd":"/proj","prompt":"add the shishi bucket implementation"}
{"ts":"2026-05-18T14:31:15Z","kind":"edit","session_id":"sess_x","cwd":"/proj","tool":"Write","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T14:33:48Z","kind":"bash","session_id":"sess_x","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":1,"description":"Run the bucket tests"}
{"ts":"2026-05-18T14:35:21Z","kind":"prompt","session_id":"sess_x","cwd":"/proj","prompt":"the ring buffer drops too much, can we weight by relevance"}
{"ts":"2026-05-18T14:42:09Z","kind":"edit","session_id":"sess_x","cwd":"/proj","tool":"Edit","file_path":"/proj/src/bucket.py"}
{"ts":"2026-05-18T14:43:32Z","kind":"bash","session_id":"sess_x","cwd":"/proj","command":"pytest tests/test_bucket.py","exit_code":0,"description":"Re-run the bucket tests"}
EOF
}

GOOD_ENTRY='Started on the shishi bucket implementation. First instinct was a ring buffer with a fixed-size window, so I wrote bucket.py around that idea and ran pytest. The first run failed: when events arrive in bursts, the window drops context I wanted to keep, because relevance is not correlated with recency. The user pushed back on the ring buffer and asked about weighting by relevance instead. I rewrote the accumulator in bucket.py as a content-aware filter at ingestion and the tests passed on the next pytest run. The whole detour took under fifteen minutes once the real constraint was visible. Recency is a tempting proxy for relevance and it was wrong here.'

# run_case <name> <expect_exit: 0|1> <expected_substring_or_-> [args...]
run_case() {
  local name="$1"; shift
  local expect_exit="$1"; shift
  local want="$1"; shift
  local out rc
  out="$("$SCRIPT" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne "$expect_exit" ]]; then
    echo "FAIL: $name — expected exit $expect_exit, got $rc. Output: $out"
    FAIL=$((FAIL+1)); return
  fi
  if [[ "$want" != "-" ]] && ! printf '%s' "$out" | grep -q "$want"; then
    echo "FAIL: $name — output missing '$want'. Output: $out"
    FAIL=$((FAIL+1)); return
  fi
  echo "PASS: $name"; PASS=$((PASS+1))
}

write_events

# 1: a good entry passes everything
printf '%s\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "good entry passes" 0 - "$ENTRY" "$EVENTS"

# 2: a single leading H1 title is allowed
printf '# 2026-05-18 — shishi bucket\n\n%s\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "leading H1 title allowed" 0 - "$ENTRY" "$EVENTS"

# 3: section headers inside the entry fail no_headers
printf '%s\n\n## What I tried\n\nMore prose about bucket.py here.\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "inner header fails" 1 "no_headers" "$ENTRY" "$EVENTS"

# 4: bullet lists fail no_bullets
printf '%s\n\n- tried the ring buffer\n- pivoted to a filter\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "bullets fail" 1 "no_bullets" "$ENTRY" "$EVENTS"

# 5: numbered lists fail no_bullets
printf '%s\n\n1. tried the ring buffer\n2. pivoted\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "numbered list fails" 1 "no_bullets" "$ENTRY" "$EVENTS"

# 6: bold-label pseudo-sections fail no_bold_labels
printf '%s\n\n**Lesson:** recency is not relevance.\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "bold label fails" 1 "no_bold_labels" "$ENTRY" "$EVENTS"

# 7: third-person entry fails first_person
printf 'The developer started on the shishi bucket in bucket.py. The first attempt used a ring buffer with a fixed window and pytest failed on burst input because the window dropped context that mattered. The approach was changed to a content-aware filter at ingestion and the pytest run passed. The whole exercise showed that recency does not equal relevance, and the new accumulator keeps high-value events regardless of arrival order. The change was small but the constraint behind it was only visible after the failing run, which is why the detour happened at all.\n' > "$ENTRY"
run_case "third person fails" 1 "first_person" "$ENTRY" "$EVENTS"

# 8: self-praise vocabulary fails no_self_praise
printf '%s I successfully implemented an elegant solution.\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "self-praise fails" 1 "no_self_praise" "$ENTRY" "$EVENTS"

# 9: labeled lesson fails no_lesson_label
printf '%s\n\nLessons Learned: recency is not relevance.\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "lesson label fails" 1 "no_lesson_label" "$ENTRY" "$EVENTS"

# 10: assistant meta-text fails no_meta_text
printf 'Here is the diary entry based on the events:\n\n%s\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "meta text fails" 1 "no_meta_text" "$ENTRY" "$EVENTS"

# 11: too-short entry fails word_count
printf 'I tried bucket.py and pytest failed once.\n' > "$ENTRY"
run_case "short entry fails word_count" 1 "word_count" "$ENTRY" "$EVENTS"

# 12: entry mentioning a file absent from events fails no_hallucinated_files
printf '%s Later I also refactored scheduler.go for good measure.\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "hallucinated file fails" 1 "no_hallucinated_files" "$ENTRY" "$EVENTS"

# 13: entry sharing no concrete tokens with the events fails grounded
printf 'Spent the afternoon reworking the deployment story. I moved the cron driver onto the queue runner, then I chased a flaky timeout in the gateway for an hour before finding the keepalive default was wrong. I set it explicitly, reran the smoke checks, and they came back green. I kept the old path behind a flag in case the queue runner misbehaves under load. Defaults you have never read are the first suspects when behavior changes between environments, and that was the whole story of the day really.\n' > "$ENTRY"
run_case "ungrounded entry fails" 1 "grounded" "$ENTRY" "$EVENTS"

# 14: without an events file, grounding checks are skipped and a good entry passes
printf '%s\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "no events file: grounding skipped" 0 - "$ENTRY"

# 15: --json emits parseable JSON with per-check results
printf '%s\n' "$GOOD_ENTRY" > "$ENTRY"
out="$("$SCRIPT" --json "$ENTRY" "$EVENTS" 2>&1)"
if printf '%s' "$out" | jq -e '.checks | length > 5' >/dev/null 2>&1 \
  && printf '%s' "$out" | jq -e '.failed == 0' >/dev/null 2>&1; then
  echo "PASS: json output"; PASS=$((PASS+1))
else
  echo "FAIL: json output — got: $out"; FAIL=$((FAIL+1))
fi

# 16: --json on a bad entry reports the failing check by name
printf '%s\n\n- a bullet\n' "$GOOD_ENTRY" > "$ENTRY"
out="$("$SCRIPT" --json "$ENTRY" "$EVENTS" 2>&1)"
if printf '%s' "$out" | jq -e '[.checks[] | select(.name == "no_bullets")][0].pass == false' >/dev/null 2>&1; then
  echo "PASS: json reports failing check"; PASS=$((PASS+1))
else
  echo "FAIL: json reports failing check — got: $out"; FAIL=$((FAIL+1))
fi

# 17: missing entry file is a usage error (exit 2)
run_case "missing entry file" 2 - "$SANDBOX/does-not-exist.md"

# 21: an entry truncated mid-sentence fails complete_ending
printf '%s\n\nAfter verifying the fixes with pytest and coordinating reviews\n' "$GOOD_ENTRY" > "$ENTRY"
run_case "truncated entry fails complete_ending" 1 "complete_ending" "$ENTRY" "$EVENTS"

# 18: dropped-subject first person ("Started on...") with a single I passes
printf 'Started on the shishi bucket in bucket.py. First instinct was a ring buffer with a fixed window. Wrote about eighty lines and hit a wall: pytest failed on burst input because the window dropped context that mattered, since relevance is not correlated with recency. The user pushed back and suggested weighting by relevance. Threw out the ring buffer, rewrote the accumulator as a content-aware filter at ingestion, and the next pytest run passed. Most of the time went into making the constraint visible rather than fixing it, which is where I should have started. Recency is a tempting proxy for relevance and it was wrong here.\n' > "$ENTRY"
run_case "dropped-subject voice passes" 0 - "$ENTRY" "$EVENTS"

# 19: real entries run long — 700-ish words still passes word_count
{ for i in 1 2 3 4 5 6; do printf '%s ' "$GOOD_ENTRY"; done; echo; } > "$ENTRY"
run_case "700-word entry passes" 0 - "$ENTRY" "$EVENTS"

# 20: recap bloat — beyond ~900 words fails word_count
{ for i in 1 2 3 4 5 6 7 8 9; do printf '%s ' "$GOOD_ENTRY"; done; echo; } > "$ENTRY"
run_case "1000-word entry fails word_count" 1 "word_count" "$ENTRY" "$EVENTS"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
