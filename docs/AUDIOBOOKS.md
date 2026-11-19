# Audiobooks — design note (v1.5.0)

An audiobook is a book. It sits on the same shelf, has the same metadata,
status and rating, and can be lent as a physical copy if one exists. A book can
hold text and audio at the same time. This note makes one recommendation per
question. It was written on 2026-11-13; the versions quoted are the latest on
pub.dev on that date.

## Recommendations in brief

| Question | Answer |
|---|---|
| Formats | `.m4b`/`.m4a` and a folder of `.mp3`. No `.opus`/`.ogg` in 1.5. |
| Player | `just_audio` everywhere, through `just_audio_media_kit` (libmpv) on Linux and Windows. `audio_service` for background playback and the lock screen. |
| F-Droid | Fine in **both** flavours. On Android the stack is ExoPlayer/Media3 (Apache-2.0) and AndroidX media, with no prebuilt native libraries. |
| Model | Every audio file is a `book_file` row with a duration, an order and a label. Chapters live in an app-local table derived from the files. |
| Position | Seconds from the start of the whole audiobook, sent in two **new** columns on `reading_progress`. `page`/`unit` are left alone. |
| Listening time | A sitting gets a `kind` (`read`/`listen`) and positions in seconds. Old clients are never sent listening sittings. |
| File sync | Audio uploads like any book file. Other devices download it **only when asked** (resumable). |

## 1. Formats and import

**`.m4b` (and `.m4a`)** is the best case: one file, with chapters, cover and
tags inside it. The MP4 container has everything we need:

- duration comes from `moov/mvhd`
- the cover is `covr`, and the tags are `©nam` (title), `©ART` (author) and
  `©wrt` (by convention the narrator) in `moov/udta/meta/ilst`
- chapters come in two forms. Nero `chpl` in `moov/udta` is a flat list of
  start time and title. A QuickTime chapter track is a text track that
  `tref/chap` points to, read from its `stts`/`stsz`/`stco` tables. Read `chpl`
  first and fall back to the chapter track; tools write either or both.

The atom walk uses a `RandomAccessFile` and seeks past `mdat`. It never reads
the file into memory: `moov` is often at the end of a 900 MB file.

**A folder of `.mp3`** becomes one audiobook, and each file is one chapter.
Parts play in this order:

1. ID3 `TPOS` (disc), then `TRCK` (track), but only when those numbers are
   unique across the folder. Rips that number every file "1" are common.
2. Otherwise a natural sort of the file names, so "2" comes before "10".
   Subfolders such as `CD1/`, `CD2/` are taken in natural order.

The book title comes from `TALB` (album) and the author from `TPE2`/`TPE1`. A
chapter's label is `TIT2`, or the file name when that is missing. Duration comes
from the Xing/VBRI header. If there is none, the player is asked for it, which
is slow but exact.

**Detection.**

- A single `.m4b`, `.m4a` or `.mp3` that is dropped, picked or shared becomes a
  one-part audiobook.
- Several audio files picked together, or a folder whose only books are audio
  files, prompt "One audiobook from these 24 files?". The answer defaults to yes.
- Folder import (`supportedFormats` in `folder_import_service.dart`) treats each
  leaf directory of audio files as one book, and skips single files under 10
  minutes, because a library folder can contain music.
- Magic bytes are checked at both ends, the same way PDF and EPUB are:
  - `ftyp` at offset 4 means MP4
  - `ID3` or an MPEG frame sync means MP3

**Cover**, in order of preference: the m4b `covr`; the first part's `APIC`
(front cover type 3 first); `cover.jpg`/`folder.jpg`/`front.jpg` in the folder;
the only image in the folder. If there is none, the book gets a generated spine.
The bytes then go through the existing cover pipeline (thumbnails, dominant
colour, push to the server).

**Parsing.** Use `audio_metadata_reader` 1.8.1 (MIT, pure Dart) for the ID3
tags and pictures. Write our own small MP4 reader for duration and chapters:
the package's MP4 chapter support is thin, and it does not list `.m4b` as an
extension.

*As built* (`app/lib/audio/`), two things moved to our own code:

- **The MP4 tags and `covr`** come from `mp4_reader.dart` too. It walks
  `moov` anyway, and the package does not read `©wrt`, the narrator.
- **MP3 durations** come from `mp3_duration.dart`, which reads the first
  frame's Xing/Info or VBRI header and otherwise estimates from the bitrate.
  The package's own figure was 36 % short on a 22.05 kHz mono MPEG-2 file,
  which is a common audiobook encoding, and part durations are summed and
  synced, so they have to be right.

**Not in 1.5:**

- **`.opus`/`.ogg`**: `just_audio` on macOS is AVPlayer, which does not play
  Ogg. Adding it means routing macOS through media_kit as well. That is a small
  follow-up once the rest works.
- **Audible `.aax`**: it is DRM, so never.
- **Streaming from the server** (see §6).

## 2. Player library

**Pick: `just_audio` 0.10.6 + `just_audio_media_kit` 2.1.0 (Linux and Windows
only) + `audio_service` 0.18.19 (+ `audio_service_mpris` 0.2.1 on Linux).**

| Platform | Playback | Background / lock screen |
|---|---|---|
| Android | `just_audio` → ExoPlayer (Media3) | `audio_service`: MediaSession, notification, lock screen, Bluetooth buttons |
| macOS | `just_audio` → AVPlayer | `audio_service`: Now Playing, media keys |
| Linux | `just_audio_media_kit` → `media_kit` 1.2.6 → system libmpv | `audio_service_mpris` (MPRIS: desktop widgets, media keys) |
| Windows | `just_audio_media_kit` → libmpv DLL from `media_kit_libs_windows_audio` | none in 1.5 (SMTC is a later nicety) |
| iOS | not a Vellum target (there is no `app/ios`). `just_audio` and `audio_service` both support it if that changes. | |

Reasons:

- `just_audio` is the de facto audiobook player API. It gives position and
  duration streams, a list of sources for multi-part books, speed control, and
  on Android exact MP3 seeking through index seeking. `audio_service` is built
  by the same author to drive it.
- **F-Droid**: on Android this stack is `androidx.media3` and `androidx.media`,
  both Apache-2.0, open source, and accepted by F-Droid (AntennaPod and NewPipe
  ship ExoPlayer). It needs no Play Services and no downloaded `.so`, so it
  goes in both flavours without a `flavour.sh` change. The licences are
  `just_audio` MIT/Apache-2.0, `audio_service`/`audio_session`/`media_kit`
  MIT, and `just_audio_media_kit` Unlicense. libmpv is LGPL when linked
  dynamically, which is compatible with AGPL-3.0. Vellum still cannot go on
  f-droid.org, but that is because of PDFium and has nothing to do with audio.
- **Rejected: `media_kit` on every platform.** On Android it means
  `media_kit_libs_android_audio`, which is a *prebuilt* libmpv/FFmpeg. That is
  the same class of problem as PDFium, and it adds several MB per ABI. We only
  register `just_audio_media_kit` for Linux and Windows (its default), so no
  libmpv reaches the APK.
- **Rejected: `audioplayers`** (6.8.1). It is built for sound effects. It has
  no `audio_service` integration story, multi-part playback is weaker, and on
  Linux it uses GStreamer through a separate code path.

Costs:

- Linux now needs libmpv at run time: `libmpv2` (or `libmpv1`) in the `.deb`
  `Depends`. The spike showed `libmpv-dev` is not needed to build (§7a). The
  AppImage either bundles libmpv and its FFmpeg (tens of MB) or requires it on
  the host.
- On Android, `MainActivity` has to extend `AudioServiceActivity` instead of
  `FlutterActivity`, and the manifest needs a `mediaPlayback` foreground
  service next to the existing `dataSync` one.
- `just_audio_media_kit`'s last release was April 2025. It is a thin adapter,
  so if it breaks, we vendor it.

## 3. Data model

### App (drift, `app/lib/data/database.dart`)

`BookFiles` gets these columns, all **synced**:

```dart
IntColumn  get durationMs => integer().nullable()();  // null for text formats
IntColumn  get track      => integer().nullable()();  // 1-based part order within the book's audio
TextColumn get label      => text().nullable()();     // part title ("Chapter 3", "Disc 1 – 04")
TextColumn get narrator   => text().nullable()();
```

It also gets one **app-local** column:

```dart
BoolColumn get present => boolean().withDefault(const Constant(true))();
```

`present` is false when this device knows the file but does not hold its bytes
(§6). Library doctor, backups and the push loop must not treat such a row as a
missing file.

Chapters go in a new table, `AudioChapters`. It is **app-local and derived**,
like `BookTexts`, so it can be dropped and rebuilt from the files and needs no
`updatedAt`/`needsPush`:

```dart
class AudioChapters extends Table {
  TextColumn get fileId  => text().references(BookFiles, #id)();
  IntColumn  get idx     => integer()();
  TextColumn get title   => text().nullable()();
  IntColumn  get startMs => integer()();   // within this file
  @override Set<Column> get primaryKey => {fileId, idx};
}
```

An mp3 part gets a single row at `startMs = 0` titled from `label`, so the
player reads chapters from one place.

`Books` gets two **app-local** columns next to `readingProgress`/`lastReadAt`,
and like them they are never on the server's `book` row:

```dart
RealColumn     get listenPosition => real().nullable()();     // seconds from the start of the audiobook
DateTimeColumn get lastListenedAt => dateTime().nullable()();
```

`RemoteReadingPositions` gets `audioPosition` and `audioDuration`, both REAL
and nullable.

This is `schemaVersion` 39 → 40.

**Rules.**

- A book's audiobook is its audio `book_file`s ordered by `track`.
- One audio edition per book in 1.5. Importing audio onto a book that already
  has audio asks whether to replace it.
- `readingProgress`/`lastReadPage` keep meaning *text* and are never written by
  the player. A book with both text and audio therefore has two independent
  places.
- Every consumer of `bookFiles` that assumes text must skip audio formats:
  `read_button.dart`, `readingUnitForFormats`, the local text index, dedupe,
  send-to-device and the Insights format list.

### Server (migration 0043; 0039–0042 went to other work)

```sql
ALTER TABLE book_file ADD COLUMN duration_ms INTEGER;
ALTER TABLE book_file ADD COLUMN track       INTEGER;
ALTER TABLE book_file ADD COLUMN label       TEXT;
ALTER TABLE book_file ADD COLUMN narrator    TEXT;

ALTER TABLE reading_progress ADD COLUMN audio_position REAL;  -- seconds
ALTER TABLE reading_progress ADD COLUMN audio_duration REAL;  -- seconds, the whole audiobook
```

All of these are nullable with no default, so `migrations_with_data.rs` is
satisfied. `schema_parity.rs` pins `book_file` and must be updated with this
migration.

**Server code changes:**

- `upload_file` accepts the extensions `m4b`, `m4a` and `mp3`, and its sniff
  learns MP4 and MP3.
- The upload takes `duration_ms`, `track`, `label` and `narrator` as query
  parameters. The server does not parse audio. The original file name is lost
  once the file is content-addressed, so `track` and `label` **must** travel
  with the upload.
- `FileDto` and the books-list enrichment return the four fields.
- `text_index::enqueue`, the browser reader, Send to device and cover rendering
  skip audio.
- OPDS lists audio with `audio/mp4` or `audio/mpeg`.
- A new capability, `audiobooks`, is added.

Syncing `duration_ms` is the right choice, not just a convenient one. A
position in seconds across a multi-part book is a sum of part durations, so
every device has to sum the *same* numbers.

## 4. Position and "continue listening"

**Locally**, the player writes `books.listenPosition` (seconds from the start of
part 1) and `lastListenedAt`. It writes when it pauses, seeks or skips a
chapter, and every 15 s while playing. It sets the existing
`needsProgressPush`. The part and the offset within it come from the cumulative
`durationMs`.

**On the wire**, the audio position travels in the two new `reading_progress`
columns. Nothing about `progress`/`page`/`unit` changes, and `unit` stays
`page|chapter`. A new unit value such as `second` was rejected for two reasons:

1. A device that both reads and listens owns one row per book. If audio used
   `page`/`unit`, every switch between reading and listening would overwrite the
   other position. Separate columns keep both.
2. Today's servers answer **400** to an unknown `unit`. Unknown JSON fields, by
   contrast, are silently ignored (`ProgressInput` does not use
   `deny_unknown_fields`).

How each combination of old and new behaves:

| Client → server | Behaviour |
|---|---|
| New app → old server | The audio fields are dropped. The app checks the `audiobooks` capability, and without it does not show audio offers. |
| Old app → new server | It never sends audio fields. The upsert uses `COALESCE(excluded.audio_position, reading_progress.audio_position)`, so a text-only push from a device keeps that device's audio position. |
| New server → old app | The extra fields are ignored. Its offers compare `progress`/`page` only, and those are unchanged. |

**The offer** reuses `ReadingPositionService.offerFor`'s rules with a
same-edition guard in place of the same-unit guard. A position is only offered
when:

- the remote `audio_duration` is within 2 s of ours, so it is the same edition
  (seconds from a different narration would point somewhere plausible and
  wrong)
- it is at least 30 s ahead

The prompt reads "You were at 5:12:33 on Pixel 8 — go there?". It is offered,
never adopted, as everywhere else.

**Continue listening** is a local query that watches books where all of these
hold:

- `lastListenedAt IS NOT NULL`
- `listenPosition < total − 30 s`
- `status != 'finished'`

It is ordered by `lastListenedAt` and shown next to *Continue reading*.

Status rules carry over from reading:

- The first play makes an unread book `reading`. This is the one automatic
  transition.
- Reaching the end *offers* "Mark as finished".
- `finishedAt` does not depend on the medium, so a book is finished once
  whether it was read or heard.

## 5. Listening time in Insights

A listening sitting is a `reading_session` row with `kind = 'listen'`.

**App** (schema +1, in v1.5.3): `ReadingSessions` gains these columns, and
`startPage`/`endPage` stay null for listening:

```dart
TextColumn get kind        => text().withDefault(const Constant('read'))();
IntColumn  get startSecond => integer().nullable()();
IntColumn  get endSecond   => integer().nullable()();
```

**Server** (the next free migration at that time):

```sql
ALTER TABLE reading_session ADD COLUMN kind TEXT NOT NULL DEFAULT 'read';  -- a constant default
ALTER TABLE reading_session ADD COLUMN start_second INTEGER;
ALTER TABLE reading_session ADD COLUMN end_second   INTEGER;
```

**Recording.**

- The `SessionRecorder` is owned by the player (`AudiobookPlayer`, itself owned
  by `PlaybackHost`), not by a page, because playback outlives the page.
- A sitting begins on play, is touched whenever the player saves its position
  (every 15 s while playing, and on seeks), and ends on pause, a system pause,
  the sleep timer, the end of the book and dispose. Writes are queued so a
  pause right behind a play closes the sitting the play opened.
- A listening sitting under five seconds is dropped (position moves by itself
  while playing, so only length says whether it was one).
- Two-minute coalescing still applies, but `begin()` must match on `kind` as
  well as `bookId`, so that reading straight after listening starts a new
  sitting.
- *Not built:* closing, at startup, a sitting left open by a killed app. An
  open sitting is `needsPush = false` like a pulled one, so there is no marker
  to find it by; it keeps its last touch (at most 15 s old) locally but is not
  pushed. Reading sittings have the same gap. Closing it needs an `open` flag.
- The time counted is **wall-clock time**: 1 h at 1.5× is 1 h listened. The
  seconds of audio covered (`endSecond − startSecond`) are kept beside it for
  pace.

**Compatibility.** This is what keeps listening from turning into reading time
on other devices:

- An old client would count a listening sitting as reading time with no pages.
  So `list_sessions` returns `kind = 'listen'` rows only to clients that ask
  with `?kinds=read,listen`.
- An old server would store a listening sitting as reading (serde drops
  `kind`). So the app pushes listening sittings only after the server
  advertises the `listening_sessions` capability, and keeps them dirty until
  then, as `book_status` does. The app sends `?kinds=read,listen` on every
  pull; an old server ignores it and sends reading sittings only.
- A server with 0044 refuses a `kind` other than `read` or `listen`, and a
  sitting pushed with no `kind` (an old app) is a reading sitting.

**Insights.**

- Every existing query in `stats_queries.dart`, `month_review.dart` and
  `book_reading_stats.dart` gains `kind = 'read'`. Every existing number keeps
  its meaning, and the "minutes read" goal stays a reading goal.
- A *Reading / Listening* switch sits at the top of the page, defaulting to
  *Reading*. *Listening* shows the same time-based views: streaks, heat map,
  time per day, when and where you listen. The page-based views, the goals and
  the best-day card are hidden. The switch is shown once there is any listening
  sitting, and a history with listening but no reading opens on *Listening*.
- *Books finished* stays in *Reading* as it was. *Listening* shows *Finished
  by listening*: the finished books in the range that have a listening
  sitting. (This revises the first draft, which left finishes out of both
  views: a listener asked how many books they finished by ear, and the
  listening sitting is the honest way to say it.)
- The month and year pages count listening on its own line (time and days) and
  never add it to pages, reading time, reading days or streaks.
- The book page gains *Your listening* next to *Your reading*.

## 6. Syncing the audio files

Audiobooks are big compared with text:

| | Size |
|---|---|
| An EPUB | 1–5 MB |
| An m4b at 64 kb/s | about 29 MB an hour, so a 15-hour book is about 430 MB |
| An mp3 folder at 128 kb/s | about twice that |

A library of 50 audiobooks is 20–40 GB.

**Upload: yes, by default**, through the existing blob path:

- streaming `upload_file`, content-addressed, deduped by hash
- *keep on this device* still excludes a book
- an audiobook over 2 GB needs a larger `VELLUM_MAX_UPLOAD_MB`, and the app
  should say so when the server refuses one
- the server is the library, and it is also the backup of a 40-hour rip that
  someone made once

**Download: on demand.**

- A pull inserts audio `book_file` rows with `present = false` and does not
  fetch the bytes. The book shows its duration, and offers "Download (430 MB)"
  and, once downloaded, "Remove download".
- The transfer reuses `downloadFileTo` with the `.part` file, and gains
  **resume through `Range`**. The server already serves ranges, and losing
  400 MB to a dropped connection is not acceptable.
- On Android it defaults to Wi-Fi only.
- An opt-in preference, *Download audiobooks automatically*, restores today's
  behaviour per device.

**Old clients:** the books-list enrichment leaves out audio files for clients
that don't send `audio=1`. Otherwise a pre-1.5 app would download every
audiobook to a phone it cannot play them on.

**Backups:** scheduled backups exclude `files/` audio by default (a toggle
includes it). A manual backup asks. The manifest records what was left out, so
*Verify* does not report the missing files as damage.

**Streaming instead of download** is deferred. It needs the auth header on
every backend, and v1.6.2 is about to replace `?token=` URLs.

## 7. Risks, and what to prototype first

**Spike first.** It goes on a throw-away branch, before any schema work. It is a
single screen that plays an m4b and a 30-part mp3 folder on Android, Linux,
Windows and macOS. It should:

- seek to 5:12:33 and back
- report the duration
- list the chapters from our MP4 reader, tested on ten real-world m4bs (tools
  disagree on `chpl` versus chapter tracks)

It also builds the `.deb` and the AppImage, and runs them on a clean Ubuntu 22.04
and 24.04.

Risks, roughly in order:

1. **libmpv on Linux.** The library name differs between distributions
   (`libmpv1` versus `libmpv2`). The AppImage must decide whether to bundle it.
   If the spike fails here, the fallback is to *require* the host's mpv and
   document it, not to change libraries.
2. **`just_audio_media_kit` is unmaintained**, with no release since April
   2025. Mitigation: vendor it, since it is small.
3. **Stats leakage.** If one query misses the `kind = 'read'` filter, listening
   counts as reading. Mitigation: a test that seeds a listening sitting and
   asserts that every reading total is unchanged.
4. **MP3 duration and seeking** in VBR files without a Xing header. Mitigation:
   index seeking on Android, the player's duration at import, and the summed
   durations stored once and synced.
5. **The Android service change.** Moving `MainActivity` to
   `AudioServiceActivity` touches the incoming-share channel and the launcher
   shortcuts. The `mediaPlayback` foreground-service type is required on
   Android 14 and later.
6. **Disk and backup size**, handled by on-demand download and backups that
   exclude audio by default.

## 7a. What the spike found (2026-11-15)

Run on the development machine (Ubuntu 24.04-based, x86-64) with
`just_audio` 0.10.6, `just_audio_media_kit` 2.1.0, `media_kit` 1.2.6,
`media_kit_libs_linux` 1.2.1 and `media_kit_libs_windows_audio` 1.0.9. The
fixtures were made with ffmpeg: a 5 h 30 min AAC `.m4b` with six chapters
(20 MB at 8 kb/s) and a folder of 30 ten-second CBR mp3s with ID3v2.3 tags.

**The stack is viable on Linux.** Measured:

| | Result |
|---|---|
| m4b load | duration 5:30:00.128 reported in 0.7–0.9 s |
| m4b seek to 5:12:33 and back to 0:10 | lands within 1 s of the target both ways |
| mp3 playlist of 30 sources | loads in 0.1–0.2 s, plays, advances to the next part on its own |
| `seek(position, index: n)` into another part | **broken**: jumps to part *n* but the position is dropped (mpv logs `error running command seek`) |
| `setFilePath(part, initialPosition: x)` | exact, every time; `completed` fires at the end of the part |

- **libmpv**: only the runtime `libmpv2` (0.37) is installed here, and that is
  enough. `media_kit` opens `libmpv.so`, then `libmpv.so.2`, then
  `libmpv.so.1`, so the `.so.1`/`.so.2` split in §7 risk 1 is already handled
  and `libmpv-dev` is **not** needed to build. The `.deb` needs
  `libmpv2 | libmpv1` in `Depends`, not a `-dev` package.
- **`media_kit_libs_linux` downloads mimalloc** from GitHub during the CMake
  step (on by default, `MIMALLOC_USE_STATIC_LIBS`). A Linux build therefore
  needs the network once, like the Windows build that downloads its libmpv DLL.
  Flatpak or any offline build will want `-DMIMALLOC_USE_STATIC_LIBS=OFF`.
- **The cross-part seek bug** is in `just_audio_media_kit`'s `seek`: after
  `jump()` it checks the *previous* part's duration, sees it is non-zero, and
  seeks a file that is still loading. A two-phase seek (index, wait, position)
  works but needs a wait that has nothing reliable to wait on when parts have
  equal durations. **So the player loads one part at a time** with
  `setFilePath(initialPosition:)` and moves to the next part itself on
  `completed`. That is one code path on every backend, and positions in seconds
  across the whole book map to (part, offset) in one place. The cost is a gap
  of a few hundred milliseconds between mp3 parts, which is acceptable for
  speech. This supersedes "a list of sources for multi-part books" in §2.
- **Initialisation is lazy.** `JustAudioMediaKit.ensureInitialized()` is
  called the first time a player is made, not in `main()`, so a Linux machine
  without libmpv still starts and only the player page says what is missing.
  The plugin has no `pubspec` plugin entry, so nothing registers it behind our
  back.
- **Android**: `flutter build apk --debug` succeeds with the plugins, in the
  full flavour *and* the free one. The APK gains no new `.so`: the Android side
  is `androidx.media3:media3-exoplayer` 1.4.1 (plus its dash/hls/smoothstreaming
  modules, which `just_audio` lists unconditionally). Nothing in `flavour.sh`
  needs to change. Playback on Android was **not** run (the emulator was in use
  by other work), nor on Windows or macOS.
- **Licences** checked in the pub cache: `just_audio` MIT,
  `just_audio_media_kit` Unlicense, `media_kit`/`media_kit_libs_*` MIT,
  `audio_metadata_reader` MIT.
- **The m4b fixture has both chapter forms**: ffmpeg writes Nero `chpl` *and* a
  QuickTime chapter track (`tref/chap` → a text track), with `moov` after
  `mdat`. The reader's tests build files with only one of the two, so both
  paths are exercised.
- Not done in the spike: ten real-world m4bs, the `.deb`/AppImage on clean
  Ubuntu 22.04/24.04, and `audio_service`, which is v1.5.1.

## 8. Task breakdown

**v1.5.0 — an audiobook is a book**

- [x] **L** This note
- [x] **M** Spike (§7, findings in §7a): Linux playback, the Android build, the MP4 chapter reader. *Open:* playback on Android, Windows and macOS; ten real-world m4bs; the `.deb`/AppImage on clean Ubuntu 22.04/24.04
- [x] **M** Schema: app v40 and the server migration (0043: `book_file` and `reading_progress` columns), the `audiobooks` capability, `schema_parity.rs`
- [x] **L** Import: detection, ordering, tags, duration, chapters, cover, magic bytes at both ends. *Open:* the "One audiobook from these 24 files?" prompt — several audio files are grouped per folder without asking
- [x] **M** Server: accept audio uploads plus the file fields, hide audio from old clients (`?audio=1`), skip it in the text index, KOReader digests, send and cover rendering, OPDS mime types
- [ ] **L** Sync: upload audio, `present` flag, on-demand resumable download; audit every `bookFiles` consumer (doctor, backups, dedupe, read button, local text index). *Done so far:* audio uploads with its fields (only to a server with `audiobooks`), pulled parts keep them and get their chapters re-read, the doctor skips `present = false`, the read button, text index and send sheet skip audio. *Open:* the pull still downloads audio straight away — nothing sets `present = false` yet — and there is no Range resume, Wi-Fi-only default or backup exclusion
- [x] **L** Basic player page: play and pause, ±30 s, chapter list and skip, position saved locally and on `reading_progress`, the "go there?" offer. *Open:* the "Mark as finished" offer is a snack bar at the end; there is no *Continue listening* yet (v1.5.2). *Unverified:* the page itself has only run against a fake engine in tests; the real engine's calls (`setFilePath(initialPosition:)`, `completed`) are the ones the spike exercised on Linux

**Hooks left for later.** `AudiobookPlayer` (`app/lib/audio/audiobook_player.dart`)
holds no widget, so v1.5.1's `audio_service` handler can own it instead of the
page; speed goes on `AudioEngine`, next to `play`/`pause`; the v1.5.3 session
recorder hangs off the player's play/pause/ended transitions.

**v1.5.1 — a player you can live with**

- [x] **L** `audio_service`: background playback, notification and lock screen on Android, Now Playing on macOS, MPRIS on Linux; a mini-player while browsing. *Unverified:* everything past the handler, which is tested; see §9 and `docs/BACKLOG.md`
- [x] **M** Speed (0.5–3×, per book, app-local) and a sleep timer (minutes, or the end of the chapter, with a fade)

**v1.5.2 — on the shelf**

- [x] **M** An *Audiobooks* facet or section, a headphones badge, spine thickness from duration when there is no page count (about 30 pages an hour), *Continue listening* in the app and the home widget. See §10

**v1.5.3 — in the numbers**

- [ ] **M** Listening sittings: recorder in the player service, app and server schema, `?kinds=` and the `listening_sessions` capability
- [ ] **M** Insights: the Reading/Listening switch, `kind = 'read'` on every existing query, *Your listening* on the book page

## 9. v1.5.1 as built

**Plugin: `audio_service`, not `just_audio_background`.** `just_audio_background`
takes over the `AudioPlayer` and describes a *playlist* of `MediaItem`s, so the
notification and lock screen would show one part at a time, with a seek bar
over that part only, and the notification's skip buttons would move between
parts. Vellum plays one file at a time (§7a) and keeps its own timeline over
the parts. `audio_service` lets a handler (`VellumAudioHandler`,
`lib/audio/audio_handler.dart`) wrap the existing `AudiobookPlayer`: the session
sees the whole book (one `MediaItem`, the book's duration, the chapter as its
title) and each button calls the same method as the page's. Both are
free software and the Android side is `androidx.media` only, so **both flavours
carry it** and `flavour.sh` is untouched.

**Who owns the player.** `PlaybackHost` (`playback_host.dart`) owns the
`AudiobookPlayer`, not the page. The page, the mini bar and the media session
are views of it. Opening the same book returns the running player; another book
saves and replaces it. The mini bar (`now_playing_bar.dart`) is the shell's
`bottomNavigationBar` (above the navigation bar on a phone, alone beside the
rail or drawer on wider windows), so the floating buttons ride above it and it
never covers the shelf. It closes with the book.

**Platforms.**

| | Session |
|---|---|
| Android | `audio_service`: notification, lock screen, headset and Bluetooth buttons. Foreground service of type `mediaPlayback` (`FOREGROUND_SERVICE_MEDIA_PLAYBACK` for API 34+). `MainActivity` now extends `AudioServiceActivity`. |
| macOS | `audio_service`: Now Playing, media keys. |
| Linux | MPRIS through `audio_service_mpris` (pure Dart over D-Bus; MPL-2.0 `dbus`, Linux only). If there is no session bus the session simply does not start. |
| Windows | `audio_service` has no Windows support: no system controls. Playback continues while the app is open. |

Leaving the player page does not stop playback anywhere.

**Audio focus.** `just_audio` already follows the `audio_session` focus events;
the engine only chooses the speech profile (`configureAudioSession`). A call or
another app's playback pauses, a short interruption resumes afterwards, a
navigation prompt ducks, and unplugging the headphones pauses ("becoming
noisy"). The controller follows the engine's `playingStream`, so the page and
the notification show what is true, and an outside pause saves the position.
The sleep timer's fade and a duck both use the volume; they do not combine, and
the fade wins in its last ten seconds.

**Speed.** 0.5 to 3.0 in 0.05 steps, with presets. It is remembered **per
book, per device, in the preferences** (`listen.speed.<bookId>`), so there is
no schema change and nothing syncs. The pitch is kept: ExoPlayer, AVPlayer and
libmpv all time-stretch. Chosen over a global speed because narrators differ.

**Sleep timer.** 5/10/15/30/45/60 minutes or the end of the chapter. The
countdown runs only while playing. The volume fades linearly over the last ten
seconds of *listening* time (at 2x the last ten book-seconds are only five
fade-seconds long, so it is computed in listening time). Skipping to another
chapter moves "end of chapter" to that chapter. When it stops, the position is
saved through the ordinary pause path, which queues it for the
reading-progress channel.

**Saving in the background.** Unchanged: the 15-second timer, pause, seek and
dispose. A process killed outright loses at most 15 seconds.

## 10. v1.5.2 as built

**The facet** is a *filter chip* at the start of the shelf's chip row, not a
section: it is one more predicate on the single `watchLibrary` query
(`audioOnly`), so it combines with shelves, genre, status, search, sort and
Group by without a second stream. The chip appears only when the library has
audio (or the filter is on, so it can always be turned off). A book with text
*and* audio is in it.

**One book, one place.** A book with text and audio appears once, not once per
medium. It carries the badge (it can be listened to) and has both Read and
Listen on its page. The two positions stay apart: *Continue reading* follows
`readingProgress`, *Continue listening* follows `listenPosition`, so one book
can be in both strips. Its list row keeps the file icon and adds the
headphones.

**The badge** is `AudioBadge`: a white headphones glyph on a dark ring (the
finished mark's trick), at the foot of the spine (the title leaves it 24 px),
bottom right of a face-out cover, and a plain icon in the list. Two glyphs, no
layers and no bitmaps; books without audio pay nothing. It is part of
`SpineFace`, so both materials (cover slice and generated) get it.

**Thickness** is decided at render time, not baked into the synced
`spineStyle`: with audio and no `pageCount`, the width is the page-count curve
at 30 pages per hour of total duration (`SpineStyle.effectiveWidth`), clamped
like page counts. A real page count wins. Rendering rather than rewriting the
style means a book whose audio is attached or measured later changes
immediately, on every device, with no sync. The physical room still uses the
page curve (it has no durations to hand) and is unchanged.

**Continue listening** uses §4's rule (`isListeningOnTheGo`), plus *abandoned*
leaves it, as it leaves the widget. It is a second row under *Continue reading*
with the same card and a headphones glyph; its subtitle is "42% · at 1:02:33".
Tapping opens the player, which resumes at the saved position. On a short
screen the compact row shows both kinds of card.

**The home widget** has one slot and keeps it: it shows whichever of reading or
listening happened last (`pickContinue`), with "42% · at 1:02:33" for audio.
One of each would need a second layout and a second widget provider; not worth
it for a launcher tile. No Android code changed.

