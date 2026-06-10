#!/usr/bin/env bash
#
# Test harness for ../tests/eval/relint.sh — uniform re-scoring of a results
# directory with the current linter.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-relint.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/eval/relint.sh"
SANDBOX="$(mktemp -d -t diary-relint-test.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# Fabricate a results dir: one good entry, one truncated entry, one decline,
# one error row.
R="$SANDBOX/results"
mkdir -p "$R/entries/model-a"
GOOD='Started on the shishi bucket. I wrote bucket.py around a ring buffer, watched pytest fail on burst input, and pivoted to a content-aware filter at ingestion. The second pytest run passed. Recency turned out to be a poor proxy for relevance, and I should have questioned it before writing eighty lines. The detour cost an hour but made the real constraint visible, which the next session will benefit from when it touches the accumulator again.'
printf '%s\n' "$GOOD" > "$R/entries/model-a/pivot-canonical.md"
printf '%s\n\nThen I went on verifying the fixes with pytest and\n' "$GOOD" > "$R/entries/model-a/user-correction.md"
cat > "$R/scores.jsonl" <<EOF
{"model":"model-a","fixture":"pivot-canonical.jsonl","expect":"entry","outcome":"entry","seconds":10,"words":75,"score":0.5,"failed_checks":["stale"],"entry":"$R/entries/model-a/pivot-canonical.md"}
{"model":"model-a","fixture":"user-correction.jsonl","expect":"entry","outcome":"entry","seconds":12,"words":80,"score":1,"failed_checks":[],"entry":"$R/entries/model-a/user-correction.md"}
{"model":"model-a","fixture":"routine-no-entry.jsonl","expect":"no_entry","outcome":"declined","seconds":5,"words":0,"score":1,"failed_checks":[],"entry":""}
{"model":"model-b","fixture":"pivot-canonical.jsonl","expect":"entry","outcome":"error","seconds":3,"words":0,"score":0,"failed_checks":[],"entry":""}
EOF

out="$(bash "$SCRIPT" "$R" 2>&1)"; rc=$?

# --- 1: rescored file exists with same row count ------------------------------
n="$(wc -l < "$R/scores-relint.jsonl" 2>/dev/null | tr -d ' ')"
if [[ $rc -eq 0 && "$n" == "4" ]]; then
  ok "rescored file has all rows"
else
  bad "rescored file has all rows" "rc=$rc rows=$n out=$out"
fi

# --- 2: good entry rescored with current linter (stale 0.5 -> 1) --------------
s="$(jq -r 'select(.fixture == "pivot-canonical.jsonl" and .model == "model-a") | .score' "$R/scores-relint.jsonl" 2>/dev/null)"
if [[ "$s" == "1" ]]; then
  ok "good entry rescored to 1"
else
  bad "good entry rescored to 1" "score=$s"
fi

# --- 3: truncated entry penalized by current linter ---------------------------
s="$(jq -r 'select(.fixture == "user-correction.jsonl") | .score' "$R/scores-relint.jsonl" 2>/dev/null)"
ck="$(jq -r 'select(.fixture == "user-correction.jsonl") | .failed_checks | join(",")' "$R/scores-relint.jsonl" 2>/dev/null)"
if jq -e 'select(.fixture == "user-correction.jsonl") | .score < 1' "$R/scores-relint.jsonl" >/dev/null 2>&1 \
  && printf '%s' "$ck" | grep -q "complete_ending"; then
  ok "truncated entry penalized"
else
  bad "truncated entry penalized" "score=$s checks=$ck"
fi

# --- 4: declined and error rows pass through unchanged ------------------------
d="$(jq -r 'select(.outcome == "declined") | .score' "$R/scores-relint.jsonl" 2>/dev/null)"
e="$(jq -r 'select(.outcome == "error") | .score' "$R/scores-relint.jsonl" 2>/dev/null)"
if [[ "$d" == "1" && "$e" == "0" ]]; then
  ok "declines and errors pass through"
else
  bad "declines and errors pass through" "declined=$d error=$e"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
