#!/usr/bin/env bash
#
# check-entry.sh — mechanical linter for diary entries.
#
# Checks one entry file against the voice and structure rules in SKILL.md,
# and (when an events file is given) against the session's raw events for
# grounding and hallucination.
#
# Usage:
#   check-entry.sh [--json] <entry.md> [events.jsonl]
#
# Without events.jsonl the grounding checks are skipped, not failed.
#
# Exit codes:
#   0  all checks passed (skips allowed)
#   1  at least one check failed
#   2  usage error (missing file, bad arguments)
#
# Output: one line per check (PASS/FAIL/SKIP) plus a summary, or a single
# JSON object with --json. Used standalone and by tests/eval/run-eval.sh.
#
# Dependencies: bash 3.2+, grep, awk, wc, jq (for --json and events parsing).

set -u

JSON=0
if [[ "${1:-}" == "--json" ]]; then
  JSON=1
  shift
fi

ENTRY_FILE="${1:-}"
EVENTS_FILE="${2:-}"

if [[ -z "$ENTRY_FILE" || ! -f "$ENTRY_FILE" ]]; then
  echo "usage: check-entry.sh [--json] <entry.md> [events.jsonl]" >&2
  exit 2
fi
if [[ -n "$EVENTS_FILE" && ! -f "$EVENTS_FILE" ]]; then
  echo "events file not found: $EVENTS_FILE" >&2
  exit 2
fi

# Results accumulate as "name<TAB>status<TAB>detail" lines (bash 3.2 — no
# associative arrays).
RESULTS=""
add_result() { # name status detail
  RESULTS="${RESULTS}${1}	${2}	${3}
"
}

ENTRY_TEXT="$(cat "$ENTRY_FILE")"

# Body = entry minus one optional leading H1 title line.
if printf '%s\n' "$ENTRY_TEXT" | head -1 | grep -qE '^# '; then
  BODY="$(printf '%s\n' "$ENTRY_TEXT" | tail -n +2)"
else
  BODY="$ENTRY_TEXT"
fi

# --- structure checks -------------------------------------------------------

# no_headers: no markdown headers in the body (one leading H1 title allowed).
if printf '%s\n' "$BODY" | grep -qE '^#{1,6} '; then
  add_result no_headers fail "section headers inside the entry"
else
  add_result no_headers pass ""
fi

# no_bullets: no bullet or numbered list lines.
if printf '%s\n' "$ENTRY_TEXT" | grep -qE '^[[:space:]]*([-*+•][[:space:]]|[0-9]+\.[[:space:]])'; then
  add_result no_bullets fail "bullet or numbered list lines"
else
  add_result no_bullets pass ""
fi

# no_bold_labels: no '**Label:**'-style pseudo-sections at line start.
if printf '%s\n' "$ENTRY_TEXT" | grep -qE '^\*\*[^*]+\*\*'; then
  add_result no_bold_labels fail "bold-label pseudo-section"
else
  add_result no_bold_labels pass ""
fi

# --- voice checks -----------------------------------------------------------

# first_person: at least one first-person pronoun. The diary's idiomatic
# dropped-subject openings ("Started on...", "Was working on...") mean some
# genuine entries carry only a single I/my/me.
I_COUNT="$(printf '%s\n' "$ENTRY_TEXT" | grep -owE "I|I'd|I've|I'm|my|me|myself" | wc -l | tr -d ' ')"
if [[ "${I_COUNT:-0}" -ge 1 ]]; then
  add_result first_person pass ""
else
  add_result first_person fail "no first-person pronouns (I/my/me)"
fi

# past_tense: at least one common past-tense narrative verb.
if printf '%s\n' "$ENTRY_TEXT" | grep -qiwE 'tried|wrote|rewrote|pivoted|learned|fixed|broke|started|moved|found|hit|kept|noticed|realized|ran|added|removed|built|spent|failed|passed|changed|turned|was|were|had'; then
  add_result past_tense pass ""
else
  add_result past_tense fail "no past-tense narrative verbs found"
fi

# no_self_praise: self-evaluative vocabulary is banned by SKILL.md.
PRAISE="$(printf '%s\n' "$ENTRY_TEXT" | grep -oiwE 'elegant|elegantly|seamless|seamlessly|successfully|flawless|flawlessly|beautifully|masterful|masterfully' | sort -u | tr '\n' ' ')"
if [[ -n "$PRAISE" ]]; then
  add_result no_self_praise fail "self-praise vocabulary: $PRAISE"
else
  add_result no_self_praise pass ""
fi

# no_lesson_label: the lesson is a sentence, never a label.
if printf '%s\n' "$ENTRY_TEXT" | grep -qiE "lessons? learned|^lesson[: ]|takeaways?:|key takeaway"; then
  add_result no_lesson_label fail "labeled lesson section"
else
  add_result no_lesson_label pass ""
fi

# no_meta_text: assistant framing has no place inside an entry.
if printf '%s\n' "$ENTRY_TEXT" | grep -qiE "^here('s| is)|as an ai|based on the (events|log|session)|the events show|the diary entry"; then
  add_result no_meta_text fail "assistant meta-text framing"
else
  add_result no_meta_text pass ""
fi

# word_count: 60-900 words. Below: filler or fragment. Above: recap bloat
# (real accepted entries in the wild run 300-800 words).
WORDS="$(printf '%s\n' "$ENTRY_TEXT" | wc -w | tr -d ' ')"
if [[ "$WORDS" -ge 60 && "$WORDS" -le 900 ]]; then
  add_result word_count pass "$WORDS words"
else
  add_result word_count fail "$WORDS words (need 60-900)"
fi

# complete_ending: the last line must end like a finished sentence —
# mid-sentence cutoffs are a real local-model failure mode (output budget
# exhausted) that no other check catches.
LAST_LINE="$(printf '%s\n' "$ENTRY_TEXT" | sed -e 's/[[:space:]]*$//' | grep -v '^$' | tail -1)"
if printf '%s' "$LAST_LINE" | grep -qE '[.!?"”)]$'; then
  add_result complete_ending pass ""
else
  TAIL_SNIPPET="$(printf '%s' "$LAST_LINE" | tail -c 40)"
  add_result complete_ending fail "entry ends mid-sentence: …$TAIL_SNIPPET"
fi

# --- grounding checks (need events) ----------------------------------------

if [[ -n "$EVENTS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  # Candidate tokens that an entry grounded in this session would mention:
  # file basenames, command program names, and notable words (>=6 chars)
  # from user prompts.
  EVENT_TOKENS="$(jq -r '
      (.file_path // empty | split("/") | last),
      (.command // empty | split(" ") | first),
      (.prompt // empty | gsub("[^A-Za-z0-9_.-]"; " ") | split(" ")[] | select(length >= 6))
    ' "$EVENTS_FILE" 2>/dev/null | sort -u | grep -v '^$' || true)"

  MATCHED=0
  MATCHED_LIST=""
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if printf '%s' "$ENTRY_TEXT" | grep -qiF "$tok"; then
      MATCHED=$((MATCHED+1))
      MATCHED_LIST="$MATCHED_LIST$tok "
    fi
  done <<EOF
$EVENT_TOKENS
EOF
  if [[ "$MATCHED" -ge 2 ]]; then
    add_result grounded pass "matched: $MATCHED_LIST"
  else
    add_result grounded fail "only $MATCHED concrete tokens from the events appear (need >=2)"
  fi

  # no_hallucinated_files: every file-like token in the entry must exist in
  # the events (matched by basename).
  ENTRY_FILES="$(printf '%s\n' "$ENTRY_TEXT" | grep -oE '[A-Za-z0-9_][A-Za-z0-9_./-]*\.(py|sh|md|js|jsx|ts|tsx|json|jsonl|yml|yaml|toml|rs|go|java|rb|c|h|cpp|hpp|cc|html|css|sql|txt|swift|kt|conf|ini|lock)' | sort -u || true)"
  HALLUCINATED=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    base="${f##*/}"
    if ! grep -qiF "$base" "$EVENTS_FILE"; then
      HALLUCINATED="$HALLUCINATED$f "
    fi
  done <<EOF
$ENTRY_FILES
EOF
  if [[ -n "$HALLUCINATED" ]]; then
    add_result no_hallucinated_files fail "files not in events: $HALLUCINATED"
  else
    add_result no_hallucinated_files pass ""
  fi
else
  add_result grounded skip "no events file"
  add_result no_hallucinated_files skip "no events file"
fi

# --- report -----------------------------------------------------------------

N_PASS=0; N_FAIL=0; N_SKIP=0
while IFS='	' read -r name status detail; do
  [[ -z "$name" ]] && continue
  case "$status" in
    pass) N_PASS=$((N_PASS+1)) ;;
    fail) N_FAIL=$((N_FAIL+1)) ;;
    skip) N_SKIP=$((N_SKIP+1)) ;;
  esac
done <<EOF
$RESULTS
EOF

if [[ "$JSON" -eq 1 ]]; then
  printf '%s' "$RESULTS" | jq -Rn --arg entry "$ENTRY_FILE" \
    --argjson passed "$N_PASS" --argjson failed "$N_FAIL" --argjson skipped "$N_SKIP" '
    [inputs | select(length > 0) | split("\t") |
      {name: .[0],
       pass: (if .[1] == "pass" then true elif .[1] == "fail" then false else null end),
       status: .[1],
       detail: .[2]}] as $checks |
    {entry: $entry, checks: $checks, passed: $passed, failed: $failed,
     skipped: $skipped,
     score: (if ($passed + $failed) > 0 then ($passed / ($passed + $failed) * 100 | round / 100) else null end)}'
else
  while IFS='	' read -r name status detail; do
    [[ -z "$name" ]] && continue
    case "$status" in
      pass) echo "PASS $name" ;;
      fail) echo "FAIL $name — $detail" ;;
      skip) echo "SKIP $name — $detail" ;;
    esac
  done <<EOF
$RESULTS
EOF
  echo
  echo "passed=$N_PASS failed=$N_FAIL skipped=$N_SKIP"
fi

[[ "$N_FAIL" -eq 0 ]] || exit 1
exit 0
