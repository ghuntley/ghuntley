//! Git HTTP protocol router
//!
//! This module provides the router for the Git Smart HTTP protocol.
//! It sets up the routes for Git HTTP operations, including discovery,
//! fetch, and push operations.

use std::sync::Arc;

use axum::{
    extract::Path,
    middleware,
    routing::{get, post},
    Router,
};
use tower_http::compression::CompressionLayer;
use tower_http::trace::TraceLayer;
use tracing::info;

use crate::data::git::Git;
use crate::service::observability::metrics;

use super::{GitHttp, GitHttpConfig};
use super::handlers::{GitHandlers, GitRequestState};
use super::lfs::LfsHandlers;

/// Git HTTP router
pub struct GitRouter;

impl GitRouter {
    /// Create a new Git HTTP router
    ///
    /// This method creates a new router for the Git Smart HTTP protocol.
    /// It sets up the routes for discovery, fetch, and push operations.
    pub fn new(
        git_http: Arc<GitHttp>,
        git: Arc<Git>,
    ) -> Router {
        // Create request state
        let state = Arc::new(GitRequestState {
            git_http: git_http.clone(),
            git: git.clone(),
        });

        // Get path prefix
        let path_prefix = git_http.config().path_prefix.clone().unwrap_or_default();
        let base_path = format!("{}/{{repo_name}}", path_prefix);

        // Create router with basic Git Smart HTTP protocol routes
        let mut router = Router::new()
            // Discovery endpoint - called by Git clients to discover capabilities
            .route(
                &format!("{}/info/refs", base_path),
                get(GitHandlers::info_refs),
            )
            // Upload-pack endpoint - used for Git fetch and clone operations
            .route(
                &format!("{}/git-upload-pack", base_path),
                post(GitHandlers::upload_pack),
            )
            // Receive-pack endpoint - used for Git push operations
            .route(
                &format!("{}/git-receive-pack", base_path),
                post(GitHandlers::receive_pack),
            );

        // Add Git LFS routes if enabled
        if git_http.config().enable_lfs {
            let lfs_base_path = format!("{}/info/lfs", base_path);

            // LFS batch API endpoint
            router = router.route(
                &format!("{}/objects/batch", lfs_base_path),
                post(LfsHandlers::batch),
            );

            // LFS object upload endpoint
            router = router.route(
                &format!("{}/objects/{{repo_name}}/{{oid}}/upload", lfs_base_path),
                post(LfsHandlers::upload_object),
            );

            // LFS object download endpoint
            router = router.route(
                &format!("{}/objects/{{repo_name}}/{{oid}}", lfs_base_path),
                get(LfsHandlers::download_object),
            );

            // LFS object verification endpoint
            router = router.route(
                &format!("{}/objects/{{repo_name}}/{{oid}}/verify", lfs_base_path),
                post(LfsHandlers::verify_object),
            );

            info!("Git LFS endpoints initialized");
        }

        // Add middleware and other layers
        router = router
            // Add middleware for authentication
            .layer(middleware::from_fn_with_state(
                state.clone(),
                GitHandlers::auth_middleware,
            ))
            // Add compression layer for better performance
            .layer(CompressionLayer::new())
            // Add tracing layer for observability
            .layer(TraceLayer::new_for_http())
            // Add state
            .with_state(state);

        // Log initialization
        info!(
            path_prefix = path_prefix,
            enable_push = git_http.config().enable_push,
            enable_lfs = git_http.config().enable_lfs,
            "Git HTTP protocol router initialized"
        );

        // Register metrics
        Self::register_metrics();

        router
    }

    /// Register Git HTTP metrics with Prometheus
    fn register_metrics() {
        // Register HTTP request duration metrics
        metrics::register_histogram(
            "git_http_request_duration_seconds",
            "Git HTTP request duration in seconds",
            &["operation", "repo"],
        );

        // Register bytes transferred metrics
        metrics::register_counter(
            "git_http_bytes_transferred",
            "Git HTTP bytes transferred",
            &["operation", "repo", "direction"],
        );

        // Register operation count metrics
        metrics::register_counter(
            "git_http_operations_total",
            "Git HTTP operations count",
            &["operation", "repo", "user", "status"],
        );

        // Register LFS metrics
        metrics::register_counter(
            "git_lfs_operations_total",
            "Git LFS operations count",
            &["operation", "repo", "user", "status"],
        );

        metrics::register_histogram(
            "git_lfs_object_size_bytes",
            "Git LFS object size in bytes",
            &["repo"],
        );

        metrics::register_counter(
            "git_lfs_bytes_transferred",
            "Git LFS bytes transferred",
            &["operation", "repo", "direction"],
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use http_body_util::BodyExt;
    use tower::ServiceExt;
    use super::super::auth::{BasicAuthService, GitAuthConfig, GitOperation};
    use tempfile::tempdir;
    use tokio::process::Command;

    /// Create a test Git repository
    async fn create_test_repo() -> (tempfile::TempDir, String) {
        let temp_dir = tempdir().unwrap();
        let repo_path = temp_dir.path().to_str().unwrap().to_string();

        // Initialize Git repository
        let status = Command::new("git")
            .arg("init")
            .arg("--bare")
            .arg(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        (temp_dir, repo_path)
    }

    #[tokio::test]
    async fn test_git_router_routes() {
        // Create test repository
        let (_temp_dir, repo_path) = create_test_repo().await;

        // Create Git instance
        let git = Arc::new(Git::new(repo_path.clone()));

        // Create authentication service
        let auth_service = Arc::new(BasicAuthService::new(GitAuthConfig::default())
            .add_user("testuser", "testpass")
            .add_permission("testuser", "testrepo", GitOperation::Write));

        // Create Git HTTP config
        let config = GitHttpConfig {
            enable_push: true,
            path_prefix: Some("/git".to_string()),
            ..GitHttpConfig::default()
        };

        // Create Git HTTP service
        let git_http = Arc::new(GitHttp::new(config)
            .with_auth_service(auth_service));

        // Create router
        let app = GitRouter::new(git_http, git);

        // Test info/refs route
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/git/testrepo/info/refs?service=git-upload-pack")
                    .method("GET")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check status code (repository not found, but route exists)
        assert_eq!(response.status(), StatusCode::NOT_FOUND);

        // Test upload-pack route
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/git/testrepo/git-upload-pack")
                    .method("POST")
                    .header("Content-Type", "application/x-git-upload-pack-request")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check status code (repository not found, but route exists)
        assert_eq!(response.status(), StatusCode::NOT_FOUND);

        // Test receive-pack route
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/git/testrepo/git-receive-pack")
                    .method("POST")
                    .header("Content-Type", "application/x-git-receive-pack-request")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check status code (repository not found, but route exists)
        assert_eq!(response.status(), StatusCode::NOT_FOUND);

        // Test invalid route
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/git/testrepo/invalid")
                    .method("GET")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check status code (route doesn't exist)
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }
}
