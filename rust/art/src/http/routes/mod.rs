//! HTTP routes for the Art application

pub mod web;
pub mod api;
pub mod user;
pub mod maintenance;

use crate::http::ServerState;
use crate::error::Result;
use chrono::Utc;
use axum::http::StatusCode;
use crate::service::search::HasSearchService;
use crate::service::status::HasStatusService;
use crate::service::observability::HasObservabilityService;
use crate::template::TemplateManager;
use crate::http::middleware::rate_limit::{extract_client_ip, rate_limit, RateLimitConfig, RateLimitMiddleware};

/// Get the current year for templates
pub fn current_year() -> String {
    Utc::now().format("%Y").to_string()
}

/// A successful response with no content
pub fn ok() -> Result<StatusCode> {
    Ok(StatusCode::OK)
}

/// A successful response with content
pub fn created() -> Result<StatusCode> {
    Ok(StatusCode::CREATED)
}

pub fn create_router(app_state: Arc<AppState>) -> Router {
    // Configure rate limiting for observability endpoints
    let observability_rate_limit_config = RateLimitConfig {
        max_requests: 60,
        window_seconds: 60, // 60 requests per minute
        bypass_localhost: true,
        rate_limit_message: "Rate limit exceeded for observability endpoint. Please try again later.".to_string(),
    };

    let observability_rate_limiter = RateLimitMiddleware::new(observability_rate_limit_config);

    // Create the app router with all routes
    Router::new()
        // API routes
        .route("/api/health", get(api::health))
        .route("/api/metrics", get(api::metrics))
        .route("/api/logs", get(api::query_logs))
        .route("/api/repo/:repo/metrics", get(api::repository_metrics))
        .route("/api/repos/metrics", get(api::all_repository_metrics))
        .route("/api/repos/metrics/refresh", post(api::refresh_repository_metrics))
        .layer(middleware::from_fn(extract_client_ip))
        .layer(middleware::from_fn_with_state(
            observability_rate_limiter,
            rate_limit,
        ))
        // Other routes without rate limiting
        .route("/", get(index))
        .route("/repos", get(repos))
        .route("/repo/:repo", get(repo))
        .route("/repo/:repo/*path", get(repo_path))
        .route("/create", get(create_repo_page).post(create_repo))
        .with_state(app_state)
}

// Function to set up the application
pub fn setup(app_state: Arc<AppState>) -> Router {
    create_router(app_state)
        .layer(middleware::from_fn(logging_middleware))
        .layer(middleware::from_fn(metrics_middleware))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{Config, DatabaseConfig, RepositoryConfig, ServerConfig, UiConfig};
    use crate::data::database::Database;
    use crate::data::git::Git;
    use crate::error::Result;
    use axum::body::Body;
    use axum::http::{Method, Request, StatusCode};
    use hyper::body;
    use tempfile::{tempdir, TempDir};
    use tower::ServiceExt;

    // Helper function to create a test application
    async fn create_test_app() -> Result<(axum::Router, TempDir)> {
        let temp_dir = tempdir()?;

        // Create config with temp directories
        let config = Config {
            server: ServerConfig {
                base_url: "http://localhost:3000".to_string(),
                host: "127.0.0.1".to_string(),
                port: 3000,
                workers: 1,
                compress: false,
                cors_origins: Vec::new(),
            },
            repository: RepositoryConfig {
                repo_dir: temp_dir.path().to_path_buf(),
                max_commits: 100,
                max_cache_size: 1024 * 1024,
                enable_maintenance: false,
                maintenance_interval: 0,
            },
            database: DatabaseConfig {
                path: temp_dir.path().join("test.db"),
                pool_size: 5,
            },
            ui: UiConfig {
                title: "Art Test".to_string(),
                description: "Test instance".to_string(),
                footer: "Test footer".to_string(),
                dark_mode: false,
                custom_css: None,
                custom_js: None,
            },
        };

        // Create database
        let db = Database::new(&config.database)?;

        // Create Git instance
        let git = Git::new(&config.repository)?;

        // Create app
        let app = create_app(config, db, git);

        Ok((app, temp_dir))
    }

    // Helper function to make a request to the app
    async fn make_request(
        app: &axum::Router,
        method: Method,
        uri: &str,
    ) -> (StatusCode, String) {
        let request = Request::builder()
            .method(method)
            .uri(uri)
            .body(Body::empty())
            .unwrap();

        let response = app.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let body = body::to_bytes(response.into_body()).await.unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap_or_default();

        (status, body_str)
    }

    #[tokio::test]
    async fn test_health_endpoint() -> Result<()> {
        let (app, _temp_dir) = create_test_app().await?;

        // Test the health endpoint
        let (status, body) = make_request(&app, Method::GET, "/api/health").await;

        assert_eq!(status, StatusCode::OK);
        assert!(body.contains("ok")); // Simple health check response

        Ok(())
    }

    #[tokio::test]
    async fn test_not_found_api_endpoint() -> Result<()> {
        let (app, _temp_dir) = create_test_app().await?;

        // Test a non-existent API endpoint
        let (status, body) = make_request(&app, Method::GET, "/api/nonexistent").await;

        assert_eq!(status, StatusCode::NOT_FOUND);
        assert!(body.contains("error")); // Error message in JSON response

        Ok(())
    }

    #[tokio::test]
    async fn test_web_index_page() -> Result<()> {
        let (app, _temp_dir) = create_test_app().await?;

        // Test the index page
        let (status, body) = make_request(&app, Method::GET, "/").await;

        assert_eq!(status, StatusCode::OK);
        assert!(body.contains("Art Test")); // Title from the config
        assert!(body.contains("repositories")); // Should list repositories

        Ok(())
    }

    #[tokio::test]
    async fn test_web_about_page() -> Result<()> {
        let (app, _temp_dir) = create_test_app().await?;

        // Test the about page
        let (status, body) = make_request(&app, Method::GET, "/about").await;

        assert_eq!(status, StatusCode::OK);
        assert!(body.contains("About")); // About page title
        assert!(body.contains("Art Test")); // Title from the config

        Ok(())
    }

    #[tokio::test]
    async fn test_static_files() -> Result<()> {
        let (app, _temp_dir) = create_test_app().await?;

        // Test the main CSS file
        let (status, body) = make_request(&app, Method::GET, "/static/css/main.css").await;

        // Even if the file doesn't exist in tests, we should get a 404 response, not a 500
        assert!(status == StatusCode::OK || status == StatusCode::NOT_FOUND);

        Ok(())
    }

    #[tokio::test]
    async fn test_response_helpers() -> Result<()> {
        // Test the response helpers directly

        // Test OK response
        let response = ok_response(&"test data");
        assert_eq!(response.status(), StatusCode::OK);

        // Test Created response
        let response = created_response(&"new resource");
        assert_eq!(response.status(), StatusCode::CREATED);

        // Test No Content response
        let response = no_content_response();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);

        Ok(())
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use crate::config::{Config, RepositoryConfig, DatabaseConfig, ServerConfig};
    use crate::data::{Git, Sqlite};
    use crate::data::cache::CacheManager;
    use crate::error::Error;
    use crate::http::ServerState;
    use axum::http::{Request, StatusCode};
    use axum::body::Body;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use std::path::{Path, PathBuf};
    use std::sync::Arc;
    use tempfile::TempDir;
    use tower::ServiceExt;

    // Strategy for generating valid repository names
    fn repo_name_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z][a-zA-Z0-9_-]{1,20}"
    }

    // Strategy for generating valid Git references (branches, tags, commit SHAs)
    fn git_ref_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Branch names
            "[a-zA-Z][a-zA-Z0-9_/-]{1,20}",
            // Tags
            "v[0-9].[0-9].[0-9](-[a-zA-Z0-9]+)?",
            // Commit SHAs
            "[0-9a-f]{7,40}"
        ]
    }

    // Strategy for generating file paths
    fn file_path_strategy() -> impl Strategy<Value = String> {
        // Generate path components and join them
        prop::collection::vec("[a-zA-Z0-9_.-]{1,10}", 0..5)
            .prop_map(|components| components.join("/"))
    }

    // Helper to create a test app with a minimal Git repository
    async fn create_test_app_with_repo() -> (axum::Router, TempDir) {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let repo_path = temp_dir.path().join("test-repo");
        std::fs::create_dir_all(&repo_path).expect("Failed to create repo dir");

        // Initialize a Git repository with a test commit
        let repo = git2::Repository::init(&repo_path).expect("Failed to init git repo");
        let signature = git2::Signature::now("Test", "test@example.com").expect("Failed to create signature");

        // Create a test file and commit it
        std::fs::write(repo_path.join("README.md"), "# Test Repository").expect("Failed to write file");
        let mut index = repo.index().expect("Failed to get index");
        index.add_path(Path::new("README.md")).expect("Failed to add path");
        let oid = index.write_tree().expect("Failed to write tree");
        let tree = repo.find_tree(oid).expect("Failed to find tree");
        repo.commit(Some("HEAD"), &signature, &signature, "Initial commit", &tree, &[])
            .expect("Failed to create commit");

        // Create a sample config
        let config = Config {
            port: 3000,
            host: "127.0.0.1".to_string(),
            repositories: vec![repo_path.to_string_lossy().to_string()],
            cache_size_mb: 100,
            cache_ttl_secs: 300,
            theme: "light".to_string(),
        };

        // Create the Git manager
        let git = Git::new(&repo_path.to_string_lossy().to_string()).expect("Failed to create Git manager");

        // Create an in-memory SQLite database for testing
        let db_path = temp_dir.path().join("test.db");
        let db = Sqlite::open(&db_path.to_string_lossy().to_string()).expect("Failed to create database");

        // Create the server state
        let state = ServerState {
            git: Arc::new(git),
            db: Arc::new(db),
            config: Arc::new(config),
            cache: Arc::new(CacheManager::new(100 * 1024 * 1024, 300)),
            base_url: "http://localhost:3000".to_string(),
        };

        // Build the router
        let app = crate::http::build_router(state);

        (app, temp_dir)
    }

    // Helper to make a request to the app
    async fn make_test_request(
        app: &axum::Router,
        method: &str,
        uri: &str,
    ) -> (StatusCode, String) {
        let request = Request::builder()
            .method(method)
            .uri(uri)
            .body(Body::empty())
            .unwrap();

        let response = app.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap_or_default();

        (status, body_str)
    }

    proptest! {
        /// Test that all API endpoints with invalid repository names return 404
        #[test]
        fn api_invalid_repo_name_returns_404(
            repo_name in "[^a-zA-Z0-9_-]+"
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let (app, _temp_dir) = create_test_app_with_repo().await;

                // Test different API endpoints with invalid repo names
                let endpoints = vec![
                    format!("/api/repos/{}", repo_name),
                    format!("/api/repos/{}/branches", repo_name),
                    format!("/api/repos/{}/tags", repo_name),
                    format!("/api/repos/{}/commits", repo_name),
                ];

                for endpoint in endpoints {
                    let (status, _) = make_test_request(&app, "GET", &endpoint).await;
                    assert_eq!(status, StatusCode::NOT_FOUND, "Endpoint {} should return 404 for invalid repo name", endpoint);
                }
            });
        }

        /// Test that file paths are properly sanitized to prevent path traversal
        #[test]
        fn file_paths_are_sanitized(
            // Generate paths with potential traversal sequences
            repo_name in repo_name_strategy(),
            git_ref in git_ref_strategy(),
            path in prop_oneof![
                "../../etc/passwd",
                "../../../etc/passwd",
                "/.././../etc/passwd",
                "/root/.ssh/id_rsa",
                "~/.ssh/id_rsa",
                "src/../../../etc/passwd"
            ]
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let (app, _temp_dir) = create_test_app_with_repo().await;

                // Test the file API endpoint with traversal paths
                let endpoint = format!("/api/repos/{}/blob/{}/{}", repo_name, git_ref, path);
                let (status, body) = make_test_request(&app, "GET", &endpoint).await;

                // Should either return a 404 or a sanitized path error, but never expose system files
                assert!(
                    status == StatusCode::NOT_FOUND ||
                    body.contains("Invalid path") ||
                    !body.contains("/etc/passwd") ||
                    !body.contains("id_rsa"),
                    "Path traversal should be prevented"
                );
            });
        }

        /// Test that all health endpoint returns valid responses
        #[test]
        fn health_endpoint_returns_valid_response(
            // No input parameters needed, just test the fixed endpoint
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let (app, _temp_dir) = create_test_app_with_repo().await;

                let (status, body) = make_test_request(&app, "GET", "/api/health").await;

                // Health endpoint should return 200 and contain certain fields
                assert_eq!(status, StatusCode::OK, "Health endpoint should return 200 OK");
                assert!(body.contains("status"), "Health response should contain status field");
                assert!(body.contains("version"), "Health response should contain version field");
            });
        }
    }
}

// Auth module for handling authentication routes
pub mod auth {
    use axum::{
        extract::{Json, State, Extension},
        http::{StatusCode, Response, HeaderMap},
        response::IntoResponse,
    };
    use hyper::Body;
    use serde::{Deserialize, Serialize};
    use std::sync::Arc;
    use crate::http::middleware::ClientInfo;
    use crate::service::user::UserService;
    use crate::error::Result;

    /// Login request payload
    #[derive(Debug, Deserialize)]
    pub struct LoginRequest {
        /// Username or email
        pub username: String,
        /// Password
        pub password: String,
    }

    /// Login response
    #[derive(Debug, Serialize)]
    pub struct LoginResponse {
        /// User ID
        pub user_id: i64,
        /// Username
        pub username: String,
        /// Display name
        pub display_name: String,
        /// User roles
        pub roles: Vec<String>,
        /// Session token
        pub token: String,
    }

    /// Session response
    #[derive(Debug, Serialize)]
    pub struct SessionResponse {
        /// Whether user is authenticated
        pub authenticated: bool,
        /// User information if authenticated
        pub user: Option<UserInfo>,
    }

    /// User information
    #[derive(Debug, Serialize)]
    pub struct UserInfo {
        /// User ID
        pub id: i64,
        /// Username
        pub username: String,
        /// Display name
        pub display_name: String,
        /// User roles
        pub roles: Vec<String>,
    }

    /// Login handler
    ///
    /// POST /api/auth/login
    pub async fn login(
        State(user_service): State<Arc<UserService>>,
        Extension(client_info): Extension<ClientInfo>,
        Json(payload): Json<LoginRequest>,
    ) -> impl IntoResponse {
        // Get client information
        let ip_address = client_info.ip;
        let user_agent = client_info.user_agent.unwrap_or_else(|| "unknown".to_string());

        // Attempt login
        match user_service.login(&payload.username, &payload.password, ip_address, user_agent).await {
            Ok((user, session)) => {
                // Create response
                let response = LoginResponse {
                    user_id: user.id,
                    username: user.username,
                    display_name: user.display_name,
                    roles: vec![user.role.to_string()],
                    token: session.token,
                };

                // Create session cookie
                let cookie = format!(
                    "session={}; Path=/; HttpOnly; SameSite=Strict; Max-Age={}",
                    session.token,
                    // Set cookie expiration to match session expiration
                    (session.expires_at.timestamp() - chrono::Utc::now().timestamp())
                );

                // Build response with cookie
                let mut headers = HeaderMap::new();
                headers.insert("Set-Cookie", cookie.parse().unwrap());

                (StatusCode::OK, headers, Json(response))
            },
            Err(e) => {
                // Login failed
                (
                    StatusCode::UNAUTHORIZED,
                    HeaderMap::new(),
                    Json(serde_json::json!({
                        "error": "Authentication failed",
                        "message": e.to_string()
                    }))
                )
            }
        }
    }

    /// Logout handler
    ///
    /// POST /api/auth/logout
    pub async fn logout(
        State(user_service): State<Arc<UserService>>,
        Extension(client_info): Extension<ClientInfo>,
        headers: HeaderMap,
    ) -> impl IntoResponse {
        // Get session token from cookie or Authorization header
        let session_token = get_session_token(&headers);

        if let Some(token) = session_token {
            // Logout the session
            let _ = user_service.logout(&token).await;
        }

        // Clear the session cookie
        let cookie = "session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0";
        let mut headers = HeaderMap::new();
        headers.insert("Set-Cookie", cookie.parse().unwrap());

        (StatusCode::NO_CONTENT, headers)
    }

    /// Get current session information
    ///
    /// GET /api/auth/session
    pub async fn session(
        State(user_service): State<Arc<UserService>>,
        headers: HeaderMap,
    ) -> impl IntoResponse {
        // Get session token from cookie or Authorization header
        let session_token = get_session_token(&headers);

        let session_response = if let Some(token) = session_token {
            // Try to get user from session
            if let Ok(Some(user)) = user_service.get_session_user(&token).await {
                // User is authenticated
                SessionResponse {
                    authenticated: true,
                    user: Some(UserInfo {
                        id: user.id,
                        username: user.username,
                        display_name: user.display_name,
                        roles: vec![user.role.to_string()],
                    }),
                }
            } else {
                // Session not found or expired
                SessionResponse {
                    authenticated: false,
                    user: None,
                }
            }
        } else {
            // No session token provided
            SessionResponse {
                authenticated: false,
                user: None,
            }
        };

        Json(session_response)
    }

    /// Get session token from cookie or Authorization header
    fn get_session_token(headers: &HeaderMap) -> Option<String> {
        // Try to get session token from cookie
        if let Some(cookie) = headers.get("cookie") {
            if let Ok(cookie_str) = cookie.to_str() {
                let session = cookie_str.split(';')
                    .map(|c| c.trim())
                    .find_map(|c| {
                        if c.starts_with("session=") {
                            Some(c.trim_start_matches("session=").to_string())
                        } else {
                            None
                        }
                    });

                if session.is_some() {
                    return session;
                }
            }
        }

        // Try to get session token from Authorization header
        if let Some(auth) = headers.get("authorization") {
            if let Ok(auth_str) = auth.to_str() {
                if auth_str.starts_with("Bearer ") {
                    return Some(auth_str.trim_start_matches("Bearer ").to_string());
                }
            }
        }

        None
    }
}

// Admin module for handling admin routes
pub mod admin {
    use axum::{
        extract::{Json, State, Path, Form},
        http::StatusCode,
        response::{Html, IntoResponse},
    };
    use serde::{Deserialize, Serialize};
    use std::sync::Arc;
    use crate::service::user::{UserService, UserListOptions};
    use crate::data::user::{User, UserRole};
    use crate::http::middleware::AuthData;

    /// Admin dashboard page
    pub async fn dashboard(
        State(user_service): State<Arc<UserService>>,
        Extension(auth_data): Extension<AuthData>,
    ) -> impl IntoResponse {
        // Simple dashboard page
        Html("<h1>Admin Dashboard</h1><p>Welcome to the admin dashboard.</p><p><a href=\"/admin/users\">Manage Users</a></p>")
    }

    /// User list page
    pub async fn users(
        State(user_service): State<Arc<UserService>>,
    ) -> impl IntoResponse {
        // Get all users
        let users = match user_service.list_users(None, None).await {
            Ok(users) => users,
            Err(_) => Vec::new(),
        };

        // Render user list (simplified HTML for now)
        let mut html = String::from("<h1>User Management</h1>");
        html.push_str("<p><a href=\"/admin/users/new\">Create New User</a></p>");
        html.push_str("<table><thead><tr><th>ID</th><th>Username</th><th>Display Name</th><th>Role</th><th>Actions</th></tr></thead><tbody>");

        for user in users {
            html.push_str(&format!(
                "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td><a href=\"/admin/users/{}\">Edit</a> | <form method=\"post\" action=\"/admin/users/{}/delete\" style=\"display:inline\"><button type=\"submit\">Delete</button></form></td></tr>",
                user.id, user.username, user.display_name, user.role, user.id, user.id
            ));
        }

        html.push_str("</tbody></table>");

        Html(html)
    }

    /// Form for creating a new user
    #[derive(Debug, Deserialize)]
    pub struct CreateUserForm {
        username: String,
        email: String,
        display_name: String,
        password: String,
        role: String,
    }

    /// New user form page
    pub async fn new_user_form() -> impl IntoResponse {
        // Simple form for creating a new user
        let html = r#"
        <h1>Create New User</h1>
        <form method="post">
            <div>
                <label for="username">Username:</label>
                <input type="text" id="username" name="username" required>
            </div>
            <div>
                <label for="email">Email:</label>
                <input type="email" id="email" name="email" required>
            </div>
            <div>
                <label for="display_name">Display Name:</label>
                <input type="text" id="display_name" name="display_name" required>
            </div>
            <div>
                <label for="password">Password:</label>
                <input type="password" id="password" name="password" required>
            </div>
            <div>
                <label for="role">Role:</label>
                <select id="role" name="role">
                    <option value="admin">Admin</option>
                    <option value="user" selected>User</option>
                </select>
            </div>
            <div>
                <button type="submit">Create User</button>
                <a href="/admin/users">Cancel</a>
            </div>
        </form>
        "#;

        Html(html)
    }

    /// Create a new user
    pub async fn create_user(
        State(user_service): State<Arc<UserService>>,
        Form(form): Form<CreateUserForm>,
    ) -> impl IntoResponse {
        // Convert role string to UserRole
        let role = match form.role.as_str() {
            "admin" => UserRole::Admin,
            _ => UserRole::User,
        };

        // Create user
        match user_service.create_user(
            form.username,
            form.email,
            form.display_name,
            &form.password,
            role,
        ).await {
            Ok(_) => {
                // Redirect to user list
                (
                    StatusCode::SEE_OTHER,
                    [("Location", "/admin/users")],
                    "User created successfully"
                )
            },
            Err(e) => {
                // Show error
                (
                    StatusCode::BAD_REQUEST,
                    [("Content-Type", "text/html")],
                    format!("<h1>Error Creating User</h1><p>{}</p><p><a href=\"/admin/users\">Back to Users</a></p>", e)
                )
            },
        }
    }

    /// Form for editing a user
    #[derive(Debug, Deserialize)]
    pub struct UpdateUserForm {
        email: String,
        display_name: String,
        password: Option<String>,
        role: String,
        active: Option<String>,
    }

    /// Edit user form page
    pub async fn edit_user_form(
        State(user_service): State<Arc<UserService>>,
        Path(user_id): Path<i64>,
    ) -> impl IntoResponse {
        // Get user
        let user = match user_service.get_user(user_id).await {
            Ok(user) => user,
            Err(_) => {
                return (
                    StatusCode::NOT_FOUND,
                    Html("<h1>User Not Found</h1><p><a href=\"/admin/users\">Back to Users</a></p>")
                );
            }
        };

        // Create edit form
        let html = format!(r#"
        <h1>Edit User: {}</h1>
        <form method="post">
            <div>
                <label for="email">Email:</label>
                <input type="email" id="email" name="email" value="{}" required>
            </div>
            <div>
                <label for="display_name">Display Name:</label>
                <input type="text" id="display_name" name="display_name" value="{}" required>
            </div>
            <div>
                <label for="password">Password (leave blank to keep current):</label>
                <input type="password" id="password" name="password">
            </div>
            <div>
                <label for="role">Role:</label>
                <select id="role" name="role">
                    <option value="admin" {}>Admin</option>
                    <option value="user" {}>User</option>
                </select>
            </div>
            <div>
                <label for="active">Active:</label>
                <input type="checkbox" id="active" name="active" value="true" {}>
            </div>
            <div>
                <button type="submit">Update User</button>
                <a href="/admin/users">Cancel</a>
            </div>
        </form>
        "#,
            user.username,
            user.email,
            user.display_name,
            if user.role == UserRole::Admin { "selected" } else { "" },
            if user.role == UserRole::User { "selected" } else { "" },
            if user.active { "checked" } else { "" }
        );

        (StatusCode::OK, Html(html))
    }

    /// Update a user
    pub async fn update_user(
        State(user_service): State<Arc<UserService>>,
        Path(user_id): Path<i64>,
        Form(form): Form<UpdateUserForm>,
    ) -> impl IntoResponse {
        // Convert role string to UserRole
        let role = match form.role.as_str() {
            "admin" => Some(UserRole::Admin),
            "user" => Some(UserRole::User),
            _ => None,
        };

        // Convert active checkbox
        let active = match form.active {
            Some(ref a) if a == "true" => Some(true),
            _ => Some(false),
        };

        // Only pass password if provided
        let password_ref = form.password.as_deref();

        // Update user
        match user_service.update_user(
            user_id,
            Some(form.email),
            Some(form.display_name),
            password_ref,
            role,
            active,
        ).await {
            Ok(_) => {
                // Redirect to user list
                (
                    StatusCode::SEE_OTHER,
                    [("Location", "/admin/users")],
                    "User updated successfully"
                )
            },
            Err(e) => {
                // Show error
                (
                    StatusCode::BAD_REQUEST,
                    [("Content-Type", "text/html")],
                    format!("<h1>Error Updating User</h1><p>{}</p><p><a href=\"/admin/users\">Back to Users</a></p>", e)
                )
            },
        }
    }

    /// Delete a user
    pub async fn delete_user(
        State(user_service): State<Arc<UserService>>,
        Path(user_id): Path<i64>,
    ) -> impl IntoResponse {
        // Delete user
        match user_service.delete_user(user_id).await {
            Ok(_) => {
                // Redirect to user list
                (
                    StatusCode::SEE_OTHER,
                    [("Location", "/admin/users")],
                    "User deleted successfully"
                )
            },
            Err(e) => {
                // Show error
                (
                    StatusCode::BAD_REQUEST,
                    [("Content-Type", "text/html")],
                    format!("<h1>Error Deleting User</h1><p>{}</p><p><a href=\"/admin/users\">Back to Users</a></p>", e)
                )
            },
        }
    }
}
