#!/usr/bin/env bash
#
# kanban init — create .kanban/board.html in the current project.
#
# Steps:
#   1. mkdir .kanban/
#   2. npx -y rewritable new -o .kanban/board.html    (skipped if exists)
#   3. splice the kanban INLINE_DOC body into the file
#   4. report the resulting path
#
# Idempotent: if .kanban/board.html already exists, exits 0 without action.

set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
KANBAN_DIR="$PROJECT_DIR/.kanban"
BOARD="$KANBAN_DIR/board.html"
SEED_BODY="$SKILL_DIR/seeds/kanban-body.html"

if [[ -f "$BOARD" ]]; then
  echo "$BOARD already exists; nothing to do." >&2
  echo "$BOARD"
  exit 0
fi

mkdir -p "$KANBAN_DIR"

# --- 1. fresh rwa container ------------------------------------------------
if ! command -v npx >/dev/null 2>&1; then
  echo "kanban init: npx not found. Install Node.js (>=20.16) and try again." >&2
  exit 1
fi

echo "Creating fresh rwa container at $BOARD …" >&2
npx -y rewritable@latest new "$BOARD" >/dev/null 2>&1 || {
  echo "kanban init: 'npx rewritable new' failed." >&2
  exit 1
}

# --- 2. splice the kanban body into INLINE_DOC -----------------------------
python3 - "$BOARD" "$SEED_BODY" <<'PY'
import sys, re, os, tempfile

board_path, body_path = sys.argv[1], sys.argv[2]
with open(board_path, 'r', encoding='utf-8') as f: src = f.read()
with open(body_path,  'r', encoding='utf-8') as f: body = f.read().strip()

marker = 'const INLINE_DOC = `'
i = src.find(marker)
if i < 0: sys.exit("kanban init: cannot find INLINE_DOC marker in fresh rwa file")
cs = i + len(marker)
j = cs
while j < len(src):
    if src[j] == '\\': j += 2; continue
    if src[j] == '`': break
    j += 1
if j >= len(src): sys.exit("kanban init: unterminated INLINE_DOC literal")

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

# --- 3. .gitignore unless user already manages .kanban ---------------------
GI="$PROJECT_DIR/.gitignore"
if [[ -f "$GI" ]] && ! grep -qE '(^|/)\.kanban/?$' "$GI"; then
  printf '\n# Local project kanban (kanban skill)\n.kanban/\n' >> "$GI"
elif [[ ! -f "$GI" ]]; then
  printf '# Local project kanban (kanban skill)\n.kanban/\n' > "$GI"
fi

echo "$BOARD"
