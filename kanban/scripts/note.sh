#!/usr/bin/env bash
#
# kanban note — append a timestamped note to a card.
#
# Usage:
#   kanban note <card-id> "Your note text"
#
# Notes accumulate on a card as a chronological log of what's happened.
# They show up on the card detail (not in the board column view).

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban note: board not found at $BOARD." >&2; exit 1; }

[[ $# -ge 2 ]] || { echo "Usage: kanban note <card-id> \"note text\"" >&2; exit 1; }
CARD_ID="$1"; shift; TEXT="$*"

# Resolve agent identity (same logic as claim.sh).
if [[ -n "${KANBAN_AGENT_NAME:-}" ]]; then
  AGENT="$KANBAN_AGENT_NAME"
elif [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
  AGENT="$(printf '%s' "$CLAUDE_SESSION_ID" | cut -c1-8)"
else
  AGENT=""
fi
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

python3 - "$BOARD" "$CARD_ID" "$TEXT" "$AGENT" "$NOW" "$SKILL_DIR" <<'PY'
import sys, json, subprocess

board, cid, text, agent, ts, skill_dir = sys.argv[1:7]

# Read current card to append to notes array.
r = subprocess.run(
    ["python3", f"{skill_dir}/scripts/rwa_splice.py", "--board", board, "read"],
    capture_output=True, text=True, check=True,
)
cards = json.loads(r.stdout)
card = next((c for c in cards if c.get("id") == cid), None)
if card is None:
    sys.stderr.write(f"kanban note: card not found: {cid}\n"); sys.exit(2)

notes = card.get("notes") or []
notes.append({"ts": ts, "by": agent, "text": text})

patch = {"notes": notes}
r2 = subprocess.run(
    ["python3", f"{skill_dir}/scripts/rwa_splice.py", "--board", board, "update", cid, "--json", json.dumps(patch)],
    check=False,
)
sys.exit(r2.returncode)
PY
echo "noted on $CARD_ID"
