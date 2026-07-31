# Next features — requested 2026-07-28

Nine items, written down as asked and **not implemented yet**. Items 8 and 9 came
out of the discussion rather than the original list. Each records
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

**The books coming back on the next sync is fine, and not a bug** (decided
2026-07-28): pressing Sync means you want the library, so bringing it back is
the honest answer. No disconnect prompt, no special case — the delete clears
this device, and Sync is how you undo that if you change your mind.

One thing the confirmation should still say: **disk space is not freed until
the sweep runs** (30 days) or the trash is emptied from the section directly
above it in Preferences. Offering "empty the trash now" straight afterwards
saves a second trip.

Scope is now **books only** — see item 8, which is where "and my physical
copies too" is properly answered.

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

**When it is ambiguous, ask** (decided 2026-07-28). "Move" is only well-defined
when you are looking at a shelf; from the whole library there is nothing to
leave. So the sheet that asks which shelf also asks what to do — *Move here* or
*Add here* — rather than the app picking one and being quietly wrong half the
time. Two buttons on a sheet that is already open costs nothing.

When you *are* viewing a shelf, Move can be the default of the two, since that
is what was asked for.

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

## 8. A sync dialogue: choose what syncs

**Asked for.** Instead of "everything or nothing", a dialogue where you pick
which resources sync — books, physical copies, loans, and so on.

**Today.** Sync is all-or-nothing per pass: `SyncService.sync()` runs books,
covers, files, shelves, copies, loans, copy photos and personal data in one go.
The single exception is reading position, which has its own opt-in
(`settings.syncReadingPosition`) because it is per-device rather than
per-library.

**Shape.** A screen — reached from *Library server*, and shown once when first
connecting — listing each resource with a switch:

| | |
|---|---|
| Books, covers and files | the catalogue itself |
| Physical copies and rooms | where your books live |
| Loans | who has what, and the history |
| Highlights, notes and bookmarks | personal, per account |
| Reading sittings | personal, per account |
| Reading position | already its own opt-in |
| Copy photos | pictures of your shelves |

Each switch skips the matching pass in `_pull`/`_push`. The plumbing is mostly
in place: those passes are already separate methods returning their own counts,
so this is a settings object threaded through plus the switches themselves.

**Two things worth getting right:**

- **Turning one off should offer to un-publish it**, the way "Sync reading
  position" already does with `forgetDevice`. Otherwise switching loans off
  leaves them on the server forever, which is not what someone unticking a box
  about their lending history expects.
- **Off must mean off in both directions.** A resource that stops pushing but
  keeps pulling would look like it is still syncing, and one that stops pulling
  but keeps pushing quietly publishes what you asked it not to.

This also answers the open question in item 1: nothing else needs deciding about
what "delete all books" reaches, because what leaves this device and what
reaches the server become separate, explicit choices.

---

## 9. Rooms shared with you are invisible in the app

**Found while answering "how does the rooms feature work?"** — not asked for, but
it is a gap rather than a preference.

**Today.** A room is published as one document (`layout`), and it can be *shared*
— `shares.rs` accepts `scope: 'layout'`, viewer-only. The console can list and
draw a room shared with you. The app cannot: `fetchLayout(id)` takes an id the
device already knows, which in practice means a room this device published. There
is no "rooms shared with me" list anywhere in the app.

So the second tab — the place rooms actually live — shows only your own, while
the browser shows everyone's. That is backwards.

**What to build.** `GET /api/layouts` already returns what the caller can see,
with an `owned` flag per row (`LayoutSummary`), so the server side exists. The app
needs a list of them in the physical tab and a way to open one read-only.

**The question to settle first.** Opening someone else's room can mean two
things, and they age differently:

- **Mirror it read-only** — fetch on demand, draw it, never write it to the local
  tables. Always current, useless offline, and it cannot be edited by mistake.
- **Copy it in** — import it as a room of your own, which then diverges from
  theirs and needs the same publish/409 conversation as any other room.

Read-only mirroring is the smaller and more honest of the two, and matches what
viewer-only sharing already means everywhere else.

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
6. **#8** — after #1, since the two share the question of what "my library"
   consists of, and #8 is the one that answers it properly.
7. **#9** — small once its one question is answered, and it closes a gap where
   the browser currently shows more than the app does.
8. **#5** — last, and in the three stages above rather than as one piece: it is
   larger than everything else here put together.
