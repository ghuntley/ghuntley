//! Error types for the application

use thiserror::Error;
use axum::response::{Response, IntoResponse};
use axum::http::StatusCode;
use tracing::{error, debug};
use serde_json::json;

/// Result type alias for Art operations
pub type Result<T> = std::result::Result<T, Error>;

/// Main error type for Art operations
#[derive(Error, Debug)]
pub enum Error {
    /// Configuration errors
    #[error("Configuration error: {0}")]
    Config(String),

    /// Git errors
    #[error("Git error: {0}")]
    Git(#[from] git2::Error),

    /// Git command errors (different from git2::Error)
    #[error("Git command error: {0}")]
    GitError(String),

    /// Git protocol errors
    #[error("Git protocol error: {0}")]
    GitProtocol(String),

    /// Database errors
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    /// Connection pool errors
    #[error("Connection pool error: {0}")]
    Pool(#[from] r2d2::Error),

    /// HTTP errors
    #[error("HTTP error: {0}")]
    Http(#[from] hyper::Error),

    /// IO errors
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// IO errors with context
    #[error("IO error: {0}")]
    IoError(String),

    /// Template rendering errors
    #[error("Template error: {0}")]
    Template(#[from] askama::Error),

    /// Not found errors
    #[error("Not found: {0}")]
    NotFound(String),

    /// Invalid input errors
    #[error("Invalid input: {0}")]
    InvalidInput(String),

    /// Invalid request errors
    #[error("Invalid request: {0}")]
    InvalidRequest(String),

    /// Authentication errors
    #[error("Authentication error: {0}")]
    Authentication(String),

    /// Authorization errors
    #[error("Authorization error: {0}")]
    Authorization(String),

    /// Internal server errors
    #[error("Internal server error: {0}")]
    Internal(String),

    /// Internal application error
    #[error("Internal error: {0}")]
    InternalApp(String),

    /// Repository not found
    #[error("Repository '{0}' not found")]
    RepositoryNotFound(String),

    /// File not found
    #[error("File '{0}' not found")]
    FileNotFound(String),

    /// Commit not found
    #[error("Commit '{0}' not found")]
    CommitNotFound(String),

    /// Branch not found
    #[error("Branch '{0}' not found")]
    BranchNotFound(String),

    /// Tag not found
    #[error("Tag '{0}' not found")]
    TagNotFound(String),

    /// Cache error
    #[error("Cache error: {0}")]
    Cache(String),

    /// Unauthorized
    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    /// Forbidden
    #[error("Forbidden: {0}")]
    Forbidden(String),

    /// LFS error
    #[error("LFS error: {0}")]
    Lfs(String),

    /// Serialization error
    #[error("Serialization error: {0}")]
    Serialization(String),

    /// Deserialization error
    #[error("Deserialization error: {0}")]
    Deserialization(String),

    /// User not found
    #[error("User '{0}' not found")]
    UserNotFound(String),

    /// Username already taken
    #[error("Username '{0}' is already taken")]
    UsernameTaken(String),

    /// Email already taken
    #[error("Email '{0}' is already taken")]
    EmailTaken(String),

    /// Rate limit exceeded
    #[error("Rate limit exceeded: {0}")]
    RateLimitExceeded(String),

    /// Configuration errors
    #[error("Configuration error: {0}")]
    ConfigurationError(String),

    /// Email-related errors
    #[error("Email error: {0}")]
    EmailError(String),

    /// Invalid operation errors
    #[error("Invalid operation: {0}")]
    InvalidOperation(String),

    /// Duplicate resource errors
    #[error("Duplicate resource: {0}")]
    DuplicateResource(String),

    /// Feature or service not enabled
    #[error("Not enabled: {0}")]
    NotEnabled(String),

    /// Repository errors
    #[error("Repository error: {0}")]
    Repository(String),

    /// Server errors
    #[error("Server error: {0}")]
    Server(String),

    /// HTTP client errors (reqwest)
    #[error("HTTP client error: {0}")]
    Reqwest(#[from] reqwest::Error),

    /// Task join errors
    #[error("Task join error: {0}")]
    JoinError(#[from] tokio::task::JoinError),
}

// Implementation for converting errors to HTTP responses
impl IntoResponse for Error {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            // Client errors (4xx)
            Error::NotFound(msg) => {
                debug!(?self, "Not found error");
                (StatusCode::NOT_FOUND, msg.clone())
            }
            Error::InvalidRequest(msg) => {
                debug!(?self, "Invalid request error");
                (StatusCode::BAD_REQUEST, msg.clone())
            }
            Error::Authentication(msg) => {
                debug!(?self, "Authentication error");
                (StatusCode::UNAUTHORIZED, msg.clone())
            }
            Error::Authorization(msg) => {
                debug!(?self, "Authorization error");
                (StatusCode::FORBIDDEN, msg.clone())
            }

            // Server errors (5xx)
            Error::Git(e) => {
                error!(?self, "Git error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Database(e) => {
                error!(?self, "Database error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Pool(e) => {
                error!(?self, "Pool error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Http(e) => {
                error!(?self, "HTTP error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Io(e) => {
                error!(?self, "IO error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Template(e) => {
                error!(?self, "Template error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::Config(e) => {
                error!(?self, "Config error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Internal(e) => {
                error!(?self, "Internal server error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::InternalApp(e) => {
                error!(?self, "Internal application error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::RepositoryNotFound(e) => {
                error!(?self, "Repository not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::FileNotFound(e) => {
                error!(?self, "File not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::CommitNotFound(e) => {
                error!(?self, "Commit not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::BranchNotFound(e) => {
                error!(?self, "Branch not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::TagNotFound(e) => {
                error!(?self, "Tag not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::Cache(e) => {
                error!(?self, "Cache error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Unauthorized(e) => {
                error!(?self, "Unauthorized");
                (StatusCode::UNAUTHORIZED, e.clone())
            }
            Error::Forbidden(e) => {
                error!(?self, "Forbidden");
                (StatusCode::FORBIDDEN, e.clone())
            }
            Error::Lfs(e) => {
                error!(?self, "LFS error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Serialization(e) => {
                error!(?self, "Serialization error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Deserialization(e) => {
                error!(?self, "Deserialization error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::UserNotFound(e) => {
                error!(?self, "User not found");
                (StatusCode::NOT_FOUND, e.clone())
            }
            Error::UsernameTaken(e) => {
                error!(?self, "Username already taken");
                (StatusCode::CONFLICT, e.clone())
            }
            Error::EmailTaken(e) => {
                error!(?self, "Email already taken");
                (StatusCode::CONFLICT, e.clone())
            }
            Error::RateLimitExceeded(e) => {
                error!(?self, "Rate limit exceeded");
                (StatusCode::TOO_MANY_REQUESTS, e.clone())
            }
            Error::ConfigurationError(e) => {
                error!(?self, "Configuration error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::EmailError(e) => {
                error!(?self, "Email error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::InvalidOperation(e) => {
                error!(?self, "Invalid operation");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::DuplicateResource(e) => {
                error!(?self, "Duplicate resource");
                (StatusCode::CONFLICT, e.clone())
            }
            Error::NotEnabled(e) => {
                error!(?self, "Not enabled");
                (StatusCode::NOT_IMPLEMENTED, e.clone())
            }
            Error::Repository(e) => {
                error!(?self, "Repository error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Server(e) => {
                error!(?self, "Server error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.clone())
            }
            Error::Reqwest(e) => {
                error!(?self, "HTTP client error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
            Error::JoinError(e) => {
                error!(?self, "Task join error");
                (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            }
        };

        // Create a JSON response body
        let body = json!({
            "status": status.as_u16(),
            "error": message
        });

        (status, axum::Json(body)).into_response()
    }
}

/// API-specific error that converts to an HTTP response
#[derive(Debug)]
pub struct ApiError(pub StatusCode, pub String);

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let ApiError(status, message) = self;

        // Log errors differently based on status
        if status.is_server_error() {
            error!(?status, ?message, "API server error");
        } else {
            debug!(?status, ?message, "API client error");
        }

        // Create a JSON response body
        let body = json!({
            "status": status.as_u16(),
            "error": message
        });

        (status, axum::Json(body)).into_response()
    }
}

/// Create a not found error
pub fn not_found(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::NOT_FOUND, message.into())
}

/// Create a bad request error
pub fn bad_request(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::BAD_REQUEST, message.into())
}

/// Create an internal server error
pub fn internal_error(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::INTERNAL_SERVER_ERROR, message.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::response::IntoResponse;
    use axum::http::StatusCode;
    use std::io;

    #[test]
    fn test_error_conversion() {
        // Test converting various error types to HTTP responses

        // NotFound error
        let err = Error::NotFound("Repository not found".to_string());
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::NOT_FOUND);

        // InvalidRequest error
        let err = Error::InvalidRequest("Invalid parameter".to_string());
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);

        // Authentication error
        let err = Error::Authentication("Invalid credentials".to_string());
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

        // Authorization error
        let err = Error::Authorization("Permission denied".to_string());
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);

        // Internal error
        let err = Error::Internal("Something went wrong".to_string());
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn test_api_error() {
        // Test the ApiError type

        // Not found error
        let err = not_found("Repository not found");
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::NOT_FOUND);

        // Bad request error
        let err = bad_request("Invalid parameter");
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);

        // Internal server error
        let err = internal_error("Something went wrong");
        let res = err.into_response();
        assert_eq!(res.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn test_error_display() {
        // Test the Display implementation for Error

        let err = Error::NotFound("Repository not found".to_string());
        assert_eq!(err.to_string(), "Not found: Repository not found");

        let err = Error::InvalidRequest("Invalid parameter".to_string());
        assert_eq!(err.to_string(), "Invalid request: Invalid parameter");

        let err = Error::Internal("Something went wrong".to_string());
        assert_eq!(err.to_string(), "Internal server error: Something went wrong");
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use axum::http::StatusCode;
    use std::io;

    proptest! {
        /// Test that all error variants can be converted to a string
        #[test]
        fn error_display_all_variants(message in ".*") {
            let errors = vec![
                Error::Config(message.clone()),
                Error::Git(git2::Error::from_str(&message).to_string()),
                Error::Database(rusqlite::Error::InvalidPath(message.clone()).to_string()),
                Error::Pool(r2d2::Error::ConnectionError(io::Error::new(io::ErrorKind::Other, message.clone())).to_string()),
                Error::Git(git2::Error::from_str(&message)),
                Error::Database(rusqlite::Error::InvalidPath(message.clone())),
                Error::Pool(r2d2::Error::ConnectionError(io::Error::new(io::ErrorKind::Other, message.clone()))),
                Error::Http(hyper::Error::new_closed()),
                Error::Io(io::Error::new(io::ErrorKind::Other, message.clone())),
                Error::Template(askama::Error::Custom(message.clone())),
                Error::NotFound(message.clone()),
                Error::InvalidRequest(message.clone()),
                Error::Authentication(message.clone()),
                Error::Authorization(message.clone()),
                Error::Internal(message.clone()),
            ];

            for error in errors {
                // Convert error to string representation
                let display = format!("{}", error);

                // The display string should not be empty
                assert!(!display.is_empty(), "Error display should not be empty");

                // Should include the error variant name
                match error {
                    Error::Config(_) => assert!(display.contains("Config"), "Config error should mention 'Config'"),
                    Error::Git(_) => assert!(display.contains("Git"), "Git error should mention 'Git'"),
                    Error::Database(_) => assert!(display.contains("Database"), "Database error should mention 'Database'"),
                    Error::Pool(_) => assert!(display.contains("pool") || display.contains("Pool"), "Pool error should mention 'pool'"),
                    Error::Http(_) => assert!(display.contains("HTTP") || display.contains("Http"), "Http error should mention 'HTTP'"),
                    Error::Io(_) => assert!(display.contains("IO") || display.contains("Io"), "IO error should mention 'IO'"),
                    Error::Template(_) => assert!(display.contains("Template"), "Template error should mention 'Template'"),
                    Error::NotFound(_) => assert!(display.contains("Not found"), "NotFound error should mention 'Not found'"),
                    Error::InvalidRequest(_) => assert!(display.contains("Invalid request"), "InvalidRequest error should mention 'Invalid request'"),
                    Error::Authentication(_) => assert!(display.contains("Authentication"), "Authentication error should mention 'Authentication'"),
                    Error::Authorization(_) => assert!(display.contains("Authorization"), "Authorization error should mention 'Authorization'"),
                    Error::Internal(_) => assert!(display.contains("Internal"), "Internal error should mention 'Internal'"),
                }

                // If a non-empty message was provided, it should be included
                if !message.is_empty() {
                    // Note: Some error types might not directly include the message
                    if let Error::NotFound(_) | Error::InvalidRequest(_) |
                             Error::Authentication(_) | Error::Authorization(_) |
                             Error::Internal(_) | Error::Config(_) = error {
                        assert!(display.contains(&message),
                               "Error message should include the provided message: {} not in {}",
                               message, display);
                    }
                }
            }
        }

        /// Test that ApiError handles status codes and messages correctly
        #[test]
        fn api_error_properties(
            message in ".*",
            status_code in 400u16..600u16,
        ) {
            // Create a valid status code (in the 4xx or 5xx range)
            let status = StatusCode::from_u16(status_code).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);

            // Create an ApiError
            let api_error = ApiError(status, message.clone());

            // Convert to a response
            let response = api_error.into_response();

            // Response should have the expected status code
            assert_eq!(response.status(), status);

            // Helper functions should create appropriate ApiErrors
            let not_found = not_found(message.clone());
            assert_eq!(not_found.0, StatusCode::NOT_FOUND);
            assert_eq!(not_found.1, message);

            let bad_request = bad_request(message.clone());
            assert_eq!(bad_request.0, StatusCode::BAD_REQUEST);
            assert_eq!(bad_request.1, message);

            let internal_error = internal_error(message.clone());
            assert_eq!(internal_error.0, StatusCode::INTERNAL_SERVER_ERROR);
            assert_eq!(internal_error.1, message);
        }

        /// Test that errors can be converted to responses
        #[test]
        fn error_into_response(message in ".*") {
            // Create errors of different types
            let errors = vec![
                Error::NotFound(message.clone()),
                Error::InvalidRequest(message.clone()),
                Error::Authentication(message.clone()),
                Error::Authorization(message.clone()),
                Error::Internal(message.clone()),
                Error::Config(message.clone()),
                Error::Git(git2::Error::from_str(&message)),
                Error::Database(rusqlite::Error::InvalidPath(message.clone())),
            ];

            for error in errors {
                // Convert error to response
                let response = error.into_response();

                // Check that the status code is appropriate for the error type
                match error {
                    Error::NotFound(_) => assert_eq!(response.status(), StatusCode::NOT_FOUND),
                    Error::InvalidRequest(_) => assert_eq!(response.status(), StatusCode::BAD_REQUEST),
                    Error::Authentication(_) => assert_eq!(response.status(), StatusCode::UNAUTHORIZED),
                    Error::Authorization(_) => assert_eq!(response.status(), StatusCode::FORBIDDEN),
                    // All other errors should be internal server errors
                    _ => assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR),
                }
            }
        }
    }
}
