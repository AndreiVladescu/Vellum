//! The duplicate check, server-side (next features #5).
//!
//! **Why it lives here rather than in the console's JavaScript.** The app and
//! the console both import catalogues, and if each decides for itself what
//! counts as a duplicate they will disagree — the same CSV imported from the
//! browser and from the phone would produce different libraries, and the one
//! that was wrong would be whichever you used second. So the rules live in one
//! place that both can call.
//!
//! The rules are the app's, deliberately unchanged (`duplicate_finder.dart`,
//! `import_plan.dart`), and their *order* is the safety property:
//!
//! 1. **Same file bytes** (sha256) — certain.
//! 2. **Same ISBN**, compared digits-only — certain.
//! 3. **Similar title and an agreeing author** — a suggestion, never certain,
//!    because "Dune" and "Dune Messiah" are two books and no amount of string
//!    distance knows that.
//!
//! Nothing here writes. It answers "what would this row collide with", and the
//! caller shows that in a review screen before anything is committed — the same
//! dry run the app's folder import has had since plan 5 #15.

use axum::Json;
use axum::extract::State;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// One row the caller is thinking of importing.
#[derive(Deserialize)]
pub struct Candidate {
    /// Echoed back untouched, so the caller can line verdicts up with its rows
    /// without relying on order.
    pub key: String,
    pub title: String,
    #[serde(default)]
    pub isbn: Option<String>,
    #[serde(default)]
    pub authors: Vec<String>,
    /// The sha256 of the file, when the caller has hashed one.
    #[serde(default)]
    pub sha256: Option<String>,
}

#[derive(Deserialize)]
pub struct CheckInput {
    pub candidates: Vec<Candidate>,
}

/// The most rows one call may ask about.
///
/// The matching below is quadratic in the worst arm — every candidate against
/// every visible book — so an uncapped list is a denial of service an ordinary
/// member can trigger: 5,000 candidates against a 200-book library measured at
/// 11 seconds of CPU, and it scales with both. A real catalogue import sends
/// its rows in batches anyway, so this costs nothing legitimate.
const MAX_CANDIDATES: usize = 1000;

/// Why a candidate looks like something already in the library. Ordered
/// strongest first, which is the order the caller should trust them in.
#[derive(Serialize, PartialEq, Eq, PartialOrd, Ord, Clone, Copy, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
    SameFile,
    SameIsbn,
    SimilarTitle,
}

#[derive(Serialize)]
pub struct Verdict {
    pub key: String,
    /// Absent when nothing collided — the ordinary case for a fresh import.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<Reason>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub book_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Whether the caller should treat this as certain enough to deselect the
    /// row by default. False for a title match, which is a suggestion.
    pub certain: bool,
}

/// `POST /api/import/check` — what would each of these collide with?
pub async fn check(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<CheckInput>,
) -> AppResult<Json<Vec<Verdict>>> {
    if input.candidates.len() > MAX_CANDIDATES {
        return Err(AppError::BadRequest(format!(
            "too many rows in one check ({}); send at most {MAX_CANDIDATES} at a time",
            input.candidates.len()
        )));
    }
    // Only books the caller can see: a collision they have no access to is not
    // information they are entitled to, and importing "again" is the right
    // outcome for a book that is not theirs.
    let existing: Vec<(String, String, Option<String>)> =
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "SELECT b.id, b.title, b.isbn FROM book b WHERE {}",
            crate::books::access_predicate()
        )))
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id)
        .fetch_all(&state.db)
        .await?;

    let ids: Vec<String> = existing.iter().map(|(id, _, _)| id.clone()).collect();
    let authors = crate::books::author_map_for(&state, &ids).await?;
    let hashes = file_hashes_for(&state, &ids).await?;

    // The two *certain* signals are exact equality, so they go in a map and
    // cost one lookup each instead of a pass over the library. Only the fuzzy
    // title arm has to compare against everything, which is what MAX_CANDIDATES
    // bounds.
    let mut by_sha: std::collections::HashMap<&str, (&String, &String)> = Default::default();
    let mut by_isbn: std::collections::HashMap<String, (&String, &String)> = Default::default();
    for (id, title, isbn) in &existing {
        if let Some(shas) = hashes.get(id) {
            for sha in shas {
                by_sha.entry(sha.as_str()).or_insert((id, title));
            }
        }
        if let Some(normalized) = normalize_isbn(isbn.as_deref()) {
            by_isbn.entry(normalized).or_insert((id, title));
        }
    }

    let mut verdicts = Vec::with_capacity(input.candidates.len());
    for c in &input.candidates {
        let mut best: Option<(Reason, &String, &String)> = None;

        if let Some(sha) = c.sha256.as_deref()
            && let Some((id, title)) = by_sha.get(sha)
        {
            best = Some((Reason::SameFile, id, title));
        }
        if best.is_none()
            && let Some(isbn) = normalize_isbn(c.isbn.as_deref())
            && let Some((id, title)) = by_isbn.get(&isbn)
        {
            best = Some((Reason::SameIsbn, id, title));
        }
        if best.is_none() {
            for (id, title, _) in &existing {
                if titles_match(&c.title, title)
                    && authors_agree(
                        &c.authors,
                        authors.get(id).map(|v| v.as_slice()).unwrap_or(&[]),
                    )
                {
                    best = Some((Reason::SimilarTitle, id, title));
                    break;
                }
            }
        }

        verdicts.push(match best {
            Some((reason, id, title)) => Verdict {
                key: c.key.clone(),
                reason: Some(reason),
                book_id: Some(id.clone()),
                title: Some(title.clone()),
                certain: reason != Reason::SimilarTitle,
            },
            None => Verdict {
                key: c.key.clone(),
                reason: None,
                book_id: None,
                title: None,
                certain: false,
            },
        });
    }
    Ok(Json(verdicts))
}

async fn file_hashes_for(
    state: &AppState,
    ids: &[String],
) -> AppResult<std::collections::HashMap<String, Vec<String>>> {
    let mut out: std::collections::HashMap<String, Vec<String>> = Default::default();
    if ids.is_empty() {
        return Ok(out);
    }
    // Scoped to the books the caller can see. It used to read every row in the
    // table: harmless as written, because the map is only ever indexed by a
    // visible id — and one careless edit away from handing back a collision
    // with somebody else's book.
    let mut sql =
        String::from("SELECT book_id, sha256 FROM book_file WHERE sha256 <> '' AND book_id IN (");
    sql.push_str(
        &std::iter::repeat_n("?", ids.len())
            .collect::<Vec<_>>()
            .join(","),
    );
    sql.push(')');
    let mut query = sqlx::query_as::<_, (String, String)>(sqlx::AssertSqlSafe(sql.as_str()));
    for id in ids {
        query = query.bind(id);
    }
    let rows: Vec<(String, String)> = query.fetch_all(&state.db).await?;
    for (book_id, sha) in rows {
        out.entry(book_id).or_default().push(sha);
    }
    Ok(out)
}

/// Digits only, so `978-0-441-01359-3` and `9780441013593` compare equal.
/// Mirrors `normalizeIsbn` in `import_plan.dart`.
pub fn normalize_isbn(isbn: Option<&str>) -> Option<String> {
    let raw = isbn?;
    let digits: String = raw
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == 'x' || *c == 'X')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    (!digits.is_empty()).then_some(digits)
}

/// Lowercased, punctuation dropped, articles removed. Mirrors
/// `normalizeForMatch` in `import_plan.dart` — including its stop-word list,
/// because a rule that is *nearly* the same is worse than one that differs
/// openly.
pub fn normalize_for_match(value: &str) -> String {
    const STOP_WORDS: [&str; 3] = ["a", "an", "the"];
    value
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .filter(|w| !STOP_WORDS.contains(w))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Token-sorted, so "Dune, Frank Herbert" and "Frank Herbert Dune" don't count
/// as different.
fn comparable_title(title: &str) -> String {
    let normalized = normalize_for_match(title);
    let mut words: Vec<&str> = normalized.split(' ').filter(|w| !w.is_empty()).collect();
    words.sort_unstable();
    words.join(" ")
}

/// Within an edit distance of two, the same threshold the app uses.
fn titles_match(a: &str, b: &str) -> bool {
    let (x, y) = (comparable_title(a), comparable_title(b));
    if x.is_empty() || y.is_empty() {
        return false;
    }
    x == y || levenshtein_within(&x, &y, 2)
}

/// Two authors agree when they share a name — or when *neither* has one, which
/// is the app's rule and matters for catalogues that carry no author column.
fn authors_agree(candidate: &[String], existing: &[String]) -> bool {
    let a: Vec<String> = candidate
        .iter()
        .map(|n| normalize_for_match(n))
        .filter(|n| !n.is_empty())
        .collect();
    let b: Vec<String> = existing
        .iter()
        .map(|n| normalize_for_match(n))
        .filter(|n| !n.is_empty())
        .collect();
    if a.is_empty() || b.is_empty() {
        return a.is_empty() && b.is_empty();
    }
    a.iter().any(|name| b.contains(name))
}

/// Levenshtein distance, but only asking "is it within `limit`". Two rows of
/// the table rather than the full matrix: a library of a few thousand titles is
/// a few million comparisons and the allocation is what costs.
fn levenshtein_within(a: &str, b: &str, limit: usize) -> bool {
    let (a, b): (Vec<char>, Vec<char>) = (a.chars().collect(), b.chars().collect());
    if a.len().abs_diff(b.len()) > limit {
        return false;
    }
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut cur = vec![0usize; b.len() + 1];
    for (i, ca) in a.iter().enumerate() {
        cur[0] = i + 1;
        let mut row_best = cur[0];
        for (j, cb) in b.iter().enumerate() {
            let cost = usize::from(ca != cb);
            cur[j + 1] = (prev[j] + cost).min(prev[j + 1] + 1).min(cur[j] + 1);
            row_best = row_best.min(cur[j + 1]);
        }
        // Every remaining row can only grow: bail out as soon as the whole row
        // is already past the limit.
        if row_best > limit {
            return false;
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[b.len()] <= limit
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn isbns_compare_digits_only() {
        assert_eq!(
            normalize_isbn(Some("978-0-441-01359-3")),
            normalize_isbn(Some("9780441013593"))
        );
        assert_eq!(normalize_isbn(Some("")), None);
        assert_eq!(normalize_isbn(None), None);
    }

    #[test]
    fn titles_ignore_case_punctuation_articles_and_word_order() {
        assert!(titles_match(
            "The Left Hand of Darkness",
            "left hand of darkness"
        ));
        assert!(titles_match("Dune, Frank Herbert", "Frank Herbert Dune"));
        assert!(titles_match("Piranesi", "Piranesi."));
    }

    #[test]
    fn genuinely_different_books_do_not_match() {
        // The case that makes this a suggestion rather than a certainty.
        assert!(!titles_match("Dune", "Dune Messiah"));
        assert!(!titles_match("Solaris", "Piranesi"));
    }

    #[test]
    fn authors_agree_when_they_share_a_name_or_neither_has_one() {
        assert!(authors_agree(
            &["Ursula K. Le Guin".into()],
            &["ursula k le guin".into()]
        ));
        assert!(authors_agree(&[], &[]));
        assert!(!authors_agree(&["Frank Herbert".into()], &[]));
        assert!(!authors_agree(
            &["Frank Herbert".into()],
            &["Stanislaw Lem".into()]
        ));
    }

    #[test]
    fn the_distance_bail_out_agrees_with_the_full_answer() {
        assert!(levenshtein_within("kitten", "sitting", 3));
        assert!(!levenshtein_within("kitten", "sitting", 2));
        assert!(levenshtein_within("same", "same", 0));
        assert!(!levenshtein_within("short", "much longer string", 2));
    }
}
