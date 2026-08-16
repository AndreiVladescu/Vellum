# Bugs found — 2026-08-16

Found by reading the code after fixing the Android toolbar/fullscreen report
(`app/lib/main.dart`, `app/lib/physical/environment_editor_page.dart`). Items
1 and 2 are fixed; item 3 was found on a later pass and is **not fixed yet**.
Kept here as a record of what was found and how, rather than deleted, since
the reasoning is what makes it checkable later.

Not duplicated here: the console sticky-header bug and the settle-bounds item
already tracked in [`BACKLOG.md`](BACKLOG.md#open--possible-follow-ups).

---

## ✅ 1. Seven pages could hide their own last row under Android's gesture bar

**Fixed** — commit `ae19d77`.

**Same bug class as the "Move to trash" fix** (`NEXT_FEATURES.md` #2,
commit `cd69376`): a page-level list with no bottom inset ends with its last
row flush against the screen edge, where the system gesture/nav bar sits on
top of it and eats the tap. That fix added `pageInsets()`
(`app/lib/widgets/page_insets.dart`) to 16 scroll views at the time. These
seven either predated that pass or were added after it without picking up the
convention — none of them imported or called `pageInsets`:

| File | List | What was unreachable on a long list |
|---|---|---|
| `app/lib/settings/trash_page.dart` | `ListView.builder` | The last trashed book's **Restore** / **Delete forever** buttons |
| `app/lib/shelf/author_page.dart` | `ListView.separated` | The last book by that author |
| `app/lib/shelf/series_page.dart` | `ListView.separated` | The last volume in the series |
| `app/lib/wishlist/wishlist_page.dart` | `ListView.separated` | The last wishlist entry |
| `app/lib/dedupe/duplicates_page.dart` | `ListView.separated` | The last duplicate pair's merge action |
| `app/lib/add_book/add_book_page.dart` | `ListView.builder` (search results, in an `Expanded`) | The last search result |
| `app/lib/add_book/scan_page.dart` | `ListView.builder` (scanned books, in an `Expanded`) | The last scanned book's **Undo** |

Each now passes `padding: pageInsets(context, EdgeInsets.zero)` (or wraps
its existing padding the same way), matching the convention
`stocktake_page.dart` already followed. `flutter analyze` and the full test
suite (1151 tests, including the dedicated widget test for each of these
seven pages) pass unchanged.

Worth a repeat of this grep on a future pass — `page_insets.dart`'s own doc
comment predicted there'd be more of these, and it was right twice.

---

## ✅ 2. `book_detail_page.dart`'s app bar could carry up to 8 action icons at once

**Fixed** — commit `67f81ba`.

Same shape as the room-editor bug, smaller in degree. The app bar had 5
actions shown unconditionally (find my copy, lend/return, add to shelf, sync
toggle, edit) plus 3 more that only applied on a connected, shared server
(ask to borrow, ask to edit, send to a device) — sitting in the same row
rather than behind a condition on the row itself. On a synced book you don't
own, on a server with mail configured, all 8 could show at once.

The 3 connection-dependent actions now collapse into one **More** button,
shown only when at least one of them applies — the same fix the room editor's
toolbar just got. The 5 that make sense regardless of connection state stay
on the bar. `flutter analyze` and the full test suite pass unchanged; no
widget test constructs `BookDetailPage` directly, so this was verified by
reading rather than by a test asserting on the icon count.

---

## 3. The OPDS browser's intro screen can hide its own last catalogue card

**Not fixed.** Same bug class as #1, one instance item #1's grep missed
because it isn't a bare top-level `ListView(` the earlier pattern-match would
flag on its own — it's inside `_OpdsIntro`, a separate `StatelessWidget`
embedded in `OpdsBrowserPage`'s body.

`app/lib/import/opds_browser_page.dart`: `_OpdsIntro` (shown before anything
has been browsed or picked) is a `ListView` ending in one `Card`/`ListTile`
per built-in free catalogue, each tappable (`onTap: () => onPick!(...)`).  Its
padding is a flat `EdgeInsets.fromLTRB(24, 24, 24, 24)` — no `pageInsets()`.

The reason #1's seven didn't need checking against a `bottomNavigationBar`
but this one does: `OpdsBrowserPage`'s own `Scaffold` sets
`bottomNavigationBar: _selected.isEmpty ? null : Padding(...)` — a button that
appears once you've picked something. In the intro state (`_selected.isEmpty`,
which is the state this screen is *in* while `_OpdsIntro` is what's showing),
that's `null`, so Scaffold isn't self-insetting the body against the system
bar the way it would if a bottom bar were always present. The last free
catalogue in the list can end up under Android's gesture bar, same as #1.

**Fix shape**, matching #1 exactly:
```dart
return ListView(
  padding: pageInsets(context, const EdgeInsets.fromLTRB(24, 24, 24, 24)),
  ...
```
plus the import of `../widgets/page_insets.dart`.

**Checked and ruled out on the same pass** (re-running #1's grep, widened to
catch `ListView.builder`/`.separated` too, then reading each hit's Scaffold):
`folder_import_page.dart`'s review list (its `bottomNavigationBar` condition
is `_phase == _Phase.review && _plan.isNotEmpty` — exactly when the list has
rows, so it's always self-inset when it matters); `physical_libraries_page.dart`'s
hardcoded `bottom: 88` (odd, but this tab sits under `main.dart`'s
`NavigationBar`, which already self-insets it against the real system bar —
88 is just extra breathing room, not covering for a missing inset); and every
`ListView` that turned out to be `shrinkWrap: true` inside a bounded dialog or
already-`SafeArea`'d sheet.
