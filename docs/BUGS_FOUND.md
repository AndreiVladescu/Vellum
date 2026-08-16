# Bugs found — 2026-08-16

Found by reading the code after fixing the Android toolbar/fullscreen report
(`app/lib/main.dart`, `app/lib/physical/environment_editor_page.dart`, already
committed). **Not fixed yet — this is a list to act on, not a changelog.**

Not duplicated here: the console sticky-header bug and the settle-bounds item
already tracked in [`BACKLOG.md`](BACKLOG.md#open--possible-follow-ups).

---

## 1. Seven pages can hide their own last row under Android's gesture bar

**Same bug class as the "Move to trash" fix** (`NEXT_FEATURES.md` #2,
commit `cd69376`): a page-level list with no bottom inset ends with its last
row flush against the screen edge, where the system gesture/nav bar sits on
top of it and eats the tap. That fix added `pageInsets()`
(`app/lib/widgets/page_insets.dart`) to 16 scroll views at the time. These
seven either predate that pass or were added after it without picking up the
convention — none of them import or call `pageInsets`:

| File | List | What's unreachable on a long list |
|---|---|---|
| `app/lib/settings/trash_page.dart:29` | `ListView.builder` | The last trashed book's **Restore** / **Delete forever** buttons |
| `app/lib/shelf/author_page.dart:48` | `ListView.separated` | The last book by that author |
| `app/lib/shelf/series_page.dart:32` | `ListView.separated` | The last volume in the series |
| `app/lib/wishlist/wishlist_page.dart:41` | `ListView.separated` | The last wishlist entry |
| `app/lib/dedupe/duplicates_page.dart:141` | `ListView.separated` | The last duplicate pair's merge action |
| `app/lib/add_book/add_book_page.dart:372` | `ListView.builder` (search results, in an `Expanded`) | The last search result |
| `app/lib/add_book/scan_page.dart:351` | `ListView.builder` (scanned books, in an `Expanded`) | The last scanned book's **Undo** |

The scan page one is the sharpest: *Undo* is a correction for a barcode
misread, and it's exactly the button a fast scan-a-shelf session needs most on
the book that was just added — i.e. the one most likely to be last in the
list.

**Fix shape**, matching the existing convention exactly
(`stocktake_page.dart:187` does this today):
```dart
ListView.builder(
  padding: pageInsets(context, EdgeInsets.zero), // or whatever the current padding is
  ...
)
```
For the two `Expanded` cases, wrap the existing (absent) padding the same way.

Worth a repo-wide grep before closing this out — `page_insets.dart`'s own doc
comment already predicted more of these ("other long scrolling pages were not
audited").

---

## 2. `book_detail_page.dart`'s app bar can carry up to 8 action icons at once

**Lower confidence — flagging, not certain.** Same shape as the room-editor
bug just fixed, smaller in degree. The app bar's `actions` (`book_detail_page.dart:355-450`)
has 4 icons that are always shown (lend/return, add to shelf, sync toggle,
edit) plus up to 4 more that appear conditionally (ask to borrow, ask to
edit, send to device, find my copy) depending on server connection and
sharing state. On a shared server with a synced book, several of the
conditional ones can be true simultaneously, stacking with the permanent
four.

Unlike the room editor, the title here (`Text(book.title)`) degrades
gracefully — it truncates with an ellipsis instead of getting shoved off
entirely — so this is milder and may not be worth touching. Worth a look on a
narrow phone with a long book title and a shared, connected library, which is
the specific combination that stacks the most icons at once.
