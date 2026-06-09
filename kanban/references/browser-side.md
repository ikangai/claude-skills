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

## Keeping the CLI and browser in sync

Mental model: **reload (or the `↻ sync from file` button) pulls the latest from the file; ⌘S pushes the browser's state to the file.** That keeps the two surfaces consistent no matter which one moved last.

### On every page load (the reliable path)

Before the board paints, the runtime reconciles the file *into* the browser. It reads the cards straight out of the freshly-loaded document (the `INLINE_DOC` snapshot, which the browser just parsed from the file on disk) and adopts them over whatever stale state IndexedDB held:

- **CLI writes show up on reload.** After Claude runs `kanban add / claim / move / note / delete`, reload the tab — or click **`↻ sync from file`** in the footer — and the board reflects the file. Adds appear, status changes propagate, deletes drop.
- **Uncommitted local drags survive the reload.** If the human dragged a card but hasn't pressed ⌘S, that drag is preserved across the reload while the file's other changes merge in around it. The board tracks exactly which cards were dragged, so a CLI move of *another* card still comes through.
- **Same-card conflicts go to the local drag.** If the human dragged card-X locally and Claude also `kanban move card-X` from the CLI, the local drag wins on the status field until the next ⌘S settles it to disk.

This path needs no network and works on `file://`. The `↻ sync from file` button is just a reload — the honest, always-available way to pull CLI changes in.

### While the tab stays open (best-effort live sync)

A ~2.5 s poll also tries to pick up CLI changes *without* a reload, but how far it gets depends on how the board was opened:

- **After the first ⌘S, or over http(s):** live updates work. Once the human commits once, the runtime holds a File System Access handle it can re-read; the poll uses that (or `fetch`, when the board is served over http(s)) and merges changes in with a brief highlight pulse — no reload needed.
- **On a fresh `file://` open (before any commit):** there is no live source. **Chrome blocks `fetch()` of `file://` URLs** (each `file://` page has an opaque `null` origin, and cross-origin `file://` fetches are denied), and no FSA handle exists yet. The poll quietly no-ops; reload / `↻` is the way to pull changes until the first commit.

The poll pauses when the tab is hidden (`document.hidden`) and runs once on tab focus.

## Where the data lives

Two storage layers under the hood:

1. **The file** is durable state. It contains the `INLINE_DOC` template literal with the latest committed cards JSON.
2. **IndexedDB** is working state, namespaced by the document's UUID. Every drag and commit updates IDB; commits also write the file.

On the container's *first* open, the rwa runtime hydrates IDB from `INLINE_DOC` and renders that. On *every subsequent* open it renders from IDB and ignores `INLINE_DOC` — which is what makes a board the browser has opened before go stale the moment the CLI rewrites the file. (The `INLINE_DOC` literal itself is always current: the browser just parsed it from the file on disk. It's the *IDB-wins* hydration rule that drops it on the floor.)

The kanban body closes that gap at load time — see [Keeping the CLI and browser in sync](#keeping-the-cli-and-browser-in-sync). Because the freshly-parsed `INLINE_DOC` is in scope, the board reads the file's cards from it directly (no `fetch`, which `file://` forbids anyway) and reconciles them over the stale IDB doc *before the first paint*, then writes the result back into IDB so a later ⌘S and the next load agree with what the user sees.

When the user presses ⌘S, the rwa runtime writes the current document state (DOM-derived) back into the file's `INLINE_DOC` literal, so the file and IDB match again. The reconcile-on-load and ⌘S-on-save form the two halves of the loop: load pulls the file in, ⌘S pushes the browser out.

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
