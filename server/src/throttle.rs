//! A tiny in-memory failed-login limiter. Keyed by lowercase email, it caps the
//! number of failed attempts inside a sliding window. State lives only in
//! memory (resets on restart), which is acceptable: Argon2 already makes each
//! attempt slow, and this exists to blunt an unbounded remote guessing loop.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const MAX_FAILURES: usize = 10;
const WINDOW: Duration = Duration::from_secs(15 * 60);
/// Above this many keys, `allowed` sweeps the whole map for aged-out entries.
/// Bounds memory against an attacker spraying random (never-succeeding) emails,
/// which otherwise leave one entry each forever (`clear` only runs on success).
const MAX_KEYS: usize = 1000;

#[derive(Default)]
pub struct LoginThrottle(Mutex<HashMap<String, Vec<Instant>>>);

impl LoginThrottle {
    /// True if another attempt for `key` is permitted right now.
    pub fn allowed(&self, key: &str) -> bool {
        let mut map = self.0.lock().unwrap();
        let now = Instant::now();
        // Periodic prune: when the map has grown large, drop every entry whose
        // failures have all aged out of the window, so it can't grow unbounded.
        if map.len() > MAX_KEYS {
            map.retain(|_, hits| {
                hits.retain(|t| now.duration_since(*t) < WINDOW);
                !hits.is_empty()
            });
        }
        match map.get_mut(key) {
            Some(hits) => {
                hits.retain(|t| now.duration_since(*t) < WINDOW);
                hits.len() < MAX_FAILURES
            }
            None => true,
        }
    }

    /// Record a failed attempt for `key`.
    pub fn record_failure(&self, key: &str) {
        let now = Instant::now();
        let mut map = self.0.lock().unwrap();
        let hits = map.entry(key.to_string()).or_default();
        hits.retain(|t| now.duration_since(*t) < WINDOW);
        hits.push(now);
    }

    /// Forget a key's failures (called after a successful login).
    pub fn clear(&self, key: &str) {
        self.0.lock().unwrap().remove(key);
    }
}

#[cfg(test)]
impl LoginThrottle {
    /// Seed a stale (fully aged-out) entry, for the prune test.
    fn seed_stale(&self, key: &str) {
        let hits = match Instant::now().checked_sub(WINDOW * 2) {
            Some(old) => vec![old],
            None => Vec::new(),
        };
        self.0.lock().unwrap().insert(key.to_string(), hits);
    }

    fn len(&self) -> usize {
        self.0.lock().unwrap().len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prunes_stale_entries_once_the_map_grows() {
        let t = LoginThrottle::default();
        for i in 0..2000 {
            t.seed_stale(&format!("k{i}@x"));
        }
        assert_eq!(t.len(), 2000);
        // One call past the size threshold triggers the sweep of aged entries.
        assert!(t.allowed("fresh@x"));
        assert!(t.len() < 2000, "stale entries should be pruned");
    }

    #[test]
    fn blocks_after_max_failures_and_clears() {
        let t = LoginThrottle::default();
        for _ in 0..MAX_FAILURES {
            assert!(t.allowed("a@b.c"));
            t.record_failure("a@b.c");
        }
        assert!(
            !t.allowed("a@b.c"),
            "should be blocked after {MAX_FAILURES}"
        );
        // A different key is unaffected.
        assert!(t.allowed("other@b.c"));
        // Clearing (success) unblocks.
        t.clear("a@b.c");
        assert!(t.allowed("a@b.c"));
    }
}
