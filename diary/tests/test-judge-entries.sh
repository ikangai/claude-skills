#!/usr/bin/env bash
#
# Test harness for ../tests/eval/judge-entries.sh — the LLM-judge pass.
#
# Injects a stub judge via JUDGE_CMD so no real model is called. Asserts on
# the judgments.jsonl rows produced from a fabricated results directory.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-judge-entries.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/eval/judge-entries.sh"
SANDBOX="$(mktemp -d -t diary-judge-test.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# Fabricate a results dir: two entry rows (one with a file, one declined).
R="$SANDBOX/results"
mkdir -p "$R/entries/model-a"
cat > "$R/entries/model-a/pivot-canonical.md" <<'EOF'
Started on the shishi bucket. I wrote bucket.py, watched pytest fail, and pivoted to a content-aware filter. The second run passed.
EOF
cat > "$R/scores.jsonl" <<EOF
{"model":"model-a","fixture":"pivot-canonical.jsonl","expect":"entry","outcome":"entry","seconds":10,"words":25,"score":1,"failed_checks":[],"entry":"$R/entries/model-a/pivot-canonical.md"}
{"model":"model-a","fixture":"routine-no-entry.jsonl","expect":"no_entry","outcome":"declined","seconds":5,"words":0,"score":1,"failed_checks":[],"entry":""}
EOF

# Stub judge: echoes a fixed JSON array naming the id it was asked about.
STUB="$SANDBOX/stub-judge.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# Reads the prompt on stdin; extracts entry ids of the form [id: X] and
# emits one judgment per id.
ids=$(grep -oE '\[id: [^]]+\]' | sed 's/\[id: //; s/\]//')
printf '['
first=1
for id in $ids; do
  [[ $first -eq 0 ]] && printf ','
  printf '{"id":"%s","voice":8,"narrative":7,"faithfulness":9,"overall":8,"notes":"stub"}' "$id"
  first=0
done
printf ']\n'
EOF
chmod +x "$STUB"

# --- 1: judgments.jsonl gets one row per written entry (declines skipped) ---
out="$(JUDGE_CMD="$STUB" bash "$SCRIPT" "$R" 2>&1)"; rc=$?
n="$(wc -l < "$R/judgments.jsonl" 2>/dev/null | tr -d ' ')"
if [[ $rc -eq 0 && "$n" == "1" ]]; then
  ok "one judgment per written entry"
else
  bad "one judgment per written entry" "rc=$rc rows=$n out=$out"
fi

# --- 2: judgment row carries model, fixture, and scores ----------------------
row="$(head -1 "$R/judgments.jsonl" 2>/dev/null)"
if printf '%s' "$row" | jq -e '.model == "model-a" and .fixture == "pivot-canonical.jsonl" and .overall == 8' >/dev/null 2>&1; then
  ok "judgment row carries scores"
else
  bad "judgment row carries scores" "row=$row"
fi

# --- 3: empty results dir (no entries) exits 0 with a note --------------------
R2="$SANDBOX/r2"
mkdir -p "$R2"
cat > "$R2/scores.jsonl" <<'EOF'
{"model":"model-a","fixture":"routine-no-entry.jsonl","expect":"no_entry","outcome":"declined","seconds":5,"words":0,"score":1,"failed_checks":[],"entry":""}
EOF
out="$(JUDGE_CMD="$STUB" bash "$SCRIPT" "$R2" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -qi "no entries"; then
  ok "no entries handled gracefully"
else
  bad "no entries handled gracefully" "rc=$rc out=$out"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
