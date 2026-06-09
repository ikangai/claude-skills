# Changelog

All notable changes to the kanban skill are documented here.

## 2026-06-09

### Fixed

- **The board no longer goes stale after CLI edits.** Once a browser had opened a
  board, it kept rendering its cached IndexedDB state and ignored later
  `kanban add` / `claim` / `move` / `note` writes to the file — opening the same
  file in a normal window showed empty columns while the file (and an incognito
  window) had every card. The intended file→browser sync relied on
  `fetch(location.href)` of the board's own `file://` URL, which Chrome rejects
  (`TypeError: Failed to fetch`), so the poll silently did nothing. The board now
  reconciles the file into the browser on **every load**: it reads the cards
  straight from the freshly-parsed `INLINE_DOC` (no network) and adopts them over
  stale IndexedDB before the first paint. A reload — or the new **↻ sync from
  file** button — now always reflects the latest CLI writes. This removes the need
  for the manual `indexedDB.deleteDatabase(...)` workaround noted under 2026-05-27.

### Added

- **`↻ sync from file` button** in the footer: reloads the board from disk, the
  reliable way to pull CLI changes into an open tab on `file://`.
- **`assign.sh`** — hand a card to another agent or human (sets `assigned_to`;
  optional `--move=<status>` for review handoffs). Distinct from `claim.sh`
  ("I'm taking this").

### Changed

- An uncommitted local drag is now preserved across a reload, tracked per browser
  tab (`sessionStorage`) so two tabs of the same board can't pollute each other's
  merge; the set clears on commit. Only the cards actually dragged keep their
  local status — a CLI move of any other card still comes through on reload.
- Live auto-refresh without a reload now works after the first ⌘S (via the File
  System Access handle) or over http(s); on a fresh `file://` open Chrome blocks
  reading the file, so reload / ↻ is the path until the first commit.
- `references/browser-side.md` and `SKILL.md` rewritten to describe the real sync
  model; the old docs claimed a `fetch()`-based poll that cannot work on `file://`.

## 2026-05-27

### Fixed

- **Drag-and-drop changes survive a refresh.** `onDrop` previously updated the
  DOM via `writeCards` but never wrote to IndexedDB, where the rwa runtime
  keeps the canonical doc string. On reload, the runtime re-hydrated the DOM
  from IDB and the drag was thrown away. `commit()` (⌘S) reads from IDB too,
  so the bug also meant that pressing ⌘S saved the *pre*-drag state. Fix
  splices the new cards JSON into the IDB doc on drop, then sets the dirty
  flag so ⌘S behaves the way users expect.
- **CLI changes seen via polling sync now reach IDB.** `syncFromDisk` had the
  same shape as the drag bug: `writeCards(merged); render();` with no IDB
  write. A `kanban add` from the terminal would appear in an open browser tab
  but be wiped by the next ⌘S (which read the stale IDB doc). Fix calls the
  same `persistDocToIdb` helper after the merge — no dirty-flag flip on this
  path, since the polling sync is bringing file state IN, not introducing new
  browser-only changes.

### Notes for existing boards

The rwa runtime hydrates from `INLINE_DOC` only on first open of a file; on
every subsequent open it reads the doc from IndexedDB and ignores the inline
template. That means an existing tab will keep running the old (broken)
runtime until its IDB is cleared. To pick up the fix on a board you've
already opened:

```js
indexedDB.deleteDatabase('rwa_' + window.runtime.id)
```

…in the DevTools console for that tab, then reload. Your cards are safe —
they re-hydrate from the file on the next load.
