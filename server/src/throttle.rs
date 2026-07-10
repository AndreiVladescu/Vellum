//! A tiny in-memory failed-login limiter. Keyed by lowercase email, it caps the
//! number of failed attempts inside a sliding window. State lives only in
//! memory (resets on restart), which is acceptable: Argon2 already makes each
//! attempt slow, and this exists to blunt an unbounded remote guessing loop.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const MAX_FAILURES: usize = 10;
const WINDOW: Duration = Duration::from_secs(15 * 60);

#[derive(Default)]
pub struct LoginThrottle(Mutex<HashMap<String, Vec<Instant>>>);

impl LoginThrottle {
    /// True if another attempt for `key` is permitted right now.
    pub fn allowed(&self, key: &str) -> bool {
        let mut map = self.0.lock().unwrap();
        let now = Instant::now();
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
mod tests {
    use super::*;

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
