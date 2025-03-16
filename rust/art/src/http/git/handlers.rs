//! Git HTTP protocol handlers
//!
//! This module implements the HTTP handlers for the Git Smart HTTP protocol.
//! It provides handlers for discovery, advertising refs, and handling
//! upload-pack and receive-pack operations for Git clone, fetch, and push.

use std::path::Path;
use std::sync::Arc;

use axum::{
    extract::{Path as AxumPath, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Extension,
};
use bytes::Bytes;
use futures::StreamExt;
use hyper::header;
use serde::Deserialize;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::data::git::Git;
use crate::error::{Error, Result};
use crate::service::observability::{metrics, trace};

use super::{GitHttp, GitHttpConfig};
use super::auth::{GitAuthResult, GitAuthService, GitOperation};

/// Git service info
///
/// This struct is returned by the git-upload-pack and git-receive-pack
/// info/refs endpoints, which advertise the capabilities of the server.
#[derive(Debug, Deserialize)]
pub struct GitServiceInfo {
    /// The service name (git-upload-pack or git-receive-pack)
    pub service: String,
}

/// Git request state
pub struct GitRequestState {
    /// Git HTTP service instance
    pub git_http: Arc<GitHttp>,

    /// Git repository instance
    pub git: Arc<Git>,
}

/// Git HTTP handlers for the Smart HTTP protocol
pub struct GitHandlers;

impl GitHandlers {
    /// Create a new Git HTTP handlers instance
    pub fn new() -> Self {
        Self
    }

    /// Handle GET /info/refs request for Git discovery
    ///
    /// This endpoint is called by Git clients to discover the capabilities
    /// of the server. It returns a list of refs with capabilities.
    pub async fn info_refs(
        State(state): State<Arc<GitRequestState>>,
        AxumPath(repo_name): AxumPath<String>,
        Query(params): Query<GitServiceInfo>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
    ) -> Result<Response> {
        debug!("Git info/refs request for repo: {}, service: {}", repo_name, params.service);

        // Check if service is valid
        let (service, operation) = match params.service.as_str() {
            "git-upload-pack" => ("upload-pack", GitOperation::Read),
            "git-receive-pack" => ("receive-pack", GitOperation::Write),
            _ => return Err(Error::invalid_request("Invalid service")),
        };

        // Check authentication and permissions
        if let Some(auth_service) = state.git_http.auth_service() {
            let config = auth_service.config();

            // Check if authentication is required
            let auth_required = match operation {
                GitOperation::Read => config.require_auth_for_read,
                GitOperation::Write => config.require_auth_for_write,
            };

            if auth_required && !auth_result.authenticated {
                // If authentication is required but user is not authenticated
                let realm = &config.realm;
                let headers = [(
                    header::WWW_AUTHENTICATE,
                    format!("Basic realm=\"{}\"", realm).parse().unwrap()
                )];

                return Ok((StatusCode::UNAUTHORIZED, headers).into_response());
            }

            // Check permissions for this repository
            let has_permission = auth_service
                .check_permission(&auth_result, &repo_name, operation)
                .await?;

            if !has_permission {
                return Err(Error::forbidden("You don't have permission to access this repository"));
            }
        }

        // Get repository path
        let repo_path = state.git_http.get_repo_path(&repo_name).await?;
        if !Path::new(&repo_path).exists() {
            return Err(Error::not_found(format!("Repository '{}' not found", repo_name)));
        }

        // Set up response headers
        let mut response_headers = HeaderMap::new();
        response_headers.insert(
            header::CONTENT_TYPE,
            format!("application/x-{}-advertisement", params.service).parse().unwrap()
        );
        response_headers.insert(
            header::CACHE_CONTROL,
            "no-cache".parse().unwrap()
        );

        // Start process to generate refs
        let mut cmd = Command::new("git");
        cmd.arg(service)
            .arg("--stateless-rpc")
            .arg("--advertise-refs")
            .arg(&repo_path);

        // Capture start time for metrics
        let start = std::time::Instant::now();

        // Execute git command
        let output = cmd.output().await.map_err(|e| {
            error!("Failed to execute git command: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Track metrics
        metrics::HTTP_REQUEST_DURATION
            .with_label_values(&["git_info_refs", &repo_name])
            .observe(start.elapsed().as_secs_f64());

        // Check if command was successful
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Git info/refs command failed: {}", stderr);
            return Err(Error::internal(format!("Git command failed: {}", stderr)));
        }

        // Prepare response with correct pkt-line format
        let mut response_data = Vec::new();

        // Write service header and flush
        response_data.extend_from_slice(
            format!("# service={}\n", params.service).as_bytes()
        );
        response_data.extend_from_slice("0000".as_bytes()); // flush

        // Add git output
        response_data.extend_from_slice(&output.stdout);

        // Return response
        Ok((
            StatusCode::OK,
            response_headers,
            response_data,
        ).into_response())
    }

    /// Handle POST /git-upload-pack for Git fetch and clone operations
    ///
    /// This endpoint is called by Git clients to fetch objects from the server.
    pub async fn upload_pack(
        State(state): State<Arc<GitRequestState>>,
        AxumPath(repo_name): AxumPath<String>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
        body: Bytes,
    ) -> Result<Response> {
        debug!("Git upload-pack request for repo: {}", repo_name);

        // Check authentication and permissions
        if let Some(auth_service) = state.git_http.auth_service() {
            // Check if authentication is required for read
            let config = auth_service.config();

            if config.require_auth_for_read && !auth_result.authenticated {
                // If authentication is required but user is not authenticated
                let realm = &config.realm;
                let headers = [(
                    header::WWW_AUTHENTICATE,
                    format!("Basic realm=\"{}\"", realm).parse().unwrap()
                )];

                return Ok((StatusCode::UNAUTHORIZED, headers).into_response());
            }

            // Check permissions for this repository
            let has_permission = auth_service
                .check_permission(&auth_result, &repo_name, GitOperation::Read)
                .await?;

            if !has_permission {
                return Err(Error::forbidden("You don't have permission to access this repository"));
            }
        }

        // Get repository path
        let repo_path = state.git_http.get_repo_path(&repo_name).await?;
        if !Path::new(&repo_path).exists() {
            return Err(Error::not_found(format!("Repository '{}' not found", repo_name)));
        }

        // Start git upload-pack process
        let mut cmd = Command::new("git");
        cmd.arg("upload-pack")
            .arg("--stateless-rpc")
            .arg(&repo_path)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());

        // Capture start time for metrics
        let start = std::time::Instant::now();

        // Spawn process
        let mut child = cmd.spawn().map_err(|e| {
            error!("Failed to spawn git upload-pack process: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Write request body to stdin
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(&body).await.map_err(|e| {
            error!("Failed to write to git upload-pack stdin: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Close stdin to signal EOF
        drop(stdin);

        // Get output
        let output = child.wait_with_output().await.map_err(|e| {
            error!("Failed to wait for git upload-pack process: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Track metrics
        metrics::HTTP_REQUEST_DURATION
            .with_label_values(&["git_upload_pack", &repo_name])
            .observe(start.elapsed().as_secs_f64());

        metrics::BYTES_TRANSFERRED
            .with_label_values(&["git_upload_pack", &repo_name, "out"])
            .inc_by(output.stdout.len() as u64);

        metrics::BYTES_TRANSFERRED
            .with_label_values(&["git_upload_pack", &repo_name, "in"])
            .inc_by(body.len() as u64);

        // Check if command was successful
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Git upload-pack command failed: {}", stderr);
            return Err(Error::internal(format!("Git command failed: {}", stderr)));
        }

        // Set up response headers
        let mut response_headers = HeaderMap::new();
        response_headers.insert(
            header::CONTENT_TYPE,
            "application/x-git-upload-pack-result".parse().unwrap()
        );
        response_headers.insert(
            header::CACHE_CONTROL,
            "no-cache".parse().unwrap()
        );

        // Return response
        Ok((
            StatusCode::OK,
            response_headers,
            output.stdout,
        ).into_response())
    }

    /// Handle POST /git-receive-pack for Git push operations
    ///
    /// This endpoint is called by Git clients to push objects to the server.
    pub async fn receive_pack(
        State(state): State<Arc<GitRequestState>>,
        AxumPath(repo_name): AxumPath<String>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
        body: Bytes,
    ) -> Result<Response> {
        debug!("Git receive-pack request for repo: {}", repo_name);

        // Check if receive-pack is enabled
        if !state.git_http.config().enable_push {
            return Err(Error::forbidden("Push operations are disabled"));
        }

        // Check if push size is too large
        if let Some(max_size) = state.git_http.config().max_push_size {
            if body.len() > max_size {
                return Err(Error::invalid_request(
                    format!("Push size exceeds maximum allowed size of {} bytes", max_size)
                ));
            }
        }

        // Check authentication and permissions
        if let Some(auth_service) = state.git_http.auth_service() {
            // Write operations always require authentication
            if !auth_result.authenticated {
                // If user is not authenticated
                let realm = &auth_service.config().realm;
                let headers = [(
                    header::WWW_AUTHENTICATE,
                    format!("Basic realm=\"{}\"", realm).parse().unwrap()
                )];

                return Ok((StatusCode::UNAUTHORIZED, headers).into_response());
            }

            // Check permissions for this repository
            let has_permission = auth_service
                .check_permission(&auth_result, &repo_name, GitOperation::Write)
                .await?;

            if !has_permission {
                return Err(Error::forbidden("You don't have permission to push to this repository"));
            }
        }

        // Get repository path
        let repo_path = state.git_http.get_repo_path(&repo_name).await?;
        if !Path::new(&repo_path).exists() {
            return Err(Error::not_found(format!("Repository '{}' not found", repo_name)));
        }

        // Start git receive-pack process
        let mut cmd = Command::new("git");
        cmd.arg("receive-pack")
            .arg("--stateless-rpc")
            .arg(&repo_path)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());

        // Capture start time for metrics
        let start = std::time::Instant::now();

        // Spawn process
        let mut child = cmd.spawn().map_err(|e| {
            error!("Failed to spawn git receive-pack process: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Write request body to stdin
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(&body).await.map_err(|e| {
            error!("Failed to write to git receive-pack stdin: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Close stdin to signal EOF
        drop(stdin);

        // Get output
        let output = child.wait_with_output().await.map_err(|e| {
            error!("Failed to wait for git receive-pack process: {}", e);
            Error::internal(format!("Git command failed: {}", e))
        })?;

        // Track metrics
        metrics::HTTP_REQUEST_DURATION
            .with_label_values(&["git_receive_pack", &repo_name])
            .observe(start.elapsed().as_secs_f64());

        metrics::BYTES_TRANSFERRED
            .with_label_values(&["git_receive_pack", &repo_name, "out"])
            .inc_by(output.stdout.len() as u64);

        metrics::BYTES_TRANSFERRED
            .with_label_values(&["git_receive_pack", &repo_name, "in"])
            .inc_by(body.len() as u64);

        // Get user info for logging
        let user_info = auth_result.user.as_deref().unwrap_or("anonymous");

        // Check if command was successful
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Git receive-pack command failed: {}", stderr);

            // Log push failure
            info!(
                user = user_info,
                repo = repo_name,
                success = false,
                error = %stderr,
                "Git push failed"
            );

            return Err(Error::internal(format!("Git command failed: {}", stderr)));
        }

        // Log successful push
        info!(
            user = user_info,
            repo = repo_name,
            success = true,
            "Git push successful"
        );

        // If auto-gc is enabled, trigger garbage collection
        if state.git_http.config().auto_gc {
            Self::trigger_gc(repo_name.clone(), repo_path.clone());
        }

        // Set up response headers
        let mut response_headers = HeaderMap::new();
        response_headers.insert(
            header::CONTENT_TYPE,
            "application/x-git-receive-pack-result".parse().unwrap()
        );
        response_headers.insert(
            header::CACHE_CONTROL,
            "no-cache".parse().unwrap()
        );

        // Return response
        Ok((
            StatusCode::OK,
            response_headers,
            output.stdout,
        ).into_response())
    }

    /// Trigger git garbage collection in the background
    fn trigger_gc(repo_name: String, repo_path: String) {
        // Spawn a background task for garbage collection
        tokio::spawn(async move {
            debug!("Starting background garbage collection for {}", repo_name);

            // Run git gc with minimal output
            let output = Command::new("git")
                .arg("gc")
                .arg("--auto")
                .arg("--quiet")
                .current_dir(&repo_path)
                .output()
                .await;

            match output {
                Ok(output) => {
                    if !output.status.success() {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        warn!("Git gc failed for {}: {}", repo_name, stderr);
                    } else {
                        debug!("Git gc completed successfully for {}", repo_name);
                    }
                },
                Err(e) => {
                    warn!("Failed to spawn git gc process for {}: {}", repo_name, e);
                }
            }
        });
    }

    /// Middleware to check and inject authentication information
    pub async fn auth_middleware(
        State(state): State<Arc<GitRequestState>>,
        headers: HeaderMap,
        mut request: axum::http::Request<axum::body::Body>,
    ) -> Result<axum::http::Request<axum::body::Body>> {
        // Default authentication result (not authenticated)
        let mut auth_result = GitAuthResult::failure();

        // Check if authentication service is available
        if let Some(auth_service) = state.git_http.auth_service() {
            // Try to authenticate
            auth_result = auth_service.authenticate(&headers).await?;
        }

        // Add authentication result as extension to request
        request.extensions_mut().insert(auth_result);

        // Continue with request
        Ok(request)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::auth::{BasicAuthService, GitAuthConfig};
    use std::path::PathBuf;
    use axum::http::StatusCode;
    use axum::http::Request;
    use axum::body::Body;
    use tower::ServiceExt;
    use tempfile::tempdir;

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

    /// Create auth headers for testing
    fn create_auth_headers(username: &str, password: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();

        // Create basic auth header
        let credentials = format!("{}:{}", username, password);
        let encoded = base64::encode(credentials);
        let auth_value = format!("Basic {}", encoded);

        // Add to headers
        headers.insert("authorization", auth_value.parse().unwrap());

        headers
    }

    #[tokio::test]
    async fn test_auth_middleware() -> Result<()> {
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
            ..GitHttpConfig::default()
        };

        // Create Git HTTP service
        let git_http = Arc::new(GitHttp::new(config)
            .with_auth_service(auth_service));

        // Create request state
        let state = Arc::new(GitRequestState {
            git_http: git_http.clone(),
            git: git.clone(),
        });

        // Create request with valid auth
        let headers = create_auth_headers("testuser", "testpass");
        let request = Request::builder()
            .uri("/testrepo")
            .method("GET")
            .header("content-type", "application/json")
            .body(Body::empty())
            .unwrap();

        // Apply middleware
        let result = GitHandlers::auth_middleware(
            State(state.clone()),
            headers,
            request,
        ).await?;

        // Extract auth result from extensions
        let auth_result = result.extensions().get::<GitAuthResult>().unwrap();

        // Verify authentication was successful
        assert!(auth_result.authenticated);
        assert_eq!(auth_result.user, Some("testuser".to_string()));

        // Create request with invalid auth
        let headers = create_auth_headers("testuser", "wrongpass");
        let request = Request::builder()
            .uri("/testrepo")
            .method("GET")
            .header("content-type", "application/json")
            .body(Body::empty())
            .unwrap();

        // Apply middleware
        let result = GitHandlers::auth_middleware(
            State(state.clone()),
            headers,
            request,
        ).await?;

        // Extract auth result from extensions
        let auth_result = result.extensions().get::<GitAuthResult>().unwrap();

        // Verify authentication failed
        assert!(!auth_result.authenticated);
        assert_eq!(auth_result.user, None);

        Ok(())
    }
}
