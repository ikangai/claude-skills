#!/usr/bin/env bash
#
# kanban list — list cards on the board.
#
# Usage:
#   kanban list                              # all cards, grouped by column
#   kanban list --status=todo                # one column
#   kanban list --agent=alpha                # filtered by assignee
#   kanban list --json                       # raw JSON for downstream use
#
# Default output is a compact table grouped by column, suitable for both
# human reading and quick agentic scanning. --json is for scripting.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban list: board not found at $BOARD." >&2; exit 1; }

STATUS=""; AGENT=""; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status=*) STATUS="${1#*=}"; shift ;;
    --agent=*)  AGENT="${1#*=}"; shift ;;
    --status)   STATUS="$2"; shift 2 ;;
    --agent)    AGENT="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    *)          echo "kanban list: unknown arg $1" >&2; exit 1 ;;
  esac
done

ARGS=(--board "$BOARD" list)
[[ -n "$STATUS" ]] && ARGS+=(--status "$STATUS")
[[ -n "$AGENT"  ]] && ARGS+=(--agent "$AGENT")

if [[ "$JSON" -eq 1 ]]; then
  python3 "$SKILL_DIR/scripts/rwa_splice.py" "${ARGS[@]}"
  exit 0
fi

# Human-readable grouping.
python3 - "$BOARD" "$STATUS" "$AGENT" "$SKILL_DIR" <<'PY'
import sys, json, subprocess

board, status_filter, agent_filter, skill_dir = sys.argv[1:5]
r = subprocess.run(
    ["python3", f"{skill_dir}/scripts/rwa_splice.py", "--board", board, "read"],
    capture_output=True, text=True, check=True,
)
cards = json.loads(r.stdout)
if status_filter: cards = [c for c in cards if c.get("status") == status_filter]
if agent_filter:  cards = [c for c in cards if c.get("assigned_to") == agent_filter]

order = ["todo", "in_progress", "review", "done"]
labels = {"todo": "TO DO", "in_progress": "IN PROGRESS", "review": "REVIEW", "done": "DONE"}
groups = {s: [] for s in order}
for c in cards:
    s = c.get("status", "todo")
    if s in groups: groups[s].append(c)

if not cards:
    print("(no cards)")
    sys.exit(0)

for s in order:
    if not groups[s]: continue
    print(f"{labels[s]}  ({len(groups[s])})")
    for c in groups[s]:
        pri = c.get("priority", "none")
        pri_marker = {"high": "!", "medium": "·", "low": " ", "none": " "}.get(pri, " ")
        agent = c.get("assigned_to") or ""
        agent_part = f"  [{agent}]" if agent else ""
        tags = c.get("tags") or []
        tag_part = f"  {' '.join('#' + t for t in tags[:3])}" if tags else ""
        print(f"  {pri_marker} {c.get('id','?')}  {c.get('title','(untitled)')}{agent_part}{tag_part}")
    print()
PY
