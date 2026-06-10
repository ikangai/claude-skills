#!/usr/bin/env bash
#
# relint.sh — re-score a run-eval.sh results directory with the current
# linter.
#
# The linter evolves; entries kept in a results directory don't. This tool
# re-runs tests/check-entry.sh over every kept entry and recomputes scores
# uniformly, so model comparisons are never skewed by which linter version
# happened to be in place when each model ran.
#
# Usage:
#   relint.sh <results-dir>
#
# Reads  <results-dir>/scores.jsonl
# Writes <results-dir>/scores-relint.jsonl  (same rows, rescored)
#
# Rows whose outcome is not "entry" (declines, errors) pass through
# unchanged — only linter-derived scores are recomputed.
#
# Dependencies: bash 3.2+, jq.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/../check-entry.sh"
FIXDIR="$HERE/fixtures"

RESULTS="${1:-}"
if [[ -z "$RESULTS" || ! -f "$RESULTS/scores.jsonl" ]]; then
  echo "usage: relint.sh <results-dir>  (needs scores.jsonl inside)" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

OUT="$RESULTS/scores-relint.jsonl"
: > "$OUT"

while IFS= read -r row; do
  OUTCOME="$(printf '%s' "$row" | jq -r '.outcome')"
  ENTRY="$(printf '%s' "$row" | jq -r '.entry')"
  FIXTURE="$(printf '%s' "$row" | jq -r '.fixture')"
  EXPECT="$(printf '%s' "$row" | jq -r '.expect')"

  if [[ "$OUTCOME" != "entry" || -z "$ENTRY" || ! -f "$ENTRY" ]]; then
    printf '%s\n' "$row" >> "$OUT"
    continue
  fi

  FIXFILE="$FIXDIR/$FIXTURE"
  if [[ -f "$FIXFILE" ]]; then
    LINT_JSON="$(bash "$LINT" --json "$ENTRY" "$FIXFILE" 2>/dev/null)"
  else
    LINT_JSON="$(bash "$LINT" --json "$ENTRY" 2>/dev/null)"
  fi
  [[ -z "$LINT_JSON" ]] && LINT_JSON="null"

  printf '%s' "$row" | jq -c --argjson lint "$LINT_JSON" --arg expect "$EXPECT" '
    ($lint.score // 0) as $lintscore |
    .score = (if $expect == "no_entry" then 0 else $lintscore end) |
    .failed_checks = ([$lint.checks[]? | select(.pass == false) | .name])
  ' >> "$OUT"
done < "$RESULTS/scores.jsonl"

echo "Wrote $OUT"
exit 0
