#!/usr/bin/env bash
#
# run-eval.sh — evaluate local models on diary synthesis.
#
# For every model × fixture pair: synthesize an entry via
# scripts/synthesize-local.sh, lint it with tests/check-entry.sh, score the
# outcome against the fixture's expectation (tests/eval/fixtures/manifest.jsonl),
# and aggregate everything into a results directory.
#
# Usage:
#   run-eval.sh [--models id1,id2|all] [--fixtures f1.jsonl,f2.jsonl|all]
#               [--results DIR]
#
#   --models    comma-separated model ids, or "all" = every non-embedding
#               model the server reports (default: all)
#   --fixtures  comma-separated fixture filenames under fixtures/, or "all"
#               (default: all from manifest.jsonl)
#   --results   output directory (default: tests/eval/results/<timestamp>)
#
# Environment: DIARY_LM_URL et al. are passed through to synthesize-local.sh.
#
# Outputs in the results directory:
#   scores.jsonl              one row per model × fixture
#   summary.md                score matrix with per-model means and timings
#   entries/<model>/<fixture>.md   the generated entries (kept for judging)
#
# Scoring:
#   expectation "entry":    written entry -> linter score (0..1); declined or
#                           error -> 0
#   expectation "no_entry": declined -> 1; anything else -> 0
#   expectation "either":   declined -> 1; written entry -> linter score
#
# The first request to an unloaded model includes LM Studio's JIT load time;
# seconds are wall-clock per call. LM Studio serves one large model at a
# time, so run this sequentially (it does).
#
# Dependencies: bash 3.2+, curl, jq.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SYNTH="$HERE/../../scripts/synthesize-local.sh"
LINT="$HERE/../check-entry.sh"
FIXDIR="$HERE/fixtures"
MANIFEST="$FIXDIR/manifest.jsonl"

LM_URL="${DIARY_LM_URL:-http://localhost:1234/v1}"
MODELS="all"
FIXTURES="all"
RESULTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models)   MODELS="${2:-all}"; shift 2 ;;
    --fixtures) FIXTURES="${2:-all}"; shift 2 ;;
    --results)  RESULTS="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "manifest not found: $MANIFEST" >&2; exit 2; }

[[ -z "$RESULTS" ]] && RESULTS="$HERE/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS/entries"
SCORES="$RESULTS/scores.jsonl"
: > "$SCORES"

if [[ "$MODELS" == "all" ]]; then
  MODELS="$(curl -sS --max-time 10 "$LM_URL/models" 2>/dev/null \
    | jq -r '[.data[].id | select(test("embed") | not)] | join(",")')"
  if [[ -z "$MODELS" ]]; then
    echo "could not list models from $LM_URL/models" >&2
    exit 1
  fi
fi

if [[ "$FIXTURES" == "all" ]]; then
  FIXTURES="$(jq -r '.fixture' "$MANIFEST" | tr '\n' ',' | sed 's/,$//')"
fi

echo "Models:   $MODELS"
echo "Fixtures: $FIXTURES"
echo "Results:  $RESULTS"
echo

for MODEL in $(printf '%s' "$MODELS" | tr ',' ' '); do
  MODEL_SAFE="$(printf '%s' "$MODEL" | tr '/' '_')"
  ENTRY_DIR="$RESULTS/entries/$MODEL_SAFE"
  mkdir -p "$ENTRY_DIR"

  for FIXTURE in $(printf '%s' "$FIXTURES" | tr ',' ' '); do
    FIXFILE="$FIXDIR/$FIXTURE"
    if [[ ! -f "$FIXFILE" ]]; then
      echo "skipping unknown fixture: $FIXTURE" >&2
      continue
    fi
    EXPECT="$(jq -r --arg f "$FIXTURE" 'select(.fixture == $f) | .expect' "$MANIFEST" | head -1)"
    [[ -z "$EXPECT" ]] && EXPECT="entry"

    OUTDIR="$(mktemp -d -t diary-eval-out.XXXXXX)"
    T0="$(date +%s)"
    SYNTH_OUT="$(DIARY_LM_URL="$LM_URL" "$SYNTH" --events "$FIXFILE" \
      --model "$MODEL" --out "$OUTDIR" 2>&1)"
    RC=$?
    T1="$(date +%s)"
    SECONDS_TAKEN=$((T1 - T0))

    OUTCOME="error"
    ENTRY_FILE=""
    LINT_JSON="null"
    WORDS=0
    if [[ $RC -eq 0 ]]; then
      if printf '%s' "$SYNTH_OUT" | grep -q "declined"; then
        OUTCOME="declined"
      else
        ENTRY_FILE="$(ls "$OUTDIR"/*.md 2>/dev/null | head -1)"
        if [[ -n "$ENTRY_FILE" ]]; then
          OUTCOME="entry"
          WORDS="$(wc -w < "$ENTRY_FILE" | tr -d ' ')"
          LINT_JSON="$(bash "$LINT" --json "$ENTRY_FILE" "$FIXFILE" 2>/dev/null)"
          [[ -z "$LINT_JSON" ]] && LINT_JSON="null"
        fi
      fi
    fi

    # Keep the generated entry for later judging.
    KEPT_ENTRY=""
    if [[ -n "$ENTRY_FILE" ]]; then
      KEPT_ENTRY="$ENTRY_DIR/${FIXTURE%.jsonl}.md"
      cp "$ENTRY_FILE" "$KEPT_ENTRY"
    fi
    rm -rf "$OUTDIR"

    SCORE="$(jq -nr --arg expect "$EXPECT" --arg outcome "$OUTCOME" \
      --argjson lint "$LINT_JSON" '
      if $expect == "no_entry" then
        (if $outcome == "declined" then 1 else 0 end)
      elif $outcome == "declined" then
        (if $expect == "either" then 1 else 0 end)
      elif $outcome == "entry" then
        ($lint.score // 0)
      else 0 end')"

    FAILED_CHECKS="$(printf '%s' "$LINT_JSON" | jq -c '[.checks[]? | select(.pass == false) | .name]' 2>/dev/null)"
    [[ -z "$FAILED_CHECKS" || "$FAILED_CHECKS" == "null" ]] && FAILED_CHECKS="[]"

    jq -nc \
      --arg model "$MODEL" \
      --arg fixture "$FIXTURE" \
      --arg expect "$EXPECT" \
      --arg outcome "$OUTCOME" \
      --arg entry "$KEPT_ENTRY" \
      --argjson seconds "$SECONDS_TAKEN" \
      --argjson words "${WORDS:-0}" \
      --argjson score "$SCORE" \
      --argjson failed "$FAILED_CHECKS" \
      '{model: $model, fixture: $fixture, expect: $expect, outcome: $outcome,
        seconds: $seconds, words: $words, score: $score,
        failed_checks: $failed, entry: $entry}' >> "$SCORES"

    printf '%-55s %-28s %-9s %5ss  score=%s\n' "$MODEL" "$FIXTURE" "$OUTCOME" "$SECONDS_TAKEN" "$SCORE"
  done
done

# --- summary.md --------------------------------------------------------------

jq -rs '
  group_by(.model) | map({
    model: .[0].model,
    mean: ((map(.score) | add / length * 100 | round) / 100),
    total_s: (map(.seconds) | add),
    cells: map({(.fixture): {score, outcome, seconds}}) | add
  }) | sort_by(-.mean) as $rows |
  ($rows[0].cells | keys_unsorted) as $fixtures |
  (["model", "mean"] + $fixtures + ["total s"]) as $hdr |
  ([$hdr, ($hdr | map("---"))] + ($rows | map(
    [.model, (.mean | tostring)]
    + (.cells as $c | $fixtures | map(
        $c[.] as $cell |
        if $cell == null then "—"
        elif $cell.outcome == "error" then "ERR"
        elif $cell.outcome == "declined" then "decl/" + ($cell.score | tostring)
        else ($cell.score | tostring) end))
    + [(.total_s | tostring)]
  ))) | map("| " + join(" | ") + " |") | join("\n")
' "$SCORES" > "$RESULTS/summary.md.tmp"

{
  echo "# Diary synthesis eval — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "Scores are linter pass-rates (0..1) for written entries; declines score 1 on"
  echo "no_entry/either fixtures and 0 on entry fixtures; errors score 0. Mean is the"
  echo "per-model average over the fixtures run. Seconds include JIT model load on"
  echo "the first call to each model."
  echo
  cat "$RESULTS/summary.md.tmp"
} > "$RESULTS/summary.md"
rm -f "$RESULTS/summary.md.tmp"

echo
echo "Wrote $SCORES and $RESULTS/summary.md"
