//! HTTP error handling

use crate::error::Error;
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

/// Convert application errors to HTTP responses
impl IntoResponse for Error {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            // Client errors
            Error::NotFound(ref msg) => (StatusCode::NOT_FOUND, msg.clone()),
            Error::InvalidRequest(ref msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            Error::Authentication(ref msg) => (StatusCode::UNAUTHORIZED, msg.clone()),
            Error::Authorization(ref msg) => (StatusCode::FORBIDDEN, msg.clone()),

            // Server errors
            Error::Git(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Git error: {}", err),
            ),
            Error::Database(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Database error: {}", err),
            ),
            Error::Pool(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Connection pool error: {}", err),
            ),
            Error::Http(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("HTTP error: {}", err),
            ),
            Error::Io(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("IO error: {}", err),
            ),
            Error::Template(ref err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Template error: {}", err),
            ),
            Error::Config(ref msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Configuration error: {}", msg),
            ),
            Error::Internal(ref msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Internal server error: {}", msg),
            ),
        };

        // Log the error
        if status == StatusCode::INTERNAL_SERVER_ERROR {
            error!("{}: {}", status.as_str(), error_message);
        } else {
            debug!("{}: {}", status.as_str(), error_message);
        }

        // Create a JSON response with the error details
        let body = Json(json!({
            "error": {
                "status": status.as_u16(),
                "message": error_message,
            }
        }));

        (status, body).into_response()
    }
}

/// HTTP error response for API handlers
#[derive(Debug)]
pub struct ApiError(pub StatusCode, pub String);

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.0;
        let message = self.1;

        // Log the error
        if status.is_server_error() {
            error!("{}: {}", status.as_str(), message);
        } else {
            debug!("{}: {}", status.as_str(), message);
        }

        let body = Json(json!({
            "error": {
                "status": status.as_u16(),
                "message": message,
            }
        }));

        (status, body).into_response()
    }
}

/// Create a not found API error
pub fn not_found(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::NOT_FOUND, message.into())
}

/// Create a bad request API error
pub fn bad_request(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::BAD_REQUEST, message.into())
}

/// Create an internal server error
pub fn internal_error(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::INTERNAL_SERVER_ERROR, message.into())
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use axum::http::StatusCode;
    use crate::error::Error;
    use axum::response::Response;
    use serde_json::Value;
    use hyper::body::Bytes;

    // Strategy to generate valid HTTP status codes (4xx and 5xx for errors)
    fn status_code_strategy() -> impl Strategy<Value = StatusCode> {
        (400u16..600).prop_map(|code| {
            StatusCode::from_u16(code)
                .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR)
        })
    }

    // Strategy to generate error messages
    fn error_message_strategy() -> impl Strategy<Value = String> {
        ".{0,100}"
    }

    // Helper to extract JSON from a response
    async fn response_to_json(response: Response) -> Option<Value> {
        let body = hyper::body::to_bytes(response.into_body())
            .await
            .ok()?;
        serde_json::from_slice::<Value>(&body).ok()
    }

    proptest! {
        /// Test that all error types have the correct status code conversion
        #[test]
        fn error_to_status_code_mapping(
            message in "[a-zA-Z0-9 _.-]{1,50}"
        ) {
            // Create errors of different types
            let not_found_error = Error::NotFound(message.clone());
            let invalid_request_error = Error::InvalidRequest(message.clone());
            let auth_error = Error::Authentication(message.clone());
            let authorization_error = Error::Authorization(message.clone());
            let internal_error = Error::Internal(message.clone());
            let config_error = Error::Config(message.clone());

            // Check that each error type maps to the correct status code
            let not_found_response = not_found_error.into_response();
            assert_eq!(not_found_response.status(), StatusCode::NOT_FOUND);

            let invalid_request_response = invalid_request_error.into_response();
            assert_eq!(invalid_request_response.status(), StatusCode::BAD_REQUEST);

            let auth_response = auth_error.into_response();
            assert_eq!(auth_response.status(), StatusCode::UNAUTHORIZED);

            let authorization_response = authorization_error.into_response();
            assert_eq!(authorization_response.status(), StatusCode::FORBIDDEN);

            let internal_response = internal_error.into_response();
            assert_eq!(internal_response.status(), StatusCode::INTERNAL_SERVER_ERROR);

            let config_response = config_error.into_response();
            assert_eq!(config_response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        }

        /// Test that ApiError correctly forms error responses
        #[test]
        fn api_error_forms_correct_response(
            status_code in status_code_strategy(),
            message in error_message_strategy(),
        ) {
            // Create an ApiError with the given status code and message
            let api_error = ApiError(status_code, message.clone());

            // Convert it to a response
            let response = api_error.into_response();

            // Check that the status code is preserved
            assert_eq!(response.status(), status_code);

            // Check that the body is valid JSON with the error message
            tokio::runtime::Runtime::new().unwrap().block_on(async {
                if let Some(json) = response_to_json(response).await {
                    if let Some(error_msg) = json.get("error").and_then(|v| v.as_str()) {
                        assert_eq!(error_msg, message);
                    } else {
                        // If we couldn't extract the error message from JSON, fail the test
                        assert!(false, "Response JSON should contain an 'error' field with the message");
                    }
                } else {
                    // If we couldn't parse the body as JSON, fail the test
                    assert!(false, "Response body should be valid JSON");
                }
            });
        }

        /// Test the error helper functions
        #[test]
        fn error_helpers_produce_correct_errors(
            message in error_message_strategy(),
        ) {
            // Test the not_found helper
            let not_found_error = not_found(message.clone());
            assert_eq!(not_found_error.0, StatusCode::NOT_FOUND);
            assert_eq!(not_found_error.1, message);

            // Test the bad_request helper
            let bad_request_error = bad_request(message.clone());
            assert_eq!(bad_request_error.0, StatusCode::BAD_REQUEST);
            assert_eq!(bad_request_error.1, message);

            // Test the internal_error helper
            let internal_error_error = internal_error(message.clone());
            assert_eq!(internal_error_error.0, StatusCode::INTERNAL_SERVER_ERROR);
            assert_eq!(internal_error_error.1, message);
        }

        /// Test error response content type and structure
        #[test]
        fn error_response_has_correct_content_type_and_structure(
            status_code in status_code_strategy(),
            message in error_message_strategy(),
        ) {
            // Create an ApiError
            let api_error = ApiError(status_code, message.clone());

            // Convert it to a response
            let response = api_error.into_response();

            // Check the content-type header is application/json
            let content_type = response.headers().get("content-type")
                .map(|h| h.to_str().unwrap_or(""))
                .unwrap_or("");

            assert!(content_type.contains("application/json"),
                "Response Content-Type should be application/json");

            // Check the body structure
            tokio::runtime::Runtime::new().unwrap().block_on(async {
                if let Some(json) = response_to_json(response).await {
                    // Check required fields exist
                    assert!(json.get("error").is_some(), "Response JSON should contain an 'error' field");
                    assert!(json.get("status").is_some(), "Response JSON should contain a 'status' field");

                    // Check field types
                    assert!(json.get("error").unwrap().is_string(), "The 'error' field should be a string");
                    assert!(json.get("status").unwrap().is_number(), "The 'status' field should be a number");

                    // Check field values
                    assert_eq!(json.get("error").unwrap().as_str().unwrap(), message);
                    assert_eq!(json.get("status").unwrap().as_u64().unwrap() as u16, status_code.as_u16());
                } else {
                    assert!(false, "Response body should be valid JSON");
                }
            });
        }
    }
}
