# Next features — requested 2026-07-28

Eleven items, written down as asked and **not implemented yet**. Items 8 to 11
came out of the discussion rather than the original list. Each records
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

## 10. Cosmetics in a physical room

**Asked for.** A way to put decoration in a physical library — the room should
look like a room, not only like shelf geometry.

**Today.** A room holds three things: an optional backdrop photo, `physical_shelves`
segments (shelf / side panel / divider / label, all of them a line between two
points), and `book_placements`. There is nowhere to put a plant, a lamp, a
framed picture or a pair of bookends, and the segment model is the wrong shape
for them — a pot plant is not a line.

**The shape that fits: a prop.** A fourth kind of thing in the room, with its
own table, drawn by `room_painter` alongside the shelves:

| field | |
|---|---|
| `id`, `environmentId` | as everything else in the room |
| `kind` | `plant`, `lamp`, `frame`, `vase`, `clock`, `bookend`, `boxes`, `cat` |
| `x`, `y` | world metres, bottom-left, exactly like a placement |
| `width`, `height` | metres — real sizes, so a lamp next to a paperback looks right |
| `rotation`, `flip` | a bookend has a handedness |
| `tint` | one of the room palette's colours, so props don't fight the spines |
| `z` | in front of the shelf or behind it |

**Three things that make this cheaper than it looks:**

1. **No server work at all.** A room publishes as one opaque JSON document
   (`layouts::publish` checks only "is an object" and a 512 KiB cap), so props
   ride the existing publish/revision/409 path as a `props` array. No migration,
   no endpoint, no schema-parity entry. Older viewers — including `web/room.js` —
   ignore the key and draw the room exactly as they do today.
2. **Props settle like books.** `settle()` already answers "where does this come
   to rest, and what is in the way"; a plant dropped on a shelf should use it
   unchanged. A **bookend** is the nice case: it is a prop *and* a barrier, which
   is the machinery dividers now use, so it works the moment it is drawn.
3. **Draw them, don't ship them.** Each prop is a small `Path` in code — a dozen
   shapes, no image assets, nothing to license, no pixelation at any zoom, and
   they take the room's own palette. A photo-cut-out prop is the alternative and
   is worse on every one of those counts.

**Do this part first, it is a third of the value for a tenth of the work:** the
room's *own* look. Wall and floor colours on `physical_environments`, a floor
line at y = 0 with a skirting board, and a soft shadow under each shelf. That is
one migration column and a few lines in the painter, it needs no new concepts,
and it is what makes an empty room stop looking like graph paper.

**One open question.** Are props part of the *library* (they describe a room, so
everyone the room is shared with sees them) or personal to the device? Rooms are
already library data and are shared viewer-only, so library is the consistent
answer — but a cat on someone else's shelf is a different kind of statement from
a shelf, and it is worth deciding on purpose rather than by default.

---

## 11. Bookcase styles, and accessories you can bring your own art to

**Asked for.** User-modifiable styles of bookcase, plus accessories — book
nooks, small decorations. The proposal: a transparent collider box carrying the
image of the accessory, either imported or chosen from a decorations menu.

This is item 10 taken seriously. #10 asks *what* a prop is; this asks *where the
art comes from* and *how furniture gets a look*, which turn out to be the two
decisions that cost money.

### The collider idea is right, and wants a third layer

A book placement is already a footprint in metres plus an image drawn in it, so
an accessory is a placement that isn't a book — most of the room's machinery
applies unchanged. But an image's bounding box is almost never its footprint: a
plant's pot is a small rect at bottom centre while its leaves overhang the
neighbouring books, and a hanging picture has no footprint at all. So three
layers, not two:

| Layer | What | Why separate |
|---|---|---|
| **Artwork** | The image or vector, at its own aspect ratio | May overhang the collider — leaves, a lamp shade |
| **Collider** | A rect in metres, or nothing | What `settle` and the barrier logic see |
| **Anchor** | Where in the artwork the collider sits | The pot, not the bounding box |

And the collider needs a *kind*, because this room's whole model is what rests
on what:

- **solid** — books can't occupy it (a lamp, a bookend). This is the barrier
  path dividers already use.
- **surface** — a top edge books *can* rest on (a stack of boxes, a nook's
  roof). This is `SettleSegment`.
- **none** — no physics: a poster on the back panel, a rug.
- **aperture** — a hole things go inside. See the nook below.

Three of those four are existing code paths. An accessory is mostly a new
*renderer* over geometry the room already understands.

### Bookcase styles: a generator, not a container

A bookcase today is implied — some shelf segments and some panels. **Keep it
that way.** Making a bookcase a first-class object with child shelves is
conceptually cleaner and is a trap: it invalidates everything that reasons about
a flat list of shelves (fill, tidy, stocktake, printed labels, the accessible
room summary, the published room document, the console's renderer) and
immediately raises "what happens when I drag one shelf out of a bookcase",
which has no good answer.

Instead, a **template that emits segments**: pick a style, give it a width,
height and shelf count, and it writes the rows it is made of in one transaction.
Style is then presentation over unchanged geometry — a `style` string per
segment that the painter interprets (pine, walnut, painted steel, glass, wire).
Nothing downstream needs to know. If a bookcase should move or delete as a unit,
that is a `group_id` tag on the segments, not a hierarchy.

The payoff is the same one the bulk book add just delivered a layer up: **a room
built in four gestures instead of forty.**

### Where the art comes from — the fork that decides the cost

| Source | Cost |
|---|---|
| **Vector, drawn in code** | No assets, no licensing, no pixelation, takes the room palette. Every new prop is a code change and a release. |
| **Bundled raster assets** | Licensing is a real chore for a GitHub-release project, and app size grows for something most people won't use. |
| **User-imported images** | The most powerful, and the most hidden work — see below. |

Imported images carry five problems worth knowing before starting:

1. **Transparency is mandatory and users won't know it.** A JPEG of a plant
   brings a white rectangle onto the shelf. PNG/WebP with alpha, and the import
   dialog has to *say so* the way the CSV importer states its columns.
2. **Pixels aren't metres.** An import needs a scale, which means asking "how
   tall is this really?" — the conversation `BackdropCalibration` already has.
   Reuse it rather than inventing a second one.
3. **The anchor must be set by hand**, or everything floats: a one-time "drag
   the footprint onto the base of the object" step.
4. **Sync changes shape.** Vector props ride the room document (opaque JSON
   server-side, 512 KiB cap) with **no server work at all**. Images can't — they
   need the blob channel (a row, then the bytes, as copy photos do in migration
   0024), and therefore a migration and an endpoint. This is the single biggest
   cost difference between the two options.
5. **A shared room renders someone else's untrusted image on your device.**
   Backdrop photos set the precedent, but sharing multiplies it.

**Recommendation: built-in vector props first, imports as a separate later
stage.** Not because imports are wrong — because the two have almost disjoint
costs and the first is nearly free.

### The book nook is a room inside a room

The cheap version is a sticker with a solid collider: most of the visual payoff,
and it is just another prop.

The interesting version is that a nook's aperture **is a
`physical_environment`** — Vellum already has environments with their own
backdrop, calibration, shelves and placements. Placing one inside another gives
nested rooms for free (a nook in a bookcase in a study), and tapping it zooms
into the editor that already exists.

Build the cheap one; give the prop an optional `contains_environment_id` from
day one and leave it null, so the door stays open.

### The part that will actually go wrong

This is a **content problem wearing a code problem's clothes**. The engine is
about a week; the twelve decorations that look good *together* are the real
work, and imported art will not match — one object has a baked-in shadow,
another has perspective, a third is lit from the left. The room is a flat front
elevation, so anything with perspective reads as pasted on.

Three mitigations, designed in rather than bolted on:

1. **State the contract at import**: front elevation, no perspective,
   transparent background.
2. **An optional palette tint** per prop, to pull imported art toward the room's
   colours.
3. **Vellum draws the contact shadow itself**, at the collider's base. If every
   object gets the same soft shadow from the same source, mismatched artwork
   still *sits* on the shelf consistently. This one detail does more for
   coherence than any amount of asset curation.

### Two things to decide up front

- **Z-order.** Today it is backdrop → shelves → books. Props need at least three
  named bands (behind books, among them, in front) — not a free-form float, or
  everything ends up at 0.5.
- **Library or personal?** Same question as #10, with a sharper edge: if props
  are personal they stay out of the sync path entirely and get much cheaper.

### Staging

1. **Bookcase templates** — no new concepts, no sync work, immediately felt.
2. **Segment styles** — a `style` field the painter interprets.
3. **Vector props** with the four collider kinds; rides the existing room
   document.
4. **Imported images** — calibration, anchor, blob channel, migration.
5. **Nested environments** for nooks, only if 3 and 4 land well.

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

**#10 and #11** sit outside this order. Their cheap first stages — the room's own
wall, floor and shadows (#10), and bookcase templates (#11) — are small enough to
slot in anywhere and are what an empty room most obviously lacks. Everything past
that is a want rather than a gap: worth doing when the room is otherwise
finished, and #11 stage 4 (imported art) is the only part of either that needs a
server migration.
