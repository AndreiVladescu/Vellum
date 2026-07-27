//! Live sync hints over Server-Sent Events (plan 5 #8).
//!
//! **SSE, not WebSocket.** One-way server→client is all this needs; SSE rides
//! plain HTTP/1.1 through every reverse proxy with no upgrade dance, reconnects
//! natively, and axum has it built in. A WebSocket would add a second protocol
//! for no gain.
//!
//! **Hints, not data.** An event carries an id and an operation, never a book.
//! That is what keeps this from becoming a second sync path with its own
//! conflict rules: a client that hears "book X changed" runs the *existing*
//! delta pull, so row-level LWW stays the single conflict model and there is no
//! new merge logic anywhere. It also means an event is cheap enough to fan out
//! and harmless to miss — losing one costs a slightly later pull, not data.
//!
//! **Never broadcast an id the subscriber cannot see.** Fan-out is global (one
//! `broadcast` channel), but every event is filtered through `access.rs` per
//! subscriber before it goes out. Without that, the stream would be an
//! existence oracle over the whole library — exactly the hole #46's RBAC matrix
//! found in `books.rs`.

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::State;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures_util::stream::Stream;
use serde::Serialize;
use tokio::sync::broadcast;

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;

/// How many events a slow subscriber may fall behind before it is dropped.
///
/// Bounded on purpose: a client that cannot keep up with invalidation hints is
/// better off reconnecting and doing one full delta pull than being buffered
/// indefinitely by a server that has real work to do.
const CHANNEL_CAPACITY: usize = 256;

/// What changed. The client turns any of these into "pull soon".
#[derive(Clone, Debug, Serialize)]
pub struct ChangeEvent {
    /// `book`, `shelf`, `copy`, `loan` — which stream to invalidate.
    pub kind: &'static str,
    pub id: String,
    /// `upsert` or `delete`.
    pub op: &'static str,
}

/// The fan-out channel, held in [`AppState`].
#[derive(Clone)]
pub struct EventBus(broadcast::Sender<ChangeEvent>);

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}

impl EventBus {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(CHANNEL_CAPACITY);
        Self(tx)
    }

    /// Publishes a change. Deliberately infallible from the caller's side: with
    /// no subscribers `send` returns an error, and a mutation must never fail
    /// because nobody was listening.
    pub fn publish(&self, event: ChangeEvent) {
        let _ = self.0.send(event);
    }

    pub fn subscribe(&self) -> broadcast::Receiver<ChangeEvent> {
        self.0.subscribe()
    }

    /// Live subscriber count, for the stats dashboard.
    pub fn subscribers(&self) -> usize {
        self.0.receiver_count()
    }
}

/// Convenience for the mutating handlers, so a publish is one line and can't
/// accidentally be written before the commit.
pub fn publish(state: &AppState, kind: &'static str, id: &str, op: &'static str) {
    state.events.publish(ChangeEvent {
        kind,
        id: id.to_string(),
        op,
    });
}

/// `GET /api/events` — the authenticated event stream.
pub async fn stream(
    State(state): State<AppState>,
    user: AuthUser,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.events.subscribe();
    let stream = async_stream::stream! {
        let mut rx = rx;
        loop {
            match rx.recv().await {
                Ok(change) => {
                    if !visible_to(&state, &user, &change).await {
                        continue;
                    }
                    let data = serde_json::json!({ "id": change.id, "op": change.op });
                    yield Ok(Event::default().event(change.kind).data(data.to_string()));
                }
                // Lagged: this subscriber missed events. Say so rather than
                // pretending — the client's answer is a full delta pull, which
                // is exactly what it would have done for each missed hint.
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    yield Ok(Event::default()
                        .event("lagged")
                        .data(serde_json::json!({ "missed": n }).to_string()));
                }
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    };
    // A comment every 20 s keeps proxies and phone radios from deciding an idle
    // stream is dead.
    Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(20))
            .text("keep-alive"),
    )
}

/// Whether this subscriber is allowed to know that [change] happened.
///
/// A **delete** is the subtle case: the row is already gone, so there is
/// nothing left to check permissions against and `book_access` would answer
/// "no" for everyone, silencing every deletion. Deletions are therefore
/// announced to all authenticated subscribers — which leaks only that *some*
/// book id disappeared, and the client's response is a delta pull that returns
/// exactly the deletions it is entitled to (`/api/deletions` is already
/// scoped). An id alone tells a subscriber nothing they can act on.
async fn visible_to(state: &AppState, user: &AuthUser, change: &ChangeEvent) -> bool {
    if change.op == "delete" {
        return true;
    }
    match change.kind {
        "book" => book_access(state, user, &change.id)
            .await
            .map(|a| a.can_view())
            .unwrap_or(false),
        // Shelves, copies and loans are owned outright rather than shared, and
        // their own access helpers answer that. A failed lookup is treated as
        // "not visible": a hint is not worth a leak.
        "shelf" => crate::access::shelf_access(state, user, &change.id)
            .await
            .map(|a| a.can_view())
            .unwrap_or(false),
        "copy" => crate::access::copy_access(state, user, &change.id)
            .await
            .map(|a| a.can_view())
            .unwrap_or(false),
        "loan" => crate::access::loan_access(state, user, &change.id)
            .await
            .map(|a| a.can_view())
            .unwrap_or(false),
        _ => false,
    }
}
