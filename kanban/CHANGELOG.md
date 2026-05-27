# Changelog

All notable changes to the kanban skill are documented here.

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
