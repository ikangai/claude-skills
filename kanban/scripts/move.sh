#!/usr/bin/env bash
#
# kanban move — change a card's status.
#
# Usage:
#   kanban move <card-id> <status> [--tokens=N]
#
# Status is one of: todo | in_progress | review | done.
#
# When moving to 'done', the assignment is preserved (so you can see who
# finished what). When moving back to 'todo', the assignment and
# claimed_at are cleared so another agent can pick it up.
#
# --tokens=N records the total tokens the task needed (absolute count,
# not additive). Typically set on the move to review/done, e.g.
#   kanban move <id> done --tokens=42100
# The in_progress clock (effort) is accounted automatically on the move.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban move: board not found at $BOARD." >&2; exit 1; }

CARD_ID=""; STATUS=""; TOKENS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tokens=*) TOKENS="${1#*=}"; shift ;;
    --tokens)   [[ $# -ge 2 ]] || { echo "kanban move: --tokens needs a value" >&2; exit 1; }; TOKENS="$2"; shift 2 ;;
    -*) echo "kanban move: unknown flag $1" >&2; exit 1 ;;
    *)  if [[ -z "$CARD_ID" ]]; then CARD_ID="$1"
        elif [[ -z "$STATUS" ]]; then STATUS="$1"
        else echo "Usage: kanban move <card-id> <status> [--tokens=N]" >&2; exit 1; fi; shift ;;
  esac
done

[[ -n "$CARD_ID" && -n "$STATUS" ]] || { echo "Usage: kanban move <card-id> <status> [--tokens=N]" >&2; exit 1; }
case "$STATUS" in todo|in_progress|review|done) ;; *) echo "kanban move: status must be todo|in_progress|review|done" >&2; exit 1 ;; esac
if [[ -n "$TOKENS" ]]; then
  [[ "$TOKENS" =~ ^[0-9]+$ ]] || { echo "kanban move: --tokens must be a non-negative integer" >&2; exit 1; }
fi

PATCH=$(python3 -c "
import json, sys
status, tokens = sys.argv[1], sys.argv[2]
patch = {'status': status}
if status == 'todo':
    patch['assigned_to'] = None
    patch['claimed_at'] = None
if tokens != '':
    patch['tokens'] = int(tokens)
print(json.dumps(patch))
" "$STATUS" "$TOKENS")

python3 "$SKILL_DIR/scripts/rwa_splice.py" --board "$BOARD" update "$CARD_ID" --json "$PATCH"
echo "moved $CARD_ID -> $STATUS${TOKENS:+ (${TOKENS} tok)}"
