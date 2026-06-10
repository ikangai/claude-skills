#!/usr/bin/env bash
#
# detect-synth.sh — first-run auto-detection of the diary synthesis backend.
#
# Probes the local LM Studio server and walks the list of suitable models
# (the ones that measured well in the diary eval — see
# references/local-models.md). First suitable model the server serves wins:
# backend "local" with that model. Server unreachable, or none of the
# served models suitable: backend "sonnet" — headless synthesis via
# `claude -p --model sonnet`.
#
# The decision is persisted to .dev-diary/.synth-config (JSON) so detection
# runs once per project. Re-detect after the environment changes (LM Studio
# installed, a suitable model downloaded) by deleting the file or passing
# --force.
#
# Usage:
#   detect-synth.sh [--config FILE] [--url URL] [--force] [--quiet]
#
#   --config FILE  config path (default: $CLAUDE_PROJECT_DIR/.dev-diary/.synth-config)
#   --url URL      server base URL to probe (default: $DIARY_LM_URL, else
#                  http://localhost:1234/v1)
#   --force        re-probe even if a config already exists
#   --quiet        suppress the result line
#
# Environment:
#   DIARY_LM_URL           probe URL (overridden by --url)
#   DIARY_LM_MODEL         pinned model — tried before the suitable list,
#                          so an explicit pin always wins when served
#   DIARY_SUITABLE_MODELS  comma-separated override of the built-in
#                          suitable-model list
#
# Output: one line, "backend=local model=<id>" or "backend=sonnet".
# Exit codes: 0 decision made (or config already present), 2 usage error.
#
# Dependencies: bash 3.2+, curl, jq.

set -u

LM_URL="${DIARY_LM_URL:-http://localhost:1234/v1}"
CONFIG="${CLAUDE_PROJECT_DIR:-$PWD}/.dev-diary/.synth-config"
FORCE=0
QUIET=0

# Models that cleared the 2026-06-10 eval (mechanical linter + judge pass,
# including correctly declining routine sessions). Deliberately short:
# "suitable" means measured, not merely present. glm-4.7-flash is excluded
# — best faithfulness, but its reasoning latency times out on large
# sessions; gpt-oss-20b is excluded for writing filler instead of NO ENTRY.
SUITABLE_DEFAULT="google/gemma-4-26b-a4b,qwen3.6-35b-a3b-configi-mlx"

usage() {
  sed -n '5,38p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --url)    LM_URL="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
[[ -z "$CONFIG" ]] && { echo "--config requires a path" >&2; exit 2; }

# Already decided and not forced: report the existing decision and leave.
if [[ -f "$CONFIG" && "$FORCE" -ne 1 ]]; then
  if EXISTING="$(jq -re '"backend=" + .backend + (if .model then " model=" + .model else "" end)' "$CONFIG" 2>/dev/null)"; then
    [[ "$QUIET" -eq 1 ]] || echo "$EXISTING (existing config: $CONFIG)"
    exit 0
  fi
  # Corrupt config — fall through and re-detect over it.
fi

# Candidate list: an explicit DIARY_LM_MODEL pin first, then the suitable
# models in measured-quality order.
CANDIDATES="${DIARY_LM_MODEL:+$DIARY_LM_MODEL,}${DIARY_SUITABLE_MODELS:-$SUITABLE_DEFAULT}"

# Probe the server. Short timeout — this runs inside a Stop hook on the
# project's first session; a down server must fail fast, not hang.
SERVED="$(curl -sS --max-time 5 "$LM_URL/models" 2>/dev/null \
  | jq -r '.data[].id' 2>/dev/null)"

BACKEND="sonnet"
MODEL=""
if [[ -n "$SERVED" ]]; then
  OLD_IFS="$IFS"; IFS=','
  for candidate in $CANDIDATES; do
    [[ -z "$candidate" ]] && continue
    if printf '%s\n' "$SERVED" | grep -qxF "$candidate"; then
      BACKEND="local"
      MODEL="$candidate"
      break
    fi
  done
  IFS="$OLD_IFS"
fi

# Record where the claude CLI lives now — hooks can run with a leaner PATH
# than an interactive shell, and a stored absolute path keeps the sonnet
# backend working there.
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"

mkdir -p "$(dirname "$CONFIG")" 2>/dev/null
jq -n \
  --arg backend "$BACKEND" \
  --arg model "$MODEL" \
  --arg url "$LM_URL" \
  --arg claude_bin "$CLAUDE_BIN" \
  --arg detected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{backend: $backend, url: $url, detected_at: $detected_at}
   + (if $model != "" then {model: $model} else {} end)
   + (if $claude_bin != "" then {claude_bin: $claude_bin} else {} end)' \
  > "$CONFIG"

if [[ "$QUIET" -ne 1 ]]; then
  if [[ "$BACKEND" == "local" ]]; then
    echo "backend=local model=$MODEL"
  else
    echo "backend=sonnet"
  fi
fi
exit 0
