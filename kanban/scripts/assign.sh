#!/usr/bin/env bash
#
# kanban assign — set a card's assignee without claiming it yourself.
#
# Usage:
#   kanban assign <card-id> <agent-name> [--move=<status>]
#
# Unlike claim, assign is the explicit-handoff verb: "alpha is taking
# this", "this needs human review by Martin". It overwrites assigned_to
# unconditionally and stamps claimed_at to now. It does NOT change
# status by default — pass --move=<status> if the handoff also implies
# a column change (e.g. --move=review for "human, please review").
#
# The agent name is a free-form string. The skill has no user
# directory; the browser renders whatever you set as a chip on the
# card. Match the casing of existing assignees on the board when
# possible (don't create both "alpha" and "Alpha").

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban assign: board not found at $BOARD." >&2; exit 1; }

CARD_ID=""
AGENT=""
MOVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --move=*) MOVE="${1#*=}"; shift ;;
    --move)   [[ $# -ge 2 ]] || { echo "kanban assign: --move needs a value" >&2; exit 1; }; MOVE="$2"; shift 2 ;;
    -*) echo "kanban assign: unknown flag $1" >&2; exit 1 ;;
    *)  if   [[ -z "$CARD_ID" ]]; then CARD_ID="$1"
        elif [[ -z "$AGENT"   ]]; then AGENT="$1"
        else echo "kanban assign: too many positional args" >&2; exit 1
        fi
        shift ;;
  esac
done

[[ -n "$CARD_ID" ]] || { echo "Usage: kanban assign <card-id> <agent-name> [--move=<status>]" >&2; exit 1; }
[[ -n "$AGENT"   ]] || { echo "Usage: kanban assign <card-id> <agent-name> [--move=<status>]" >&2; exit 1; }
if [[ -n "$MOVE" ]]; then
  case "$MOVE" in
    todo|in_progress|review|done) ;;
    *) echo "kanban assign: --move must be todo|in_progress|review|done" >&2; exit 1 ;;
  esac
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ -n "$MOVE" ]]; then
  PATCH=$(python3 -c "import json,sys; print(json.dumps({'assigned_to': sys.argv[1], 'claimed_at': sys.argv[2], 'status': sys.argv[3]}))" "$AGENT" "$NOW" "$MOVE")
else
  PATCH=$(python3 -c "import json,sys; print(json.dumps({'assigned_to': sys.argv[1], 'claimed_at': sys.argv[2]}))" "$AGENT" "$NOW")
fi

python3 "$SKILL_DIR/scripts/rwa_splice.py" --board "$BOARD" update "$CARD_ID" --json "$PATCH"
echo "assigned $CARD_ID to $AGENT"
