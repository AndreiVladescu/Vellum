# Next features — requested 2026-07-28

Seven items, written down as asked and **not implemented yet**. Each records
what was asked for, what the code does today (checked, not remembered), and what
is still open. Open questions are marked **?** — some change the work
materially, and are worth answering before anything is built.

Ordered as they were given, not by priority; a suggested order is at the bottom.

---

## 1. Delete every book, from Settings

**Asked for.** An option hidden inside Settings that deletes all books, local
*and* remote, behind a confirmation dialog so it can't be hit by mistake.

**Today.** There is no "delete everything". Individual books go to a trash with
a 30-day grace period (`repository.trashBook`), swept by
`repository.trash.sweep()` at launch. Preferences has a Trash section that can
empty it. Nothing operates on the whole library at once.

**Shape.** A destructive row at the bottom of Preferences, in its own section,
visually separated from everything above it. The confirmation should be more
than a Yes/No — for something this final, typing the number of books or the word
DELETE is the usual pattern, and is cheap to build.

**Decided (2026-07-28): trash locally, leave the server alone.** Every book
goes to the 30-day trash on this device; the server's copy is untouched. That
reuses machinery that already exists, cannot harm anyone the library is shared
with, and stays recoverable.

Two consequences to build for, both of which the UI has to say plainly:

- **The books come back on the next sync**, because the server still has them
  and the local rows are trashed rather than tombstoned. If the intent is
  "reset this device", the button should offer to disconnect from the server as
  well — otherwise it looks broken.
- **Disk space is not freed until the sweep runs** (30 days), or until the
  trash is emptied from the section directly above it in Preferences. Worth
  saying in the confirmation, and worth offering "empty the trash now" straight
  afterwards.

Still to settle when building it: whether physical copies, loans, shelves,
rooms and wishlist entries go too, or only books. The safest default is
**books only**, since everything else is either about objects you still own or
about people you lent to.

---

## 2. The "Move to trash" button sits under Android's navigation bar

**Asked for.** On Android the button is behind the system navigation buttons.
Move it up, or make the page taller so it fits.

**Today.** Confirmed a real bug. `main.dart` puts the app in
`SystemUiMode.edgeToEdge`, so the app draws behind the gesture/navigation bar —
and `book_detail_page.dart` ends with `ListView(padding: EdgeInsets.all(24))`, a
fixed 24 logical pixels with no allowance for the system inset. The last item in
the list, which is that button, ends up underneath it.

**Fix.** Add the bottom inset to the list's padding
(`MediaQuery.viewPaddingOf(context).bottom`) rather than wrapping in `SafeArea`,
which would also stop the content scrolling under the bar — the scrolling-under
look is the point of edge-to-edge, it is only the *resting* padding that is
wrong.

**Worth doing at the same time:** the same pattern elsewhere. The readers were
fixed for this during plan 5, but other long scrolling pages were not audited.
Grepping for `EdgeInsets.all(` on a page-level `ListView` would find them.

---

## 3. Make the message after deleting a book dismissible by tapping

**Asked for.** The bar shown after deleting a book (and similar) should be
tappable to dismiss, so it can be got rid of faster.

**Today.** Those are `SnackBar`s built through `appSnackBar` (see
`lib/snack_bars.dart`). They already time out — six seconds when they carry a
button, four otherwise — and can be swiped away. Tapping the bar itself does
nothing.

**Shape.** Small: wrap the content so a tap calls
`ScaffoldMessenger.of(context).hideCurrentSnackBar()`. One change in
`appSnackBar` covers every snack bar in the app at once, which is the reason
that wrapper exists.

**Care needed:** the tap must not swallow the action button — pressing *Undo*
has to undo, not merely dismiss.

---

## 4. Select several books and act on them at once (Android especially)

**Asked for.** A way to select books in the library and then do a batch job —
delete, or move them to another library inside the app.

**Today.** There is no multi-select anywhere in the app. The web console has
one (checkbox column, "Tag", "Delete selected", "Edit selected"), so the *idea*
exists in the project; the app has nothing.

**Shape.** Long-press a spine to enter selection mode, tap to add or remove,
a contextual app bar showing the count with the batch actions, and Escape or
Back to leave. This is the standard Android pattern and works with a mouse on
desktop too. Actions worth having from the start: move to trash, add/remove a
genre, and whatever "another library" turns out to mean.

**Decided (2026-07-28): the digital shelves, and "move" really means move** —
the selected books leave the shelf being viewed and join the one picked. Not
the physical shelves in a room, and not server book groups.

**One thing this leaves open, with a proposed answer.** "Move" is only
well-defined when you are looking at a shelf; from the whole library there is
nothing to leave. Proposal, unless you say otherwise: the action reads **Move to
shelf** when viewing a shelf and **Add to shelf** when viewing everything, doing
exactly what it says in each case. Same sheet, one word different, and it never
silently removes a book from a shelf you could not see.

`ShelfBooks` is many-to-many with a `position`, so both are cheap: a move is one
delete plus one insert, and the target position goes at the end.

---

## 5. Upload books to the server the way the app does

**Asked for.** A way to upload books into the server, the same way it's done in
the client app.

**Today, and this is why the question below matters.** The console already has
some of this: **Add book** opens a form (title, authors, year, pages) with a
metadata search, and **Upload to selected** takes a `.pdf`, `.epub` or image and
attaches it to the selected books. So "upload a book file" exists.

What the console does *not* have, which the app does:

- dragging files onto the window
- importing a **folder** of files at once, with the dry-run review screen
- reading metadata out of the file name (`Author - Title (Year).epub`)
- importing a **CSV/JSON catalogue**, or a Calibre library, or OPDS
- the duplicate check before anything is written

**Decided (2026-07-28): the whole import wizard, in the browser.** All four
sources, with the dry-run review and the duplicate check before anything is
written.

This is the largest item in this document by some distance, and worth splitting
when it is picked up. A sensible order, each useful on its own:

1. **CSV/JSON catalogue** — the parser is pure logic and already exists twice
   (`csv_import.dart`, and the console's own "Import CSV"); this is mostly the
   review screen.
2. **A folder of files** — needs the browser's directory picker, filename
   parsing, and per-file upload with progress.
3. **Calibre and OPDS** — the two that need the server to reach out or read a
   directory structure, and the two most likely to be wanted least.

The duplicate check should run **server-side** and be shared with the app's
importer rather than re-implemented in JavaScript, or the two will disagree
about what counts as a duplicate.

---

## 6. Simplify the console's look

**Asked for.** Modify the CSS — or whatever changed — to something a little
simpler.

**Today.** `server/web/console.css` is 348 lines: a dark theme with custom
properties, a dense data table, chips, modals, toasts.

**Decided (2026-07-28): calmer, not lighter and not rearranged.** Same layout,
same dark palette, same controls — it should stop shouting. Concretely: fewer
borders and drop them to a dimmer line colour, no shadows, more whitespace
between rows and around the table, one accent colour instead of four, and
regular weight where bold is doing decoration rather than carrying meaning.

A pure CSS pass, then — `console.css` only, no markup changes — which also makes
it safe to do alongside item 7 without the two conflicting.

---

## 7. Put the many buttons into menus

**Asked for.** There are lots of buttons; group the complicated ones into a
menu.

**Today.** Counted, on the main console screen: **7** in the header (Refresh,
Certificate, Server, Activity, Rooms, Requests, People, Log out — 8 with the one
added yesterday) and **13** in the two toolbars below it (Add book, Import CSV,
Create tag, Tag, Untag, Edit selected, Fetch metadata, Upload to selected,
Delete selected, Export CSV, Export JSON, Columns, Density), plus the search and
filter row. Twenty-odd controls before the table starts.

**Shape.** Keep on screen only what is used constantly — search, Add book, and
the selection-dependent actions — and move the rest into two or three menus:
a **⋯ Library** menu (import, export, tags, columns, density) and an **admin**
menu (Server, Activity, People, Certificate, Rooms, Requests). Selection-only
actions should appear when something is selected and be absent otherwise, the
way the app's readers show highlight actions only while text is selected.

This and item 6 are the same job seen from two angles, and should be done
together.

---

## Suggested order

1. **#2** — a real bug with a known one-line fix, on the platform it was
   reported from.
2. **#3** — small, and improves every message in the app at once.
3. **#7 + #6** — together; the console is the thing two of the seven items are
   about.
4. **#4** — the largest app-side piece, and worth doing after #7 so the two
   selection models can be designed to match.
5. **#1** — small now that it is scoped to a local trash, and the trash makes it
   forgiving.
6. **#5** — last, and in the three stages above rather than as one piece: it is
   larger than everything else here put together.
