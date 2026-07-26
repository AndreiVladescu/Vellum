use axum::{
    Json,
    http::{StatusCode, header},
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
            | AppError::Internal(m) => m.clone(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        // 401s carry a Basic challenge so OPDS e-readers show a login prompt.
        if let AppError::Unauthorized(m) = &self {
            return (
                StatusCode::UNAUTHORIZED,
                [(header::WWW_AUTHENTICATE, "Basic realm=\"Vellum\"")],
                Json(json!({ "error": m })),
            )
                .into_response();
        }
        let (status, message) = match self {
            AppError::Unauthorized(m) => (StatusCode::UNAUTHORIZED, m),
            AppError::Forbidden(m) => (StatusCode::FORBIDDEN, m),
            AppError::NotFound(m) => (StatusCode::NOT_FOUND, m),
            AppError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            AppError::Conflict(m) => (StatusCode::CONFLICT, m),
            AppError::TooManyRequests(m) => (StatusCode::TOO_MANY_REQUESTS, m),
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
