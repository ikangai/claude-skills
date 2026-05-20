# Browser side

The board file is a [rewritable](https://github.com/ikangai/rewritable) container — a self-contained `.html` that renders, stores, and rewrites itself in place. When the user opens `.kanban/board.html` in a browser, three things load: the rwa runtime, the kanban document body, and a small inline renderer that paints columns and handles drag-and-drop.

This document explains what the human sees and how the two surfaces (CLI and browser) share state.

## What the user sees

A four-column board: **To Do**, **In Progress**, **Review**, **Done**. Cards sit inside the columns, each showing its title, optional description (clamped to three lines), tag chips, and the short tail of its id. A high-priority card has a red left border, medium yellow, low blue. The assignee, if any, shows as a dark agent chip.

The runtime chrome is the same as any rewritable: a small status pill in the top-right (`● ready`), a gear for backend settings, and a `⌘S` commit button. The bottom-of-screen lens (`⌘K`) is present but largely unused for the kanban — there's no "edit the document" use-case here, since the cards are the document.

## Drag-and-drop

The inline JS in the document body binds HTML5 native drag events. Drag a card to a different column, drop it, and:

1. The card's `status` field flips to the destination column's value.
2. If the destination is `in_progress` and the card has no `claimed_at`, one gets stamped (the user's drag counts as claiming).
3. The cards JSON region in the DOM is rewritten with the new array.
4. The board re-renders.

At this point the file on disk has *not* changed yet. The runtime is "dirty" and the `⌘S` button is highlighted. Press `⌘S` (or click the button) and the rwa runtime serializes the current document state back into the `INLINE_DOC` template literal in the file. On Chromium (Chrome, Edge, Brave, Arc, etc.) this writes in-place via the File System Access API; on Firefox and Safari it falls back to a download.

The drag-then-commit pattern is intentional. It mirrors the way a person works through a board — make several moves, then commit them together. Each drag is undoable until commit.

## CLI and browser stay in sync automatically

The kanban runtime polls the file on disk every ~2.5 seconds while the tab is visible. When it sees the cards JSON has changed (because Claude ran `kanban add`, `kanban claim`, `kanban move`, `kanban note`, or `kanban delete` from the terminal), it does a three-way merge against (a) the disk state at the previous poll and (b) the cards currently in the browser. The merge result is written back to the DOM and rendered.

What this means in practice:

- **CLI adds appear automatically.** Within a few seconds of `kanban add`, a new card shows up in the To Do column with a brief highlight pulse.
- **CLI claims / moves / notes appear automatically.** Status changes propagate, assignee chips update, note counts increment — all without reloading the tab.
- **Local drags survive.** If the human drags a card to a new column but hasn't pressed ⌘S yet, and Claude makes a CLI change to a *different* card, the local drag is preserved. The CLI's change merges in alongside it.
- **Same-card conflicts go to the local drag.** If the human drags card-X locally AND Claude runs `kanban move card-X` from the CLI before the local drag is committed, the local drag wins on the status field. (Logic: the human just acted; reverting their drag would be confusing. The next ⌘S writes the local status to disk, settling the conflict.)
- **Deletes from the CLI propagate.** If `kanban delete` removes a card, the open tab drops it on the next poll.

The poll uses `fetch(location.href)` on the document's own `file://` origin, which Chromium permits since each `file://` URL is its own origin. The poll pauses when the tab is hidden (`document.hidden`) and runs once immediately on tab focus, so switching back to a board from another tab gives an instant refresh.

If you ever want to disable the sync (debugging, slow disk, network filesystem), open the browser console and run `clearInterval(<the-interval-id>)` — but you shouldn't normally need to. The sync is invisible when nothing has changed and quiet when something has.

## Where the data lives

Two storage layers under the hood:

1. **The file** is durable state. It contains the `INLINE_DOC` template literal with the latest committed cards JSON.
2. **IndexedDB** is working state, namespaced by the document's UUID. Every drag and commit updates IDB; commits also write the file.

On first open, the rwa runtime hydrates IDB from `INLINE_DOC`. On subsequent opens, IDB already has state and `INLINE_DOC` is ignored — *that* was the failure mode that motivated the polling sync above. The poll bypasses IDB hydration entirely by reading the file fresh and merging into the current DOM.

When the user presses ⌘S, the rwa runtime writes the current document state (DOM-derived) back into the file's `INLINE_DOC` literal. On the next poll, the disk version equals the browser version and nothing happens. The sync loop is self-quiescing.

## Why the data isn't just a `<div>`-tree

The cards live as JSON in a `<script type="application/json">` block rather than as a tree of `<div class="kanban-card">` elements. Two reasons:

1. **CLI ergonomics.** Editing JSON from a Python helper is trivially safe; editing HTML from a shell is a recipe for invalid markup. Keeping the data in JSON means the splicer never has to parse HTML.
2. **Re-rendering.** When the runtime renders the document, the inline JS reads the JSON and builds the DOM from scratch. If a future CLI update changes the data, the next page load picks up the change with no migration step.

The DOM is a view. The JSON is the model. The file is the database. The rwa runtime persists all three as one artifact.

## Frozen regions

The kanban body uses rwa's frozen-region markers (`<!-- rwa:frozen:begin … -->`) around three blocks: the title/sub area, the column scaffold, and the inline runtime script. These tell the agent loop inside the document — if someone ever does invoke `⌘K` here — to refuse edits that would overlap the locked regions. The cards JSON is deliberately *outside* the frozen regions: that's the editable surface.

## Print

rwa's content stylesheet handles print by hiding the runtime chrome and letting `@page` own the margins. The kanban print-view shows the columns side-by-side at whatever the paper width allows; on portrait pages with many cards in a column, cards will flow onto subsequent pages. There's no dedicated print stylesheet in v0 — the rwa defaults are good enough.

## Browser support

The board needs a modern browser:

- **Chromium-based browsers** (Chrome, Edge, Brave, Arc): in-place file writes via FSA. Best experience.
- **Firefox, Safari**: the runtime falls back to downloads — `⌘S` triggers a "Save as…" with the modified file pre-named. The user replaces the original by saving it back over the existing path. Cumbersome compared to FSA but functional.
- **iOS Safari**: works but IndexedDB is evicted aggressively. The exported `.html` on disk is the only durable artifact. The runtime nudges after a few uncommitted modifies. For a kanban that's actively edited, iOS is best treated as read-only.

If the user is on a non-Chromium desktop browser, mention the download fallback so they know what to expect on `⌘S`.
