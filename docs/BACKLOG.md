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

### ✅ 8. Books riding shelves
Done (August 2026): dragging a bookcase carries its contents. The editor tracks
`_ridingIds` for books and `_ridingPropIds` for ornaments, so both travel with
the shelf and settle against it on release rather than staying behind at their
old world positions. Confirmed by hand.

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
   `adb shell cmd jobscheduler run -f app.vellum.Vellum <id>` to force the
   job. Expect a sync with no UI and no notification. The headless isolate opens
   its own database — watch for a lock conflict if the app is in the foreground
   at the same time, which is the one failure this design could still have.
4. **Constraints.** Off Wi-Fi, or unplugged, the job must not run at all. This
   is the whole point of the defaults and the only way to check them.

**Sync notification and backgrounding** (plan 6). `syncProgressBody`'s wording
is unit-tested (`app/test/notifications/sync_tray_test.dart`) and
`SyncForegroundService.kt` compiles in `flutter build apk`, but whether it
actually does its one job — keep the app's network alive through backgrounding
— only shows up on a device:

1. **The notification itself.** Press Sync on a library with something to
   pull or push. Expect a status-bar notification with a progress bar,
   updating as the phase label on screen does, replaced by a one-line result
   ("Pulled 3, pushed 1.") once it finishes.
2. **The actual point of it.** Start a sync on a library large enough to take
   a few seconds, then switch to another app (home button, not force-stop)
   before it finishes. Expect the notification to keep updating and the
   result to be correct when you switch back — not the "could not reach the
   server ... failed host lookup" this replaced.
3. **Cleanup.** After a sync finishes (foreground or backgrounded), confirm
   there is no lingering "syncing" notification and no orphaned foreground
   service (`adb shell dumpsys activity services app.vellum.Vellum` should
   show none once it's done).

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

- **The console's import list has a header stranded in the middle of it.**
  Reported 2026-08-11 with a screenshot: reviewing an 87-book folder import,
  the `Title` header sits as a dark band a third of the way down the list,
  covering two rows.

  *Cause, already traced:* `console.css` makes **every** `thead th` sticky at
  `top: var(--thead-top, 104px)`, and `--thead-top` is set from the page's top
  bar height. That is right for tables that scroll with the page and wrong
  inside a dialog: `#imp-review` is its own scroll container
  (`max-height:44vh; overflow:auto`) inside `.modal`, so the header sticks
  104px down from *that* box's top rather than at its top edge.

  *Fix:* scope the offset, e.g. `.modal thead th { top: 0 }` — the dialog has
  no top bar to clear. Worth checking the other dialogs with tables at the same
  time, since they share the rule.

- **A bulk console import stopped partway with a network error.** Reported
  2026-08-11: importing 87 books from a folder, it stalled around the 68th with
  *"Last error: NetworkError when attempting to fetch resource"* and went no
  further.

  *What is known:* that wording is the browser's `fetch()` failure, so the call
  that failed is `POST /api/books/from-search` — **not** the file upload, which
  is XHR and reports "Network error during upload". A NetworkError means the
  connection failed rather than the server answering with an error status, so
  the server either died, was restarted, or something between the two dropped
  the connection. The import loop is sequential, so it is not a flood of
  parallel requests.

  *Ruled out:* for a *folder* import the handler makes no outbound calls —
  `fetch_description` returns early on an empty `work_key` and `download_cover`
  needs a cover URL the console does not send. (A *catalogue* import with work
  keys does call Open Library twice per book, which is why the missing HTTP
  timeout was fixed alongside this — but it cannot be this failure.)

  **Cause found (2026-08-11), and fixed.** The reporter's Raspberry Pi locked
  up entirely, which pointed at memory. Uploads themselves stream to disk and
  hold nothing — but the *enrichment* spawned after each upload calls
  `lopdf::Document::load`, which reads a whole PDF into memory, and those tasks
  were detached and unbounded. The HTTP reply is sent before enrichment runs
  (on purpose, so a large upload is not held open), so the console starts the
  next book immediately and the parses accumulate: 87 books, 87 concurrent
  whole-PDF loads. On a small machine that is an out-of-memory kill, and it
  surfaces as the *next* request failing with a dropped connection rather than
  as anything the log attributes to the parse.

  Enrichment now takes a one-permit `enrich_semaphore`, held across the whole
  task rather than just the render — the page count is the memory-hungry half.
  Kept separate from `render_semaphore` so a bulk import cannot make reading a
  book slow, and vice versa.

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
