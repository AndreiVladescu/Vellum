//! Optional TLS for the sync server. Enabled with `VELLUM_TLS=1`.
//!
//! The app is local-first and the server is an optional LAN sync backend, so we
//! don't assume a public hostname or a CA-issued certificate. Instead, on first
//! start we generate a self-signed certificate and log its SHA-256 fingerprint;
//! the user imports that certificate (or pins the fingerprint) in the app. A
//! user who already has their own certificate can drop `cert.pem`/`key.pem` in
//! place (or point `VELLUM_TLS_CERT`/`VELLUM_TLS_KEY` at them) and we use those.

use std::path::Path;

use anyhow::Context;

/// Ensure a certificate + private key exist at the given paths. If either is
/// missing, generate a self-signed pair valid for `localhost`, `127.0.0.1` and
/// any `extra_sans` (e.g. the LAN IP or hostname a phone will connect to).
///
/// Returns the leaf certificate's SHA-256 fingerprint (uppercase, colon-grouped
/// hex) so the caller can print it for the user to verify on import.
pub fn ensure_self_signed(
    cert_path: &Path,
    key_path: &Path,
    extra_sans: &[String],
) -> anyhow::Result<String> {
    if cert_path.exists() && key_path.exists() {
        // Reuse the existing material (user-provided or generated earlier) and
        // just report its fingerprint.
        let pem = std::fs::read_to_string(cert_path)
            .with_context(|| format!("reading {}", cert_path.display()))?;
        let der = first_cert_der(&pem)
            .with_context(|| format!("no CERTIFICATE block in {}", cert_path.display()))?;
        return Ok(fingerprint(&der));
    }

    let mut sans = vec!["localhost".to_string(), "127.0.0.1".to_string()];
    for s in extra_sans {
        if !sans.contains(s) {
            sans.push(s.clone());
        }
    }
    let certified =
        rcgen::generate_simple_self_signed(sans).context("generating self-signed certificate")?;
    let cert_pem = certified.cert.pem();
    let key_pem = certified.signing_key.serialize_pem();

    if let Some(parent) = cert_path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    std::fs::write(cert_path, cert_pem.as_bytes())
        .with_context(|| format!("writing {}", cert_path.display()))?;
    std::fs::write(key_path, key_pem.as_bytes())
        .with_context(|| format!("writing {}", key_path.display()))?;
    // The private key is a secret — restrict it to the owner on Unix.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(key_path, std::fs::Permissions::from_mode(0o600)).ok();
    }

    Ok(fingerprint(certified.cert.der()))
}

/// Decode the first `-----BEGIN CERTIFICATE-----` block of a PEM string to DER.
fn first_cert_der(pem: &str) -> Option<Vec<u8>> {
    const BEGIN: &str = "-----BEGIN CERTIFICATE-----";
    const END: &str = "-----END CERTIFICATE-----";
    let start = pem.find(BEGIN)? + BEGIN.len();
    let end = pem[start..].find(END)? + start;
    let b64: String = pem[start..end]
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    use base64::{Engine, engine::general_purpose::STANDARD};
    STANDARD.decode(b64).ok()
}

/// SHA-256 of the DER certificate, as `AB:CD:...` uppercase hex — the same form
/// browsers and `openssl x509 -fingerprint -sha256` show, so it's verifiable.
fn fingerprint(der: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(der);
    hex::encode_upper(digest)
        .as_bytes()
        .chunks(2)
        .map(|c| std::str::from_utf8(c).unwrap())
        .collect::<Vec<_>>()
        .join(":")
}
