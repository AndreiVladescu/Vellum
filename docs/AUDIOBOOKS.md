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
and `ilst` tags and the pictures. Write our own small MP4 reader for duration
and chapters: the package's MP4 chapter support is thin, and it does not list
`.m4b` as an extension.

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

- Linux now needs libmpv: `libmpv-dev` in `linux-flutter-deps`, and
  `libmpv2` in the `.deb` `Depends`. The AppImage either bundles libmpv and
  its FFmpeg (tens of MB) or requires it on the host.
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

### Server (next free migration at implementation time — 0039 today)

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

- The `SessionRecorder` is owned by the player service, not by a page, because
  playback outlives the page.
- A sitting begins on play, is touched every 30 s, and ends on pause, stop or
  the end of the book.
- Two-minute coalescing still applies, but `begin()` must match on `kind` as
  well as `bookId`, so that reading straight after listening starts a new
  sitting.
- At startup, sittings left open by a killed app are closed at their last
  touch.
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
  then, as `book_status` does.

**Insights.**

- Every existing query in `stats_queries.dart`, `month_review.dart` and
  `book_reading_stats.dart` gains `kind = 'read'`. Every existing number keeps
  its meaning, and the "minutes read" goal stays a reading goal.
- A *Reading / Listening* switch sits at the top of the page, defaulting to
  *Reading*. *Listening* shows the same time-based views: streaks, heat map,
  time per day, when and where you listen, and best day. The page-based views
  are hidden.
- *Books finished* belongs to neither view, since a finish is about the book.
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

## 8. Task breakdown

**v1.5.0 — an audiobook is a book**

- [x] **L** This note
- [ ] **M** Spike (§7): player on four platforms, MP4 chapter reader, Linux packaging
- [ ] **M** Schema: app v40 and the server migration (`book_file` and `reading_progress` columns), the `audiobooks` capability, `schema_parity.rs`
- [ ] **L** Import: detection, ordering, tags, duration, chapters, cover, magic bytes at both ends
- [ ] **M** Server: accept audio uploads plus the file fields, hide audio from old clients, skip it in text index, reader, send and cover rendering, OPDS mime types
- [ ] **L** Sync: upload audio, `present` flag, on-demand resumable download; audit every `bookFiles` consumer (doctor, backups, dedupe, read button, local text index)
- [ ] **L** Basic player page: play and pause, ±30 s, chapter list and skip, position saved locally and on `reading_progress`, the "go there?" offer

**v1.5.1 — a player you can live with**

- [ ] **L** `audio_service`: background playback, notification and lock screen on Android, Now Playing on macOS, MPRIS on Linux; a mini-player while browsing
- [ ] **M** Speed (0.5–3×, per book, app-local) and a sleep timer (minutes, or the end of the chapter, with a fade)

**v1.5.2 — on the shelf**

- [ ] **M** An *Audiobooks* facet or section, a headphones badge, spine thickness from duration when there is no page count (about 30 pages an hour), *Continue listening* in the app and the home widget

**v1.5.3 — in the numbers**

- [ ] **M** Listening sittings: recorder in the player service, app and server schema, `?kinds=` and the `listening_sessions` capability
- [ ] **M** Insights: the Reading/Listening switch, `kind = 'read'` on every existing query, *Your listening* on the book page
