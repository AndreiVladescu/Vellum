# Improvement plan

Implementation spec for the fixes identified in the July 2026 architecture/security
review. Tasks are ordered; each is one cohesive commit (see CLAUDE.md git rules:
short title, optional succinct bullets, **no Co-Authored-By**, one feature per
commit/push). Do the tasks in order — later ones build on earlier ones.

**Ground rules for the implementer**

- Read `CLAUDE.md` and `DESIGN.md` first. Key constraints repeated here:
  - App schema (drift, `app/lib/data/database.dart`) and server schema
    (`server/migrations/*.sql`) are maintained **manually in parallel**. Any
    schema change = bump drift `schemaVersion` + drift migration + **new** SQL
    migration file (never edit an applied one) + rerun
    `dart run build_runner build --delete-conflicting-outputs`.
  - Reading state, `readerNotes`, `sourceMetadata` are app-local-only: never add
    them to server schema or sync payloads.
  - DB reads feeding UI use drift `.watch()` streams.
- After every task: `cd server && cargo test && cargo clippy` and
  `cd app && flutter analyze && flutter test`. Fix warnings you introduced.
- When a task changes behavior documented in `DESIGN.md`, update DESIGN.md in the
  same commit.

---

## Task 1 — Server-side magic-byte validation of uploads

**Problem.** DESIGN.md claims uploads are validated by magic bytes, but only the
console JS and the app (`app/lib/data/book_file_validation.dart`) check
client-side. The API (`server/src/blobs.rs`) trusts `?filename=` extension and
`Content-Type` blindly. Malicious "PDFs" get fed to shell-out renderers
(`pdftoppm`/`mutool`/`gs`) and served to other users.

**Change** in `server/src/blobs.rs`:

1. Add a sniffer (mirror the app's logic in `book_file_validation.dart`):

```rust
#[derive(PartialEq, Clone, Copy)]
pub(crate) enum Sniffed { Pdf, Zip, Jpeg, Png, Gif, WebP, Unknown }

fn sniff(head: &[u8]) -> Sniffed {
    if head.starts_with(b"%PDF") { return Sniffed::Pdf; }
    if head.starts_with(&[0x50, 0x4B, 0x03, 0x04]) { return Sniffed::Zip; }
    if head.starts_with(&[0xFF, 0xD8, 0xFF]) { return Sniffed::Jpeg; }
    if head.starts_with(&[0x89, 0x50, 0x4E, 0x47]) { return Sniffed::Png; }
    if head.starts_with(b"GIF8") { return Sniffed::Gif; }
    if head.len() >= 12 && &head[0..4] == b"RIFF" && &head[8..12] == b"WEBP" { return Sniffed::WebP; }
    Sniffed::Unknown
}
```

2. `upload_file` — **policy decision (final): only `pdf` and `epub` are accepted
   as book files.** After deriving `ext`:
   - `ext == "pdf"` → body must sniff `Pdf`, else
     `AppError::BadRequest("file is not a valid PDF")`.
   - `ext == "epub"` → body must sniff `Zip`, else
     `BadRequest("file is not a valid EPUB")`.
   - any other ext → `BadRequest("only pdf and epub files are supported")`.
   Do this **before** writing the blob or DB row. Note: the app's
   `pushToServer` already catches `ServerException` per book and skips, so
   legacy odd-format rows on a device degrade gracefully.

3. `put_cover` — body must sniff `Jpeg | Png | Gif | WebP`, else
   `BadRequest("not a supported image (jpeg/png/gif/webp)")`. Derive the stored
   extension **from the sniffed type**, not from `Content-Type`; delete the now
   unused `ext_for_content_type` (keep `content_type_for_ext` — it serves
   downloads).

4. Unit tests in the existing `mod tests`: valid PDF header accepted, junk body
   with `.pdf` name → 400-mapped error, PNG-sniffed cover stores `.png`. Add an
   integration test in `server/tests/api.rs` (follow existing test style):
   upload junk to `/api/books/{id}/files?filename=x.pdf` → 400.

5. DESIGN.md: the magic-byte sentence at ~line 255 becomes true; reword to say
   both console **and API** validate.

**Commit:** `Server: validate uploads by magic bytes`

---

## Task 2 — Logout, session sweep, login throttle, timing fix

All in `server/src/auth.rs` (+ router, + app client).

1. **Logout endpoint.** Deletes the presented session row:

```rust
pub async fn logout(State(state): State<AppState>, headers: HeaderMap) -> AppResult<Json<serde_json::Value>> {
    let token = headers.get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::Unauthorized("missing bearer token".into()))?;
    sqlx::query("DELETE FROM session WHERE token_hash = ?")
        .bind(sha256_hex(token)).execute(&state.db).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
```

Route: `.route("/api/auth/logout", post(auth::logout))` in `lib.rs`.

2. **Expired-session sweep.** In `connect_db` (`lib.rs`), after migrations:
`sqlx::query("DELETE FROM session WHERE expires_at <= datetime('now')").execute(&db).await?;`
(startup-only is fine at this scale).

3. **Timing-safe login.** `login` and `user_from_basic` currently return early
when the email doesn't exist, skipping Argon2 → account enumeration by timing.
Add:

```rust
static DUMMY_HASH: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| hash_password("timing-equalizer-dummy").unwrap());
```

In the `else` (no row) branch of both functions, run
`let _ = verify_password(&password, &DUMMY_HASH);` before returning the same
"invalid email or password" error.

4. **Login throttle.** New `server/src/throttle.rs`, dependency-free:

```rust
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const MAX_FAILURES: usize = 10;
const WINDOW: Duration = Duration::from_secs(15 * 60);

/// Tracks recent failed logins per lowercase email. In-memory: resets on
/// restart, which is acceptable — Argon2 makes each attempt slow anyway.
#[derive(Default)]
pub struct LoginThrottle(Mutex<HashMap<String, Vec<Instant>>>);

impl LoginThrottle {
    pub fn allowed(&self, key: &str) -> bool {
        let mut map = self.0.lock().unwrap();
        let now = Instant::now();
        let hits = map.entry(key.to_string()).or_default();
        hits.retain(|t| now.duration_since(*t) < WINDOW);
        hits.len() < MAX_FAILURES
    }
    pub fn record_failure(&self, key: &str) {
        self.0.lock().unwrap().entry(key.to_string()).or_default().push(Instant::now());
    }
    pub fn clear(&self, key: &str) {
        self.0.lock().unwrap().remove(key);
    }
}
```

- `AppState` gains `pub throttle: std::sync::Arc<throttle::LoginThrottle>`.
  Update its construction in `main.rs` **and** `tests/api.rs`.
- New `AppError::TooManyRequests(String)` → HTTP 429 in `error.rs`.
- In `login` and `user_from_basic`: key = trimmed lowercase email. If
  `!allowed(key)` → 429 `"too many failed attempts — try again later"`. On
  password/user failure → `record_failure`; on success → `clear`.

5. **App side.** `VellumServerClient` gains
   `Future<void> logout()` (POST `/api/auth/logout`, ignore the body).
   `ServerConnection.disconnect()` (`connection_store.dart`) calls it
   best-effort first:

```dart
Future<void> disconnect() async {
  try { await client?.logout(); } catch (_) {/* offline is fine */}
  // ...existing prefs removals...
}
```

6. Integration tests: login → logout → `/api/auth/me` with the old token = 401;
   11 failed logins → 429 even with the correct password.

**Commit:** `Server: logout, session sweep, login throttle`

---

## Task 3 — Validate share-link `expires_at`

`server/src/shares.rs::create_link` accepts any string and SQLite compares it
lexically → garbage silently yields a never-expiring link. Replace the
`expires_at` block:

```rust
let expires_at: Option<String> = match input.expires_at.as_deref().map(str::trim) {
    Some("") | None => input.expires_in_days.map(|d| {
        (chrono::Utc::now() + chrono::Duration::days(d))
            .format("%Y-%m-%d %H:%M:%S").to_string()
    }),
    Some(raw) => {
        let parsed = chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d")
            .map(|d| d.and_hms_opt(23, 59, 59).unwrap())
            .or_else(|_| chrono::NaiveDateTime::parse_from_str(raw, "%Y-%m-%d %H:%M:%S"))
            .map_err(|_| AppError::BadRequest(
                "expires_at must be YYYY-MM-DD or YYYY-MM-DD HH:MM:SS".into()))?;
        Some(parsed.format("%Y-%m-%d %H:%M:%S").to_string())
    }
};
```

Also reject `expires_in_days` and `max_uses` values `<= 0` with 400. Test: bad
string → 400; `2026-01-01` produces an already-expired link (public endpoint
404s).

**Commit:** `Server: validate share-link expiry input`

---

## Task 4 — Close the first-registration race; blob cleanup on delete

Two small server correctness fixes, one commit each is overkill — but they are
unrelated, so keep them as **two commits**.

**4a. Registration race** (`auth.rs::register`): two concurrent first-registers
can both see `master_exists == false`. Wrap check + insert in one transaction:

```rust
let mut tx = state.db.begin().await?;
let master_exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM app_user WHERE is_master = 1)")
    .fetch_one(&mut *tx).await?;
if master_exists { return Err(AppError::Forbidden(/* unchanged message */)); }
// inline the insert_user SQL here against &mut *tx (or make insert_user take
// a `&mut SqliteConnection` executor), then:
tx.commit().await?;
```

**Commit:** `Server: make first-registration check transactional`

**4b. Blob cleanup** (`books.rs::delete`): FK cascades remove `book_file` rows
but cover/file blobs stay on disk forever. Before deleting the row, collect
paths; after a successful delete, remove them best-effort:

```rust
let cover: Option<Option<String>> = sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")…;
let files: Vec<String> = sqlx::query_scalar("SELECT path FROM book_file WHERE book_id = ?")…;
// existing owner check + DELETE …
for rel in files.into_iter().chain(cover.flatten()) {
    let _ = tokio::fs::remove_file(state.data_dir.join(rel)).await;
}
```

Test: create book, upload file + cover, delete book, assert the two paths no
longer exist under the test data dir.

**Commit:** `Server: delete blobs when a book is deleted`

---

## Task 5 — Delete tombstones + `updated_at`-aware pull (schema change, both sides)

**Problems.** (a) `pullFromServer` (`app/lib/data/library_repository.dart`)
`insertOnConflictUpdate`s server metadata unconditionally → local edits lost.
(b) Deletes don't propagate: a locally deleted book resurrects on pull; a
server-deleted book never disappears locally.

### 5.1 Server: `deletion` table + endpoint

New migration `server/migrations/0005_deletions.sql`:

```sql
-- Tombstones so clients can propagate deletes. owner_id is denormalized here
-- because the book row (and its FK target) is gone.
CREATE TABLE deletion (
    book_id    TEXT PRIMARY KEY,
    owner_id   TEXT,
    deleted_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- In `books.rs::delete` (after Task 4b): inside the same flow, insert the
  tombstone (`INSERT OR REPLACE INTO deletion (book_id, owner_id) VALUES (?, ?)`)
  before deleting the book row.
- If a book is later re-created at the same id via `upsert`'s INSERT branch,
  `DELETE FROM deletion WHERE book_id = ?` there.
- New endpoint `GET /api/deletions` (auth required) returning
  `[{ "book_id": …, "deleted_at": … }]`. **Policy decision (final):** return
  all tombstones to any authenticated user — it leaks only UUIDs of deleted
  books, acceptable for a personal server; note this in a comment.
- Route in `lib.rs`; document table + endpoint in DESIGN.md's server section.

### 5.2 App: local tombstones (drift schema v6)

In `database.dart`:

```dart
/// Books deleted on this device, remembered until the deletion has been
/// pushed to the server (or forever in standalone mode — rows are tiny).
@DataClassName('LocalDeletion')
class LocalDeletions extends Table {
  TextColumn get bookId => text()();
  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {bookId};
}
```

Add to `@DriftDatabase(tables: […])`, bump `schemaVersion` to 6, add
`if (from < 6) { await m.createTable(localDeletions); }`, rerun build_runner.
This table is app-local bookkeeping — do **not** mirror it in the server schema
(the server has its own `deletion` table with different semantics).

`LibraryRepository.deleteBook`: inside the existing transaction, insert a
`LocalDeletions` row for `book.id`.

### 5.3 App: sync logic

`ServerBook` (`server_client.dart`) gains `updatedAt`:

```dart
/// Server timestamps are `datetime('now')` strings in UTC: "YYYY-MM-DD HH:MM:SS".
static DateTime? _parseServerTime(String? s) =>
    s == null ? null : DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z');
```

Populate from `j['updated_at']`. Add
`Future<List<String>> listDeletions()` (GET `/api/deletions`, map `book_id`)
and `Future<void> deleteBook(String id)` (DELETE `/api/books/{id}`) to the
client.

`pullFromServer` changes, in order:

1. Fetch `client.listDeletions()` first. For each id with a local `Books` row,
   call the existing `deleteBook(...)` (it already removes cover/files/joins),
   but **do not** insert a local tombstone for these (add a
   `recordTombstone: false` parameter or a private variant) — otherwise pull
   would re-push deletions forever.
2. Load local tombstones; **skip** any server book whose id is locally
   tombstoned (it will be deleted from the server on next push).
3. Per-book upsert becomes timestamp-guarded. Load
   `{id: updatedAt}` for all local books once before the loop. Then:
   - No local row → insert, and **explicitly set `updatedAt` to the parsed
     server timestamp** (`updatedAt: Value(b.updatedAt)` in the companion) —
     otherwise the local default `now()` is newer than every future server
     edit and pulls would be skipped forever.
   - Local row exists and `serverUpdatedAt != null && localUpdatedAt < serverUpdatedAt`
     → update metadata columns (and set local `updatedAt` = server's).
   - Otherwise → skip the metadata write (local is same or newer; push wins).
   - Unparseable/missing server timestamp → fall back to current overwrite
     behavior.
   Cover/file download passes stay as they are.

`pushToServer` changes:

1. First, for every local tombstone: `client.deleteBook(id)`; treat 2xx and
   `ServerException` alike (404 = already gone, 403 = not the owner — a
   non-owner can't delete the server copy; local delete of a shared book is a
   local-only act and the book will legitimately return on pull). Remove the
   tombstone row afterwards in all cases.
2. The per-book push loop is unchanged (server bumps `updated_at` on upsert,
   which keeps the pull guard consistent).

Known limitation to note in DESIGN.md: comparison uses wall clocks of server
vs. device; skew can delay a sync by its magnitude. Fine for a personal setup.

### 5.4 Tests

- Server (`tests/api.rs`): delete a book → `/api/deletions` lists it; upsert at
  the same id → tombstone gone.
- App (`app/test/sync_test.dart`): construct `VellumDatabase` on
  `NativeDatabase.memory()` (see Task 11 for the constructor change), fake
  `VellumServerClient` via a hand-written stub class; cover: local-newer-skips,
  server-newer-overwrites, tombstone round-trip.

**Commit:** `Sync: delete tombstones and timestamp-guarded pull`

### 5.5 DESIGN.md

Update "Sync roadmap" / "Build order": conflict handling is now
last-write-wins by `updated_at` with delete tombstones; remaining is field-level
merge + live updates.

---

## Task 6 — Stream blobs on the server (no more whole-file RAM buffering)

`Cargo.toml`: add `tokio-util = { version = "0.7", features = ["io"] }` and
`futures-util = "0.3"`.

**Downloads** — rewrite `serve_blob` (`blobs.rs`):

```rust
async fn serve_blob(state: &AppState, rel: &str) -> AppResult<Response> {
    let full = state.data_dir.join(rel);
    let file = tokio::fs::File::open(&full).await
        .map_err(|_| AppError::NotFound("blob missing on disk".into()))?;
    let len = file.metadata().await.map(|m| m.len()).ok();
    let ext = Path::new(rel).extension().and_then(|e| e.to_str()).unwrap_or("");
    let body = axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(file));
    let mut res = Response::new(body);
    res.headers_mut().insert(header::CONTENT_TYPE, content_type_for_ext(ext).parse().unwrap());
    if let Some(len) = len {
        res.headers_mut().insert(header::CONTENT_LENGTH, len.into());
    }
    Ok(res)
}
```

`shares.rs::public_file`: **open the file before consuming the use** (fixes a
latent bug — today a missing file still burns a one-time use), then consume,
then stream with the existing Content-Disposition headers.

**Uploads** — `upload_file` takes `body: axum::body::Body` instead of `Bytes`
(`DefaultBodyLimit` still enforces the cap). Stream to a temp file while
hashing and capturing the first 16 bytes for the Task-1 sniff:

```rust
use futures_util::StreamExt;
use tokio::io::AsyncWriteExt;

let tmp = state.data_dir.join(format!("files/.tmp-{file_id}"));
// create_dir_all on the parent as write_blob did
let mut out = tokio::fs::File::create(&tmp).await.map_err(internal)?;
let mut hasher = Sha256::new();
let mut head: Vec<u8> = Vec::with_capacity(16);
let mut size: i64 = 0;
let mut stream = body.into_data_stream();
while let Some(chunk) = stream.next().await {
    let chunk = chunk.map_err(|e| AppError::BadRequest(format!("upload aborted: {e}")))?;
    if head.len() < 16 {
        head.extend_from_slice(&chunk[..chunk.len().min(16 - head.len())]);
    }
    hasher.update(&chunk);
    out.write_all(&chunk).await.map_err(internal)?;
    size += chunk.len() as i64;
}
out.flush().await.map_err(internal)?;
drop(out);
```

Then: empty → remove tmp + 400; sniff-validate per Task 1 (remove tmp on
failure); `tokio::fs::rename(&tmp, &full)`; insert the DB row with
`hex::encode(hasher.finalize())` and `size`. The PDF page count must now read
from disk: `lopdf::Document::load(path)` inside the existing
`spawn_blocking`. `put_cover` may keep `Bytes` (covers are small).

Verify with a large file:
`dd if=/dev/urandom of=/tmp/big.bin bs=1M count=500` won't pass the sniff, so
prepend a `%PDF-` header or use a real large PDF; watch RSS of the server
process while uploading + downloading (`curl -T`, `curl -o`).

**Commit:** `Server: stream file uploads and downloads`

---

## Task 7 — Stream blobs in the app

`server_client.dart` — add streaming variants and migrate callers; keep the
byte-based cover methods (covers are small):

```dart
/// Streams a book file to [dest] without buffering it in memory.
Future<void> downloadFileTo(String fileId, File dest) async {
  final req = http.Request('GET', _uri('/api/files/$fileId'));
  final auth = _bearer;
  if (auth != null) req.headers['authorization'] = auth;
  final res = await _http.send(req);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw ServerException('File download failed (HTTP ${res.statusCode})');
  }
  final sink = dest.openWrite();
  try {
    await sink.addStream(res.stream);
  } finally {
    await sink.close();
  }
}

/// Streams [source] up as a book file.
Future<void> uploadFileFrom(String bookId, File source, {required String format}) async {
  final mime = switch (format) {
    'pdf' => 'application/pdf',
    'epub' => 'application/epub+zip',
    _ => 'application/octet-stream',
  };
  final filename = Uri.encodeQueryComponent('book.$format');
  final req = http.StreamedRequest('POST', _uri('/api/books/$bookId/files?filename=$filename'))
    ..contentLength = await source.length()
    ..headers['content-type'] = mime;
  final auth = _bearer;
  if (auth != null) req.headers['authorization'] = auth;
  source.openRead().listen(req.sink.add,
      onDone: req.sink.close, onError: req.sink.addError, cancelOnError: true);
  final res = await http.Response.fromStream(await _http.send(req));
  _body(res);
}
```

In `library_repository.dart`: `pullFromServer`'s file loop writes via
`downloadFileTo(f.id, File(p.join(_dataDir.path, rel)))` (write to a `.part`
temp name and rename after success, so an interrupted download isn't recorded);
`pushToServer` uses `uploadFileFrom(b.id, file, format: lf.format)`. Delete the
now-unused `downloadFile`/`uploadFile` byte variants.

**Commit:** `App: stream book file transfers`

---

## Task 8 — App credential hygiene: secure token storage, https default

1. `app/pubspec.yaml`: add `flutter_secure_storage: ^9.2.0`. Linux runtime needs
   libsecret/keyring (`libsecret-1-dev` to build); mention in `app/README.md`.
2. `connection_store.dart`: keep URL/email/isMaster in SharedPreferences; move
   **only the token** to secure storage.
   - `load()` becomes: read prefs; `const storage = FlutterSecureStorage();`
     read token; **migration** — if prefs still holds `server.token`, write it
     to secure storage and remove from prefs.
   - Token becomes a cached field set at load/save; `saveSession` writes it via
     `storage.write`, `disconnect` deletes it. Getters stay synchronous.
   - If secure storage throws on read/write (no keyring), catch and fall back
     to prefs so the app still works; add a `// fallback:` comment.
3. `normalizeUrl`: default scheme-less input to **`https://`**. In
   `server_page.dart`, when the final URL starts with `http://`, show an
   inline warning (`Text` under the URL field): "Unencrypted connection — your
   password and books are sent in cleartext."
4. Update DESIGN.md's server section note about tokens accordingly.

**Commit:** `App: secure token storage, default to https`

---

## Task 9 — ETag caching for blobs

`blobs.rs`: thread an optional etag into `serve_blob`:

- `download_file`: you already SELECT the row — also select `sha256` and pass
  `Some(format!("\"{sha}\""))`.
- `get_cover`: compute a weak validator from file metadata:
  `W/"{len}-{mtime_unix}"`.
- In `serve_blob`, before opening the stream: if the request's `If-None-Match`
  equals the etag → `304` with empty body (handler needs `headers: HeaderMap`).
  Set `ETag` and `Cache-Control: private, max-age=0, must-revalidate` on 200s.

The console already cache-busts with `?t=`; leave it (harmless).

**Commit:** `Server: ETag/304 for covers and files`

---

## Task 10 — CI

New `.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  server:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: server } }
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
        with: { workspaces: server }
      - run: cargo fmt --check
      - run: cargo clippy --all-targets -- -D warnings
      - run: cargo test

  app:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: app } }
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

Before committing, run `cargo fmt` in `server/` and commit the formatting diff
(as its own preceding commit if it's large), and make sure
`clippy --all-targets -- -D warnings` passes locally.

**Commit:** `CI: analyze + test both projects` (plus optional `Server: cargo fmt`)

---

## Task 11 — Extract sync engine from `LibraryRepository`

Pure refactor, no behavior change. `library_repository.dart` (~850 lines) mixes
CRUD, the file store, and the sync engine.

1. New `app/lib/server/sync_service.dart`:

```dart
/// Two-way sync between the local library and a Vellum server. Owns no state;
/// operates on the repository's database and file store.
class SyncService {
  SyncService(this.repository);
  final LibraryRepository repository;

  Future<int> pull(VellumServerClient client) async { … }  // moved pullFromServer
  Future<int> push(VellumServerClient client) async { … }  // moved pushToServer
}
```

2. Move `pullFromServer`/`pushToServer` bodies there verbatim. They need the
   repository's data dir: add `Directory get dataDir => _dataDir;` to the
   repository (with a doc comment saying it's for the sync service / file
   store). Tombstone helpers from Task 5 move too.
3. `grep -rn "pullFromServer\|pushToServer" app/lib` and update the call sites
   (drawer / server page) to construct `SyncService(repository)`.
4. While here, make `VellumDatabase` testable:
   `VellumDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());`
   — needed by Task 5's tests if not already done.
5. Move the Task 5 sync tests alongside as `app/test/sync_service_test.dart`.

**Commit:** `App: extract SyncService from LibraryRepository`

---

## Task 12 — Extract the settle/packing geometry for testability

`environment_editor_page.dart` (~1,300 lines) contains the drop/settle
heuristic inline; two open backlog bugs live there ("books riding shelves",
"settle bounds").

1. New `app/lib/physical/settle.dart` with **pure functions** (no Flutter
   imports beyond `dart:ui` `Rect`/`Offset` if convenient — prefer plain
   doubles/records so tests need no binding). Identify in the page: the code
   that (a) finds the highest support under a dropped book's span, (b) nudges
   sideways out of overlap, (c) decides off-shelf removal. Extract with
   signatures shaped like:

```dart
/// Where a book released at [dropped] comes to rest among [shelves] and
/// [others], or null when nothing supports it (the placement is removed).
SettleResult? settle({required Rect dropped, required List<Segment> shelves,
    required List<Rect> others});
```

2. Behavior-preserving: the page calls the new functions; `flutter analyze`
   clean; manually verify drag/settle in `flutter run -d linux`.
3. `app/test/settle_test.dart`: book drops onto shelf top; stacks on another
   book; falls with no support → null; **document the two known bugs as tests
   with the current (buggy) expectation and a `// BACKLOG:` comment**, so
   fixing them later flips the expectations deliberately.

**Commit:** `App: extract settle geometry, add tests`

---

## Task 13 — Schema-parity test (drift ↔ server migrations)

The dual schema is enforced only by discipline. Add
`server/tests/schema_parity.rs`: open an in-memory DB, run migrations, and for
each **synced** table (`book`, `author`, `book_author`, `genre`, `book_genre`,
`book_file`) assert `PRAGMA table_info(...)` column names equal a hard-coded
expected list. Exclude app-local columns/tables per DESIGN.md. Comment at the
top: *"If this test fails you probably changed one schema without the other —
see CLAUDE.md."* It won't catch drift-side-only changes by itself, but any
server-side edit now surfaces the checklist, and the expected list doubles as
the canonical contract. Mention the test in DESIGN.md's data-model section.

**Commit:** `Server: schema-parity regression test`

---

## Task 14 — Documentation and metadata polish

- `app/pubspec.yaml`: real `description:` ("Personal library manager — visual
  bookshelf for digital and physical books"), keep version.
- DESIGN.md: fold in all doc updates deferred from earlier tasks if any were
  missed; fix the spine-color claim ("extracted from the cover") to match the
  title-hash implementation, or mark it aspirational with a pointer to
  BACKLOG.md.
- README.md "Status": mention logout/tombstone sync once implemented.
- Add a short **Deployment** note to DESIGN.md's server section: run behind a
  TLS reverse proxy (caddy/nginx); the server itself is plain HTTP;
  `VELLUM_PUBLIC_URL` must be the public https URL so minted share links are
  correct.

**Commit:** `Docs: deployment notes, metadata polish`

---

## Deferred / explicitly out of scope

- Field-level merge conflict resolution and live updates (websocket/poll).
- Per-resource short-lived tokens to replace the `?token=` query param
  (document the logging caveat in DESIGN.md for now — done in Task 8/14).
- Rate limiting beyond login (uploads, public links).
- Splitting `console.html`; `book_detail_page.dart` size; cover-derived spine
  colours (BACKLOG.md items).
- Upsert ID-squatting (`PUT /api/books/{id}` lets any member claim an
  arbitrary UUID): acceptable on a personal server; revisit if accounts ever
  include strangers.
