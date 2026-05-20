#!/usr/bin/env python3
"""
rwa_splice.py — read and write the kanban cards JSON inside a rewritable
board.html, without touching any other part of the file.

The cards array lives between two exact substrings:

    START = '<script type="application/json" id="kanban-cards">\\n'
    END   = '\\n</script>'

Everything between is a JSON array. This script reads it, hands it to a
subcommand for modification, and writes it back. Writes are atomic
(write to tempfile, rename) so a crash mid-write never leaves a corrupt
board.

The kanban cards JSON lives inside INLINE_DOC, which is itself inside a
template literal in the .html file. The rwa runtime's commit (⌘S in the
browser) escapes the literal correctly when it rewrites the file. For
CLI edits we don't have to think about that — the cards JSON contains
no backticks or $ {, so the surrounding template-literal escaping in
INLINE_DOC stays intact.

Subcommands:
  read                       print cards JSON to stdout
  add <json>                 append a card object (JSON on stdin or as arg)
  update <id> <json>         shallow-merge fields into card <id>
  delete <id>                remove card <id>
  list [--status=S] [--agent=A]   filter and print
  count                      print one line per status: <status>=<count>

Exit codes:
  0  success
  2  not found / no-op
  3  malformed input or file
"""

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

START = '<script type="application/json" id="kanban-cards">\n'
END = '\n<\\/script>'   # </script> is escaped to <\/script> inside the rwa template literal


def _unescape_tl(s):
    """Reverse of the rwa runtime's escapeTL — turn the file-on-disk form
    of a string back into the logical string that JS sees inside the
    template literal. Order matters: undo backslash last."""
    s = s.replace('<\\/script', '</script')
    s = s.replace('\\${', '${')
    s = s.replace('\\`', '`')
    s = s.replace('\\\\', '\\')
    return s


def _escape_tl(s):
    """Same shape as escapeTL in seeds/rewritable.html. Applied to JSON
    text before it is spliced back into the template literal. Order
    matters: do backslash first so subsequent escapes don't double-up."""
    s = s.replace('\\', '\\\\')
    s = s.replace('`', '\\`')
    s = s.replace('${', '\\${')
    s = s.replace('</script', '<\\/script')
    return s


def load(path):
    """Read the file and locate the cards JSON region.

    Returns (full_text, start_index, end_index, cards_list).
    start_index points to the first char of the JSON body (after START).
    end_index points to the first char of END (i.e. the '\\n' before </script>).
    """
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except FileNotFoundError:
        sys.stderr.write(f"rwa_splice: file not found: {path}\n")
        sys.exit(3)

    s = text.find(START)
    if s < 0:
        sys.stderr.write("rwa_splice: cannot locate kanban-cards start marker\n")
        sys.exit(3)
    body_start = s + len(START)
    e = text.find(END, body_start)
    if e < 0:
        sys.stderr.write("rwa_splice: cannot locate kanban-cards end marker\n")
        sys.exit(3)

    body = text[body_start:e].strip()
    body = _unescape_tl(body)
    if not body:
        cards = []
    else:
        try:
            cards = json.loads(body)
            if not isinstance(cards, list):
                raise ValueError("cards must be a JSON array")
        except (json.JSONDecodeError, ValueError) as err:
            sys.stderr.write(f"rwa_splice: cards JSON malformed: {err}\n")
            sys.exit(3)

    return text, body_start, e, cards


def save(path, text, body_start, body_end, cards):
    """Replace the cards body with `cards` (re-serialized) and atomically
    write the file back to `path`. The file is written to a sibling temp
    file and renamed; on any error the original is untouched.

    Two layers of escape protect the data on its journey to the browser:

      1. `</script` is encoded as `<\\/script` inside the JSON text. This
         is a JSON-spec-legal alternate form (\\/ is the escape for /).
         It prevents the HTML parser from closing the inner
         <script type="application/json" id="kanban-cards"> tag when the
         runtime later sets innerHTML on a doc containing this JSON.
      2. The whole JSON text is then escapeTL-encoded so it survives
         sitting inside the outer rwa runtime's INLINE_DOC template
         literal."""
    new_body = json.dumps(cards, indent=2, ensure_ascii=False)
    # Layer 1: protect the inner <script type="application/json"> from
    # premature closure when its content is later rendered to the DOM.
    new_body = new_body.replace('</script', '<\\/script')
    # Layer 2: protect the outer bootstrap <script id="rwa-bootstrap">.
    new_body = _escape_tl(new_body)
    new_text = text[:body_start] + new_body + text[body_end:]

    dir_ = os.path.dirname(os.path.abspath(path)) or '.'
    fd, tmp = tempfile.mkstemp(prefix='.kanban-', suffix='.html.tmp', dir=dir_)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(new_text)
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise


# ─── subcommands ──────────────────────────────────────────────────────

def cmd_read(args):
    _, _, _, cards = load(args.board)
    print(json.dumps(cards, indent=2, ensure_ascii=False))


def cmd_add(args):
    text, s, e, cards = load(args.board)

    raw = args.json if args.json else sys.stdin.read()
    try:
        card = json.loads(raw)
    except json.JSONDecodeError as err:
        sys.stderr.write(f"rwa_splice add: input is not valid JSON: {err}\n")
        sys.exit(3)
    if not isinstance(card, dict):
        sys.stderr.write("rwa_splice add: input must be a JSON object\n")
        sys.exit(3)
    if 'id' not in card or not card['id']:
        sys.stderr.write("rwa_splice add: card must have a non-empty 'id'\n")
        sys.exit(3)
    if any(c.get('id') == card['id'] for c in cards):
        sys.stderr.write(f"rwa_splice add: card id already exists: {card['id']}\n")
        sys.exit(2)

    card.setdefault('status', 'todo')
    card.setdefault('priority', 'none')
    card.setdefault('tags', [])
    card.setdefault('assigned_to', None)
    card.setdefault('claimed_at', None)
    card.setdefault('notes', [])
    card.setdefault('subtasks', [])
    card.setdefault('created_at', datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))

    cards.append(card)
    save(args.board, text, s, e, cards)
    print(card['id'])


def cmd_update(args):
    text, s, e, cards = load(args.board)

    raw = args.json if args.json else sys.stdin.read()
    try:
        patch = json.loads(raw)
    except json.JSONDecodeError as err:
        sys.stderr.write(f"rwa_splice update: patch is not valid JSON: {err}\n")
        sys.exit(3)
    if not isinstance(patch, dict):
        sys.stderr.write("rwa_splice update: patch must be a JSON object\n")
        sys.exit(3)

    idx = next((i for i, c in enumerate(cards) if c.get('id') == args.id), None)
    if idx is None:
        sys.stderr.write(f"rwa_splice update: card not found: {args.id}\n")
        sys.exit(2)

    cards[idx].update(patch)
    save(args.board, text, s, e, cards)


def cmd_delete(args):
    text, s, e, cards = load(args.board)
    before = len(cards)
    cards = [c for c in cards if c.get('id') != args.id]
    if len(cards) == before:
        sys.stderr.write(f"rwa_splice delete: card not found: {args.id}\n")
        sys.exit(2)
    save(args.board, text, s, e, cards)


def cmd_list(args):
    _, _, _, cards = load(args.board)
    out = cards
    if args.status:
        out = [c for c in out if c.get('status') == args.status]
    if args.agent:
        out = [c for c in out if c.get('assigned_to') == args.agent]
    print(json.dumps(out, indent=2, ensure_ascii=False))


def cmd_count(args):
    _, _, _, cards = load(args.board)
    counts = {'todo': 0, 'in_progress': 0, 'review': 0, 'done': 0}
    for c in cards:
        s = c.get('status', 'todo')
        if s in counts:
            counts[s] += 1
    for k in ('todo', 'in_progress', 'review', 'done'):
        print(f"{k}={counts[k]}")


def main():
    ap = argparse.ArgumentParser(description="Read/write the cards JSON inside a kanban board.html")
    ap.add_argument('--board', required=True, help="Path to board.html")
    sub = ap.add_subparsers(dest='cmd', required=True)

    sub.add_parser('read').set_defaults(func=cmd_read)

    a = sub.add_parser('add'); a.add_argument('--json', help="card JSON; stdin if omitted"); a.set_defaults(func=cmd_add)

    u = sub.add_parser('update'); u.add_argument('id'); u.add_argument('--json', help="patch JSON; stdin if omitted"); u.set_defaults(func=cmd_update)

    d = sub.add_parser('delete'); d.add_argument('id'); d.set_defaults(func=cmd_delete)

    l = sub.add_parser('list'); l.add_argument('--status'); l.add_argument('--agent'); l.set_defaults(func=cmd_list)

    sub.add_parser('count').set_defaults(func=cmd_count)

    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
