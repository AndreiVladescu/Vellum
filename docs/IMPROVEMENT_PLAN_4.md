# Improvement plan 4

Follow-up to [`IMPROVEMENT_PLAN_3.md`](IMPROVEMENT_PLAN_3.md) (all 16 tasks
landed) and the July 2026 platform round: **opt-in server TLS with self-signed
cert generation**, **certificate import/pinning in the app**, the **Android
project made build-ready** (adaptive icon, scoped backup rules, R8/resource
shrinking, `minSdk` pin, HTTPS-only network config), the refined **logo**, and
the **"Vellum"** window/label capitalisation. This plan is a fresh review of the
codebase as it stands after that work.

Same ground rules as before:

- Read `CLAUDE.md` and `DESIGN.md` first. Schema changes = drift `schemaVersion`
  bump + idempotent drift migration + **new** SQL migration (only when the
  column/table is synced!) + build_runner rerun + update
  `server/tests/schema_parity.rs` when a synced table changes. App-local-only
  columns (reading state, `readerNotes`, `sourceMetadata`, `needsPush`,
  `coverEtag`) get **no** server migration.
- After every task: `cargo test && cargo clippy --all-targets -- -D warnings`
  and `cargo fmt --check` in `server/`; `flutter analyze && flutter test` in
  `app/`. After a server migration, `touch server/src/lib.rs` so `migrate!()`
  re-embeds.
- One cohesive feature per commit, short title, optional succinct bullets, no
  Co-Authored-By.

**Standing decisions — do not revisit:** conflict handling stays row-level LWW
(field-level merge was rejected; see DESIGN.md). Android is now *active*, not
deferred.

Items are grouped by theme and ordered by severity within each group.
**§A is correctness/data-safety — do those first.** §B (accessibility) is the
biggest single quality gap and is newly urgent now that Android/TalkBack is in
scope. The rest can be cherry-picked.

---

## A. Correctness & data safety

### 1. A rotated server certificate fails sync with an opaque error

**Problem.** `clientTrusting` (`app/lib/server/cert_trust.dart`) pins the
imported certificate by SHA-256. Certs never expire (rcgen generates them valid
1975–4096), but if the user **regenerates** the server cert — deletes
`cert.pem`, adds a SAN via `VELLUM_TLS_SANS`, moves to a new machine — the
pinned copy no longer matches and every request fails with a bare
`HandshakeException`. `_run` (`server_page.dart:86-87`) renders that as
"Could not reach the server.\n<exception>", which gives the user no idea the
fix is *re-import the certificate*.

**Change.** In `_run`, detect `HandshakeException` (and `TlsException`) before
the generic catch and set a specific message: "The server's certificate isn't
trusted or has changed — import it below." When disconnected, that message
already sits next to the Import control; when connected, add an **Import /
update certificate** row to `_buildConnected` too (currently cert import only
exists on the sign-in screen). Show the trusted cert's short fingerprint there
so a changed cert is visible.

**Commit:** `App: clear message + re-import path when the server cert changes`

### 2. `http://` on Android fails silently with no guidance

**Problem.** The network config (`network_security_config.xml`) blocks cleartext
except loopback, and the app still lets the user type an `http://` URL (with the
existing red warning). On Android a real-LAN `http://` server now fails at
connect with a generic socket error — the warning says "insecure", not
"won't work on this device".

**Change.** When `Theme.of(context).platform == android` **and** the normalised
URL is `http://` and not a loopback host, upgrade the warning to an error state
and disable Log in, with copy pointing at the server's `VELLUM_TLS=1` option.
Purely a UI guard; no networking change.

**Commit:** `App: block non-loopback http on Android with a clear reason`

### 3. Backup archive can't be taken off an Android device

**Problem.** `BackupService` (`app/lib/data/backup_service.dart`) writes the
`.zip` into `getApplicationDocumentsDirectory()` — private app storage the user
can't reach on Android. On desktop the file is browsable; on a phone the backup
is effectively trapped, and restore has no way to reach a file outside the
sandbox either.

**Change.** After writing the archive, on touch platforms hand it to the system
share sheet / "save to Downloads" (add `share_plus` or use `file_selector`'s
`getSaveLocation`). For restore, the existing `openFile` picker already reaches
SAF — verify it copies the picked file in (Android hands back a cached path).
Keep the desktop path unchanged.

**Commit:** `Backup: export/import the archive via the system picker on mobile`

---

## B. Accessibility (screen readers, focus, targets)

There is **no `Semantics`, `semanticLabel`, or `ExcludeSemantics` anywhere in
`app/lib`.** On desktop that mostly degrades to control defaults; on Android,
TalkBack will read the visual bookshelf as an unlabelled pile of images and the
icon-only buttons as nothing useful. This is the app's largest quality gap.

### 4. Label the book spines and cover thumbnails

**Problem.** `SpineFace`/`BookSpine` and `CoverThumb` are `Image`/`CustomPaint`
widgets with no semantics, so a screen reader announces "image" (or silence) for
every book.

**Change.** Wrap each spine/cover in `Semantics(label: '<title> by <authors>',
button: true, ...)` and mark the decorative generated-spine art
`ExcludeSemantics`. One helper (`bookSemanticLabel(book)`) shared by shelf and
detail.

**Commit:** `A11y: semantic labels for book spines and covers`

### 5. Label icon-only controls and the shelf as a list

**Problem.** The search field's leading icon, the filter icon
(`main.dart` app bar), the FAB, drawer entries, and the physical-editor toolbar
are icon-only. `Tooltip` gives desktop hover text but not always a semantic
label; several have neither.

**Change.** Add `tooltip:`/`semanticLabel:` to every `IconButton`/`FloatingActionButton`,
give the shelf `ListView` a container semantics, and confirm the bottom nav
items read their labels. Audit tap targets are ≥48dp on touch (the genre/filter
chips especially).

**Commit:** `A11y: labels for icon controls + minimum tap targets`

### 6. Focus traversal + large-text layout pass

**Problem.** Keyboard/switch focus order is whatever widget order produces, and
no screen has been checked at `textScaleFactor` 1.5–2.0 (common on phones).

**Change.** Add `FocusTraversalGroup` where order is non-obvious (the two-pane
detail, the toolbars) and do a quick pass at large text, wrapping the few fixed
`Text` rows that would clip in `Flexible`/`FittedBox`. Verify with
`flutter run` + the accessibility inspector.

**Commit:** `A11y: focus order and large-text layout fixes`

---

## C. Security hardening (open SECURITY_AUDIT items)

`docs/SECURITY_AUDIT.md` still lists four 🟡 low-severity **Open** items. None
are urgent for a single-user LAN deployment, but they're cheap to close.

### 7. L1 — session token travels in the URL query

**Problem.** Public-link and some auth flows carry `?token=` in the URL
(`server/src/auth.rs`), which lands in proxy logs and browser history.

**Change.** Accept the token from an `Authorization: Bearer`/POST body on those
routes and stop reading it from the query string (keep query as a deprecated
fallback for one release if public links already exist in the wild).

**Commit:** `server: stop carrying the session token in the URL`

### 8. L5 — basic-auth cache stores unsalted SHA-256 of passwords

**Problem.** `BasicAuthCache` (`server/src/auth.rs`) keys on an unsalted
SHA-256 of the password so OPDS Basic auth avoids an Argon2 verify per request.
An attacker with a memory dump gets offline-crackable hashes.

**Change.** Key the cache on an HMAC of the password under a random
process-startup key (or the first 16 bytes of an HKDF), so the cached value is
useless outside the running process. Behaviour unchanged.

**Commit:** `server: salt the basic-auth verification cache`

### 9. L6 — untrusted-PDF cover render shells out

**Problem.** Cover extraction falls back to `gs`/`mutool`/`pdftoppm`
(`server/src/blobs.rs`; bounded by `render_semaphore`) on attacker-supplied
PDFs — a parser-exploit surface running as the server user.

**Change.** Run the shell-out under a timeout + resource caps
(`ulimit`/`setrlimit` via a small wrapper, or `-dSAFER` for Ghostscript which is
already the safe default; confirm it's set), and prefer the pure-Rust `lopdf`
path. Document the residual risk if the tools remain optional.

**Commit:** `server: sandbox the PDF-cover shell-out`

### 10. L2 — plaintext token fallback when no keyring

**Problem.** `connection_store.dart` falls back to storing the session token in
plaintext `SharedPreferences` when the secure store is unavailable. Silent, so
the user never knows their token is unprotected.

**Change.** When the fallback path is taken, surface a one-time notice on the
server page ("Secure storage unavailable — the session token is stored
unencrypted on this device"). No behaviour change; just honesty. (Android's
Keystore is always available, so this is desktop-only in practice.)

**Commit:** `App: warn when the session token can't be stored securely`

---

## D. Android → shippable

Config/policy work to turn "builds a debug APK" into "installable release".
See the `android-readiness` memory. **No on-device test was possible in the dev
environment (`/dev/kvm` absent) — each of these needs a real device/emulator
smoke test.**

### 11. Release signing scaffold

**Problem.** `build.gradle.kts` signs release with the **debug** key ("Replace
with a real keystore"). Unshippable and non-updatable.

**Change.** Wire the standard `key.properties` flow: read a gitignored
`android/key.properties`, define a `release` `signingConfig` from it, fall back
to debug signing when the file is absent (so `flutter run --release` still
works on a fresh checkout). Document the `keytool` command; **do not** commit a
keystore.

**Commit:** `android: release signing from key.properties (debug fallback)`

### 12. App bundle + per-ABI size

**Problem.** The release APK is an 87 MB fat binary (arm64 + armeabi-v7a +
x86_64 + libpdfium + libsqlite3). A single install ships two unused ABIs.

**Change.** Document/add `flutter build appbundle` as the distribution artifact
(Play delivers per-ABI, ~30 MB), and add an `--split-per-abi` note for sideload
APKs. Optionally set `ndk.debugSymbolLevel = "SYMBOL_TABLE"` for smaller native
symbols. Add the Android build to CI alongside the existing Linux step.

**Commit:** `android: app-bundle build + CI, per-ABI docs`

### 13. Edge-to-edge + predictive-back verification

**Problem.** `enableOnBackInvokedCallback` is set but the predictive-back
animation and Android 15 edge-to-edge (targetSdk 35+) haven't been verified;
content may draw under the status/nav bars without a `SafeArea` audit.

**Change.** Set `SystemUiMode.edgeToEdge` in `main()`, audit that each
`Scaffold` body honours insets (`SafeArea` where needed), and smoke-test
predictive back on a device.

**Commit:** `android: edge-to-edge + predictive-back polish`

### 14. Open-with import (SEND/VIEW intent)

**Problem.** On a phone, opening a PDF/EPUB from a file manager or email can't
target Vellum — the most natural mobile import path is missing.

**Change.** Add an intent-filter for `VIEW`/`SEND` of `application/pdf` +
`application/epub+zip`, and handle the incoming content URI (e.g.
`receive_sharing_intent`) by routing it into the existing `_acceptFile` flow.
A feature, not a config tweak — scope it on its own.

**Commit:** `android: import a PDF/EPUB opened/shared from another app`

---

## E. Reader & interaction polish (from BACKLOG)

### 15. Save in-chapter scroll position in the EPUB reader

**Problem.** `epub_reader_page.dart` resumes by chapter (`lastReadPage` =
chapter index) but not scroll offset within the chapter — reopening a long
chapter jumps to its top.

**Change.** Persist a per-book scroll fraction (a new **app-local-only** column,
so no server migration) and restore it after the chapter's HTML lays out. Keep
chapter resume as the coarse anchor.

**Commit:** `Reader: remember scroll position within an EPUB chapter`

### 16. Books ride their shelf when it moves

**Problem.** Moving a shelf in the physical editor leaves its books behind
(BACKLOG "books riding shelves"); an occupied shelf is currently pinned against
dragging to hide the issue.

**Change.** When a shelf drag commits, translate every `book_placement` whose
position sits on that shelf by the same delta, and drop the occupied-shelf drag
lock. Clamp to shelf bounds while here (BACKLOG "settle bounds").

**Commit:** `Physical: books move with their shelf; clamp to bounds`

### 17. Honour the spine-artwork preference in the physical view

**Problem.** The physical editor always draws cover-slice spines; the
`SpineArt` preference (generated dominant-colour spine) is ignored there, so the
two views can disagree.

**Change.** Thread the preference into the physical `SpineFace` render path the
same way the shelf does.

**Commit:** `Physical: respect the spine-artwork preference`

---

## F. Performance & scale

### 18. Verify large-library shelf/scroll cost

**Problem.** The shelf uses `ListView.builder` (good), but each spine decodes a
cover slice and the dominant-colour backfill runs at startup. On a large library
(1000+ books) on a phone, decode churn and the backfill pass could jank.

**Change.** Confirm `cacheWidth`/`cacheHeight` are set on every cover
`Image.file` (detail already does), cap the startup backfill to a bounded batch
per frame, and profile a synthetic 1000-book library with the performance
overlay on a mid-range device. Add whatever `RepaintBoundary`/decode-budget
fixes the profile shows.

**Commit:** `Perf: bound cover decode + colour backfill for large libraries`

---

## G. Future patches (deferred — not this round)

### 19. Transactional email (SMTP), then password reset & invites

**Goal.** Let the server send email so it can support **password reset** ("forgot
password" → emailed reset link) and **member invites** (master emails a join
link instead of hand-creating accounts + sharing a password out of band).

**Plan (in order):**
1. **SMTP plumbing first.** Add an opt-in mailer configured by env
   (`VELLUM_SMTP_HOST/PORT/USER/PASS`, `VELLUM_MAIL_FROM`), disabled by default so
   the LAN/local-first story is unchanged. A Gmail setup works via
   `smtp.gmail.com:587` + a **Google App Password** (not the account password;
   requires 2FA) — document that. Use a maintained Rust SMTP crate (e.g.
   `lettre`, async + STARTTLS/`rustls`, reusing our ring provider). Health-check
   the config on boot and log clearly when mail is off.
2. **Password reset.** `POST /api/auth/forgot` issues a single-use, short-TTL
   token (store only its hash, like sessions), emails `${PUBLIC_URL}/reset/<tok>`;
   `POST /api/auth/reset` consumes it and sets a new Argon2 hash. Always answer
   "if that email exists, a link was sent" (no account-existence leak); throttle
   per email + IP like login. A minimal `reset.html` page in `web/`.
3. **Invites.** Master-only `POST /api/invites` (scope like a share) mints a
   token, emails a join link; the app/console redeems it to register the member
   and apply the grant. Reuses the token pattern above.

**Notes.** Email is a new outbound-network + secret surface — keep it strictly
opt-in, never log credentials or tokens, and treat SMTP creds like the DB path
(env only). App-side: a "Forgot password?" link on the sign-in screen and an
"Invite member" action in the sharing page. **Deferred to a later patch.**

**Commits (later):** `server: opt-in SMTP mailer`, then
`server+app: password reset by email`, then `server+app: emailed member invites`

---

## Suggested order

1. **§A 1–3** (correctness: cert-rotation UX, Android http guard, mobile backup).
2. **§B 4–6** (accessibility — do before any store release; TalkBack is a review
   criterion).
3. **§D 11–13** (release signing, app bundle, edge-to-edge — the gate to
   shipping), interleaved with a real-device pass.
4. **§C 7–10**, **§E 15–17**, **§F 18** as cherry-picks.

§D 14 (open-with) and §E items are user-facing niceties; schedule them after the
release gate is clear.
