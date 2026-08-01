# Vellum — Security Audit

**Last reviewed:** 2026-08-01 (see *Second review* below)
**First audit:** 2026-07-11
**Scope:** `server/` (Rust axum + sqlx sync backend) and `app/` (Flutter client),
including authentication, RBAC, blob/upload handling, the web console, sync, and
third-party dependency versions.
**Method:** Manual source review of the security-relevant code paths plus a
review of resolved dependency versions (`Cargo.lock`, `pubspec.yaml`). No
dynamic testing or fuzzing was performed. Automated advisory scanners
(`cargo audit`, `flutter pub outdated`) were **not** available in the review
environment — running them is a recommendation below.

> **Context that shapes severity.** Vellum is local-first; the server is an
> *optional* self-hosted sync backend that "should sit behind a TLS reverse
> proxy" (DESIGN.md). It is multi-user by design: a master account provisions
> member accounts, and members can be granted viewer/editor shares. Findings are
> rated for the **multi-user, internet-reachable** deployment the server
> supports. For a single-user server on a trusted LAN, several ratings drop.

---

## Severity legend

| Level | Meaning |
|---|---|
| 🔴 High | Exploitable by a low-privileged authenticated user; leads to disclosure of other users' data or server files. Fix promptly. |
| 🟠 Medium | Real risk requiring a specific condition (malicious peer, crafted media, deployment window). Fix soon. |
| 🟡 Low | Defense-in-depth gap or low-impact/edge issue. Fix opportunistically. |
| 🔵 Info | Positive control or informational note. |

## Findings at a glance

| ID | Sev | Status | Title | Location |
|----|-----|--------|-------|----------|
| H1 | 🔴 | ✅ Fixed (2026-07-11) | Arbitrary file read via client-controlled `cover_path` (path traversal) | `server/src/books.rs`, `server/src/blobs.rs` |
| M1 | 🟠 | ✅ Fixed (2026-07-11) | Decompression / pixel bombs on untrusted covers & EPUB zips (DoS) | `server/src/blobs.rs` |
| M2 | 🟠 | ✅ Fixed (2026-07-11) | Client-side path traversal on sync pull (server-supplied ids unvalidated) | `app/lib/server/sync_service.dart` |
| M3 | 🟠 | ✅ Mitigated (opt-in, 2026-07-11) | Master-bootstrap takeover window (first registrant becomes owner) | `server/src/auth.rs` + deployment |
| M4 | 🟠 | ✅ Fixed (2026-07-11) | Dependencies behind latest; no automated advisory scanning in CI | `server/Cargo.toml`, `app/pubspec.yaml` |
| L1 | 🟡 | ✅ Fixed (2026-07-25) | `?token=` in URL leaks into proxy logs / browser history | `server/src/auth.rs` |
| L2 | 🟡 | ✅ Fixed (2026-07-25) | Session token plaintext fallback when no OS keyring | `app/lib/server/connection_store.dart` |
| L3 | 🟡 | ✅ Fixed (2026-07-11) | Missing HTTP security headers (CSP, nosniff, frame-options) | `server/src/lib.rs` |
| L4 | 🟡 | ✅ Fixed (2026-07-11) | Login throttle keyed by email only (no per-IP cap) | `server/src/throttle.rs`, `auth.rs` |
| L5 | 🟡 | ✅ Fixed (2026-07-25) | Basic-auth cache holds unsalted SHA-256 of passwords in memory | `server/src/auth.rs` |
| L6 | 🟡 | ✅ Hardened (2026-07-25) | Untrusted-PDF cover render shells out to `gs`/`mutool`/`pdftoppm` | `server/src/blobs.rs` |
| P1 | 🟡 | ✅ Fixed (2026-07-28) | Annotation tombstones readable by every account via the unscoped `/deletions` | `server/src/books.rs` |
| P2 | 🔵 | ✅ Fixed (2026-07-28) | Avatar upload's stated 4 MB cap unreachable behind axum's 2 MB default | `server/src/lib.rs` |
| S1 | 🔴 | ✅ Fixed (2026-08-01) | Arbitrary file **write** outside the data directory via a client-chosen id | `server/src/books.rs`, `blobs.rs`, `physical_copies.rs` |
| S2 | 🟠 | ✅ Fixed (2026-08-01) | Unbounded quadratic work in `/api/import/check` (authenticated DoS) | `server/src/import_check.rs` |
| S3 | 🟡 | ✅ Fixed (2026-08-01) | Duplicate check read every `book_file` row regardless of visibility | `server/src/import_check.rs` |
| S4 | 🟡 | ✅ Fixed (2026-08-01) | Tombstones keyed by id alone, so a cross-kind collision would silently overwrite | `server/migrations/0025_deletion_key.sql` |
| S5 | 🔴 | ✅ Fixed (2026-08-01) | Stored XSS in the admin console via values interpolated into inline handlers | `server/web/console.js` |

> **Remediation note (2026-07-11):** H1, M1, M2 (destructive, low-effort) plus a
> second round — M3 (opt-in), M4, L3, L4 — have been hardened (see the ✅ notes in
> each section). Still open: M4's `flutter_secure_storage` major upgrade, and
> L1, L2, L5, L6.

---

## Round 3 — the personal-data endpoints (2026-07-28)

Covers `server/src/personal.rs` and migration 0023 (annotations, reading
sittings, private notes, profile photo), added after the original audit. The
review followed plan 6 #3's checklist; two findings, both fixed, plus four
invariants confirmed by reading and by driving a live server.

### 🟡 P1 — Annotation tombstones leaked through the shared deletions list

Annotation deletions were recorded in the shared `deletion` table so the
existing tombstone machinery would carry them. But `GET /api/deletions` is
**unscoped by design** — a deleted book is a library-wide fact every device
needs — so any authenticated account could read the ids and timings of every
other account's annotation deletions.

Confirmed live: account B, unrelated to A's book, saw
`{"book_id":"secret-note","kind":"annotation"}` after A deleted it. The
disclosure is an opaque id plus a timestamp, no content — hence 🟡 rather than
🟠 — but it is cross-account information that should not exist.

**Fixed** by excluding `kind = 'annotation'` from that endpoint. They already
had a per-user endpoint (`personal::list_annotation_deletions`, scoped by
`owner_id`); the shared list was a leftover from the first implementation.

### 🔵 P2 — The avatar's stated size cap could never fire

`put_avatar` checks for 4 MB and returns "avatar must be under 4 MB". It never
ran: body limits in this server are per-route, the avatar route had none, and
axum's 2 MB default rejected the request first with "Failed to buffer the
request body" — an error naming neither avatars nor a size, at a limit that
disagreed with the documented one.

Not a memory-safety problem (the default limit was doing the protecting), but a
stated invariant that wasn't the real one. **Fixed** by giving the route an
explicit 4 MB `DefaultBodyLimit`, so the handler's own check is what answers.

### Confirmed, no change needed

- **Avatar paths cannot traverse.** The path is `avatars/<user id>` where the id
  comes from the token, and ids are server-generated UUIDs (`insert_user`).
  Nothing client-supplied reaches the filesystem.
- **Every list is doubly scoped.** All three (`annotations`, `sessions`,
  `notes`) filter on `user_id` *and* join `access_predicate()`, so a book that
  stops being shared stops returning your rows with it.
- **Ids cannot be taken over.** The annotation upsert carries
  `WHERE annotation.user_id = ?` on the update half; another account guessing an
  id gets 404, not a write. Tested.
- **No unbounded decode.** Avatars are stored and served as bytes, sniffed by
  magic number and never decoded server-side, so M1's pixel-bomb reasoning does
  not reapply. SVG is not in the accepted set, so no script-in-image path.

*Round 3 reflects the code at `2fb63f4`.*

---

## Detailed findings

### 🔴 H1 — Arbitrary file read via client-controlled `cover_path`

**Where:** `books.rs::create` / `upsert` / `update` accept a `cover_path` string
from the JSON body and store it verbatim. `blobs.rs::get_cover` later reads it
back and serves `state.data_dir.join(cover_path)` via `serve_blob`, which opens
and streams that path.

**Problem:** `cover_path` is never validated. A path segment in the *body*
(unlike the `{id}` URL segment, which axum won't let contain `/`) may contain
`/` and `..`. `PathBuf::join("../../../etc/passwd")` escapes the data directory,
and `serve_blob` streams whatever it opens.

**Exploit (any authenticated member, no special privilege):**
1. `POST /api/books` with `{"title":"x","cover_path":"../../etc/passwd"}` — the
   caller becomes the book's owner.
2. `GET /api/books/{id}/cover` → returns the contents of `/etc/passwd`.

Replace the path with `../vellum.db` (or wherever `VELLUM_DB` points relative to
`VELLUM_DATA_DIR`) to exfiltrate the **entire database** — every user's Argon2
password hash, all session token hashes, every book, share, and link. Any file
the server process can read is reachable.

**Impact:** Full read access to the server filesystem and database for any
account holder. On a shared server this is a privilege escalation from
"member" to "read everything." (On a strictly single-user server the only
account is the master, who already controls the host, so practical impact there
is low — but the multi-user model is a first-class feature.)

**Fix (recommended):** Do **not** accept `cover_path` from clients at all —
covers are set only by `put_cover` (upload) and the PDF/EPUB render path, and
the app relies on covers syncing through the dedicated cover endpoint (the
`COALESCE(?, cover_path)` already preserves the stored value when omitted).
Remove `cover_path` from `BookInput`/`BookUpdate`, or, if it must stay,
**reject** any value that is not exactly `covers/<uuid>.<ext>` (no `..`, no
absolute path, and after canonicalization still inside `data_dir`). The same
guard should apply to `spine_style` only insofar as it is never used as a path
(it isn't today — it is opaque JSON — so it's fine).

**✅ Fix applied (2026-07-11):** `books.rs::validate_cover_path` rejects any
client-supplied `cover_path` that isn't a single `covers/<name>` segment (no
`/`, `\`, `..`, or NUL), called from `create`/`upsert`/`update`. As a
defence-in-depth backstop, `blobs.rs::is_safe_rel` now gates `serve_blob` (and
the anonymous `public_file` download), so even a pre-existing poisoned row can't
resolve outside the data dir. Unit tests cover both helpers.

---

### 🟠 M1 — Decompression / pixel bombs on untrusted media (DoS)

**Where:** `blobs.rs`.
- `make_thumb` / `ensure_thumb` call `image::open(cover)` then `.thumbnail(w, …)`.
  Magic-byte validation proves the upload *is* a JPEG/PNG/GIF/WebP, but a small,
  highly-compressed file can decode to enormous pixel dimensions ("pixel bomb")
  and allocate gigabytes before the downscale runs.
- `epub_cover_bytes` does `f.read_to_end(&mut buf)` on a zip entry named by the
  (attacker-authored) OPF manifest, with **no size cap** — a zip bomb entry
  inflates unbounded into memory.

**Impact:** A single crafted cover or EPUB can OOM-kill the server process
(availability). Both paths run in `spawn_blocking`, so a *panic* is contained,
but an allocation failure aborts the whole process.

**Fix:**
- For image decoding, use the `image` crate's `Limits` (e.g.
  `image::io::Reader::with_guessed_format().limits(...)`) to cap decoded
  dimensions/allocation before `decode()`.
- For the EPUB cover, cap the entry read (e.g. `f.take(MAX_COVER_BYTES)` with a
  few MB ceiling) and bail if exceeded.
- Consider a small upper bound on cover upload size independent of the 2 GB
  book-file limit (covers already use a 32 MB `DefaultBodyLimit`, which bounds
  the *compressed* input but not the *decoded* size).

**✅ Fix applied (2026-07-11):** the EPUB cover extractor now caps each zip
entry read at 32 MiB via `Read::take` (zip-bomb guard), and `make_thumb` decodes
through `image::ImageReader` with explicit `Limits` (max 12000×12000 px, 256 MiB
alloc) so a small "pixel bomb" cover can't OOM the process. A generic cover
upload-size cap (last bullet) is still worth adding.

---

### 🟠 M2 — Client-side path traversal on sync pull

**Where:** `app/lib/server/sync_service.dart` builds local blob paths directly
from server-supplied ids/formats:
```dart
final rel = p.join('covers', '${b.id}.jpg');        // b.id from server JSON
final rel = p.join('files', '${f.id}.${f.format}'); // f.id, f.format from server JSON
```
No validation that `b.id`/`f.id` are UUIDs or that `f.format` is `pdf`/`epub`.

**Problem:** A malicious or compromised server (or a MITM if the app is pointed
at plain `http://`) can return an id like `../../../.bashrc`, causing the app to
**write outside its data directory** on the user's machine during a pull.

**Impact:** Arbitrary file write on the client, bounded by the app process's
permissions. The trust boundary softens this — the user chooses which server to
connect to — but there is no defense in depth, and "connect to a friend's shared
library" is a supported flow.

**Fix:** Validate every server-supplied id against a UUID pattern and `format`
against the `{pdf, epub}` allow-list before using them in a path; reject/skip
rows that fail. (Mirror the server's own discipline of only ever generating
UUID-named blobs.)

**✅ Fix applied (2026-07-11):** `sync_service.dart::_isSafeSegment` rejects any
id/format containing a path separator, `..`, whitespace, or that is `.`/empty,
and now guards all three pull sites that build `covers/<id>.jpg` and
`files/<id>.<format>` — an unsafe value is skipped and surfaced as a `SyncIssue`
rather than written. A regression test drives a traversal file id through a fake
server and asserts nothing is fetched or recorded.

---

### 🟠 M3 — Master-bootstrap takeover window

**Where:** `auth.rs::register` — "the first account created becomes the master,"
after which registration closes.

**Problem:** If the server is reachable on the network **before** the legitimate
owner registers, whoever registers first becomes master (full admin over the
library). A fresh instance exposed to the internet is claimable by an attacker.

**Impact:** Complete library takeover on a misconfigured/opened-too-early deploy.

**Fix (operational + optional code):** Document that the owner must register
immediately, ideally over localhost, before exposing the port. Optionally gate
the very first registration behind a one-time bootstrap secret
(`VELLUM_BOOTSTRAP_TOKEN` env var checked in `register` until a master exists),
so an open port alone can't be claimed.

**✅ Mitigated (opt-in, 2026-07-11):** `auth.rs::require_bootstrap_token` now
enforces a `VELLUM_BOOTSTRAP_TOKEN` env secret on `register` when it is set —
the first registration must present a matching `bootstrap_token` (compared as
SHA-256 to avoid a length/timing tell). Unset ⇒ behaviour unchanged, so this is
opt-in: operators exposing a fresh instance should set it. (The app's register
screen would need a token field to use it interactively; today the bootstrap
registration is done via curl/console.)

---

### 🟠 M4 — Dependency currency & no automated advisory scanning

Resolved versions are current-ish and no *known-exploited* advisory was
identified by manual inspection, but there is no automated gate:

**Rust (`Cargo.lock`):** `axum 0.8.9`, `sqlx 0.8.6`, `reqwest 0.12.28`,
`rustls 0.23.41`, `tokio 1.52.3`, `argon2 0.5.3`, `image 0.25.10`,
`lopdf 0.43.0`, `zip 2.4.2`, `hyper 1.10.1`. These are recent majors. Two crates
parse untrusted input and deserve extra attention as advisories land:
`lopdf` (PDF parsing of uploads — see L6) and `zip` (EPUB reading — see M1).

**Flutter (`pubspec.yaml`):** `flutter_secure_storage ^9.2.0` — a **major
version behind** (10.x is available); `drift`, `archive`, `pdfrx`,
`shared_preferences`, and others are a few minors behind (per
`flutter pub outdated`).

**Fix:** Add `cargo audit` (or `cargo deny check advisories`) and a
`flutter pub outdated`/dependency-review step to CI so a newly-disclosed CVE in a
dependency fails the build. Plan the `flutter_secure_storage` 9→10 upgrade.

**✅ Fixed (2026-07-11):** a new `audit` CI job runs `cargo audit` (prebuilt via
`taiki-e/install-action`) against `server/Cargo.lock`, so a newly-disclosed
RustSec advisory now fails CI. *Still open:* the `flutter_secure_storage` 9→10
major upgrade, and a Dart-side advisory check (no first-party tool exists;
`flutter pub outdated` remains informational).

---

### 🟡 L1 — `?token=` in URL can leak into logs/history

`auth.rs` used to accept a session token as a `?token=` query param (scoped to
cover/download **GET**s) so a browser `<img src>`/`<a download>` could reach an
authenticated blob. Query strings land in reverse-proxy access logs and browser
history, so that path leaked the token.

**✅ Fixed (2026-07-25):** the token is now read **only** from the
`Authorization` header — the query fallback (and its `is_blob_get`/`query_token`
helpers) is gone. The web console loads covers and downloads with an
`Authorization: Bearer` `fetch()` into an object URL (`blob:`) rather than a
bare `src`/`href`, so the token never enters a URL. The CSP's `img-src` now
allows `blob:` for those object URLs; an integration test asserts a `?token=`
query authenticates nothing, even on a cover GET.

### 🟡 L2 — Session token plaintext fallback

`connection_store.dart` stores the bearer token in the OS secure store
(Keychain/libsecret/Keystore), but **falls back to `SharedPreferences`
(plaintext on disk)** when no keyring is available. Reasonable for usability, but
on a headless Linux box without a keyring the token sits in cleartext, silently.

**✅ Fixed (2026-07-25):** the fallback still happens (usability), but is no
longer silent. `ServerConnection` tracks when the token was written/loaded in
plaintext (`shouldWarnInsecureToken`) and the server page shows a one-time,
dismissable notice — "Secure storage unavailable — the session token is stored
unencrypted on this device" — pointing at disconnecting or installing a keyring.
Android's Keystore is always present, so in practice this is desktop-only.

### 🟡 L3 — Missing HTTP security headers

`web.rs` serves the console and public landing page without
`Content-Security-Policy`, `X-Content-Type-Options: nosniff`, or
`X-Frame-Options`/`frame-ancestors`. No XSS was found (the console and
`public.html` escape all interpolated data — see Info notes), and the strict CSP
would need work because the console uses inline handlers, but at minimum add
`X-Content-Type-Options: nosniff` (blobs are served same-origin) and a
frame-ancestors/`X-Frame-Options: DENY` to blunt clickjacking and MIME-sniffing.

**✅ Fixed (2026-07-11):** a `security_headers` middleware in `lib.rs::router`
now sets `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and a CSP
(`default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none';
frame-ancestors 'none'`; inline styles/scripts allowed so the console/public
pages still work) on every response. An integration test asserts their presence.

### 🟡 L4 — Login throttle keyed by email only

`throttle.rs` caps failed logins per **email** (10 / 15 min), not per source IP.
A password spray across many distinct emails from one IP isn't rate-limited by
this mechanism. Mitigated by Argon2's per-attempt cost and the memory-bounded
key sweep, so impact is low, but a per-IP cap on `/api/auth/login` would harden
it.

### 🟡 L5 — Basic-auth cache holds unsalted password hashes in memory

`BasicAuthCache` stored `sha256(password)` (unsalted) with a 5-minute TTL to
avoid an Argon2 verify on every OPDS request. A cached value that leaked (log,
partial dump, swapped page) was an offline-crackable password hash.

**✅ Fixed (2026-07-25):** the cache now stores `sha256(key ‖ password)` where
`key` is a random 32-byte secret generated once per process (`CACHE_KEY`), never
persisted or logged. Without the in-process key the fingerprint isn't
precomputable, so it can't be cracked offline. Behaviour is unchanged (same
TTL, same password-specific hit test); the fingerprint is used only to recognise
the same password within the process, not as a MAC.

### 🟡 L6 — Untrusted-PDF cover render shells out to external tools

`render_first_page` invokes `pdftoppm`/`pdftocairo`/`mutool`/`gs` on uploaded
PDFs. This is well-contained: a 30 s `timeout` with `kill_on_drop`, a
concurrency semaphore (2), and Ghostscript run with `-dSAFER`.

**✅ Hardened (2026-07-25):** each render subprocess now also runs under
`setrlimit` resource caps applied via `pre_exec` before `exec` (Unix):
`RLIMIT_AS` 1 GiB, `RLIMIT_CPU` 30 s, `RLIMIT_FSIZE` 64 MiB, `RLIMIT_CORE` 0. So
even within the wall timeout a malicious PDF can't exhaust host memory, spin CPU
indefinitely, fill the disk, or dump core. The residual risk is parsing
attacker-controlled PDFs in a third-party binary (historically a rich bug
source, esp. Ghostscript) — the render is a pure convenience with **no**
pure-Rust rasteriser available (`lopdf` only parses the page tree for the count,
it can't render), so the shell-out stays optional. Keep those host tools
patched, or run the server in a container/seccomp sandbox where these render
subprocesses have no network and a scratch-only filesystem.

---

### 🟡 L7 — Book-existence oracle on `PUT`/`DELETE` (fixed 2026-07-26)

**Found by the RBAC matrix** (`server/tests/rbac.rs`, plan 5 #46) the first time
it ran — which is the argument for that test in one sentence.

`GET`, `PATCH`, the cover and file endpoints all answered **404** to a caller
with no access, deliberately, so an unauthorised user can't discover which book
ids exist. `PUT /api/books/{id}` and `DELETE /api/books/{id}` did not: both
checked *permission* without first checking *visibility*, so an unrelated
account received **403** for a real id and 404 for a fake one — a working
existence oracle over the whole library. `PUT`'s message made it worse by
claiming the caller had "read-only access to this book", which they did not.

**Fixed** by checking `can_view()` first and returning 404, then the permission
check, in both handlers — the order every other handler already used. The matrix
now pins the behaviour for all seven actor kinds, so a future endpoint that gets
it wrong fails a test rather than shipping.

### 🟡 L8 — Secret-bearing paths in the request log (fixed 2026-07-26)

Introduced and fixed in the same session. The request logger added for plan 5
#37 wrote the full request path, and plan 5 #31's reset link is
`/reset/<token>` — so a live, single-use credential was being written into a
file that gets tailed, shipped to an operator, and pasted into bug reports.
Public share links (`/p/<token>`, `/api/public/<token>`) had the same shape.

This is L1's problem (a token in a URL reaching logs) reappearing through a new
door, which is the argument for treating "does this URL contain a secret?" as a
property of the route rather than of the query string.

**Fixed** by redacting the token segment before the path is logged
(`observability::redact_path`), keeping the request's shape — `/reset/<redacted>`
— because that is what the log is for. Unit-tested, and confirmed against a
running server.

## What's done well (🔵 Info)

These are genuine strengths worth preserving:

- **No SQL injection.** Every query uses sqlx bind parameters. The few `format!`
  interpolations build fixed table names or append a constant `AND … >= ?`
  fragment — the values are always bound, never interpolated.
- **Password storage.** Argon2 with per-hash salt; a precomputed dummy hash
  equalizes login/basic-auth timing so account existence doesn't leak; failed
  attempts are throttled.
- **Token hygiene.** 256-bit session tokens and 192-bit link tokens from
  `OsRng`; only their SHA-256 is stored (unique-indexed); logout deletes the
  session; expired sessions are swept; sliding 30-day expiry.
- **Upload validation.** Server-side magic-byte sniffing (`sniff`) is the source
  of truth for both book files and covers — a renamed file can't slip through,
  and the stored extension comes from the sniffed bytes.
- **Access control.** Resolved per request against owner/master/shares;
  "no access" and "not found" are indistinguishable, so book-id existence isn't
  leaked. Deletes require ownership; edits require editor.
- **CSRF.** All endpoints authenticate via the `Authorization` header (not
  cookies), so a cross-site page can't forge them; there is no query-string
  token shortcut (see L1).
- **Resource bounds.** The 2 GB body limit is scoped to just the two upload
  handlers (every other route keeps axum's small default); uploads stream to a
  temp file and are hashed/validated before commit (never buffered whole in
  RAM); render shell-outs are semaphore- and timeout-bounded; rate limiters are
  memory-capped.
- **No XSS found.** The web console (`esc()` applied at every HTML sink) and
  `public.html` consistently HTML-escape all user/book-derived data.
- **Error hygiene.** Internal errors are logged server-side and returned to the
  client as a generic "internal server error"; only developer-authored messages
  are surfaced.
- **Transport.** The app defaults new server URLs to `https://`, warns on plain
  `http://`, and does **not** bypass certificate validation anywhere.
- **Public share links.** Use-count is consumed atomically with a revalidating
  `UPDATE … WHERE <valid>`, so a one-time link can't be double-spent under
  concurrency; the file handle is opened before the use is consumed.

---

## Prioritized remediation checklist *(from the first audit — all now done)*

1. **H1** — Stop accepting/serving a client-controlled `cover_path`; restrict
   cover paths to server-generated `covers/<uuid>.<ext>`. *(highest priority)*
2. **M1** — Cap image decode dimensions and EPUB cover entry size.
3. **M2** — Validate server-supplied ids/formats as UUID/allow-list before using
   them as filesystem paths on the app side.
4. **M3** — Add a bootstrap secret and/or document register-before-expose.
5. **M4** — Wire `cargo audit` + `flutter pub outdated` into CI; plan
   `flutter_secure_storage` 9→10. *(`cargo audit` and `osv-scanner` both run in
   CI as of 2026-08-01; the latter covers Dart, Rust, Actions and Docker.)*
6. **L1–L6** — Address as defense-in-depth: security headers, per-IP login cap,
   keyring-unavailable warning, and sandboxing the PDF render subprocesses.

*Rounds 1–2 reflect the code at commit `b4fa85f`; round 3 at `2fb63f4`.*

---

# Second review — 2026-08-01

**Scope:** everything added since the first audit — the personal-data channel
(annotations, sittings, notes, profile photos), copy photos, the un-publish
endpoints, the shared duplicate check and the console import wizard, room
layouts and props, plus a re-read of the id → filesystem paths across the whole
server.

**Method:** manual source review, plus this time the automated scanning the
first audit could only recommend: `cargo audit` and `osv-scanner` both run in
CI, the latter covering the Flutter, Rust, GitHub Actions and Docker dependency
sets from one advisory database. Each finding below was **reproduced before
being fixed** — S1 by writing a file outside the data directory, S2 by timing a
request. Still no fuzzing.

## 🔴 S1 — Arbitrary file write outside the data directory

**Where:** any handler interpolating a path parameter into a path —
`covers/{id}.{ext}` in `blobs.rs`, `copy-photos/{id}` in `physical_copies.rs`.

**What.** Sync is id-driven: `PUT /books/{id}` creates a book under whatever id
the caller picks. axum percent-decodes a captured path segment, so
`..%2F..%2Fescaped` arrives at the handler as `../../escaped`. Creating a book
with that id and then uploading its cover wrote the file **outside the store** —
demonstrated landing at `/tmp/escaped.png` from a data directory two levels
below it. Any account with edit rights could write anywhere the server process
could write, which on a typical deployment includes the database itself.

This is the sibling of H1 from the first audit. H1 was the *body* field
(`cover_path`) and was fixed; the id in the *URL* reaches the same place and was
missed, because the two look nothing alike at the call site.

**Fixed** in `1f14fa5`, in two layers:

- `ids::reject_smuggled_separators`, middleware that runs before any handler and
  refuses a path segment whose percent-decoded form contains `/`, `\` or NUL, or
  is `.`/`..`. Wildcard routes are unaffected: their separators are real ones in
  the URL, not smuggled inside a segment.
- `ids::check`, a whitelist (`[A-Za-z0-9._-]`, 1–128 chars, not `.`/`..`) applied
  at every handler that accepts a client-chosen id, so nothing hostile reaches
  the database either.

`tests/path_safety.rs` pins the attack and that ordinary ids — uuids, `book-1`,
`A_book.2` — still work.

## 🟠 S2 — Unbounded quadratic work in the duplicate check

**Where:** `import_check.rs::check`.

**What.** `POST /api/import/check` accepted an unbounded `candidates` array and
compared each one against every visible book, with a Levenshtein distance in the
worst arm. Measured: **5,000 candidates against a 200-book library took 11.5
seconds** of CPU on an async worker, and it scales with both sides. Any member
could repeat it; no rate limit applied.

**Fixed** by capping a request at 1,000 rows — a real import batches anyway — and
by indexing the two *exact* signals (file hash, ISBN) into maps, so only the
fuzzy title arm still touches the whole library. The same 1,000-row batch now
answers in well under a second. `tests/import_check.rs` asserts both the refusal
and that a legitimate batch stays fast.

## 🟡 S3 — Duplicate check read every file hash on the server

**Where:** `import_check.rs::file_hashes_for`.

**What.** The query selected every row of `book_file` regardless of who could
see the book, ignoring the `ids` argument it was given. Not a disclosure as
written — the map is only ever indexed by a visible id — but it loaded other
accounts' file hashes into memory on every call, and was one careless edit away
from reporting a collision with somebody else's book.

**Fixed:** the query is now bound to the visible ids.

## 🟡 S4 — Tombstones keyed by id alone

**Where:** the `deletion` table, keyed by `book_id` since migration 0005.

**What.** The table grew a `kind` and came to hold tombstones for seven kinds of
thing, but kept a primary key that assumed an id could only be deleted once
across all of them. Every write site is an `INSERT OR REPLACE`/`ON CONFLICT`, so
a cross-kind collision would not error — it would silently overwrite the other
kind's tombstone and resurrect a deleted row on the next pull. Ids are UUIDs, so
nothing has collided in practice.

**Fixed** in migration 0025: rebuilt with `PRIMARY KEY (kind, entity_id)`. Wire
format unchanged. Verified against a copy of a live database.

## 🔴 S5 — Stored XSS in the admin console

> **This finding was first recorded as 🔵 informational and "accepted", on the
> reasoning that the interpolated values were all ids and ids are whitelisted.
> That was wrong.** The same handlers also interpolate *names*, *emails* and
> *URLs*, which are not whitelisted and are attacker-controlled. Re-rated 🔴 and
> fixed the same day. Recorded here rather than quietly edited, because
> "checked the ids and stopped looking" is the mistake worth remembering.

**Where:** `console.js`, 31 inline handlers of the form
`onclick="fn('${esc(value)}')"`.

**What.** That is a JavaScript string inside an HTML attribute, and an HTML
parser decodes character references in attribute values **before** the engine is
handed the source. `esc()` turns `'` into `&#39;`; the parser turns it back. So:

```
written:  onclick="shareRoom('l1','My room&#39;+alert(document.domain)+&#39;')"
executed: shareRoom('l1','My room'+alert(document.domain)+'')
```

**Reachable by any member.** `layouts::publish` checks only that a room name is
non-empty, and a member may publish rooms. The console's *Rooms* screen renders
every published room's name into that handler, so a member could name a room

```
My room'+alert(document.domain)+'
```

and have it execute in the **master's** session the next time they opened the
list — with the master's token in `sessionStorage`, and every admin action
available to it. Confirmed end to end against a running server: the API accepts
the name and returns it verbatim.

Saved-view names and user emails reach the same context through
`applyView`/`deleteView`, `resetFor` and `removePerson`. The view-name sites even
carried a second `.replace(/'/g,"&#39;")` on top of `esc()`, which does nothing —
the character was already escaped, and it is the *decoding* that undoes it.

**Fixed** by removing the nested context rather than escaping for it. Every
handler is now a `data-` attribute read through `dataset`, dispatched from three
delegated listeners (`ACTIONS`, `DBL_ACTIONS`, `CHANGE_ACTIONS`). A data
attribute is plain text: escaped once as HTML, never parsed as code.

Escaping correctly for the nested case is possible, and is a trap — it has to be
right at every call site, forever, and the failure is silent. `web/tests/
import_parse.test.js` now fails the build on any `on*=` handler containing an
interpolation; the guard was verified by reintroducing one.

## Positive controls confirmed this round

- **The personal-data channel is scoped by `user_id` from the token
  everywhere**, including the separate `/annotations/deletions` endpoint added
  after P1. A shared library holds several people's highlights in the same book
  without any of them seeing the others'.
- **Un-publish (`DELETE /api/mine/{resource}`) is scoped to the caller in every
  case** — library data through the books they own, personal data by `user_id` —
  and the master is deliberately *not* treated as owning everything, so
  "forget my loans" from the master account means theirs. Pinned by tests that
  seed two accounts and assert the other's rows survive.
- **The duplicate check does not report a collision in a book the caller cannot
  see**, which would disclose both its existence and its title.
- **The console import wizard escapes every field it renders** (title, authors,
  file name, and the matched book's title) — and, since S5, renders them as text
  and data attributes only, never into a handler.
- **The import wizard's file uploads go through the existing magic-byte check**,
  so a renamed executable is refused as it always was.
- **Bearer tokens, not cookies**, so none of these state-changing endpoints is
  CSRF-reachable.

## Still not done

- **No fuzzing** of the upload and parse paths (EPUB zip, PDF, images). This
  remains the largest untested surface and the recommendation carries over.
- **No dynamic testing** against a running server beyond the reproductions above
  and the end-to-end sync test in CI.
- **The PDF render shell-outs** (`gs`, `mutool`, `pdftoppm`) are bounded by a
  timeout and a semaphore but are not sandboxed. Unchanged since L6.
- **`spin` 0.9.8 is yanked** and reachable only as a transitive dependency;
  `cargo audit` reports it as a warning. No action available until upstream
  moves.

## What this round says about the method

Three of the five findings were in code written since the first audit, and two
of those (S2, S3) were written the same week they were found. S5 was worse: it
was *seen*, rated informational, and waved through on an argument that only
covered a third of the affected call sites.

The reviewer being the code's author is the limitation behind all of that. It is
why the fuzzing recommendation below keeps repeating rather than being closed,
and why anyone reading this should treat "reviewed" as meaning "read carefully
by one interested party", not "assured".

*This round reflects the code at commit `1ec3fc3` on `main`. As before: a
best-effort manual review by the same author as the code, which is a real
limitation and the reason the fuzzing recommendation keeps repeating.*
