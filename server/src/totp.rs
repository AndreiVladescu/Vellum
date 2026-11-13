//! RFC 6238 time-based one-time passwords, and the bits around them: base32,
//! the `otpauth://` URI an authenticator app scans, its QR code, and recovery
//! codes. No I/O here — `two_factor.rs` owns the tables and the endpoints.
//!
//! The parameters are the ones every authenticator app defaults to, and are
//! not configurable: **HMAC-SHA-1, 6 digits, 30-second steps**. SHA-1 is not a
//! weakness here — HOTP needs only HMAC's PRF property, which collision attacks
//! on SHA-1 do not touch (RFC 6238 §5, RFC 4226 Appendix A) — and an app that
//! is asked for SHA-256 often silently ignores it and shows wrong codes.
//!
//! A code is accepted for the current step and one either side (±30 s), for a
//! phone whose clock has drifted or a person who types slowly. Accepting it is
//! the caller's business: [`matching_step`] says *which* step matched so the
//! caller can refuse any step at or before the last one it accepted (no
//! replay inside the window).
//!
//! Public (not `pub(crate)`) so the integration tests can compute the codes a
//! real authenticator would show.

use hmac::{Hmac, KeyInit, Mac};
use rand_core::{OsRng, RngCore};
use sha1::Sha1;

/// RFC 6238's X: seconds per step.
pub const STEP_SECONDS: u64 = 30;
pub const DIGITS: u32 = 6;
/// Steps either side of now that still count.
const SKEW: u64 = 1;
/// 160 bits: RFC 4226 §4 recommends the HMAC's output length.
const SECRET_BYTES: usize = 20;

/// The HOTP value for `counter` (RFC 4226 §5.3), as a number of `digits`
/// digits. Dynamic truncation, then modulo 10^digits.
pub fn hotp(secret: &[u8], counter: u64, digits: u32) -> u32 {
    let mut mac =
        <Hmac<Sha1> as KeyInit>::new_from_slice(secret).expect("HMAC takes a key of any length");
    mac.update(&counter.to_be_bytes());
    let hash = mac.finalize().into_bytes();
    let offset = (hash[hash.len() - 1] & 0x0f) as usize;
    let binary = u32::from_be_bytes([
        hash[offset] & 0x7f,
        hash[offset + 1],
        hash[offset + 2],
        hash[offset + 3],
    ]);
    binary % 10u32.pow(digits)
}

/// The time step a Unix time falls in.
pub fn step_at(unix_seconds: u64) -> u64 {
    unix_seconds / STEP_SECONDS
}

/// The six-digit code an authenticator shows at `unix_seconds`, zero-padded.
pub fn code_at(secret: &[u8], unix_seconds: u64) -> String {
    format!(
        "{:0width$}",
        hotp(secret, step_at(unix_seconds), DIGITS),
        width = DIGITS as usize
    )
}

/// Now, as a Unix time. A clock before 1970 is a broken server, and treating
/// it as 0 just makes every code wrong rather than panicking.
pub fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Which step within the skew window `code` is valid for, if any, considering
/// only steps strictly after `last_step` — a step that was already used is not
/// a match, whatever the code says.
///
/// Checks every step in the window rather than stopping at the first, so the
/// time it takes says nothing about which one (if any) matched.
pub fn matching_step(secret: &[u8], code: u32, now_step: u64, last_step: u64) -> Option<u64> {
    let mut found = None;
    for step in now_step.saturating_sub(SKEW)..=now_step + SKEW {
        let matches = hotp(secret, step, DIGITS) == code;
        if matches && step > last_step && found.is_none() {
            found = Some(step);
        }
    }
    found
}

/// A typed code, if it is shaped like one: six digits, ignoring spaces (apps
/// show `123 456`). Anything else is not a TOTP code — it may be a recovery code.
pub fn parse_code(typed: &str) -> Option<u32> {
    let digits: String = typed.chars().filter(|c| !c.is_whitespace()).collect();
    if digits.len() != DIGITS as usize || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    digits.parse().ok()
}

/// A fresh random secret.
pub fn new_secret() -> Vec<u8> {
    let mut bytes = vec![0u8; SECRET_BYTES];
    OsRng.fill_bytes(&mut bytes);
    bytes
}

const BASE32: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/// RFC 4648 base32 without padding — the form authenticator apps accept.
pub fn base32_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(5) * 8);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for &b in bytes {
        buffer = (buffer << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(BASE32[((buffer >> bits) & 31) as usize] as char);
        }
    }
    if bits > 0 {
        out.push(BASE32[((buffer << (5 - bits)) & 31) as usize] as char);
    }
    out
}

/// The inverse, forgiving of case, spaces and padding (the manual key is shown
/// in groups, and people retype it). `None` for anything not base32.
pub fn base32_decode(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() * 5 / 8);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for c in text.chars() {
        if c == ' ' || c == '=' || c == '-' {
            continue;
        }
        let value = BASE32
            .iter()
            .position(|&b| b as char == c.to_ascii_uppercase())? as u32;
        buffer = (buffer << 5) | value;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
        }
    }
    Some(out)
}

/// Percent-encodes everything but RFC 3986's unreserved characters.
fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The Key URI an authenticator app scans: `otpauth://totp/Issuer:account?…`
/// (the de facto format Google Authenticator defined). The issuer is repeated
/// as a parameter because some apps read only one of the two.
pub fn otpauth_uri(issuer: &str, account: &str, secret_base32: &str) -> String {
    format!(
        "otpauth://totp/{issuer_label}:{account}?secret={secret_base32}&issuer={issuer_param}\
         &algorithm=SHA1&digits={DIGITS}&period={STEP_SECONDS}",
        issuer_label = percent_encode(issuer),
        account = percent_encode(account),
        issuer_param = percent_encode(issuer),
    )
}

/// The URI as an SVG QR code — plain black on white whatever the console's
/// theme, because phone cameras read that most reliably — without the XML
/// prolog, so it can be dropped into a `data:` URL or a page as is.
pub fn qr_svg(uri: &str) -> String {
    use qrcode::render::svg;
    // Medium error correction: the URI is ~150 bytes, so this stays a small
    // code that a phone reads off a laptop screen at a glance.
    let code = qrcode::QrCode::with_error_correction_level(uri.as_bytes(), qrcode::EcLevel::M)
        .expect("an otpauth URI is far below a QR code's capacity");
    let svg = code
        .render::<svg::Color>()
        .min_dimensions(200, 200)
        .quiet_zone(true)
        .build();
    match svg.find("<svg") {
        Some(start) => svg[start..].to_string(),
        None => svg,
    }
}

// ---- recovery codes ---------------------------------------------------------

/// Crockford's base32, lowercase — the alphabet app passwords use, for the same
/// reason: nothing in it can be misread as something else.
const RECOVERY_ALPHABET: &[u8; 32] = b"0123456789abcdefghjkmnpqrstvwxyz";
/// 16 symbols × 5 bits = 80 bits each.
const RECOVERY_LEN: usize = 16;
pub const RECOVERY_CODES: usize = 10;

/// One recovery code, formatted `abcd-efgh-jkmn-pqrs`.
pub fn new_recovery_code() -> String {
    let mut bytes = [0u8; RECOVERY_LEN];
    OsRng.fill_bytes(&mut bytes);
    let mut out = String::with_capacity(RECOVERY_LEN + RECOVERY_LEN / 4);
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 && i % 4 == 0 {
            out.push('-');
        }
        out.push(RECOVERY_ALPHABET[(b & 31) as usize] as char);
    }
    out
}

/// The canonical form of something typed as a recovery code, or `None` when it
/// cannot be one. Case, dashes, spaces and Crockford's look-alikes (`o` → `0`,
/// `i`/`l` → `1`) do not matter.
pub fn normalize_recovery_code(typed: &str) -> Option<String> {
    let mut out = String::with_capacity(RECOVERY_LEN);
    for c in typed.chars() {
        let c = match c.to_ascii_lowercase() {
            '-' | ' ' => continue,
            'o' => '0',
            'i' | 'l' => '1',
            c => c,
        };
        if !c.is_ascii() || !RECOVERY_ALPHABET.contains(&(c as u8)) {
            return None;
        }
        out.push(c);
        if out.len() > RECOVERY_LEN {
            return None;
        }
    }
    (out.len() == RECOVERY_LEN).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 6238 Appendix B, SHA-1 rows. The seed is the ASCII string
    /// "12345678901234567890" and the reference values have 8 digits.
    const RFC6238_SEED: &[u8] = b"12345678901234567890";
    const RFC6238_SHA1: &[(u64, u32)] = &[
        (59, 94287082),
        (1111111109, 7081804),
        (1111111111, 14050471),
        (1234567890, 89005924),
        (2000000000, 69279037),
        (20000000000, 65353130),
    ];

    #[test]
    fn rfc_6238_sha1_test_vectors() {
        for &(time, expected) in RFC6238_SHA1 {
            assert_eq!(hotp(RFC6238_SEED, step_at(time), 8), expected, "T={time}");
            // The six-digit code is the same value's last six digits.
            assert_eq!(
                code_at(RFC6238_SEED, time),
                format!("{:06}", expected % 1_000_000),
                "T={time}"
            );
        }
    }

    /// RFC 4226 Appendix D: HOTP for counters 0–9 over the same seed.
    #[test]
    fn rfc_4226_hotp_test_vectors() {
        let expected = [
            755224, 287082, 359152, 969429, 338314, 254676, 287922, 162583, 399871, 520489,
        ];
        for (counter, want) in expected.iter().enumerate() {
            assert_eq!(hotp(RFC6238_SEED, counter as u64, 6), *want, "C={counter}");
        }
    }

    #[test]
    fn codes_keep_their_leading_zeros() {
        // T=1111111109 is 07081804 — its six-digit code starts with a zero.
        assert_eq!(code_at(RFC6238_SEED, 1111111109), "081804");
        assert_eq!(parse_code("081804"), Some(81804));
    }

    #[test]
    fn a_code_counts_one_step_either_side_and_no_further() {
        let now = step_at(1_700_000_000);
        for (offset, accepted) in [(-2i64, false), (-1, true), (0, true), (1, true), (2, false)] {
            let step = (now as i64 + offset) as u64;
            let code = hotp(RFC6238_SEED, step, DIGITS);
            assert_eq!(
                matching_step(RFC6238_SEED, code, now, 0),
                accepted.then_some(step),
                "offset {offset}"
            );
        }
    }

    #[test]
    fn a_used_step_is_never_accepted_again() {
        let now = step_at(1_700_000_000);
        let code = hotp(RFC6238_SEED, now, DIGITS);
        assert_eq!(matching_step(RFC6238_SEED, code, now, now - 1), Some(now));
        // Once `now` is the last step used, the same code is a replay…
        assert_eq!(matching_step(RFC6238_SEED, code, now, now), None);
        // …and so is the previous step's, even though it is inside the window.
        let earlier = hotp(RFC6238_SEED, now - 1, DIGITS);
        assert_eq!(matching_step(RFC6238_SEED, earlier, now, now), None);
        // The next step's code is still fine.
        let next = hotp(RFC6238_SEED, now + 1, DIGITS);
        assert_eq!(matching_step(RFC6238_SEED, next, now, now), Some(now + 1));
    }

    #[test]
    fn parse_code_wants_six_digits() {
        assert_eq!(parse_code("123456"), Some(123456));
        assert_eq!(parse_code(" 123 456 "), Some(123456));
        for bad in [
            "",
            "12345",
            "1234567",
            "12345a",
            "abcd-efgh-jkmn-pqrs",
            "١٢٣٤٥٦",
        ] {
            assert_eq!(parse_code(bad), None, "{bad}");
        }
    }

    /// RFC 4648 §10, without the padding.
    #[test]
    fn base32_test_vectors() {
        for (plain, encoded) in [
            ("", ""),
            ("f", "MY"),
            ("fo", "MZXQ"),
            ("foo", "MZXW6"),
            ("foob", "MZXW6YQ"),
            ("fooba", "MZXW6YTB"),
            ("foobar", "MZXW6YTBOI"),
        ] {
            assert_eq!(base32_encode(plain.as_bytes()), encoded);
            assert_eq!(base32_decode(encoded).unwrap(), plain.as_bytes());
        }
        assert_eq!(
            base32_decode("mzxw 6ytb oi==").unwrap(),
            b"foobar",
            "case, spaces and padding are forgiven"
        );
        assert_eq!(base32_decode("MZXW1"), None, "1 is not base32");
    }

    #[test]
    fn a_new_secret_is_160_bits_and_round_trips() {
        let s = new_secret();
        assert_eq!(s.len(), 20);
        let text = base32_encode(&s);
        assert_eq!(text.len(), 32);
        assert_eq!(base32_decode(&text).unwrap(), s);
        assert_ne!(new_secret(), s);
    }

    #[test]
    fn the_uri_is_what_authenticator_apps_expect() {
        let uri = otpauth_uri("Vellum", "ana+books@lib.test", "JBSWY3DPEHPK3PXP");
        assert_eq!(
            uri,
            "otpauth://totp/Vellum:ana%2Bbooks%40lib.test?secret=JBSWY3DPEHPK3PXP\
             &issuer=Vellum&algorithm=SHA1&digits=6&period=30"
        );
    }

    #[test]
    fn the_qr_code_is_a_bare_svg() {
        let svg = qr_svg("otpauth://totp/Vellum:a%40b?secret=JBSWY3DPEHPK3PXP&issuer=Vellum");
        assert!(svg.starts_with("<svg"), "{}", &svg[..40]);
        assert!(svg.ends_with("</svg>"));
        assert!(!svg.contains("<?xml"));
        assert!(!svg.contains("<script"));
    }

    #[test]
    fn recovery_codes_are_four_groups_and_forgive_typing_slips() {
        let code = new_recovery_code();
        assert_eq!(code.split('-').count(), 4, "{code}");
        let canonical = normalize_recovery_code(&code).unwrap();
        assert_eq!(canonical, code.replace('-', ""));
        assert_eq!(
            normalize_recovery_code(&code.to_uppercase().replace('-', " ")).as_deref(),
            Some(canonical.as_str())
        );
        assert_eq!(
            normalize_recovery_code("abcd-efgh-jkmn-pqoi").as_deref(),
            Some("abcdefghjkmnpq01")
        );
        for bad in [
            "123456",
            "abcd-efgh-jkmn",
            "abcd-efgh-jkmn-pqrs-t",
            "abcd-efgh-jkmn-pqru",
        ] {
            assert_eq!(normalize_recovery_code(bad), None, "{bad}");
        }
        let all: std::collections::HashSet<String> =
            (0..100).map(|_| new_recovery_code()).collect();
        assert_eq!(all.len(), 100);
    }
}
