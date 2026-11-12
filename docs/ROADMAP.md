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

---

## 1.1 — fixes

### v1.1.12 — the reader works the first time

Fixes from `problems_09_nov.txt`. Nothing else ships in this one.

- [x] **M** A PDF opens on the first try (pdfrx document reference is created
      once; pdfrx is warmed up at app start)
- [x] **M** A highlight or note is still drawn after reopening the book (page
      text is not read before the page is loaded)
- [ ] **M** The page no longer goes blurry after *Note on selection* — cause
      not confirmed; two mitigations are in (the pages are isolated from outside
      repaints, a new note repaints less). Needs a check on a real desktop
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

- [ ] **M** Strings out of the widgets and into `app_en.arb`
- [ ] **S** A short `docs/TRANSLATING.md` for contributors

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

## 1.3 — statistics

### v1.3.0 — your reading state follows you

- [x] **L** Your rating syncs between devices, per person, on the same
      `book_status` row the status already used (it has its own clock, so a
      stale device can neither clear a rating nor un-finish a book). Opening a
      book on a device that missed a "finished" no longer overwrites it

### v1.3.1 — goals and per-book numbers

- [ ] **M** Reading goals: books a year and minutes a day, with progress on the
      Insights page
- [ ] **M** Per-book statistics on the book's page: time spent, sittings, pace,
      estimated time left

### v1.3.2 — month by month

- [ ] **M** A review page per month (books finished, pages, minutes, best day,
      longest sitting, compared with the month before), and a list to step back
      through earlier months
- [ ] **M** Insights you can explore: a range picker (30 days / year / all
      time) and heat-map days you can tap

### v1.3.3 — the year, and the library

- [ ] **M** Year in review, with a picture you can save and share
- [ ] **M** Library statistics: the collection by genre, year, format and
      author; the unread pile; books added per month

---

## 1.4 — reader and interface

### v1.4.0 — pages you can turn

- [ ] **L** Paged EPUB mode, rather than a chapter you scroll

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

- [ ] **L** Design note: which formats (`.m4b`, a folder of `.mp3`), which
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
- [ ] **M** A landing page: counts, loans due, requests waiting, recent
      activity

### v1.6.1 — looking after it

- [ ] **M** A *Server* page: version, whether a newer release exists, the
      configuration in effect (read-only), capabilities, storage, and the
      backup, sweep and activity-log actions that exist today as endpoints
- [ ] **M** Scheduled server-side backups to a directory, with rotation

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
