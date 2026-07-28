# Improvement plan 6 — what stands between this and a v1

Follow-up to [`IMPROVEMENT_PLAN_5.md`](IMPROVEMENT_PLAN_5.md). Written 2026-07-28
against `main` @ `521f95e`, after plan 5 landed in full and personal-data sync
(annotations, sittings, private notes, profile) went in.

Plan 5 was forward-looking: structure first, then features. This one is short
and remedial. It is the answer to a single question — *what would actually bite
someone who downloaded this and called it version one?* — so every item here is
either something a user cannot do at all, something they cannot get, or
something that is now inconsistent with the rest of the app.

**Not in scope:** other languages. The ARB scaffolding and ICU plurals from
plan 5 #38 stay as they are; English-only is a deliberate v1 position, not an
oversight.

**Removed after checking:** "split `LibraryRepository`" appeared in earlier
notes as an open item. It isn't — plan 5 #10 did it (`7ca1f90`, `cf7c695`) and
the file is 382 lines of facade over thirteen services. The stale text lives in
plan 5's problem statement, which describes the code as it was in July.

## The items

**All six are done** (2026-07-28). Commits listed so "still true?" is answerable
from `git log`.

| # | Item | Why it blocked v1 | Commit |
|---|---|---|---|
| 1 | **The People screen** | You cannot add a second user without `curl` | `ba5bedc` |
| 2 | **Desktop release artifacts** | Every desktop user must install a C++ toolchain first | `2fb63f4` |
| 3 | **Audit the personal-data endpoints** | New attack surface, reviewed only by its author | `878d71b` |
| 4 | **Copy photos sync** | The last personal thing stranded on one device | `461a7cc` |
| 5 | **Reconcile the local profile with the account** | Two identities, no relationship, silent resolution | `0b59470` |
| 6 | **Last-write-wins leaves no trace** | An overwritten edit is invisible | `0b59470` |

Two findings came out of #3, both fixed and both reproduced against a running
server before the fix: annotation tombstones were readable by every account
through the unscoped `/deletions` list, and the avatar upload's stated 4 MB cap
could never fire behind axum's 2 MB default. See `docs/SECURITY_AUDIT.md`
round 3.

What #4 turned out to be worth deciding rather than assuming: copy photos are
**library** data, not personal — they hang off a copy, which already syncs, and
are visible to whoever the book is shared with. The UI now says so where photos
are added, because a photo of a copy is often a photo of a room.

---

## 1. The People screen

**The problem.** `POST /api/users` is master-only and has no interface. The web
console shows an "Accounts" number on the dashboard and nothing else; the app
has no user screen at all. So everything the server exists for — sharing,
groups, roles, per-book links, borrow requests — is gated behind an account that
can only be created by hand-crafting an authenticated HTTP request. A
multi-user server whose *second user* cannot be created through any interface is
not a v1.

**What to build.** A People section in the console (`server/web/console.js`),
master-only, listing every account with its role. Per row: promote/demote,
remove, and send a password reset. Plus "Add someone", which should prefer the
**invite** path that already exists (`migrations/0015_invites.sql`,
`server/src/auth.rs`) over setting someone else's password — an invite lets them
choose their own, and never puts a password the admin knows in the database.

**Endpoints.** `GET /users` and `POST /users` exist. Missing: change role,
remove an account, and list/revoke pending invites. Removing an account must say
what happens to what they own — the `ON DELETE CASCADE` on `app_user` takes
their shares, sessions, annotations, sittings and notes with them, and the
screen has to say so before it happens rather than after.

**Not the app.** Deliberately console-only for now. Administering a shared
library is a desk job, and duplicating it into the Flutter app doubles the
surface for a screen most people open twice.

## 2. Desktop release artifacts

**The problem.** `release.yml` builds server binaries for four targets and
Android AABs/APKs on tag. It builds nothing for Linux, Windows or macOS, so the
README's install instructions are "install Flutter, install a C++ toolchain,
build from source". That is fine for a contributor and wrong for a user.

**What to build.** Add desktop jobs to the release workflow: `flutter build
linux/windows/macos --release`, packaged per platform (a tarball for Linux
keeping the `bundle` layout intact — the executable needs `lib/` and `data/`
beside it — a zip for Windows, a zip of the `.app` for macOS), with
`SHA256SUMS`, attached to the tagged release next to the server binaries.

**Honesty about signing.** macOS builds will be unsigned and unnotarized, and
Windows builds unsigned; both will warn on first launch. Say so in the release
notes rather than letting people discover it. Code signing needs certificates
that cost money and belong to a person, not a repository.

## 3. Audit the personal-data endpoints

**The problem.** `docs/SECURITY_AUDIT.md` reflects commit `b4fa85f`. Since then
`server/src/personal.rs` added eight endpoints, three user-scoped tables and a
new file-write path (avatar upload). It was written to the same rules as
`reading.rs` and its isolation between accounts is tested — but "the author
tested it" is not a review.

**What to check, specifically.**

- The avatar write: the path is `avatars/<user id>` from the *token*, not from
  input, so traversal shouldn't be reachable — confirm that, and confirm the
  4 MB cap and magic-byte sniff can't be walked past with a crafted file.
- Every list query filters on `user.id` **and** joins `access_predicate()`.
  A missing join means a book that stops being shared keeps leaking rows.
- The annotation upsert's `WHERE annotation.user_id = ?` on the update half —
  the thing that stops one account overwriting another's row by id.
- Decompression/pixel-bomb parity with M1: the avatar is stored, not decoded,
  server-side. Confirm nothing later decodes it unbounded.

Then update the audit document with the findings and the commit it reflects.

## 4. Copy photos sync

**The problem.** After personal-data sync, highlights, sittings, private notes
and your profile photo all follow the account. Photos of your shelves — taken
in the physical view, stored in `photos/` — still do not. They are now the only
personal thing stranded on one device, which reads as an oversight rather than
a decision.

**What to build.** They are per-copy, not per-user, and physical copies already
sync (plan 5 #4). So this is the *blob* pattern, not the personal one: a
`copy_photo` table alongside `physical_copy`, with the bytes going through the
existing blob upload/download path that covers and book files use.

**The question to settle first.** A copy photo can show a room. A shared library
means someone else sees it. Covers and files are already shared that way, so the
consistent answer is "it syncs with the copy", but it deserves a sentence in the
UI where photos are added rather than being discovered later.

## 5. Reconcile the local profile with the account

**The problem.** `UserProfileStore` (name, email, photo, on this device) and the
server account (`app_user`) are unrelated. You can be "Ana" locally and signed
in as `bob@example.com`, and nothing says so. Since personal sync landed, the
first sync silently resolves the difference by whichever timestamp is newer —
which will surprise someone exactly once, and the surprise is their name and
face changing.

**What to build.** On connect, if the local profile has a name and it differs
from the account's, ask which to keep — the same shape as the existing
"Resume where you left off?" prompt, which is the app's established answer to
"two truths, don't guess". After that the newest-wins rule is fine, because the
two are known to be the same person.

Show the account's email under the name in the drawer when connected, so the
identity you are syncing as is visible without opening a screen.

## 6. Last-write-wins leaves no trace

**The problem.** Two devices edit a book offline; the later `updated_at` wins
and the other edit is gone with no record. Field-level merge was considered and
rejected in plan 3 for good reasons and is not being reopened. But *silence* is
a separate choice from *last-write-wins*, and it is the one worth revisiting: at
present nothing anywhere says an edit was discarded.

**What to build.** When a pull replaces a book that had local changes pending
(`needsPush` set) with a newer server version, record it as a sync issue — the
mechanism already exists and already surfaces in the sync report. The message
should name the book and say the local edit was replaced by a newer one from
elsewhere. No new UI, no conflict resolution, no merge: just stop being silent.

---

## Order

1. **The People screen** — the only item that makes an existing headline
   feature usable rather than making a working one better.
2. **Desktop artifacts** — the difference between a product and a source tree.
3. **The audit pass** — before, not after, anyone is invited to the server.
4. **5, 6, 4** — smaller, independent, and each removes a silent surprise.
