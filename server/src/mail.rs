//! Outbound transactional email (plan 5 #31, stage 1).
//!
//! **Off unless configured.** Vellum's whole story is a local-first app and an
//! optional LAN server; adding a mandatory outbound-SMTP dependency would break
//! that, and email is a new secret (a password) plus a new network egress. So a
//! server with no `VELLUM_SMTP_HOST` simply has no mailer, every feature that
//! needs one is hidden rather than broken, and nothing is logged that could leak
//! a credential.
//!
//! What *is* logged at boot: whether mail is on or off, and the host it will use
//! — never the username or password.

use lettre::message::header::ContentType;
use lettre::message::{Attachment, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};

use crate::error::{AppError, AppResult};

/// The mailer, present only when the operator configured SMTP.
#[derive(Clone)]
pub struct Mailer {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from: String,
}

impl Mailer {
    /// Reads the configuration from the environment.
    ///
    /// Returns `Ok(None)` when mail is simply off (no host configured) and an
    /// error only when it is configured *incorrectly* — a typo in a port or a
    /// missing `VELLUM_MAIL_FROM` should stop the server at boot rather than
    /// surface as a failed password reset weeks later.
    pub fn from_env() -> anyhow::Result<Option<Self>> {
        let Ok(host) = std::env::var("VELLUM_SMTP_HOST") else {
            return Ok(None);
        };
        let host = host.trim().to_string();
        if host.is_empty() {
            return Ok(None);
        }

        let port: u16 = match std::env::var("VELLUM_SMTP_PORT") {
            Ok(raw) => raw
                .trim()
                .parse()
                .map_err(|_| anyhow::anyhow!("VELLUM_SMTP_PORT must be a port number"))?,
            // 587 (submission + STARTTLS) rather than 465 or 25: it is what
            // Gmail, Fastmail and most providers expect, and 25 is usually
            // blocked outbound anyway.
            Err(_) => 587,
        };

        let from = std::env::var("VELLUM_MAIL_FROM").map_err(|_| {
            anyhow::anyhow!("VELLUM_MAIL_FROM is required when VELLUM_SMTP_HOST is set")
        })?;
        // Parsed once here so a malformed address fails at boot, not at send.
        from.parse::<lettre::message::Mailbox>()
            .map_err(|e| anyhow::anyhow!("VELLUM_MAIL_FROM is not a valid address: {e}"))?;

        // STARTTLS on the submission port. `relay()` would use implicit TLS on
        // 465; `starttls_relay` matches the 587 default above and refuses to
        // continue in the clear if the server doesn't offer TLS.
        let mut builder = AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&host)
            .map_err(|e| anyhow::anyhow!("SMTP transport: {e}"))?
            .port(port);

        // Credentials are optional: an internal relay may not want any.
        if let Ok(user) = std::env::var("VELLUM_SMTP_USER") {
            let pass = std::env::var("VELLUM_SMTP_PASS").unwrap_or_default();
            builder = builder.credentials(Credentials::new(user, pass));
        }

        tracing::info!("mail: enabled via {host}:{port} (from {from})");
        Ok(Some(Self {
            transport: builder.build(),
            from,
        }))
    }

    /// Sends a plain-text message.
    ///
    /// Errors are returned as `Internal` and the *contents* are never logged:
    /// these bodies carry reset links, which are credentials for the duration of
    /// their TTL.
    pub async fn send(&self, to: &str, subject: &str, body: &str) -> AppResult<()> {
        let message = Message::builder()
            .from(
                self.from
                    .parse()
                    .map_err(|e| AppError::Internal(format!("mail from: {e}")))?,
            )
            .to(to
                .parse()
                .map_err(|_| AppError::BadRequest("not a valid email address".into()))?)
            .subject(subject)
            .header(ContentType::TEXT_PLAIN)
            .body(body.to_string())
            .map_err(|e| AppError::Internal(format!("mail body: {e}")))?;

        self.transport.send(message).await.map_err(|e| {
            // The error may name the host and the failure, never the body.
            tracing::error!("mail send failed: {e}");
            AppError::Internal("could not send the email".into())
        })?;
        Ok(())
    }

    /// Sends a message carrying one file (plan 5 #53).
    ///
    /// Kept separate from [`send`] rather than folded into it with an optional
    /// argument: an attachment turns the message into a multipart one, and the
    /// two call sites want different failure stories — a reset link that can't
    /// be delivered is an internal error, a 40 MB book that a recipient refuses
    /// is the user's problem to see and act on.
    pub async fn send_with_attachment(
        &self,
        to: &str,
        subject: &str,
        body: &str,
        filename: &str,
        content_type: &str,
        bytes: Vec<u8>,
    ) -> AppResult<()> {
        let attachment = Attachment::new(filename.to_string()).body(
            bytes,
            content_type
                .parse()
                .map_err(|e| AppError::Internal(format!("mail content type: {e}")))?,
        );
        let message = Message::builder()
            .from(
                self.from
                    .parse()
                    .map_err(|e| AppError::Internal(format!("mail from: {e}")))?,
            )
            .to(to
                .parse()
                .map_err(|_| AppError::BadRequest("not a valid email address".into()))?)
            .subject(subject)
            .multipart(
                MultiPart::mixed()
                    .singlepart(SinglePart::plain(body.to_string()))
                    .singlepart(attachment),
            )
            .map_err(|e| AppError::Internal(format!("mail body: {e}")))?;

        self.transport.send(message).await.map_err(|e| {
            tracing::error!("mail send (attachment) failed: {e}");
            // Deliberately more specific than `send`'s message: the most common
            // failure here is the recipient service rejecting the sender or the
            // size, and "could not send the email" would leave the user with
            // nothing to act on.
            AppError::BadGateway(
                "the mail server refused the message — check the size limit and \
                 that the sender address is approved by the recipient service"
                    .into(),
            )
        })?;
        Ok(())
    }
}

/// Whether mail is available, for the capability handshake and for handlers that
/// must degrade rather than fail.
pub fn is_enabled(mailer: &Option<Mailer>) -> bool {
    mailer.is_some()
}

/// Builds a mailer pointing at [host] without reading the environment.
///
/// For tests: env vars are process-wide, so configuring mail through them would
/// race every other test in the same binary. Nothing is connected until a send
/// is attempted, so this is safe with a host that doesn't exist.
pub fn for_testing(host: &str, from: &str) -> Mailer {
    Mailer {
        transport: AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(host)
            .expect("test relay")
            .build(),
        from: from.to_string(),
    }
}
