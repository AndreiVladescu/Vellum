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

### ✅ 9. Console import header stranded mid-list
The `thead th` sticky offset (`--thead-top`, sized for the page's top bar) was
applied inside dialogs too, so the import review's header stuck 104px down its
own scroll box. `server/web/console.css` now has `.modal thead th { top:0; }`.

### ✅ 10. Bulk console import stopped on a network error
The enrichment after each upload ran `lopdf::Document::load` on whole PDFs with
no limit, so a large folder import held dozens of parses in memory at once and
the Raspberry Pi ran out. Enrichment now takes a one-permit `enrich_semaphore`
held for the whole task, separate from the render semaphore.

### ✅ 11. Settle bounds
A book nudged out of an overlap no longer leaves its shelf: when the nearer
push would carry it past an end and the other side has room, it goes there
instead. A shelf with no room either way still falls through to the surface
below (`settle.dart`, pinned in `test/settle_test.dart`).

### ✅ 12. Dominant colour in the physical view
The room editor passes the spine-artwork preference to `SpineFace` and repaints
when it changes, so a book is drawn the same way in both views.

---

## Manual device checks (CI can't do these)

**Emulator pass, 2026-11-13** (`app/tool/emulator.sh`; Pixel 6 and Pixel Tablet
AVDs, Android 14, debug build). Passed on the phone: all three shortcuts cold
and warm; the widget (added through the launcher, shows cover, title and
progress); tapping the widget (this opened only the shelf until the fix
`android: widget tap opens the book`, since the click sent a `vellum://`
URI nothing reads instead of the shortcut extra); open-with a PDF (cold) and
share an EPUB (warm), both landing on the add-book form with the file attached
(through `file://` URIs from app storage, see below); Material You (system
palette forced to blue with `settings put secure
theme_customization_overlay_packages`, the app followed it once *Use the system
colours* was on); the PDF reader (open, pinch to roughly 6x with
`sendevent` after `adb root`, text sharp at every level, highlight, and the
text away from the mark as crisp as with none, in-book search 1/46).
Failed or open:

- **Large text.** At font scale 1.3 the *All* / *New shelf* chips on the shelf
  are clipped, and the book detail's *Resume reading* row overflows by 14 px
  (the open-externally button); at 2.0 the same row overflows by 102 px and
  the star-rating row by 8 px. Screenshots are in the agent scratch area.
- **Widget empty state.** The widget treats 98 % progress, not the *Finished*
  status, as "finished", like the shelf strip. Setting *Finished* by hand left
  it showing the book; read to the end to check the fall-back.
- **Tablet (2560x1600, 320 dpi).** No wide layout: the shelf, the book detail
  and its notes box stretch edge to edge, the drawer is modal and the bottom
  bar stays. Rotation to portrait works. Reader, insights and sync not looked
  at on the tablet.
- **Not possible on the emulator:** a real *Open with* from Files and a Gmail
  share (the shell cannot grant a `content://` URI, so the import copy was
  checked with `file://`); multi-file share (`am` cannot send a URI list);
  the generic-mime case; the empty widget preview (the picker shows a grey box,
  there is no preview layout); camera scanning; battery and Wi-Fi constraints;
  the 2.12 items that need a real phone.

**Emulator pass, 2026-11-13 (evening)** (debug build of the commit after
"system bars hide only in the reader"; Android 16 phone `vellum_android16`
first, then the Pixel Tablet and the Android 14 phone; a local `cargo run`
server reached through `adb reverse tcp:3000 tcp:3000` and `http://localhost:3000`,
because the app refuses cleartext to `10.0.2.2`). Passed:

- *Android 16, system bars.* The "Viewing full screen" hint came from
  `immersiveSticky` set app-wide in `main()`. Fixed (`android: system bars
  hide only in the reader`): the app is edge to edge, the bars hide while a
  reader is open. On a fresh install the shelf and the Physical tab show no
  hint, the bars stay and nothing sits under the gesture bar; the hint now
  appears once, in the reader.
- *Android 16, background sync.* Job id 1 is in the `androidx.work.systemjobscheduler`
  namespace, so the job is run with `cmd jobscheduler run -f -n
  androidx.work.systemjobscheduler app.vellum.Vellum <id>`. WorkManager still
  refuses ("executed before schedule") until the initial delay has passed:
  move the clock a day with `adb root; date MMDDhhmmYYYY.ss`, run it, then put
  the clock back and `adb unroot` (root restarts adbd and drops `adb reverse`;
  the first run returned RETRY for exactly that reason). With the forward back
  the worker returned SUCCESS and the server saw its requests; the status-bar
  progress notification was posted and cleared.
- *Loan reminders permission (Android 16).* The switch asks; Don't allow leaves
  it off with a snack bar; asking again and Allow turns it on.
- *Material You on Android 16* follows the system palette (forced blue).
- *Sync details.* An unreachable server now reads "Could not reach the server.
  Check the address and your connection." with the raw exception on a second
  line (sign-in); the issues dialog does the same for classified failures.
- *Open with, warm.* A PDF and an EPUB in app storage (`file://`) land on the
  add-book form with the file attached. A `file:///sdcard/...` URI does nothing
  (no storage permission), which is expected.
- *PDF reader.* Opens, selecting text and the highlight button, in-book search
  (14 hits for a word, 1/14).
- *EPUB reader.* Scrolled opens and the chevrons turn chapters; paged mode
  turns pages by tap on the right third and by swipe in a text chapter
  ("Page 1 of 12" to "Page 2 of 12", and back with a swipe).
- *Tablet (2560x1600).* Permanent navigation drawer, two-column book page
  (cover and actions left, formats, copies, status and notes right).
- *Large text 1.3 and 2.0.* The shelf chips were still clipped at both (the
  chip got a tight row height and drew its label off-centre); fixed
  (`shelf: chips keep their height at large text`), looked at at 2.0 on the
  Android 16 phone. The book page's read row fits (also a widget test at 360
  and 400 px; it did not reproduce on HEAD).

Failed or open:

- **Paged mode in a chapter that holds a picture.** On the Time Machine and
  Frankenstein samples the title page (an SVG) and the Imprint (the logo) do
  not turn pages by tap, swipe or the chevron, and do not move on to the next
  chapter, so a reader is stuck there until they use the chapter list. The
  same books' text chapters paginate and turn fine. `_pageForward` returns when
  `pages.ready` is false; `measureLines` clears it while a `RenderChapterLoading`
  is under the chapter, so a picture that never finishes building keeps it
  false. Screenshots: `paged_tap_next.png`, `paged3_a.png` in the agent
  scratch area.
- **Widget after a reinstall.** On the Android 14 phone the widget said
  "Nothing on the go" while the shelf's Continue reading card had a book at
  13 %; the widget had not been refreshed since the reinstall. Open the app
  and check it follows.
- **Sample books push a reading session.** A reading session recorded on a
  device-only sample book is sent on every sync and the server answers 400
  "no such book", so each sync ends with "1 issue" on a library whose books
  are all samples. Sessions of books the server does not have should not be
  pushed.
- **Not done:** the two-factor code prompt (needs an account with 2FA on and a
  TOTP generator on the host), shortcuts and the widget add flow on Android
  16, EPUB paged mode and the reader on the tablet (the tablet's library had
  no EPUB), pinch zoom in the PDF reader (`input` cannot pinch).

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
5. **After the workmanager 0.10 bump (update in place).** On a phone that has
   the previous release installed *with background sync already on*, install
   the new build over it (`adb install -r`, do not uninstall). Before opening
   the app, run `adb shell dumpsys jobscheduler | grep -A6 app.vellum.Vellum`:
   the periodic job must still be listed (the old WorkManager row survives the
   update; the worker class and input keys are unchanged). Then open the app
   once and confirm the job is still there, once, with Unmetered + Charging
   constraints (the launch re-registers it with `ExistingPeriodicWorkPolicy.update`),
   and force it as in step 3. A job forced *before* the first launch can fail
   once because the stored callback handle belongs to the old build; that is
   expected, and the next period recovers.
6. **Android 14, 15 and 16.** Repeat step 3 on each (0.10.8 to 0.10.10 fix
   Android 16 handshake and foreground-service-permission failures). Expect
   the headless sync to complete without `Dart engine did not initialize the
   background channel` in `adb logcat` (the plugin's 30 second watchdog), and
   the job not to stay `RUNNING` after the app is backgrounded mid-run. The
   manifest drops `FOREGROUND_SERVICE_SHORT_SERVICE` on purpose (plain periodic
   work starts no foreground service); confirm no `workmanager_android:` error
   about a missing permission appears.
7. **Nothing new on desktop.** `workmanager_linux` is Dart-only and the app
   never calls it; confirm no `systemd` unit named `workmanager-*` appears
   (`systemctl --user list-units 'workmanager*'`) after running the Linux build.

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

**PDF highlights and sharpness**: `pdf_marker_paint_test.dart` pins the blend
(a pipeline one, same pixels as multiply), but only a real renderer shows the
soft page multiply caused under Impeller. On Linux and Android, zoom a text PDF
well in (past about 3x), highlight a passage, and compare the text *away* from
the mark with a page that has none: it must be as crisp, at a few zoom levels,
in scroll and paged mode, day and night.

**After the pdfrx 2.12 bump**: measured on Linux and the Android 14 emulator
(open, reopen with a highlight, pinch, sharpness, search, memory). Still owed:
the Windows and macOS release builds launching and opening a PDF (PDFium now
compiles a small C library on each platform); the AppImage; pinch and swipe
page turns in paged mode on a real phone; search on a long book; memory on a
phone (its page cache is capped at 32 MB); and pdfrx's own right-click /
selection menu in dark mode, which now comes from the separate `material_ui`
package and may no longer follow the app's theme.

**Loan due-date notifications (v1.4.2) — device check owed.** Built and unit
tested (`lib/loans/loan_reminders.dart`: what gets scheduled, and the service that
keeps it in step), but the OS side has not been seen on a device. On Android:
Preferences → *Remind me when lent books are due* asks for the notification
permission (13+) and stays off if refused; lend a book due tomorrow and check
that a notification is pending (`adb shell dumpsys alarm | grep vellum`) and
arrives at about 09:00 the day before and the day it is due; return the loan and
check it is cancelled; reboot and check it is re-registered; tap a notification
and check it opens the loans list, from a cold start as well as a running app.
Alarms are inexact on purpose (no exact-alarm permission), so a few minutes' delay
is expected. Desktop shows the switch disabled.

**Deferred from #23**, and why: keep-screen-awake, volume-key page turns and the brightness
slider each need a platform plugin, and were not worth adding three dependencies
in the same pass. None of them block the rest of the item.

**EPUB paged mode (v1.4.0) — device check owed.** Checked on Linux by driving
the reader with synthetic key, tap and touch-swipe events (page turns, rolling
into the next chapter and back onto the previous one's last page, a resize, and
switching to scrolled and back all kept the place; no page cut a line). Still
to see on a real phone: swipes and side-third taps against text selection
(long-press to select, then dragging a handle must not turn), rotation, a
chapter with a tall picture (it should be scaled to the page), and night mode.

---

## Performance round (October 2026)

Found by measuring rather than guessing — see
[`PERFORMANCE.md`](PERFORMANCE.md) for the numbers. One commit per item, in
this order.

- [x] **1. App database indexes.** The app schema has no secondary indexes: the
  shelf's `has_file` check scans `book_files` once per book, on every `books`
  write (every page turn). 393 ms → 20 ms at 5,000 books.
- [x] **2. WAL journal for the app database.** Cheaper page-turn writes, reads
  that don't wait on writers. Restore must clear stale `-wal`/`-shm` files.
- [x] **3. Cover thumbnails.** Spines decode full-size covers (up to 1.7 MB PNG
  at 908×1200). Store covers as JPEG, keep a small shelf thumbnail made off the
  UI isolate, backfill existing covers across cores.
- [x] **4. Sync re-uploads unchanged covers.** Every push of a dirty book sends
  its whole cover; the server rewrites it and bumps `updated_at`, so every
  other device downloads it again. Upload only changed covers; the server
  skips identical bytes and uses a content-hash ETag.
- [x] **5. Push lists the whole library.** Learning which files the server has
  fetches every book; ask only about the books being pushed.
- [x] **6. Concurrent pull.** A no-change sync is ~18 sequential GETs; fetch the
  independent lists together, apply them in foreign-key order.
- [x] **7. Gzip on the server's JSON responses.**
- [x] **8. Import hashing off the UI isolate.** SHA-256 of every imported file
  runs on the UI isolate, one file at a time; hash in background isolates, in
  parallel. Same for the content indexer's EPUB parse.
- [x] **9. EPUB reader: stop re-transforming chapter HTML on every build.**

---

## Open / possible follow-ups

- **EPUB reader polish.** Partly resolved by plan 5 #23: in-chapter scroll
  position **is** saved and restored (the arithmetic is pinned in
  `test/reader/epub_reader_page_test.dart`), and typography/themes now apply.
  Paged mode landed in v1.4.0 (`epub_pagination.dart`, `paged_chapter.dart`).
  Still open: heavy CSS-driven layouts rendering approximately
  (`flutter_widget_from_html_core`). Paged-mode follow-ups: auto-scroll is
  hidden there rather than turning pages on a timer; a tap in a side third on a
  link turns the page as well as following it; a re-pagination (text size,
  window) keeps the place by proportion of the chapter, not by the exact line;
  no page-turn animation; volume-key turns still need a platform plugin.

## Read aloud (v1.4.3): checks owed on a device

Written without a speech engine to hand; the controller and sentence cutting are
unit tested (`test/reader/tts/`), the engines and the page-following are not.

- **Android, EPUB, paged and scrolled.** Read aloud from the middle of a
  chapter: it starts at the top of the page (or the selection), the page turns
  as sentences go by, and it rolls into the next chapter. Pause, skip back and
  forward, stop. Check the page it turns to is the one the voice is on (the
  position is the sentence's share of the chapter's text, so a chapter heavy in
  pictures may be a page out).
- **Android, PDF.** Starts on the current page, moves the view along, skips a
  scanned page with a short notice.
- **Speed and voice** in the reader's settings sheet are remembered across
  books and restarts. The default voice follows the EPUB's `dc:language`.
- **No engine:** with the system speech service disabled, Read aloud explains
  rather than doing nothing.
- **Audio focus.** `flutter_tts` asks for focus when it speaks but reports no
  loss of it, so a phone call or another player does not pause the reader;
  leaving the app (paused/hidden) does. Decide whether that is enough.
- **Linux.** `flutter_tts` has no Linux support, so the app calls `spd-say`
  (speech-dispatcher) directly. Check with and without it installed, that stop
  cuts the voice at once, and that the speed slider is audible.
- **Windows / macOS:** the plugin's speed scales are mapped by guess
  (`PluginTtsEngine.pluginRate`); check 0.5x, 1x and 2x sound right.

## Audiobook player: background playback, speed, sleep timer (v1.5.1)

Nothing below has run on a device; the controller, the handler and the mini bar
are tested over fakes.

- **Notification.** Play a book, press Home. A media notification shows the
  chapter title, the book, the author and the cover, with previous chapter, -30 s,
  play/pause, +30 s and next chapter. Each button works; the seek bar spans the
  whole book. Paused, the notification can be swiped away; pressing play from
  the lock screen or the mini bar afterwards brings it back (Android 12+ may
  refuse a foreground-service restart: look for
  `ForegroundServiceStartNotAllowedException` in logcat).
- **Lock screen and Bluetooth.** The same controls on the lock screen, and a
  headset's play/pause and skip buttons.
- **Headphones.** Unplugging wired headphones, or switching off Bluetooth
  ones, pauses; the page, mini bar and notification all show paused, and the
  position was saved.
- **A call.** An incoming call pauses; after hanging up a short call resumes,
  a long one may not. Another app starting playback pauses the book.
  Navigation prompts duck it.
- **Leaving the page.** Back out of the player: the book keeps playing and the
  mini bar above the navigation shows it; tapping the bar reopens the player
  without the "go there?" offer. The bar's close button stops the book.
  Check the bar on a phone, on a tablet in landscape (rail) and on the
  desktop layout (drawer), and that the floating buttons sit above it.
- **Speed.** 0.5x, 1.5x and 3x sound right and the pitch does not change, on
  Android (ExoPlayer) and Linux (libmpv). The speed comes back when the book
  is reopened after a restart, and across a part change in an mp3 folder.
- **Sleep timer.** 5 minutes: the sound fades over the last ten seconds, then
  stops; the position on the book page is where it stopped. "End of chapter"
  stops at the chapter's end, including a chapter that ends with a file in an
  mp3 folder. A pause freezes the countdown.
- **Linux.** `playerctl status` and `playerctl play-pause` (or a desktop media
  widget) see and drive Vellum while a book is open.
- **macOS.** Now Playing and the media keys.
- **Windows (SMTC, never run).** `flutter build windows` compiles with
  `audio_service_win` 0.0.6. Playing a book shows the title (chapter), author
  and cover in the volume/media overlay and on the lock screen; the keyboard
  play/pause, next and previous keys drive it (next/previous change chapter);
  seeking from the overlay works; closing the book clears the overlay. If the
  session fails, playback must still work.
- **Killing the app.** Swipe it from the recents while playing: it keeps playing
  from the service (decide whether that is wanted); while paused the
  notification goes away.


**Home widget, two rows** (docs/AUDIOBOOKS.md section 10). The layout switch and
the taps only show on a launcher:

1. **Picker.** Add widget: the preview shows two rows (Reading, Listening).
   It lands 4x2.
2. **Both kinds.** With a book being read and another listened to, the 4x2
   shows both rows with cover, title and "Reading . 42% . page 214" /
   "Listening . 42% . at 1:02:33" (check the covers load, and that two covers
   do not make the update fail).
3. **Resize to 4x1.** Drag the widget down to one row: it flips to the single
   most recent book; back up, to two rows, without opening the app.
4. **Taps.** Reading row opens that book page; listening row opens the
   player at the saved position; the 4x1 row opens whichever it shows. Try
   cold (force-stopped app) and warm.
5. **Only one kind.** With nothing being listened to, the 4x2 shows the
   single row (reading), not an empty second row. Nothing at all: the empty
   state, tap opens the app.
6. **After the update.** A widget placed before this change still draws
   (old snapshot) until the app starts, then updates.
