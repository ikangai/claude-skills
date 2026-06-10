#!/usr/bin/env bash
#
# judge-entries.sh — LLM-judge pass over a run-eval.sh results directory.
#
# The mechanical linter (check-entry.sh) catches structure and grounding;
# this pass scores what the linter cannot: voice, narrative quality, and
# faithfulness. It batches the written entries into judge calls and stores
# one judgment row per entry.
#
# Usage:
#   judge-entries.sh <results-dir>
#
# Environment:
#   JUDGE_CMD    command that reads a judging prompt on stdin and prints a
#                JSON array of judgments (default: claude -p --model sonnet).
#                The prompt asks for: [{id, voice, narrative, faithfulness,
#                overall, notes}] with 0-10 scores.
#   JUDGE_BATCH  entries per judge call (default 8)
#
# Output: <results-dir>/judgments.jsonl — scores.jsonl rows joined with the
# judge's scores.
#
# Dependencies: bash 3.2+, jq, and the judge command.

set -u

RESULTS="${1:-}"
JUDGE_CMD="${JUDGE_CMD:-claude -p --model sonnet}"
JUDGE_BATCH="${JUDGE_BATCH:-8}"

if [[ -z "$RESULTS" || ! -f "$RESULTS/scores.jsonl" ]]; then
  echo "usage: judge-entries.sh <results-dir>  (needs scores.jsonl inside)" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

OUT="$RESULTS/judgments.jsonl"
: > "$OUT"

# Rows that produced an actual entry file.
ROWS="$(jq -c 'select(.outcome == "entry" and .entry != "")' "$RESULTS/scores.jsonl")"
if [[ -z "$ROWS" ]]; then
  echo "no entries to judge in $RESULTS/scores.jsonl"
  exit 0
fi

TOTAL="$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')"
echo "Judging $TOTAL entries (batch size $JUDGE_BATCH) with: $JUDGE_CMD"

BATCH_FILE="$(mktemp -t diary-judge-batch.XXXXXX)"
trap 'rm -f "$BATCH_FILE"' EXIT

judge_batch() { # reads batch rows from $BATCH_FILE, appends judgments
  local prompt entries_block judgments
  entries_block=""
  while IFS= read -r row; do
    local id entry_file entry_text
    id="$(printf '%s' "$row" | jq -r '(.model | gsub("/"; "_")) + "::" + .fixture')"
    entry_file="$(printf '%s' "$row" | jq -r '.entry')"
    [[ -f "$entry_file" ]] || continue
    entry_text="$(cat "$entry_file")"
    entries_block="$entries_block
[id: $id]
$entry_text
---"
  done < "$BATCH_FILE"
  [[ -z "$entries_block" ]] && return 0

  prompt="You are judging development diary entries written by language models from raw session event logs. The target voice: first person, past tense, one flowing chronological narrative; concrete file/command names; reversals documented explicitly; at most one closing lesson sentence with no label; no self-praise, no assistant framing, no headers or bullet lists.

Score each entry below on a 0-10 scale for:
- voice: does it read like a developer's end-of-day notebook entry in the target voice?
- narrative: is there an actual story (tried/broke/pivoted/learned) rather than a flat activity recap?
- faithfulness: does it stay within what a session event log could support, or does it invent motives, results, or detail? (You cannot see the events; judge plausibility and over-claiming.)
- overall: holistic quality as a diary entry.

Entries:
$entries_block

Respond with ONLY a JSON array, one object per entry, no markdown fences:
[{\"id\": \"<id>\", \"voice\": N, \"narrative\": N, \"faithfulness\": N, \"overall\": N, \"notes\": \"<one sentence>\"}]"

  judgments="$(printf '%s' "$prompt" | $JUDGE_CMD 2>/dev/null)"
  # Tolerate markdown fences or prose around the array.
  judgments="$(printf '%s' "$judgments" | sed -n '/\[/,$p' | sed 's/```//g')"
  if ! printf '%s' "$judgments" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "judge returned unparseable output for a batch; skipping it" >&2
    return 1
  fi

  # Join each judgment back onto its scores row.
  while IFS= read -r row; do
    local id j
    id="$(printf '%s' "$row" | jq -r '(.model | gsub("/"; "_")) + "::" + .fixture')"
    j="$(printf '%s' "$judgments" | jq -c --arg id "$id" '[.[] | select(.id == $id)] | first // empty')"
    [[ -z "$j" ]] && continue
    printf '%s' "$row" | jq -c --argjson j "$j" \
      '. + {voice: $j.voice, narrative: $j.narrative, faithfulness: $j.faithfulness,
            overall: $j.overall, judge_notes: $j.notes}' >> "$OUT"
  done < "$BATCH_FILE"
}

COUNT=0
: > "$BATCH_FILE"
while IFS= read -r row; do
  printf '%s\n' "$row" >> "$BATCH_FILE"
  COUNT=$((COUNT+1))
  if [[ "$COUNT" -ge "$JUDGE_BATCH" ]]; then
    judge_batch
    : > "$BATCH_FILE"
    COUNT=0
  fi
done <<EOF
$ROWS
EOF
[[ "$COUNT" -gt 0 ]] && judge_batch

JUDGED="$(wc -l < "$OUT" | tr -d ' ')"
echo "Wrote $OUT ($JUDGED judgments)"
exit 0
