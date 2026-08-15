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

use axum::Json;
use axum::extract::State;

use crate::error::{AppError, AppResult};

/// The mailer, present only when the operator configured SMTP.
#[derive(Clone)]
pub struct Mailer {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from: String,
}

/// A variable's value, treating empty and whitespace-only as absent.
///
/// `VELLUM_SMTP_USER=""` reaching the process is not somebody asking to
/// authenticate as nobody — it is a `${VELLUM_SMTP_USER:-}` in a compose file
/// that found nothing to substitute. Docker passes those through as empty
/// strings rather than omitting them, so "set" and "set to nothing" have to
/// mean the same thing here.
fn env_value(key: &str) -> Option<String> {
    let value = std::env::var(key).ok()?;
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_string())
}

impl Mailer {
    /// Reads the configuration from the environment.
    ///
    /// Returns `Ok(None)` when mail is simply off (no host configured) and an
    /// error only when it is configured *incorrectly* — a typo in a port or a
    /// missing `VELLUM_MAIL_FROM` should stop the server at boot rather than
    /// surface as a failed password reset weeks later.
    pub fn from_env() -> anyhow::Result<Option<Self>> {
        let Some(host) = env_value("VELLUM_SMTP_HOST") else {
            // Nothing at all, or a passthrough that resolved to nothing. Warn if
            // the *rest* of the setup is there: "mail: disabled" beside a
            // populated .env is a confusing thing to read, and the usual cause
            // is a container that was never handed the variables.
            if env_value("VELLUM_SMTP_USER").is_some() || env_value("VELLUM_MAIL_FROM").is_some() {
                tracing::warn!(
                    "mail: VELLUM_SMTP_HOST is empty or unset, so mail stays off — \
                     the other SMTP variables are set, which usually means the host \
                     one did not reach this process (in Docker, check that \
                     docker-compose.yml passes it through)"
                );
            }
            return Ok(None);
        };

        let port: u16 = match env_value("VELLUM_SMTP_PORT") {
            Some(raw) => raw
                .parse()
                .map_err(|_| anyhow::anyhow!("VELLUM_SMTP_PORT must be a port number"))?,
            // 587 (submission + STARTTLS) rather than 465 or 25: it is what
            // Gmail, Fastmail and most providers expect, and 25 is usually
            // blocked outbound anyway.
            None => 587,
        };

        let from = env_value("VELLUM_MAIL_FROM").ok_or_else(|| {
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

        // Credentials are optional: an internal relay may not want any. An
        // *empty* username is not "no username" by accident either — it would
        // authenticate as nobody and be refused, which is a worse failure than
        // not authenticating at all.
        if let Some(user) = env_value("VELLUM_SMTP_USER") {
            let pass = env_value("VELLUM_SMTP_PASS").unwrap_or_default();
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

    /// The configured sender address, for the operator's own screen.
    ///
    /// Named `sender` rather than `from_address`: a `from_*` method that takes
    /// `self` reads as a constructor everywhere else in Rust.
    ///
    /// Safe to show a master: it is the address recipients will see anyway. The
    /// username and password are never exposed, and the host is not either —
    /// knowing *that* mail works matters more than which relay carries it.
    pub fn sender(&self) -> &str {
        &self.from
    }

    /// Sends a test message and hands back what the relay actually said.
    ///
    /// The other two senders swallow the relay's error on purpose — a user
    /// resetting a password can do nothing with "535 5.7.8 Username and
    /// Password not accepted". An operator who has just typed those credentials
    /// in can do everything with it, and without it they are reduced to reading
    /// the server log to find out whether their setup works. So this one, and
    /// only this one, reports the failure verbatim.
    ///
    /// The relay's error names the host and may name the username; it never
    /// contains the password, which lettre sends but does not echo.
    pub async fn send_test(&self, to: &str) -> Result<(), String> {
        let message = Message::builder()
            .from(self.from.parse().map_err(|e| format!("mail from: {e}"))?)
            .to(to
                .parse()
                .map_err(|_| "not a valid email address".to_string())?)
            .subject("Vellum: mail is working")
            .header(ContentType::TEXT_PLAIN)
            .body(
                "This is a test from your Vellum server.\n\n\
                 If you are reading it, invitations and password resets will \
                 reach people too.\n"
                    .to_string(),
            )
            .map_err(|e| format!("mail body: {e}"))?;

        self.transport
            .send(message)
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }
}

/// Whether mail is available, for the capability handshake and for handlers that
/// must degrade rather than fail.
pub fn is_enabled(mailer: &Option<Mailer>) -> bool {
    mailer.is_some()
}

/// `GET /api/mail/status` — is mail on, and as whom.
///
/// `GET /api/capabilities` already answers the on/off half, but it is public and
/// deliberately says nothing more. An operator setting SMTP up needs the sender
/// address echoed back: the commonest configuration mistake is a `VELLUM_MAIL_FROM`
/// the relay will not accept, and seeing it beside the test button is what turns
/// a silent failure into an obvious one.
pub async fn status(
    State(state): State<crate::AppState>,
    user: crate::auth::AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only an owner may see the mail setup".into(),
        ));
    }
    Ok(Json(match &state.mailer {
        Some(m) => serde_json::json!({ "enabled": true, "from": m.sender() }),
        None => serde_json::json!({ "enabled": false }),
    }))
}

/// `POST /api/mail/test` — sends a test message to the caller's own address.
///
/// To *their* address, not one they name: this proves the relay works without
/// turning the endpoint into something that sends mail to strangers.
pub async fn test_send(
    State(state): State<crate::AppState>,
    user: crate::auth::AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only an owner may test the mail setup".into(),
        ));
    }
    let Some(mailer) = &state.mailer else {
        // Not an error the operator caused — it is the state before setup, and
        // the answer is the name of the variable that starts it.
        return Err(AppError::BadRequest(
            "mail is off on this server: set VELLUM_SMTP_HOST and VELLUM_MAIL_FROM, \
             then restart it"
                .into(),
        ));
    };
    match mailer.send_test(&user.email).await {
        Ok(()) => Ok(Json(serde_json::json!({ "sent_to": user.email }))),
        // 502: the relay refused, this server did its part. The message is the
        // relay's own, which is the whole point of the endpoint.
        Err(e) => Err(AppError::BadGateway(format!(
            "the mail server refused it: {e}"
        ))),
    }
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
