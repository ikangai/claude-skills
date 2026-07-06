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
import sys, json, subprocess, math
from datetime import datetime, timezone

board, status_filter, agent_filter, skill_dir = sys.argv[1:5]
r = subprocess.run(
    ["python3", f"{skill_dir}/scripts/rwa_splice.py", "--board", board, "read"],
    capture_output=True, text=True, check=True,
)
cards = json.loads(r.stdout)
if status_filter: cards = [c for c in cards if c.get("status") == status_filter]
if agent_filter:  cards = [c for c in cards if c.get("assigned_to") == agent_filter]

def _parse_iso(s):
    if not s or not isinstance(s, str): return None
    t = s.strip()
    if t.endswith("Z"): t = t[:-1]
    if "." in t: t = t.split(".", 1)[0]
    try: return datetime.strptime(t, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError: return None

def humanize_duration(sec):
    sec = max(0, int(sec))
    if sec < 60: return f"{sec}s"
    m = sec // 60
    if m < 60: return f"{m}m"
    h, rm = m // 60, m % 60
    if h < 24: return f"{h}h {rm}m" if rm else f"{h}h"
    d, rh = h // 24, h % 24
    return f"{d}d {rh}h" if rh else f"{d}d"

def humanize_tokens(n):
    # Must render identically to humanizeTokens() in seeds/kanban-body.html,
    # which uses JS Math.round (half-up) and Number->String (drops trailing .0).
    # Mirror that arithmetic exactly rather than Python's round() (banker's,
    # keeps .0), or the board chip and this table disagree at .0/.x5 boundaries.
    n = max(0, int(n))
    if n < 1000: return str(n)
    def one_dp(x):            # Math.round(x*10)/10, then drop a trailing .0
        v = math.floor(x * 10 + 0.5) / 10
        return str(int(v)) if v == int(v) else str(v)
    def whole(x):             # Math.round(x) for x >= 100
        return str(int(math.floor(x + 0.5)))
    if n < 1_000_000:
        k = n / 1000; return (whole(k) if k >= 100 else one_dp(k)) + "k"
    mm = n / 1_000_000; return (whole(mm) if mm >= 100 else one_dp(mm)) + "M"

def effective_effort(c):
    base = max(0, int(c.get("effort_seconds") or 0))
    started = _parse_iso(c.get("effort_started_at"))
    if started is not None:
        base += max(0, int((datetime.now(timezone.utc) - started).total_seconds()))
    return base

def cost_part(c):
    bits = []
    if c.get("model"): bits.append(str(c["model"]))
    eff = effective_effort(c)
    if eff > 0 or c.get("effort_started_at"):
        bits.append(humanize_duration(eff) + ("*" if c.get("effort_started_at") else ""))
    if c.get("tokens"): bits.append(humanize_tokens(c["tokens"]) + " tok")
    return "  · " + " · ".join(bits) if bits else ""

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
        print(f"  {pri_marker} {c.get('id','?')}  {c.get('title','(untitled)')}{agent_part}{tag_part}{cost_part(c)}")
    print()
if any(c.get("effort_started_at") for c in cards):
    print("(effort marked * is still running)")
PY
