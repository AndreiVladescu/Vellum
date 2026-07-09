# Backlog

Planned work and known issues not yet implemented. Each item records *what*,
*why*, the *current state* in the code, and *open questions* to resolve before
building. Architecture lives in [`DESIGN.md`](../DESIGN.md); this file is the
near-term to-do with rationale.

---

## 1. Add-book FAB overlaps the selection toolbar (bug)

**What.** In the physical environment editor, the “Add book” floating action
button sits on top of the selection toolbar’s buttons (the rotate-90° control)
when a book is selected.

**Current state.** `environment_editor_page.dart`: the FAB uses the default
bottom-right location, while `_SelectionBar` is `Positioned(left: 12, right: 12,
bottom: 12)` — full width — so the FAB overlays its right edge.

**Options.**
- Move the FAB left (user’s suggestion). Caveat: bottom-left already holds the
  scale bar (`_ScaleBar`, `left: 12 bottom: 12`), so a bottom-left FAB would
  collide with that instead.
- Hide the FAB while a book is selected (the toolbar owns the bottom then).
- Shorten the toolbar so it doesn’t reach under the FAB.

**Open question:** move the FAB (and where), or hide it while selecting?

---

## 2. Manual author (and more) when creating a custom book

**What.** When creating a book by hand — because auto-metadata didn’t find it —
the user wants to type the **author** (and likely year), not just the title.

**Why.** Online lookup sometimes returns nothing (niche/new titles); today those
books end up author-less until edited later.

**Current state.** `add_book_page.dart:_create()` calls
`repository.createCustomBook(title: title)` only. The repository method
**already accepts** `author`, `publishedYear`, and `description` — they’re just
not surfaced in the UI (the page has a single “Title, author, or ISBN” search
field). So this is a UI wiring task, no data-model change.

**Open question:** which fields on the custom-create form — author only, or also
year (and publisher/pages)? And keep it as extra fields revealed under the
search box, or a distinct “Create manually” form?

---

## 3. Physical book width: better model + manual override

**What.** The page-count→thickness formula is wrong for real books. Example: a
~1000-page **B5** book is very chunky, but the formula underestimates it. The
user wants to **right-click a book to set its width** when it’s off, and a
default that’s closer to reality.

**Why.** Thickness depends on paper stock and format, not page count alone; a
single linear formula can’t capture a slim novel vs. a dense B5 textbook.

**Current state.**
- `physical_metrics.dart`: `thickness = 0.008 + pages * 0.00006 m`, clamped
  6–90 mm. No notion of paper type or trim size.
- Height defaults to a flat 0.20 m; there is **no format/trim-size** concept
  (B5, A5, A4, paperback, hardcover…).
- Resizing exists but only via **tap → toolbar → Resize** (thickness/height in
  cm). There is **no right-click / context-menu** path (desktop).

**Directions to consider.**
- Tune the per-page factor and/or make it depend on a **format/paper preset**
  (which would also give a sensible height).
- Right-click (secondary-tap) a placed book → context menu → edit width/height
  quickly. Keep the tap→toolbar path for touch.
- Treat the formula as only a rough default and lean on easy manual override.

**Open questions:** improve the formula, add a format/paper preset, or mostly
rely on manual override? A calibration data point would help — e.g. the real
thickness (cm) of that ~1000-page B5 book.

---

## 4. Physical spine derived from the book, like the digital shelf

**What.** Physical books currently render as a **flat palette rectangle**. The
user wants the spine to look like the digital shelf’s — “part of the cover
book” — rather than a plain color block.

**Why.** Consistency with the digital shelf and a more real, less abstract look.

**Current state.**
- Digital shelf spines come from `SpineStyle.generate()`, which picks a color
  from a **hash-of-title palette** and adds a decoration variant + vertical
  title. Note: `DESIGN.md` says “extract dominant colors from the cover”, but
  the code today uses the **title-hash palette**, *not* the actual cover image —
  a gap worth resolving as part of this.
- `physical_metrics.color()` reuses only that palette color for the physical
  rectangle; the physical renderer draws a solid fill + title, no decoration.

**Interpretations of “spine as part of the cover”.**
- (a) Reuse the existing generated spine style (color + decoration + title
  styling) in the physical view — visual parity with the digital shelf.
- (b) Actually **extract colors from the cover image** (closing the DESIGN gap),
  used by both digital and physical spines.
- (c) Show a **sliver of the cover image itself** as the spine texture.

**Open question:** which of (a)/(b)/(c) — reuse the current generated spine,
extract real cover colors, or paint an actual slice of the cover?

---

## Notes

- Items 3 and 4 will likely update `DESIGN.md` (spine rendering + physical
  layouts) once their approach is decided.
- All physical-layout work stays **app-local** (no server/sync), per the
  original decision.
