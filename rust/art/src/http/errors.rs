//! HTTP error handling

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};
use std::fmt;

/// HTTP error type
#[derive(Debug)]
pub enum HttpError {
    /// Not found error (404)
    NotFound(String),
    /// Bad request error (400)
    BadRequest(String),
    /// Unauthorized error (401)
    Unauthorized(String),
    /// Forbidden error (403)
    Forbidden(String),
    /// Internal server error (500)
    InternalError(String),
}

impl fmt::Display for HttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HttpError::NotFound(msg) => write!(f, "Not found: {}", msg),
            HttpError::BadRequest(msg) => write!(f, "Bad request: {}", msg),
            HttpError::Unauthorized(msg) => write!(f, "Unauthorized: {}", msg),
            HttpError::Forbidden(msg) => write!(f, "Forbidden: {}", msg),
            HttpError::InternalError(msg) => write!(f, "Internal server error: {}", msg),
        }
    }
}

impl IntoResponse for HttpError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            HttpError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            HttpError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            HttpError::Unauthorized(msg) => (StatusCode::UNAUTHORIZED, msg),
            HttpError::Forbidden(msg) => (StatusCode::FORBIDDEN, msg),
            HttpError::InternalError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };

        (status, message).into_response()
    }
}

impl From<crate::error::Error> for HttpError {
    fn from(err: crate::error::Error) -> Self {
        match err {
            crate::error::Error::NotFound(msg) => HttpError::NotFound(msg),
            crate::error::Error::InvalidInput(msg) => HttpError::BadRequest(msg),
            crate::error::Error::Unauthorized(msg) => HttpError::Unauthorized(msg),
            crate::error::Error::Forbidden(msg) => HttpError::Forbidden(msg),
            _ => HttpError::InternalError(format!("{}", err)),
        }
    }
}
