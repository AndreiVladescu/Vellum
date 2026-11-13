# Roadmap

What is planned, release by release, written 2026-11-11 ahead of the public
(Reddit) release. Architecture lives in [`DESIGN.md`](../DESIGN.md); known
issues and device checks live in [`BACKLOG.md`](BACKLOG.md).

**Releases are small on purpose.** A minor version (`1.3`) is a theme; each
patch under it (`1.3.1`, `1.3.2`) is one or two things that can be finished,
reviewed and shipped on their own. A bug found after a release takes the next
free patch number and pushes the rest down by one.

Each task carries a size, which is also who writes it:

- **S** — elementary, mechanical, cause already known (Haiku)
- **M** — a contained feature in code that already has a pattern for it (Sonnet)
- **L** — new architecture, schema on both sides, or a layout engine (Opus)

Every task is reviewed before it is committed, one commit per task. Tick a box
when its commit lands.

**A finished release gets a tag.** When every box under a version is ticked and
CI is green, a commit titled `Updated for vX.Y.Z` bumps `app/pubspec.yaml`,
`server/Cargo.toml` and `CHANGELOG.md`, and that commit is tagged `vX.Y.Z`.
Pushing the tag is what builds the release.

**Tagged so far:** `v1.2.1` (2026-11-11) — everything ticked under v1.1.12,
v1.2.0, v1.2.1 and v1.3.0, plus the first slice of v1.2.2 and the dependency
updates from v1.2.3. The work landed interleaved, so it shipped as one tag.
`v1.2.2` (2026-11-11) — the published server image (listed under v1.2.3) and
the second slice of translations. The version headings below are the plan;
this list is what each tag actually carried.
`v1.2.3` (2026-11-12) — the rest of the translations (v1.2.2 in the plan), and
from the server track the console split, navigation, Overview and Server
pages (v1.6.0 and part of v1.6.1).
`v1.3.1` (2026-11-12) — reading goals and per-book statistics, as planned.
(`v1.3.0`'s rating sync shipped in `v1.2.1`; `v1.2.4`, the public release, is
still the hand-made one.)
`v1.3.2` (2026-11-12) — month by month and explorable Insights, as planned.
`v1.3.3` (2026-11-13) — the highlight blur fix and dependency updates; a fix
takes the next free number, so year in review moves to v1.3.4.
`v1.3.4` (2026-11-13) — dependency updates: `pdfrx` 2.12, `workmanager` 0.10,
`dynamic_color` 1.9; year in review moves to v1.3.5.

---

## 1.1 — fixes

### v1.1.12 — the reader works the first time

Fixes from `problems_09_nov.txt`. Nothing else ships in this one.

- [x] **M** A PDF opens on the first try (pdfrx document reference is created
      once; pdfrx is warmed up at app start)
- [x] **M** A highlight or note is still drawn after reopening the book (page
      text is not read before the page is loaded)
- [x] **M** The page no longer goes blurry after *Note on selection* — the
      highlight was drawn with a multiply blend, which Linux's Impeller
      renderer composites by resampling the page underneath. Now an opaque
      `modulate` with identical colours; measured sharp at every zoom
- [x] **M** Ctrl+F puts the caret in the search field, and searches as you type
- [x] **S** The search field's text is readable in every reader theme

---

## 1.2 — ready to show people

Everything here is about a stranger's first ten minutes. **v1.2.3 is the one
that gets posted.**

### v1.2.0 — a shelf that is not empty

- [x] **M** Sample library on first run: a "try it with a few books" action
      that adds a handful of bundled public-domain books
- [x] **M** *Copy diagnostics* in Preferences: version, platform, schema version
      and recent errors on the clipboard, with nothing personal in it

### v1.2.1 — physical view polish

- [x] **S** Shelf settle bounds: a book pushed sideways out of an overlap stops
      at the shelf's end instead of floating past it
- [x] **S** The physical view honours the spine-artwork preference, like the
      digital shelf
- [x] **S** `BACKLOG.md` clean-up: move what is already fixed to *Resolved*

### v1.2.2 — translatable

- [x] **M** Strings out of the widgets and into `app_en.arb`
- [x] **S** A short `docs/TRANSLATING.md` for contributors

### v1.2.3 — a server you can pull

- [x] **M** Server dependencies updated for the open advisories (`cargo audit`
      and osv-scanner green again)
- [x] **M** Publish the server image on every tag: Docker Hub and GHCR,
      `linux/amd64` and `linux/arm64` (a Raspberry Pi is a real target), tagged
      `X.Y.Z`, `X.Y` and `latest`, with OCI labels, provenance and an SBOM
- [x] **S** `docker-compose.yml` and `docs/DEPLOYMENT.md` pull the published
      image instead of building; the Docker Hub page shows the deployment guide
- [ ] **by hand** A Docker Hub account, the `vellum-server` repository and an
      access token, stored as the `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`
      repository secrets

### v1.2.4 — the public release

- [ ] **by hand** The device checks still owed in `BACKLOG.md`
- [ ] **by hand** Screenshots and a 20-second clip: shelf, reader, physical
      room, phone
- [ ] **S** README and store listing updated around them

---

## Next — phone and tablet testing on an emulator

Several checks in `BACKLOG.md` → *Manual device checks* can only be done on
Android, and so far only on the owner's own phone. An emulator on this machine
lets the work be checked before it ships.

- [x] **by hand** Turn on hardware acceleration (done 2026-11-13). The CPU supports it (AMD-V)
      and the `kvm_amd` module is installed but not loaded, so `/dev/kvm` is
      missing and the emulator refuses to start. One-off:
      `sudo modprobe kvm_amd && sudo usermod -aG kvm $USER` (log out and in);
      to keep it across reboots,
      `echo kvm_amd | sudo tee /etc/modules-load.d/kvm.conf`. If `modprobe`
      says SVM is disabled, enable *SVM Mode* in the BIOS.
- [x] **S** Phone: the existing AVD `vellum_test` (Pixel 6, Android 14, Google
      APIs, x86_64) boots headless and the debug APK installs and opens
      (done 2026-11-13: boots in ~30 s, installs, opens on the shelf)
- [x] **S** Tablet: a second AVD from the same Android 14 image with a tablet
      profile (Pixel Tablet), for the wide layouts (done 2026-11-13:
      `vellum_tablet`, 2560x1600 at 320 dpi; the shelf and book detail just
      stretch to the full width, no two-pane or rail yet)
- [ ] **S** Android 16: an API 36 image and AVD, for `workmanager` 0.10's
      Android 16 fixes (a ~1.5 GB download; the disk is 95 % full)
- [x] **M** A script under `tool/` that boots an AVD headless, installs the
      APK, runs a check and shuts it down, so agents can use it without
      leaving an emulator running (done 2026-11-13: `app/tool/emulator.sh`,
      `boot|install|shot|run|stop|status`; `run` always shuts down, `boot`
      waits for a busy emulator and never kills one it did not start)
- [~] **M** Work through *Manual device checks* on the emulator (2026-11-13:
      shortcuts, widget, open-with and share, Material You, reader and large
      text done on the phone, with two bugs found; the tablet's reader and
      multi-file share not done: see `BACKLOG.md`) (background
      sync on Android 14 is done: forced job, and update in place from
      `workmanager` 0.9 to 0.10, both ran): background
      sync forced with `adb shell cmd jobscheduler run -f`, the home-screen
      widget, shortcuts, share and open-with import, Material You colours,
      the reader (open, zoom, highlight sharpness, search), large text.
      What only a real device can show (camera scanning, ML Kit translation
      on a real GPU, battery and Wi-Fi constraints) stays with the owner

## 1.3 — statistics

### v1.3.0 — your reading state follows you

- [x] **L** Your rating syncs between devices, per person, on the same
      `book_status` row the status already used (it has its own clock, so a
      stale device can neither clear a rating nor un-finish a book). Opening a
      book on a device that missed a "finished" no longer overwrites it

### v1.3.1 — goals and per-book numbers

- [x] **M** Reading goals: books a year and minutes a day, with progress on the
      Insights page
- [x] **M** Per-book statistics on the book's page: time spent, sittings, pace,
      estimated time left

### v1.3.2 — month by month

- [x] **M** A review page per month (books finished, pages, minutes, best day,
      longest sitting, compared with the month before), and a list to step back
      through earlier months
- [x] **M** Insights you can explore: a range picker (30 days / year / all
      time) and heat-map days you can tap

### v1.3.4 — newer libraries

- [x] **L** `pdfrx` 2.12: measured against 2.4.7 for sharpness, open time,
      highlights after reopening, memory, search and selection, on Linux
      and the emulator
- [x] **M** `workmanager` 0.10 and `dynamic_color` 1.9

### v1.3.5 — the year, and the library

- [ ] **M** Year in review, with a picture you can save and share
- [ ] **M** Library statistics: the collection by genre, year, format and
      author; the unread pile; books added per month

---

## 1.4 — reader and interface

### v1.4.0 — pages you can turn

- [ ] **L** Paged EPUB mode, rather than a chapter you scroll

### v1.4.0a — keep up with Flutter

- [ ] **M** Move to Flutter 3.50: `package:flutter/material.dart` is deprecated
      there in favour of `package:material_ui`. CI and releases are pinned to
      3.47.9 until this is done on purpose

### v1.4.1 — finding your way around

- [ ] **M** Preferences split into sections, with a search box
- [ ] **M** Shelf grouping headers: by author, series or genre

### v1.4.2 — loans that remind you

- [ ] **M** System notifications for loan due dates (the decision logic exists;
      this is scheduling and permissions)

### v1.4.3 — read aloud

- [ ] **M** Text to speech in both readers

---

## 1.5 — audiobooks

A new kind of book, so it starts with a design note rather than code.

### v1.5.0 — an audiobook is a book

- [x] **L** Design note ([AUDIOBOOKS.md](AUDIOBOOKS.md)): which formats (`.m4b`, a folder of `.mp3`), which
      player library on five platforms and whether the F-Droid flavour can ship
      it, how position is stored (seconds, not pages) and how it reaches the
      existing per-device reading-position channel
- [ ] **L** Import and model: an audiobook is a `book_file` with a duration and
      chapters; a book can have text and audio both
- [ ] **L** A basic player: play, pause, skip, chapters, position remembered

### v1.5.1 — a player you can live with

- [ ] **L** Background playback and lock-screen controls
- [ ] **M** Playback speed and a sleep timer

### v1.5.2 — on the shelf

- [ ] **M** An *Audiobooks* section on the shelf, and *Continue listening* next
      to *Continue reading*

### v1.5.3 — in the numbers

- [ ] **M** Listening time in Insights, kept apart from reading time

---

## 1.6 — the server

### v1.6.0 — a console you can find things in

- [x] **L** `console.js` (3,100 lines in one file) split into one module per
      page, no build step, same embedded delivery
- [x] **M** Navigation in four groups — Library, Lending, People and sharing,
      Server — each page with its own address, usable on a phone
- [x] **M** A landing page: counts, loans due, requests waiting, recent
      activity

### v1.6.1 — looking after it

- [x] **M** A *Server* page: version, whether a newer release exists, the
      configuration in effect (read-only), capabilities, storage, and the
      backup, sweep and activity-log actions that exist today as endpoints
- [x] **M** Scheduled server-side backups to a directory, with rotation
      (`VELLUM_BACKUP_DIR`, `VELLUM_BACKUP_INTERVAL`, `VELLUM_BACKUP_KEEP`)

### v1.6.2 — safer access

- [ ] **L** App passwords: per-device tokens for OPDS and e-readers, so the
      account password is never typed into a Kindle
- [ ] **M** Short-lived per-resource links for covers and downloads, replacing
      the session token in a `?token=` query string
- [ ] **L** Two-factor sign-in (TOTP) for the console

### v1.6.3 — e-readers

- [ ] **L** KOReader progress sync: the server speaks KOReader's sync protocol,
      feeding the per-device reading-position channel

---

## Not planned

- Field-level merge for books (rejected; see `DESIGN.md`).
- OCR for scanned PDFs.
