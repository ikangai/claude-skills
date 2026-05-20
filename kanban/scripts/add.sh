#!/usr/bin/env bash
#
# kanban add — append a card to .kanban/board.html
#
# Usage:
#   kanban add "Title of the card" [--priority=high|medium|low|none]
#                                  [--tags=auth,refactor]
#                                  [--description="..."]
#                                  [--id=custom-slug]
#
# The id defaults to YYYY-MM-DD-<slug>, where <slug> is derived from the
# title (lowercased, non-alnum → -, collapsed, trimmed, max 40 chars).
# Status defaults to 'todo'.
#
# Prints the resulting card id on success.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
BOARD="$PROJECT_DIR/.kanban/board.html"

[[ -f "$BOARD" ]] || { echo "kanban add: board not found at $BOARD. Run 'kanban init' first." >&2; exit 1; }

TITLE=""
PRIORITY="none"
TAGS=""
DESCRIPTION=""
ID_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority=*)    PRIORITY="${1#*=}"; shift ;;
    --tags=*)        TAGS="${1#*=}"; shift ;;
    --description=*) DESCRIPTION="${1#*=}"; shift ;;
    --id=*)          ID_OVERRIDE="${1#*=}"; shift ;;
    --priority)      PRIORITY="$2"; shift 2 ;;
    --tags)          TAGS="$2"; shift 2 ;;
    --description)   DESCRIPTION="$2"; shift 2 ;;
    --id)            ID_OVERRIDE="$2"; shift 2 ;;
    --) shift; TITLE="$*"; break ;;
    -*) echo "kanban add: unknown flag $1" >&2; exit 1 ;;
    *)  if [[ -z "$TITLE" ]]; then TITLE="$1"; else TITLE="$TITLE $1"; fi; shift ;;
  esac
done

[[ -n "$TITLE" ]] || { echo "kanban add: title required" >&2; exit 1; }
case "$PRIORITY" in high|medium|low|none) ;; *) echo "kanban add: priority must be high|medium|low|none" >&2; exit 1 ;; esac

# Derive id from title if not overridden.
if [[ -n "$ID_OVERRIDE" ]]; then
  CARD_ID="$ID_OVERRIDE"
else
  SLUG=$(printf '%s' "$TITLE" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g; s/-+/-/g' \
    | cut -c1-40 \
    | sed -E 's/-+$//')
  DATE=$(date -u +%Y-%m-%d)
  CARD_ID="${DATE}-${SLUG:-card}"
fi

# Build the card JSON with python so quoting stays safe regardless of input.
python3 - "$BOARD" "$CARD_ID" "$TITLE" "$PRIORITY" "$DESCRIPTION" "$TAGS" "$SKILL_DIR" <<'PY'
import sys, json, subprocess

board, cid, title, priority, desc, tags_str, skill_dir = sys.argv[1:8]
tags = [t.strip() for t in tags_str.split(',') if t.strip()] if tags_str else []

card = {"id": cid, "title": title, "priority": priority, "tags": tags}
if desc: card["description"] = desc

r = subprocess.run(
    ["python3", f"{skill_dir}/scripts/rwa_splice.py", "--board", board, "add", "--json", json.dumps(card)],
    check=False,
)
sys.exit(r.returncode)
PY
