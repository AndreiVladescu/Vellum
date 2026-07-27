# Backlog

Planned work and known issues. Resolved items are kept briefly for history;
architecture lives in [`DESIGN.md`](../DESIGN.md).

> The forward-looking roadmap — architecture changes and new features — is
> [`IMPROVEMENT_PLAN_5.md`](IMPROVEMENT_PLAN_5.md). The open items at the bottom
> of this file are carried there (EPUB reader polish → #23, dominant colour in
> the physical view → landed).

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

## Manual device checks (CI can't do these)

**Background sync, shortcuts and the widget** (plan 5 #40). The scheduling
*policy* is unit-tested (`app/test/server/background_sync_test.dart`) and the
Kotlin, the manifest, the shortcut XML and the widget layout all compile in
`flutter build apk`. What a build cannot prove is that the OS honours any of it:

1. **Shortcuts.** Long-press the launcher icon. Expect *Scan*, *Continue*,
   *Add*. Tap each from a cold start and from a warm resume — the cold path goes
   through `takeShortcut`, the warm one through `onShortcut`, and they are
   different code.
2. **The widget.** Add *Continue reading* to the home screen. Expect the book
   you last opened, its cover and progress; tapping it should open that book.
   Then finish the book and confirm the widget falls back to the empty state
   rather than keeping it.
3. **Background sync.** Set it to *Every 6 hours* in Preferences, then use
   `adb shell cmd jobscheduler run -f com.avladescu.vellum <id>` to force the
   job. Expect a sync with no UI and no notification. The headless isolate opens
   its own database — watch for a lock conflict if the app is in the foreground
   at the same time, which is the one failure this design could still have.
4. **Constraints.** Off Wi-Fi, or unplugged, the job must not run at all. This
   is the whole point of the defaults and the only way to check them.


**Open-with / share-target import** (plan 5 #20). The Dart side is unit-tested
through a fake channel (`app/test/import/incoming_share_test.dart`) and the
Kotlin side compiles in `flutter build apk`, but the intent plumbing itself needs
a real device:

1. **Open with, cold start.** Force-stop Vellum. In Files, long-press a PDF →
   *Open with* → Vellum. Expect the add-book form with the file already attached
   and the title seeded from the file name.
2. **Share, warm resume.** Open Vellum, switch to Gmail, share an EPUB
   attachment to Vellum. Expect the same form without a restart.
3. **Multi-file share.** Select two or more PDFs in Files → Share → Vellum.
   Expect the import wizard's review list, not the single-book form.
4. **A share you then cancel.** Back out of the form; nothing should be added,
   and `cacheDir/incoming` may keep the copy (harmless — Android reclaims it).
5. **A generic mime type.** Share a PDF from an app that sends
   `application/octet-stream`; the path pattern in the manifest should still
   offer Vellum.

**Barcode scanning** (plan 5 #16): scan a real book, then deny the camera
permission and confirm the manual ISBN field still adds books.

**Reader appearance** (plan 5 #23): the settings themselves are unit-tested, but
their visual effect is not — driving `HtmlWidget` and the EPUB parse isolate under
`testWidgets` hangs rather than failing. Check by hand: each of the four page
colours; text size/line-spacing/measure sliders reflowing an EPUB; PDF night mode
on a page containing a photograph (it must not look like a negative); fit
width/page; in-book search with next/previous; "go to page"; and the hide-controls
preference plus tap-to-reveal in both readers.

**Deferred from #27**: scheduled OS notifications a day before and on the due
date. The *decision* logic is built and tested (`LoanDue.needingReminder`, which
knows not to nag twice in a day but to come back while a book is still out) and
the loans list badges what needs attention, but nothing schedules a system
notification — that needs `flutter_local_notifications` plus per-platform channel
setup, permissions and a timezone database. The in-app path (badge → *Copy a
reminder*) works everywhere today.

**Deferred from #23**, and why: paged (rather than scrolled) EPUB mode is a layout
engine of its own; keep-screen-awake, volume-key page turns and the brightness
slider each need a platform plugin, and were not worth adding three dependencies
in the same pass. None of them block the rest of the item.

---

## Open / possible follow-ups

- **Books riding shelves.** Moving a shelf still leaves its books behind; they
  keep their positions rather than travelling with the shelf. (An occupied
  shelf is currently pinned against dragging, so this is only reachable via
  shelf *edit*.)
- **Settle bounds.** The overlap resolver can push a book past a shelf’s end (it
  then floats at that height). Could clamp to shelf bounds.
- **EPUB reader polish.** Partly resolved by plan 5 #23: in-chapter scroll
  position **is** saved and restored (the arithmetic is pinned in
  `test/reader/epub_reader_page_test.dart`), and typography/themes now apply.
  Still open: paged (as opposed to scrolled) mode, and heavy CSS-driven layouts
  rendering approximately (`flutter_widget_from_html_core`).
- **Dominant colour in the physical view.** The physical editor always draws
  cover-slice spines; honouring the spine-artwork preference there too would
  keep the two views identical.
