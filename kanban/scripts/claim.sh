#!/usr/bin/env bash
#
# kanban claim — claim a card for an agent.
#
# Usage:
#   kanban claim <card-id> [--agent=<name>] [--no-move]
#
# Default behavior: sets assigned_to + claimed_at and moves status to
# in_progress. --no-move keeps the current status (useful if you're
# claiming something already in review).
#
# Agent identity, in order of preference:
#   1. --agent=<name> flag
#   2. $KANBAN_AGENT_NAME env var
#   3. short hash of $CLAUDE_SESSION_ID
#   4. literal "agent" (fallback so the field is never empty)
#
# Exits 2 if the card is already claimed by a different agent (use
# --force to override).

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban claim: board not found at $BOARD." >&2; exit 1; }

CARD_ID=""
AGENT_FLAG=""
MODEL="${KANBAN_MODEL:-}"
NO_MOVE=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent=*) AGENT_FLAG="${1#*=}"; shift ;;
    --agent)   [[ $# -ge 2 ]] || { echo "kanban claim: --agent needs a value" >&2; exit 1; }; AGENT_FLAG="$2"; shift 2 ;;
    --model=*) MODEL="${1#*=}"; shift ;;
    --model)   [[ $# -ge 2 ]] || { echo "kanban claim: --model needs a value" >&2; exit 1; }; MODEL="$2"; shift 2 ;;
    --no-move) NO_MOVE=1; shift ;;
    --force)   FORCE=1; shift ;;
    -*) echo "kanban claim: unknown flag $1" >&2; exit 1 ;;
    *)  if [[ -z "$CARD_ID" ]]; then CARD_ID="$1"; else echo "kanban claim: only one card id allowed" >&2; exit 1; fi; shift ;;
  esac
done

[[ -n "$CARD_ID" ]] || { echo "kanban claim: card id required" >&2; exit 1; }

# Resolve agent identity.
if [[ -n "$AGENT_FLAG" ]]; then
  AGENT="$AGENT_FLAG"
elif [[ -n "${KANBAN_AGENT_NAME:-}" ]]; then
  AGENT="$KANBAN_AGENT_NAME"
elif [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
  AGENT="$(printf '%s' "$CLAUDE_SESSION_ID" | cut -c1-8)"
else
  AGENT="agent"
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check existing claim unless --force.
if [[ "$FORCE" -ne 1 ]]; then
  CURRENT=$(python3 "$SKILL_DIR/scripts/rwa_splice.py" --board "$BOARD" read \
    | python3 -c "import sys,json; cards=json.load(sys.stdin); m={c.get('id'):c for c in cards}; c=m.get(sys.argv[1]); print(json.dumps(c) if c else 'null')" "$CARD_ID")
  if [[ "$CURRENT" == "null" ]]; then
    echo "kanban claim: card not found: $CARD_ID" >&2
    exit 2
  fi
  EXISTING_AGENT=$(printf '%s' "$CURRENT" | python3 -c "import sys,json; c=json.load(sys.stdin); print(c.get('assigned_to') or '')")
  if [[ -n "$EXISTING_AGENT" && "$EXISTING_AGENT" != "$AGENT" ]]; then
    echo "kanban claim: card $CARD_ID already claimed by $EXISTING_AGENT (use --force to take over)" >&2
    exit 2
  fi
fi

# Build the patch: always assigned_to + claimed_at; add status unless
# --no-move; add model when one was supplied (flag or $KANBAN_MODEL).
PATCH=$(python3 -c "
import json, sys
agent, now, model, no_move = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
patch = {'assigned_to': agent, 'claimed_at': now}
if no_move != '1':
    patch['status'] = 'in_progress'
if model:
    patch['model'] = model
print(json.dumps(patch))
" "$AGENT" "$NOW" "$MODEL" "$NO_MOVE")

python3 "$SKILL_DIR/scripts/rwa_splice.py" --board "$BOARD" update "$CARD_ID" --json "$PATCH"
echo "claimed $CARD_ID by $AGENT${MODEL:+ ($MODEL)}"
