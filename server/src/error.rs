use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;

/// Every fallible handler returns this; it renders as `{ "error": "..." }` with
/// an appropriate status code.
#[derive(Debug)]
pub enum AppError {
    Unauthorized(String),
    Forbidden(String),
    NotFound(String),
    BadRequest(String),
    Conflict(String),
    TooManyRequests(String),
    /// An upstream this server depends on refused the request — today only the
    /// SMTP relay (plan 5 #53). Distinct from `Internal` because the message is
    /// *actionable by the user* ("that address is not approved", "the file is
    /// too large for the recipient") and so, unlike an internal error, it is
    /// passed through rather than swallowed.
    BadGateway(String),
    Internal(String),
}

pub type AppResult<T> = Result<T, AppError>;

impl AppError {
    /// The human-readable message, regardless of variant — for a caller that
    /// catches the error itself instead of letting it become an HTTP response
    /// (e.g. a batch endpoint reporting one item's failure without aborting
    /// the rest; see `books::batch_upsert`).
    pub fn message(&self) -> String {
        match self {
            AppError::Unauthorized(m)
            | AppError::Forbidden(m)
            | AppError::NotFound(m)
            | AppError::BadRequest(m)
            | AppError::Conflict(m)
            | AppError::TooManyRequests(m)
            | AppError::BadGateway(m)
            | AppError::Internal(m) => m.clone(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        // No `WWW-Authenticate` here, deliberately. A Basic challenge on a 401
        // makes a *browser* pop its own native credential dialog over the
        // console — which appeared the moment the page loaded, again on every
        // failed sign-in, and left no way to log in through the console's own
        // form. OPDS e-readers do need the challenge, so it is added by a layer
        // on those routes alone (see `opds_challenge` in lib.rs).
        let (status, message) = match self {
            AppError::Unauthorized(m) => (StatusCode::UNAUTHORIZED, m),
            AppError::Forbidden(m) => (StatusCode::FORBIDDEN, m),
            AppError::NotFound(m) => (StatusCode::NOT_FOUND, m),
            AppError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            AppError::Conflict(m) => (StatusCode::CONFLICT, m),
            AppError::TooManyRequests(m) => (StatusCode::TOO_MANY_REQUESTS, m),
            AppError::BadGateway(m) => (StatusCode::BAD_GATEWAY, m),
            AppError::Internal(m) => {
                tracing::error!("internal error: {m}");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal server error".to_string(),
                )
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}
