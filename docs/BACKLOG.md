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

## Open / possible follow-ups

- **Cover-derived spine colours.** `DESIGN.md`’s spine section says colours are
  “extracted from the cover”, but the code uses a **title-hash palette**. Item 4
  reused that as-is; genuinely extracting dominant cover colours (for both
  digital and physical) is still open.
- **Cover-image slice as spine.** Follow-up to item 4: painting an actual slice
  of the cover as the spine texture (vs. the cover-or-generated `SpineFace`).
- **Books riding shelves.** Moving a shelf still leaves its books behind; they
  keep their positions rather than travelling with the shelf.
- **Settle bounds.** The overlap resolver can push a book past a shelf’s end (it
  then floats at that height). Could clamp to shelf bounds.
