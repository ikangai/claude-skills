#!/usr/bin/env bash
#
# synthesize-local.sh — synthesize a diary entry with a local model.
#
# Reads one session's events from .dev-diary/.events.jsonl, asks an
# OpenAI-compatible local server (LM Studio) to write the entry in the
# diary skill's voice, validates the response shape, and writes
# .dev-diary/YYYY-MM-DD-<slug>.md.
#
# This is the events-only synthesis path: the model sees the event log and
# nothing else. In-session synthesis by Claude (which has the full
# conversation) produces richer entries; this script trades that context
# for zero token cost and offline operation. See references/local-models.md
# for when to use which, and for measured model quality.
#
# Usage:
#   synthesize-local.sh [--events FILE] [--session ID] [--out DIR]
#                       [--model ID] [--dry-run] [--stdout]
#
#   --events FILE   events log (default: $CLAUDE_PROJECT_DIR/.dev-diary/.events.jsonl)
#   --session ID    session to synthesize (default: last session in the log)
#   --out DIR       output directory (default: directory of the events file)
#   --model ID      model id (default: $DIARY_LM_MODEL, else
#                   google/gemma-4-26b-a4b if the server lists it — the
#                   measured best, see references/local-models.md — else
#                   the first non-embedding model the server reports)
#   --dry-run       print the prompt and exit without calling the server
#   --stdout        print the entry instead of writing a file
#
# Environment:
#   DIARY_LM_URL         base URL (default http://localhost:1234/v1)
#   DIARY_LM_MODEL       model id (overridden by --model)
#   DIARY_LM_TEMP        sampling temperature (default 0.2)
#   DIARY_LM_MAX_TOKENS  completion budget (default 4096 — reasoning models
#                        spend part of this thinking; below ~4096 they can
#                        return empty content)
#   DIARY_LM_TIMEOUT     request timeout in seconds (default 300; first call
#                        to an unloaded model includes JIT model load)
#
# Exit codes:
#   0  entry written, printed, or model declined with NO ENTRY
#   1  server/model failure (caller may fall back to in-session synthesis)
#   2  usage error
#
# Dependencies: bash 3.2+, curl, jq, date.

set -u

LM_URL="${DIARY_LM_URL:-http://localhost:1234/v1}"
MODEL="${DIARY_LM_MODEL:-}"
TEMP="${DIARY_LM_TEMP:-0.2}"
MAX_TOKENS="${DIARY_LM_MAX_TOKENS:-4096}"
TIMEOUT="${DIARY_LM_TIMEOUT:-300}"

EVENTS="${CLAUDE_PROJECT_DIR:-$PWD}/.dev-diary/.events.jsonl"
SESSION=""
OUT_DIR=""
DRY_RUN=0
TO_STDOUT=0

usage() {
  sed -n '5,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --events)  EVENTS="${2:-}"; shift 2 ;;
    --session) SESSION="${2:-}"; shift 2 ;;
    --out)     OUT_DIR="${2:-}"; shift 2 ;;
    --model)   MODEL="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --stdout)  TO_STDOUT=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }

if [[ -z "$EVENTS" || ! -f "$EVENTS" ]]; then
  echo "events file not found: $EVENTS" >&2
  exit 2
fi
[[ -z "$OUT_DIR" ]] && OUT_DIR="$(dirname "$EVENTS")"

# Default to the most recent session in the (chronological, append-only) log.
if [[ -z "$SESSION" ]]; then
  SESSION="$(jq -Rrs '
    split("\n") | map(try fromjson catch empty) |
    map(.session_id // empty) | map(select(. != "")) | last // empty
  ' "$EVENTS")"
fi
if [[ -z "$SESSION" ]]; then
  echo "no session_id found in $EVENTS" >&2
  exit 2
fi

# Compact the session's events to one readable line each. Local models
# attend better to flat text than raw JSON, and exit codes carry the
# narrative, so they stay prominent.
EVENT_LINES="$(jq -Rrs --arg sid "$SESSION" '
  def trunc: if length > 400 then .[0:400] + "…" else . end;
  split("\n") | map(try fromjson catch empty) |
  map(select(.session_id == $sid)) |
  map(
    .ts + " " +
    (if .kind == "prompt" then "user prompt: " + ((.prompt // "") | trunc)
     elif .kind == "edit" then "file edited (" + (.tool // "?") + "): " + (.file_path // "")
     elif .kind == "bash" then
       "command (exit " + ((.exit_code // "?") | tostring) + "): " + ((.command // "") | trunc)
       + (if .description then "  # " + .description else "" end)
     elif .kind == "subagent" then "subagent finished: " + ((.last_message // "") | trunc)
     elif .kind == "stop" then "turn ended: " + ((.last_message // "") | trunc)
     else .kind end)
  ) | join("\n")
' "$EVENTS")"

if [[ -z "$EVENT_LINES" ]]; then
  echo "no events for session $SESSION in $EVENTS" >&2
  exit 2
fi

EVENT_COUNT="$(printf '%s\n' "$EVENT_LINES" | wc -l | tr -d ' ')"
PROJECT="$(jq -Rrs --arg sid "$SESSION" '
  split("\n") | map(try fromjson catch empty) |
  map(select(.session_id == $sid)) | map(.cwd // empty) |
  map(select(. != "")) | last // "" | split("/") | last // "project"
' "$EVENTS")"
TODAY="$(date +%Y-%m-%d)"

SYSTEM_PROMPT='You write development diary entries for a software project. You see the raw event log of one working session: user prompts, file edits, shell commands with exit codes, and end-of-turn assistant summaries. From those events you reconstruct what happened and write the entry the developer would write in a notebook at the end of the day.

Voice and structure rules:
- First person, past tense. Chronological narrative. One flowing piece of prose (paragraphs allowed, 100-400 words total).
- No section headers, no bullet or numbered lists, no bold labels.
- Concrete and specific: name files, commands, and errors exactly as they appear in the events. Never mention a file, library, or error that is not in the events.
- Document reversals explicitly: what was tried, where it broke, what it was changed to, and why.
- End with one short sentence stating the lesson, only if one was genuinely earned. No "Lesson:" label.
- No self-evaluation (no "elegant", "successfully", "seamless"). No assistant framing (no "Here is the entry", no "Based on the events").

Example of the target voice:
Started on the shishi bucket — content-aware event accumulator for tmuxllm. First instinct was a ring buffer with fixed-size window. Wrote about eighty lines and hit a wall: when events arrive in bursts, the window drops context I want to keep, because relevance is not correlated with recency. Tried weighting by token count next — keep the heavy stuff, drop the rest. Broke on a different axis: short events can be high-relevance, long events can be padding. Token count is not a relevance signal. Pivoted to a content-aware filter at ingestion. Worked in about two hours after the pivot. Token count is a tempting proxy for relevance and it is wrong.

Output format, exactly:
SLUG: <two-to-five-lowercase-words-separated-by-hyphens-naming-the-substance>

<the entry>

The bar for writing at all: would a future agent benefit from knowing this, beyond what the code itself records? If the session was routine — only reading, questions answered, no substantive change, decision, or learning — do not write an entry. In that case output exactly:
NO ENTRY
<one short line saying why>'

USER_PROMPT="Project: $PROJECT
Date: $TODAY
Session events ($EVENT_COUNT events, chronological):

$EVENT_LINES

Hard constraints, restated: first person, past tense, one flowing narrative; no headers, no bullets, no bold labels; mention only files and commands that appear in the events above; 100-400 words; the first line of your output is \"SLUG: <slug>\" — or output exactly \"NO ENTRY\" plus one reason line if the session does not warrant an entry."

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '=== system ===\n%s\n\n=== user ===\n%s\n' "$SYSTEM_PROMPT" "$USER_PROMPT"
  exit 0
fi

# Resolve the model if none was specified: prefer the measured-best model
# from the 2026-06-10 evaluation (references/local-models.md) when the
# server lists it, else the first non-embedding model the server reports.
PREFERRED_MODEL="google/gemma-4-26b-a4b"
if [[ -z "$MODEL" ]]; then
  MODEL="$(curl -sS --max-time "$TIMEOUT" "$LM_URL/models" 2>/dev/null \
    | jq -r --arg pref "$PREFERRED_MODEL" \
      '[.data[].id | select(test("embed") | not)]
       | (if index($pref) then $pref else first end) // empty' 2>/dev/null)"
  if [[ -z "$MODEL" ]]; then
    echo "could not discover a model from $LM_URL/models — is LM Studio running? (set DIARY_LM_MODEL to skip discovery)" >&2
    exit 1
  fi
fi

REQUEST="$(jq -n \
  --arg model "$MODEL" \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$USER_PROMPT" \
  --argjson temp "$TEMP" \
  --argjson max_tokens "$MAX_TOKENS" \
  '{model: $model,
    messages: [{role: "system", content: $system}, {role: "user", content: $user}],
    temperature: $temp,
    max_tokens: $max_tokens,
    stream: false}')"

RESPONSE_FILE="$(mktemp -t diary-synth-response.XXXXXX)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

HTTP_CODE="$(printf '%s' "$REQUEST" | curl -sS --max-time "$TIMEOUT" \
  -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d @- "$LM_URL/chat/completions" 2>/dev/null)" || {
  echo "request to $LM_URL/chat/completions failed — is LM Studio running?" >&2
  exit 1
}

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "server returned HTTP $HTTP_CODE: $(head -c 300 "$RESPONSE_FILE")" >&2
  exit 1
fi

CONTENT="$(jq -r '.choices[0].message.content // empty' "$RESPONSE_FILE" 2>/dev/null)"

# Strip reasoning blocks (<think>…</think>) and truncate at the first
# chat-template token leak (<|user|>, <|im_end|>, …) — both observed
# failure modes of local models.
CONTENT="$(printf '%s\n' "$CONTENT" | sed 's/<think>.*<\/think>//' | sed '/<think>/,/<\/think>/d')"
CONTENT="${CONTENT%%<|*}"
# Trim leading/trailing blank lines.
CONTENT="$(printf '%s\n' "$CONTENT" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ -z "$CONTENT" ]]; then
  echo "model returned empty content — reasoning may have consumed the completion budget; try raising DIARY_LM_MAX_TOKENS (currently $MAX_TOKENS)" >&2
  exit 1
fi

FIRST_LINE="$(printf '%s\n' "$CONTENT" | head -1)"

if printf '%s' "$FIRST_LINE" | grep -qE '^[[:space:]]*NO ENTRY'; then
  REASON="$(printf '%s\n' "$CONTENT" | sed -n '2p')"
  echo "Model declined — no entry written. ${REASON:+Reason: $REASON}"
  exit 0
fi

if printf '%s' "$FIRST_LINE" | grep -qE '^[[:space:]]*SLUG:'; then
  RAW_SLUG="${FIRST_LINE#*SLUG:}"
  BODY="$(printf '%s\n' "$CONTENT" | tail -n +2 | sed '/./,$!d')"
else
  # No SLUG line — accept the prose but name the file generically.
  RAW_SLUG="diary-entry"
  BODY="$CONTENT"
fi

SLUG="$(printf '%s' "$RAW_SLUG" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -d- -f1-5)"
[[ -z "$SLUG" ]] && SLUG="diary-entry"

if [[ -z "$BODY" ]]; then
  echo "model returned a slug but no entry body" >&2
  exit 1
fi

if [[ "$TO_STDOUT" -eq 1 ]]; then
  printf '%s\n' "$BODY"
  exit 0
fi

mkdir -p "$OUT_DIR" 2>/dev/null
TARGET="$OUT_DIR/$TODAY-$SLUG.md"
N=2
while [[ -e "$TARGET" ]]; do
  TARGET="$OUT_DIR/$TODAY-$SLUG-$N.md"
  N=$((N+1))
done

printf '%s\n' "$BODY" > "$TARGET"
echo "Wrote $TARGET (model: $MODEL, session: $SESSION)"
exit 0
