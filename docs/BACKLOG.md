# Backlog

Planned work and known issues. Resolved items are kept briefly for history;
architecture lives in [`DESIGN.md`](../DESIGN.md).

---

## Resolved

### ✅ 1. Add-book FAB overlapped the selection toolbar
The environment editor now **hides the “Add book” FAB while a book is
selected**, and the toolbar’s rotate control is enlarged (filled-tonal). No
overlap.

### ✅ 2. Manual author when creating a custom book
Added a dedicated **Author(s)** field (comma-separated → multiple authors),
separate from the subtitle, in both the **custom-create** flow
(`add_book_page.dart`, plus a Year field) and the **detail edit sheet**
(`book_detail_page.dart`). Backed by `LibraryRepository.setAuthors`.

### ✅ 3. Physical book width: presets + override
`physical_metrics.dart` now has **format presets** (mass-market, trade, A5, B5,
hardcover, A4) giving mm-per-page + optional binding allowance + trim height.
Calibrated exactly to a measured book: a 367-page B5 softcover is 21 mm →
**17.48 pages/mm** (~0.057 mm/page, no cover base) for the default and softcover
presets; hardcover adds board thickness. A `format` key is stored on
`book_placement` (schema v5); the resize dialog has a **preset dropdown** plus
manual thickness/height, reachable from the context menu (below).

### ✅ 5b. Shelf move + edit
Shelves can be **dragged to move**; right-click / long-press a shelf →
**Edit shelf… / Delete shelf** (the shelf dialog now doubles as an editor). A
**help button** and a persistent on-canvas **tip** explain the edit gestures.

### ✅ 4. Physical spine matches the digital shelf
Extracted `SpineFace` from `BookSpine` and reused it for placed books, so a
physical book shows the same cover-slice-or-generated spine as the digital
shelf, instead of a flat colour block.

### ✅ 6. Copy ↔ placement semantics
Confirmed **reference-only**: a placement means “this copy sits here” for
visualisation, not concrete inventory tracking. Current behaviour (a fresh
`physical_copy` per placement, multiples allowed) is correct as-is.

---

### ✅ 7. Cover-derived spine colours
Done (July 2026): the cover's **dominant colour** is extracted on every cover
set/pull (`cover_color.dart`, saturation-weighted histogram), cached in the
spine-style JSON, and backfilled at startup. A **spine artwork** preference
(spine mode only) switches covered books between the cover-slice spine (the
default) and a generated spine in that dominant colour.

---

## Open / possible follow-ups

- **Books riding shelves.** Moving a shelf still leaves its books behind; they
  keep their positions rather than travelling with the shelf. (An occupied
  shelf is currently pinned against dragging, so this is only reachable via
  shelf *edit*.)
- **Settle bounds.** The overlap resolver can push a book past a shelf’s end (it
  then floats at that height). Could clamp to shelf bounds.
- **EPUB reader polish.** The reader is chapter-at-a-time with resume-by-
  chapter; in-chapter scroll position isn't saved, and heavy CSS-driven
  layouts render approximately (`flutter_widget_from_html_core`).
- **Dominant colour in the physical view.** The physical editor always draws
  cover-slice spines; honouring the spine-artwork preference there too would
  keep the two views identical.
