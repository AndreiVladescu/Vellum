//! Every documented variable either reaches the container or is refused on
//! purpose.
//!
//! Compose reads `.env` only to substitute `${...}` *inside* docker-compose.yml.
//! A variable the compose file never names is silently dropped, however
//! carefully it was written in `.env` — which is how a filled-in SMTP section
//! produced `mail: disabled` with nothing in the log to explain it.
//!
//! Nothing at runtime can catch that: the server cannot know about a value it
//! was never given. So it is caught here instead, by comparing the two files
//! that have to agree.

use std::collections::BTreeSet;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    // CARGO_MANIFEST_DIR is `<repo>/server`.
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("server/ has a parent")
        .to_path_buf()
}

/// Names deliberately kept out of the container, and why.
///
/// Listed with a reason rather than just skipped: a name arriving here should
/// be a decision somebody made, not a gap nobody noticed.
const NOT_FORWARDED: &[(&str, &str)] = &[
    (
        "VELLUM_PORT",
        "the ports mapping names 3000 on the container side; moving the port \
         inside would leave the mapping pointing at nothing",
    ),
    (
        "VELLUM_DB",
        "the database lives on the named volume at its default path",
    ),
    ("VELLUM_DATA_DIR", "same volume, same reason"),
    (
        "VELLUM_TLS",
        "whatever sits in front terminates TLS; two certificate stories at once \
         is how you end up debugging both",
    ),
    ("VELLUM_TLS_CERT", "see VELLUM_TLS"),
    ("VELLUM_TLS_KEY", "see VELLUM_TLS"),
    ("VELLUM_TLS_SANS", "see VELLUM_TLS"),
];

#[test]
fn every_documented_variable_is_forwarded_or_deliberately_not() {
    let root = repo_root();
    let example = std::fs::read_to_string(root.join("server/.env.example"))
        .expect("server/.env.example is the list of what a server understands");
    let compose = std::fs::read_to_string(root.join("docker-compose.yml"))
        .expect("docker-compose.yml is how most people run it");

    // Every VELLUM_* name the example file documents, commented out or not.
    //
    // Assignments only: the prose in that file names the variables too, and
    // "VELLUM_SMTP_PASS is a real credential" is a sentence, not a setting.
    let documented: BTreeSet<String> = example
        .lines()
        .map(|l| l.trim_start_matches('#').trim())
        .filter_map(|l| l.split_once('='))
        .map(|(name, _)| name.trim())
        .filter(|name| {
            name.starts_with("VELLUM_")
                && name
                    .chars()
                    .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
        })
        .map(str::to_string)
        .collect();
    assert!(
        documented.len() > 5,
        "parsed too few names out of .env.example — the parser is wrong, not the file"
    );

    let excluded: BTreeSet<&str> = NOT_FORWARDED.iter().map(|(n, _)| *n).collect();
    let missing: Vec<&String> = documented
        .iter()
        .filter(|name| !excluded.contains(name.as_str()))
        // Named anywhere in the compose file: as a key, or in a `${...}`.
        .filter(|name| !compose.contains(name.as_str()))
        .collect();

    assert!(
        missing.is_empty(),
        "these are documented in server/.env.example but never named in \
         docker-compose.yml, so setting them does nothing in Docker: {missing:?}\n\
         Either forward them under the vellum service's `environment:` as \
         `NAME: \"${{NAME:-}}\"`, or add them to NOT_FORWARDED in this test with \
         the reason they are refused."
    );
}

#[test]
fn a_forwarded_variable_defaults_to_empty_rather_than_a_guess() {
    // `${NAME:-}` passes an empty string when .env says nothing, and the server
    // treats empty as unset. A default invented here instead would be a second
    // place to keep the real default in step with the code.
    let compose = std::fs::read_to_string(repo_root().join("docker-compose.yml")).unwrap();
    for name in ["VELLUM_SMTP_HOST", "VELLUM_SMTP_USER", "VELLUM_MAIL_FROM"] {
        let expected = format!("{name}: \"${{{name}:-}}\"");
        assert!(
            compose.contains(&expected),
            "{name} should be forwarded as {expected}, so that an unset one \
             stays unset rather than becoming a value nobody chose"
        );
    }
}

#[test]
fn the_excluded_ones_really_are_absent() {
    // A name in NOT_FORWARDED that *is* forwarded means the list has gone stale
    // and is now documenting the opposite of what happens.
    let compose = std::fs::read_to_string(repo_root().join("docker-compose.yml")).unwrap();
    for (name, why) in NOT_FORWARDED {
        let forwarded = format!("{name}: ");
        assert!(
            !compose.contains(&forwarded),
            "{name} is forwarded after all — this test says it is not, because {why}"
        );
    }
}
