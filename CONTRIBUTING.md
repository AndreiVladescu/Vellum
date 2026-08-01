# Contributing

Thanks for looking. This is a personal project that turned out well enough to
publish, so the honest framing first: **it is not looking for large
contributions**, and a big pull request that arrives unannounced is likely to
sit unmerged. Small fixes, bug reports and questions are genuinely welcome.

## The one thing worth reading first

**Most of this code was written by an LLM** (Claude), directed and reviewed by a
human. That matters for two reasons:

- The comments explain *why*, often at length, because the reasoning is the part
  that is hard to recover later. If you change a decision, change the comment
  that argues for it — a stale rationale is worse than none.
- It has never had many pairs of eyes on it. If something looks wrong, it may
  simply be wrong. Say so.

## Reporting a bug

Include:

- what you did, what happened, and what you expected instead
- your platform and how you got Vellum (release download, or built from source)
- whether the optional server is involved
- anything from the console if the app printed an error

A bug you can reproduce from a clean library is worth ten that need your exact
data. If it only happens with your data, say that too — that is a useful fact,
not a disqualification.

**Do not paste your library database or book files into an issue.** They contain
your reading history, and possibly other people's names from loans.

## Security

Please **do not open a public issue** for anything that looks exploitable —
authentication, file paths, share links, anything reachable over the network.
Email <avladescu2000@gmail.com> instead and give it a few days before saying
anything publicly.

What has been reviewed, and what has not, is written down in
[docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md). It is honest about the gaps.

## Making a change

[DEVELOPER.md](DEVELOPER.md) covers getting it building on every platform.
Before opening a pull request:

```sh
cd app     && flutter analyze && flutter test && ./tool/check_l10n.sh
cd ../server && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
```

CI runs all of that plus codegen-freshness checks, an end-to-end test against a
real server, a vulnerability scan and a Docker build. It is worth running the
above locally first — several of those checks fail for reasons that are obvious
on your machine and cryptic in a CI log.

### Things that will be asked of a pull request

**Tests that would have failed before the fix.** Not coverage for its own sake —
a test that pins the specific thing that was wrong. Most of the test files here
open with a comment saying which bug they exist to prevent; that is the shape.

**One thing per pull request.** A fix and a refactor together are two reviews
wearing one coat.

**The schema is defined twice** — drift tables in `app/lib/data/database.dart`
and SQL migrations in `server/migrations/`. If you touch one you almost
certainly touch the other, plus a drift migration, a `schemaVersion` bump and a
schema snapshot. [DEVELOPER.md](DEVELOPER.md#changing-the-schema) has the exact
commands, including the two traps that have already bitten this project:
`ALTER TABLE ... DEFAULT (expr)` fails only on a database with rows in it, and
an already-applied migration must never be edited.

**Committed generated code.** `database.g.dart` and the localisation output are
in the repository so they are reviewable. Regenerate them rather than editing
them, and commit the result — CI fails if they are stale.

**Comments in the existing register.** Explain the reasoning and the discarded
alternative, not the syntax. If a line is subtle, the comment should say what
goes wrong without it.

## Licence

Vellum is AGPL-3.0. By contributing you agree your work is licensed the same
way. If you host a modified version for other people, the licence requires you
to make your changes available to them — that is the point of it, not an
oversight.
