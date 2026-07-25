# Vellum — Security Audit

**Date:** 2026-07-11
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
| L2 | 🟡 | Open | Session token plaintext fallback when no OS keyring | `app/lib/server/connection_store.dart` |
| L3 | 🟡 | ✅ Fixed (2026-07-11) | Missing HTTP security headers (CSP, nosniff, frame-options) | `server/src/lib.rs` |
| L4 | 🟡 | ✅ Fixed (2026-07-11) | Login throttle keyed by email only (no per-IP cap) | `server/src/throttle.rs`, `auth.rs` |
| L5 | 🟡 | Open | Basic-auth cache holds unsalted SHA-256 of passwords in memory | `server/src/auth.rs` |
| L6 | 🟡 | Open | Untrusted-PDF cover render shells out to `gs`/`mutool`/`pdftoppm` | `server/src/blobs.rs` |

> **Remediation note (2026-07-11):** H1, M1, M2 (destructive, low-effort) plus a
> second round — M3 (opt-in), M4, L3, L4 — have been hardened (see the ✅ notes in
> each section). Still open: M4's `flutter_secure_storage` major upgrade, and
> L1, L2, L5, L6.

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
on a headless Linux box without a keyring the token sits in cleartext. Consider
warning the user when the secure store is unavailable, or refusing to persist.

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

`BasicAuthCache` stores `sha256(password)` (unsalted) with a 5-minute TTL to
avoid an Argon2 verify on every OPDS request. The threat it addresses (Argon2
CPU amplification) is real and the value is a short-lived in-memory SHA-256 of a
high-entropy secret, so this is acceptable and documented — noted only for
completeness. Keep the TTL short.

### 🟡 L6 — Untrusted-PDF cover render shells out to external tools

`render_first_page` invokes `pdftoppm`/`pdftocairo`/`mutool`/`gs` on uploaded
PDFs. This is well-contained: a 30 s `timeout` with `kill_on_drop`, a
concurrency semaphore (2), Ghostscript run with `-dSAFER`, and panic isolation
via `spawn_blocking`. The residual risk is parsing attacker-controlled PDFs in a
third-party binary (historically a rich bug source, esp. Ghostscript). Keep
those host tools patched, or run the server in a container/seccomp sandbox where
these render subprocesses have no network and a scratch-only filesystem.

---

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

## Prioritized remediation checklist

1. **H1** — Stop accepting/serving a client-controlled `cover_path`; restrict
   cover paths to server-generated `covers/<uuid>.<ext>`. *(highest priority)*
2. **M1** — Cap image decode dimensions and EPUB cover entry size.
3. **M2** — Validate server-supplied ids/formats as UUID/allow-list before using
   them as filesystem paths on the app side.
4. **M3** — Add a bootstrap secret and/or document register-before-expose.
5. **M4** — Wire `cargo audit` + `flutter pub outdated` into CI; plan
   `flutter_secure_storage` 9→10.
6. **L1–L6** — Address as defense-in-depth: security headers, per-IP login cap,
   keyring-unavailable warning, and sandboxing the PDF render subprocesses.

*This audit reflects the code at commit `b4fa85f` (branch `main`). It is a
best-effort manual review, not a guarantee of completeness; a follow-up with
`cargo audit`, dependency scanning, and fuzzing of the upload/parse paths is
recommended.*
