#!/usr/bin/env bash
#
# kanban upgrade — rebuild an existing board.html on the current seed body,
# preserving its cards.
#
# Existing boards never pick up seed fixes on their own: the CLI splices only
# the cards JSON, so the runtime + kanban body in a deployed board stay
# whatever generation they were created from. This script closes that gap:
#
#   1. read the cards out of the old board (rwa_splice.py read)
#   2. build a fresh container from the current seed (same path as init.sh)
#   3. splice the cards back in (rwa_splice.py write)
#   4. back up the old board, atomically replace it with the new one
#
# The fresh container gets a NEW document UUID. That is deliberate: browser
# IndexedDB state is namespaced by UUID, so any stale IDB doc from the old
# board generation cannot shadow the upgraded body on next open.
#
# Usage:
#   upgrade.sh [path/to/board.html] [--force]
#
# With no path, defaults to $CLAUDE_PROJECT_DIR/.kanban/board.html.
# Already-current boards (seed generation matches) are a no-op unless --force.
#
# Exit codes: 0 upgraded or already current, 1 error.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$SKILL_DIR/scripts"
SEED_BODY="$SKILL_DIR/seeds/kanban-body.html"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

BOARD=""
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) echo "kanban upgrade: unknown flag: $arg" >&2; exit 1 ;;
    *) BOARD="$arg" ;;
  esac
done
BOARD="${BOARD:-$PROJECT_DIR/.kanban/board.html}"

if [[ ! -f "$BOARD" ]]; then
  echo "kanban upgrade: board not found at $BOARD." >&2
  exit 1
fi
if [[ ! -f "$SEED_BODY" ]]; then
  echo "kanban upgrade: seed body not found at $SEED_BODY." >&2
  exit 1
fi

# Generation check: a marker identifier present in the current seed body but
# absent from older generations. Kept in one place so future seeds only need
# this line changed if the marker ever rotates. Rotate it whenever the seed's
# render/runtime changes in a way deployed boards should pick up.
#   draggedKey            → file↔browser sync generation (2026-06)
#   applyEffortTransition → model / effort / tokens tracking (2026-07)
GEN_MARKER="applyEffortTransition"
if ! grep -q "$GEN_MARKER" "$SEED_BODY"; then
  echo "kanban upgrade: seed body lacks generation marker '$GEN_MARKER' — refusing to guess." >&2
  exit 1
fi

# Detect the marker only in the board's RUNTIME, not in the cards JSON. The
# marker is a code identifier, but a card's own text (a note or title that
# happens to mention it) would otherwise make a stale board look current and
# get silently skipped. Excise the <script id="kanban-cards"> block first, then
# look. (Block delimiters mirror rwa_splice.py's START/END.)
board_on_current_gen () {
  python3 - "$1" "$GEN_MARKER" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
marker = sys.argv[2]
start_tag = '<script type="application/json" id="kanban-cards">'
end_tag = '<\\/script>'   # cards block closes with the escaped form on disk
i = text.find(start_tag)
if i != -1:
    j = text.find(end_tag, i)
    if j != -1:
        text = text[:i] + text[j + len(end_tag):]   # drop the cards JSON region
sys.exit(0 if marker in text else 1)
PY
}

if board_on_current_gen "$BOARD" && [[ $FORCE -eq 0 ]]; then
  echo "$BOARD is already on the current seed generation; nothing to do. (--force to rebuild anyway)" >&2
  echo "$BOARD"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "kanban upgrade: npx not found. Install Node.js (>=20.16) and try again." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kanban-upgrade.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
CARDS_JSON="$WORK_DIR/cards.json"
NEW_BOARD="$WORK_DIR/board.html"

# --- 1. read the cards out of the old board ---------------------------------
python3 "$SCRIPT_DIR/rwa_splice.py" --board "$BOARD" read > "$CARDS_JSON"
N_CARDS="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$CARDS_JSON")"

# --- 2. fresh rwa container with the current seed body ----------------------
echo "Building fresh container from current seed …" >&2
npx -y rewritable@latest new "$NEW_BOARD" >/dev/null 2>&1 || {
  echo "kanban upgrade: 'npx rewritable new' failed." >&2
  exit 1
}

python3 - "$NEW_BOARD" "$SEED_BODY" <<'PY'
import sys, os, tempfile

board_path, body_path = sys.argv[1], sys.argv[2]
with open(board_path, 'r', encoding='utf-8') as f: src = f.read()
with open(body_path,  'r', encoding='utf-8') as f: body = f.read().strip()

marker = 'const INLINE_DOC = `'
i = src.find(marker)
if i < 0: sys.exit("kanban upgrade: cannot find INLINE_DOC marker in fresh rwa file")
cs = i + len(marker)
j = cs
while j < len(src):
    if src[j] == '\\': j += 2; continue
    if src[j] == '`': break
    j += 1
if j >= len(src): sys.exit("kanban upgrade: unterminated INLINE_DOC literal")

def esc(s):
    return (s.replace('\\', '\\\\')
             .replace('`', '\\`')
             .replace('${', '\\${')
             .replace('</script', '<\\/script'))

new_src = src[:cs] + esc(body) + src[j:]

d = os.path.dirname(os.path.abspath(board_path)) or '.'
fd, tmp = tempfile.mkstemp(prefix='.kanban-', suffix='.html.tmp', dir=d)
with os.fdopen(fd, 'w', encoding='utf-8') as f: f.write(new_src)
os.replace(tmp, board_path)
PY

# --- 3. splice the preserved cards into the new board -----------------------
python3 "$SCRIPT_DIR/rwa_splice.py" --board "$NEW_BOARD" write < "$CARDS_JSON" >/dev/null

# Round-trip check before touching the original: the new board must read back
# exactly the cards we extracted.
python3 - "$SCRIPT_DIR/rwa_splice.py" "$NEW_BOARD" "$CARDS_JSON" <<'PY'
import json, subprocess, sys
splicer, new_board, cards_json = sys.argv[1], sys.argv[2], sys.argv[3]
got = json.loads(subprocess.check_output(
    ['python3', splicer, '--board', new_board, 'read'], text=True))
want = json.load(open(cards_json))
if got != want:
    sys.exit("kanban upgrade: round-trip mismatch — new board's cards differ from the original; aborting")
PY

# --- 4. back up and atomically replace ---------------------------------------
BACKUP="$BOARD.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$BOARD" "$BACKUP"
# mv across filesystems isn't atomic; stage the new file next to the target
# and rename within the same directory.
STAGED="$(dirname "$BOARD")/.board.upgrade.$$.tmp"
cp "$NEW_BOARD" "$STAGED"
mv "$STAGED" "$BOARD"

echo "Upgraded $BOARD to the current seed generation ($N_CARDS cards preserved)." >&2
echo "Backup of the old board: $BACKUP" >&2
echo "$BOARD"
