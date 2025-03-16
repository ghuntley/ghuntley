// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! User management API handlers
//!
//! This module provides HTTP API handlers for user management
//! in the Art application.

use crate::data::user::{User, UserRole};
use crate::error::Error;
use crate::service::user::UserService;
use axum::{
    extract::{Extension, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, info, warn, instrument};
use std::convert::Infallible;
use tower_cookies::{Cookie, Cookies};
use validator::Validate;

// Constants
const SESSION_COOKIE_NAME: &str = "art_session";
const SESSION_COOKIE_PATH: &str = "/";
const SESSION_COOKIE_SECURE: bool = true;
const SESSION_COOKIE_HTTP_ONLY: bool = true;

/// User API handler for HTTP requests
pub struct UserApiHandler {
    /// User service instance
    service: Arc<UserService>,
}

impl UserApiHandler {
    /// Create a new user API handler
    pub fn new(service: Arc<UserService>) -> Self {
        Self { service }
    }

    /// Create the API router for user-related endpoints
    pub fn create_router(self) -> Router {
        Router::new()
            .route("/login", post(Self::login))
            .route("/logout", post(Self::logout))
            .route("/current", get(Self::current_user))
            .route("/", get(Self::list_users))
            .route("/", post(Self::create_user))
            .route("/:id", get(Self::get_user))
            .route("/:id", put(Self::update_user))
            .route("/:id", delete(Self::delete_user))
            .with_state(Arc::new(self))
    }

    /// Handle user login
    #[instrument(skip(state, cookies, body))]
    async fn login(
        State(state): State<Arc<Self>>,
        mut cookies: Cookies,
        headers: HeaderMap,
        Json(body): Json<LoginRequest>,
    ) -> Result<impl IntoResponse, Error> {
        // Get client IP address and user agent
        let ip_address = headers
            .get("x-forwarded-for")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("unknown")
            .to_string();

        let user_agent = headers
            .get("user-agent")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("unknown")
            .to_string();

        // Authenticate user and create session
        let (user, session) = state.service.login(
            &body.username,
            &body.password,
            ip_address,
            user_agent,
        ).await?;

        // Set session cookie
        let cookie = Cookie::build(SESSION_COOKIE_NAME, session.id.clone())
            .path(SESSION_COOKIE_PATH)
            .secure(SESSION_COOKIE_SECURE)
            .http_only(SESSION_COOKIE_HTTP_ONLY)
            .finish();

        cookies.add(cookie);

        // Return user data
        Ok((StatusCode::OK, Json(UserResponse::from(user))))
    }

    /// Handle user logout
    #[instrument(skip(state, cookies))]
    async fn logout(
        State(state): State<Arc<Self>>,
        mut cookies: Cookies,
    ) -> Result<impl IntoResponse, Error> {
        // Get session ID from cookie
        if let Some(cookie) = cookies.get(SESSION_COOKIE_NAME) {
            // Attempt to remove the session
            let _ = state.service.logout(cookie.value()).await;

            // Remove the cookie
            cookies.remove(Cookie::build(SESSION_COOKIE_NAME, "")
                .path(SESSION_COOKIE_PATH)
                .finish());
        }

        // Return success even if no session existed
        Ok(StatusCode::NO_CONTENT)
    }

    /// Get the current logged-in user
    #[instrument(skip(state, cookies))]
    async fn current_user(
        State(state): State<Arc<Self>>,
        cookies: Cookies,
    ) -> Result<impl IntoResponse, Error> {
        // Get session ID from cookie
        let session_id = match cookies.get(SESSION_COOKIE_NAME) {
            Some(cookie) => cookie.value().to_string(),
            None => return Err(Error::Unauthorized("Not logged in".to_string())),
        };

        // Get user from session
        let user = match state.service.get_session_user(&session_id).await? {
            Some(user) => user,
            None => return Err(Error::Unauthorized("Session expired".to_string())),
        };

        // Return user data
        Ok((StatusCode::OK, Json(UserResponse::from(user))))
    }

    /// List all users
    #[instrument(skip(state))]
    async fn list_users(
        State(state): State<Arc<Self>>,
        Query(params): Query<ListUsersParams>,
        cookies: Cookies,
    ) -> Result<impl IntoResponse, Error> {
        // Verify that the requesting user has permission
        Self::require_admin(&state, &cookies).await?;

        // Get users with pagination
        let users = state.service.list_users(
            Some(params.limit.unwrap_or(20) as usize),
            Some(params.offset.unwrap_or(0) as usize),
        ).await?;

        // Convert to response format
        let user_responses: Vec<UserResponse> = users.into_iter()
            .map(UserResponse::from)
            .collect();

        // Return users list
        Ok((StatusCode::OK, Json(user_responses)))
    }

    /// Get a user by ID
    #[instrument(skip(state))]
    async fn get_user(
        State(state): State<Arc<Self>>,
        Path(id): Path<i64>,
        cookies: Cookies,
    ) -> Result<impl IntoResponse, Error> {
        // Verify that the requesting user has permission
        Self::require_admin(&state, &cookies).await?;

        // Get user by ID
        let user = state.service.get_user(id).await?;

        // Return user data
        Ok((StatusCode::OK, Json(UserResponse::from(user))))
    }

    /// Create a new user
    #[instrument(skip(state, body))]
    async fn create_user(
        State(state): State<Arc<Self>>,
        cookies: Cookies,
        Json(body): Json<CreateUserRequest>,
    ) -> Result<impl IntoResponse, Error> {
        // Verify that the requesting user has permission
        Self::require_admin(&state, &cookies).await?;

        // Validate the request
        body.validate().map_err(|e| Error::InvalidRequest(e.to_string()))?;

        // Create user
        let user = state.service.create_user(
            body.username,
            body.email,
            body.display_name,
            &body.password,
            body.role.unwrap_or(UserRole::User),
        ).await?;

        // Return user data
        Ok((StatusCode::CREATED, Json(UserResponse::from(user))))
    }

    /// Update an existing user
    #[instrument(skip(state, body))]
    async fn update_user(
        State(state): State<Arc<Self>>,
        Path(id): Path<i64>,
        cookies: Cookies,
        Json(body): Json<UpdateUserRequest>,
    ) -> Result<impl IntoResponse, Error> {
        // Verify that the requesting user has permission
        let current_user = Self::get_current_user(&state, &cookies).await?;

        // Users can update their own profiles, but only admins can update others
        if current_user.id != id && !current_user.is_admin() {
            return Err(Error::Forbidden("Insufficient permissions".to_string()));
        }

        // Validate the request
        body.validate().map_err(|e| Error::InvalidRequest(e.to_string()))?;

        // If the user is trying to change their role or active status and they're not an admin,
        // return an error
        if (body.role.is_some() || body.active.is_some()) && !current_user.is_admin() {
            return Err(Error::Forbidden("Cannot change role or active status".to_string()));
        }

        // Update user
        let user = state.service.update_user(
            id,
            body.email,
            body.display_name,
            body.password.as_deref(),
            body.role,
            body.active,
        ).await?;

        // Return updated user data
        Ok((StatusCode::OK, Json(UserResponse::from(user))))
    }

    /// Delete a user
    #[instrument(skip(state))]
    async fn delete_user(
        State(state): State<Arc<Self>>,
        Path(id): Path<i64>,
        cookies: Cookies,
    ) -> Result<impl IntoResponse, Error> {
        // Verify that the requesting user has permission
        Self::require_admin(&state, &cookies).await?;

        // Cannot delete yourself
        let current_user = Self::get_current_user(&state, &cookies).await?;
        if current_user.id == id {
            return Err(Error::Forbidden("Cannot delete yourself".to_string()));
        }

        // Delete user
        state.service.delete_user(id).await?;

        // Return success
        Ok(StatusCode::NO_CONTENT)
    }

    // Helper methods

    /// Get the current user from the session cookie
    async fn get_current_user(state: &Arc<Self>, cookies: &Cookies) -> Result<User, Error> {
        // Get session ID from cookie
        let session_id = match cookies.get(SESSION_COOKIE_NAME) {
            Some(cookie) => cookie.value().to_string(),
            None => return Err(Error::Unauthorized("Not logged in".to_string())),
        };

        // Get user from session
        match state.service.get_session_user(&session_id).await? {
            Some(user) => Ok(user),
            None => Err(Error::Unauthorized("Session expired".to_string())),
        }
    }

    /// Require the current user to be an admin
    async fn require_admin(state: &Arc<Self>, cookies: &Cookies) -> Result<User, Error> {
        let user = Self::get_current_user(state, cookies).await?;

        if !user.is_admin() {
            return Err(Error::Forbidden("Administrator privileges required".to_string()));
        }

        Ok(user)
    }
}

/// Login request
#[derive(Debug, Deserialize, Validate)]
pub struct LoginRequest {
    /// Username or email
    #[validate(length(min = 1, message = "Username is required"))]
    pub username: String,

    /// Password
    #[validate(length(min = 1, message = "Password is required"))]
    pub password: String,
}

/// List users query parameters
#[derive(Debug, Deserialize)]
pub struct ListUsersParams {
    /// Maximum number of users to return
    pub limit: Option<u32>,

    /// Number of users to skip
    pub offset: Option<u32>,
}

/// Create user request
#[derive(Debug, Deserialize, Validate)]
pub struct CreateUserRequest {
    /// Username
    #[validate(length(min = 3, message = "Username must be at least 3 characters"))]
    #[validate(length(max = 30, message = "Username must be at most 30 characters"))]
    pub username: String,

    /// Email
    #[validate(email(message = "Invalid email format"))]
    pub email: String,

    /// Display name
    #[validate(length(min = 1, message = "Display name is required"))]
    pub display_name: String,

    /// Password
    #[validate(length(min = 8, message = "Password must be at least 8 characters"))]
    pub password: String,

    /// User role (defaults to User)
    pub role: Option<UserRole>,
}

/// Update user request
#[derive(Debug, Deserialize, Validate)]
pub struct UpdateUserRequest {
    /// Email
    #[validate(email(message = "Invalid email format"))]
    #[validate(length(min = 1, message = "Email cannot be empty"))]
    pub email: Option<String>,

    /// Display name
    #[validate(length(min = 1, message = "Display name cannot be empty"))]
    pub display_name: Option<String>,

    /// New password
    #[validate(length(min = 8, message = "Password must be at least 8 characters"))]
    pub password: Option<String>,

    /// User role
    pub role: Option<UserRole>,

    /// Whether the account is active
    pub active: Option<bool>,
}

/// User response
#[derive(Debug, Serialize)]
pub struct UserResponse {
    /// User ID
    pub id: i64,

    /// Username
    pub username: String,

    /// Email
    pub email: String,

    /// Display name
    pub display_name: String,

    /// User role
    pub role: UserRole,

    /// Account creation timestamp
    pub created_at: String,

    /// Last login timestamp
    pub last_login: Option<String>,

    /// Whether the account is active
    pub active: bool,
}

impl From<User> for UserResponse {
    fn from(user: User) -> Self {
        Self {
            id: user.id,
            username: user.username,
            email: user.email,
            display_name: user.display_name,
            role: user.role,
            created_at: user.created_at.to_rfc3339(),
            last_login: user.last_login.map(|dt| dt.to_rfc3339()),
            active: user.active,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
        routing::{get, post, put, delete},
        Router,
    };
    use http_body_util::BodyExt;
    use tower::ServiceExt;
    use proptest::prelude::*;
    use std::net::SocketAddr;
    use sqlx::sqlite::SqlitePoolOptions;
    use std::time::Duration;

    // Create a test app with user service and handlers
    async fn create_test_app() -> Router {
        // Create an in-memory SQLite database
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .acquire_timeout(Duration::from_secs(3))
            .connect("sqlite::memory:")
            .await
            .unwrap();

        // Create and initialize user service
        let user_service = Arc::new(UserService::new(pool).unwrap());
        user_service.init().await.unwrap();

        // Create default admin user
        user_service.create_default_admin("admin", "admin@example.com", "password123").await.unwrap();

        // Create router with user API handlers
        Router::new()
            .route("/api/users/login", post(UserApiHandler::login))
            .route("/api/users/me", get(UserApiHandler::current_user))
            .route("/api/users", get(UserApiHandler::list_users))
            .route("/api/users", post(UserApiHandler::create_user))
            .route("/api/users/:id", get(UserApiHandler::get_user))
            .route("/api/users/:id", put(UserApiHandler::update_user))
            .route("/api/users/:id", delete(UserApiHandler::delete_user))
            .with_state(user_service)
    }

    // Generate valid usernames
    fn valid_username() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9_]{2,19}".prop_map(|s| s)
    }

    // Generate valid emails
    fn valid_email() -> impl Strategy<Value = String> {
        ("[a-z0-9_.-]{1,20}@[a-z0-9_.-]{1,20}\\.[a-z]{2,8}")
            .prop_map(|s| s)
    }

    // Generate valid passwords
    fn valid_password() -> impl Strategy<Value = String> {
        "[A-Za-z0-9!@#$%^&*]{8,30}".prop_map(|s| s)
    }

    // Generate valid full names
    fn valid_full_name() -> impl Strategy<Value = String> {
        "[A-Za-z ]{3,50}".prop_map(|s| s)
    }

    proptest! {
        #[test]
        fn test_login_endpoint(
            username in valid_username(),
            email in valid_email(),
            full_name in valid_full_name(),
            password in valid_password()
        ) {
            // Run the async test
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Create test app
                let app = create_test_app().await;

                // Create a test user
                let create_user = CreateUserRequest {
                    username: username.clone(),
                    email: email.clone(),
                    display_name: full_name.clone(),
                    password: password.clone(),
                    role: None,
                };

                let create_request = Request::builder()
                    .uri("/api/users")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&create_user).unwrap()))
                    .unwrap();

                let create_response = app.clone().oneshot(create_request).await.unwrap();
                prop_assert_eq!(create_response.status(), StatusCode::CREATED);

                // Test login with correct credentials
                let login_request = LoginRequest {
                    username: username.clone(),
                    password: password.clone(),
                };

                let login_request = Request::builder()
                    .uri("/api/users/login")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&login_request).unwrap()))
                    .unwrap();

                let login_response = app.clone().oneshot(login_request).await.unwrap();
                prop_assert_eq!(login_response.status(), StatusCode::OK);

                // Parse response body
                let body = login_response.into_body().collect().await.unwrap().to_bytes();
                let login_response: UserResponse = serde_json::from_slice(&body).unwrap();

                // Verify response
                prop_assert_eq!(login_response.username, username);
                prop_assert_eq!(login_response.email, email);
                prop_assert_eq!(login_response.display_name, full_name);
                prop_assert!(!login_response.id.is_empty());

                // Test login with incorrect password
                let login_request = LoginRequest {
                    username: username.clone(),
                    password: "wrong_password".to_string(),
                };

                let login_request = Request::builder()
                    .uri("/api/users/login")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&login_request).unwrap()))
                    .unwrap();

                let login_response = app.clone().oneshot(login_request).await.unwrap();
                prop_assert_eq!(login_response.status(), StatusCode::UNAUTHORIZED);
            });
        }

        #[test]
        fn test_list_users_endpoint() {
            // Run the async test
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Create test app
                let app = create_test_app().await;

                // List users
                let request = Request::builder()
                    .uri("/api/users")
                    .method("GET")
                    .body(Body::empty())
                    .unwrap();

                let response = app.clone().oneshot(request).await.unwrap();
                prop_assert_eq!(response.status(), StatusCode::OK);

                // Parse response body
                let body = response.into_body().collect().await.unwrap().to_bytes();
                let list_response: UserListResponse = serde_json::from_slice(&body).unwrap();

                // Verify response (should have at least the default admin user)
                prop_assert!(!list_response.users.is_empty());
                prop_assert_eq!(list_response.users.len(), list_response.total.min(list_response.limit));

                // Test pagination and filtering
                let request = Request::builder()
                    .uri("/api/users?limit=5&offset=0&role=admin")
                    .method("GET")
                    .body(Body::empty())
                    .unwrap();

                let response = app.clone().oneshot(request).await.unwrap();
                prop_assert_eq!(response.status(), StatusCode::OK);

                // Parse response body
                let body = response.into_body().collect().await.unwrap().to_bytes();
                let list_response: UserListResponse = serde_json::from_slice(&body).unwrap();

                // Should have at least the default admin user
                prop_assert!(!list_response.users.is_empty());

                // All users in the response should have the Admin role
                for user in &list_response.users {
                    let has_admin_role = user.role == UserRole::Admin;
                    prop_assert!(has_admin_role);
                }
            });
        }

        #[test]
        fn test_crud_operations(
            username in valid_username(),
            email in valid_email(),
            full_name in valid_full_name(),
            password in valid_password(),
            updated_full_name in valid_full_name()
        ) {
            // Run the async test
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Create test app
                let app = create_test_app().await;

                // Create a user
                let create_user = CreateUserRequest {
                    username: username.clone(),
                    email: email.clone(),
                    display_name: full_name.clone(),
                    password: password.clone(),
                    role: None,
                };

                let create_request = Request::builder()
                    .uri("/api/users")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&create_user).unwrap()))
                    .unwrap();

                let create_response = app.clone().oneshot(create_request).await.unwrap();
                prop_assert_eq!(create_response.status(), StatusCode::CREATED);

                // Parse response to get the user ID
                let body = create_response.into_body().collect().await.unwrap().to_bytes();
                let user_response: UserResponse = serde_json::from_slice(&body).unwrap();
                let user_id = user_response.id;

                // Get the user by ID
                let get_request = Request::builder()
                    .uri(&format!("/api/users/{}", user_id))
                    .method("GET")
                    .body(Body::empty())
                    .unwrap();

                let get_response = app.clone().oneshot(get_request).await.unwrap();
                prop_assert_eq!(get_response.status(), StatusCode::OK);

                // Parse response
                let body = get_response.into_body().collect().await.unwrap().to_bytes();
                let get_user: UserResponse = serde_json::from_slice(&body).unwrap();

                // Verify user data
                prop_assert_eq!(get_user.id, user_id);
                prop_assert_eq!(get_user.username, username);
                prop_assert_eq!(get_user.email, email);
                prop_assert_eq!(get_user.display_name, full_name);

                // Update the user
                let update_user = UpdateUserRequest {
                    email: Some(email.clone()),
                    display_name: Some(updated_full_name.clone()),
                    password: None,
                    role: None,
                    active: None,
                };

                let update_request = Request::builder()
                    .uri(&format!("/api/users/{}", user_id))
                    .method("PUT")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&update_user).unwrap()))
                    .unwrap();

                let update_response = app.clone().oneshot(update_request).await.unwrap();
                prop_assert_eq!(update_response.status(), StatusCode::OK);

                // Get the updated user
                let get_request = Request::builder()
                    .uri(&format!("/api/users/{}", user_id))
                    .method("GET")
                    .body(Body::empty())
                    .unwrap();

                let get_response = app.clone().oneshot(get_request).await.unwrap();
                prop_assert_eq!(get_response.status(), StatusCode::OK);

                // Parse response
                let body = get_response.into_body().collect().await.unwrap().to_bytes();
                let updated_user: UserResponse = serde_json::from_slice(&body).unwrap();

                // Verify updated fields
                prop_assert_eq!(updated_user.display_name, updated_full_name);

                let has_admin_role = updated_user.role == UserRole::Admin;
                prop_assert!(has_admin_role);

                // Delete the user
                let delete_request = Request::builder()
                    .uri(&format!("/api/users/{}", user_id))
                    .method("DELETE")
                    .body(Body::empty())
                    .unwrap();

                let delete_response = app.clone().oneshot(delete_request).await.unwrap();
                prop_assert_eq!(delete_response.status(), StatusCode::NO_CONTENT);

                // Try to get the deleted user
                let get_request = Request::builder()
                    .uri(&format!("/api/users/{}", user_id))
                    .method("GET")
                    .body(Body::empty())
                    .unwrap();

                let get_response = app.clone().oneshot(get_request).await.unwrap();
                prop_assert_eq!(get_response.status(), StatusCode::NOT_FOUND);
            });
        }
    }
}
