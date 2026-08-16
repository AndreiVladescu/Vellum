# Bugs found — 2026-08-16

Found by reading the code after fixing the Android toolbar/fullscreen report
(`app/lib/main.dart`, `app/lib/physical/environment_editor_page.dart`). Both
items below are now fixed; kept here as a record of what was found and how,
rather than deleted, since the reasoning is what makes it checkable later.

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
