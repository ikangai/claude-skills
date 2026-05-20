#!/usr/bin/env bash
#
# kanban move — change a card's status.
#
# Usage:
#   kanban move <card-id> <status>
#
# Status is one of: todo | in_progress | review | done.
#
# When moving to 'done', the assignment is preserved (so you can see who
# finished what). When moving back to 'todo', the assignment and
# claimed_at are cleared so another agent can pick it up.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban move: board not found at $BOARD." >&2; exit 1; }

[[ $# -eq 2 ]] || { echo "Usage: kanban move <card-id> <status>" >&2; exit 1; }
CARD_ID="$1"; STATUS="$2"

case "$STATUS" in todo|in_progress|review|done) ;; *) echo "kanban move: status must be todo|in_progress|review|done" >&2; exit 1 ;; esac

if [[ "$STATUS" == "todo" ]]; then
  PATCH='{"status":"todo","assigned_to":null,"claimed_at":null}'
else
  PATCH=$(python3 -c "import json,sys; print(json.dumps({'status': sys.argv[1]}))" "$STATUS")
fi

python3 "$SKILL_DIR/scripts/rwa_splice.py" --board "$BOARD" update "$CARD_ID" --json "$PATCH"
echo "moved $CARD_ID -> $STATUS"
