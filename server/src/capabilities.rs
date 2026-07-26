//! `GET /api/capabilities` (plan 5 #6) — an unauthenticated, cheap-to-compute
//! handshake so the app can learn what a server actually supports before (or
//! instead of) discovering it via 404s. A phone that hasn't updated in months
//! can end up talking to a rebuilt server; this is how it finds out.

use axum::Json;
use serde::Serialize;

/// The sync protocol's *shape* version — bump only for a breaking response
/// change (a field renamed or removed, a new one that's required), not for a
/// purely-additive one (older clients already ignore fields they don't know).
/// Nothing has ever advertised a protocol number before this, so there is no
/// prior "1" to be newer than — start here, not at the plan's illustrative 2.
const SYNC_PROTOCOL: u32 = 1;

#[derive(Serialize)]
pub struct Capabilities {
    pub server_version: &'static str,
    pub sync_protocol: u32,
    pub features: Vec<&'static str>,
}

/// Built from routes that actually exist in `lib.rs`, not from the plan's
/// example list — a capability handshake that claims a feature no route
/// backs is worse than not having one. Notably absent, and why:
/// - `content_search`: the FTS5 search index (plan 5 #2) is app-local only,
///   no server-side equivalent exists.
/// - `mail`: SMTP/password-reset is planned (docs/BACKLOG.md) but not built.
///
/// `shelf_sync`, `copy_sync`, `loan_sync` (plan 5 #4), and `batch_push`
/// (plan 5 #7) are the entries that became true after this handshake
/// shipped, exactly as its original commit predicted: shelves, physical
/// copies, and loan history all sync (`shelves.rs`, `physical_copies.rs`,
/// `loans.rs`), and `POST /books:batch` (`books::batch_upsert`) lets a large
/// first push skip one round trip per book.
///
/// `reading_progress` (plan 5 #5) is the subtle one: it advertises the
/// *separate, opt-in, per-device* channel in `reading.rs`, and emphatically
/// **not** reading state on the book row — that stays app-local-only, off the
/// LWW clock, and absent from `book`'s columns and payload (migration 0006,
/// CLAUDE.md, and the `book_upsert_ignores_reading_state` test that pins it).
const FEATURES: &[&str] = &[
    "delta_pull",
    "deletions",
    "groups",
    "shares",
    "share_links",
    "opds",
    "shelf_sync",
    "copy_sync",
    "loan_sync",
    "batch_push",
    "reading_progress",
];

pub async fn get() -> Json<Capabilities> {
    Json(Capabilities {
        server_version: env!("CARGO_PKG_VERSION"),
        sync_protocol: SYNC_PROTOCOL,
        features: FEATURES.to_vec(),
    })
}
