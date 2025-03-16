// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! API handlers for commit-related operations.
//!
//! This module contains HTTP handlers for commit-related API endpoints.

use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use tracing::{debug, error, info, warn};

use crate::error::{Error, Result};
use crate::service::commit::CommitService;
use crate::service::observability::metrics;

/// API handler for commit operations
pub struct CommitApiHandler;

/// Query parameters for commit list endpoint
#[derive(Debug, Deserialize)]
pub struct CommitListParams {
    /// Maximum number of commits to return
    pub limit: Option<usize>,

    /// Page number (0-based)
    pub page: Option<usize>,
}

/// Query parameters for commit signature endpoint
#[derive(Debug, Deserialize)]
pub struct CommitSignatureParams {
    /// Whether to force re-verification
    pub force_verify: Option<bool>,
}

impl CommitApiHandler {
    /// Get a specific commit by ID
    ///
    /// GET /api/repos/:repo/commits/:id
    pub async fn get_commit(
        State(commit_service): State<Arc<CommitService>>,
        Path((repo_name, commit_id)): Path<(String, String)>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["commit", "get"]);

        debug!("Getting commit {commit_id} for repo {repo_name}");
        let commit = commit_service.get_commit(&repo_name, &commit_id)?;

        Ok(Json(commit))
    }

    /// Get signature verification for a commit
    ///
    /// GET /api/repos/:repo/commits/:id/signature
    pub async fn get_commit_signature(
        State(commit_service): State<Arc<CommitService>>,
        Path((repo_name, commit_id)): Path<(String, String)>,
        Query(params): Query<CommitSignatureParams>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["commit", "signature"]);

        debug!("Getting signature verification for commit {commit_id} in repo {repo_name}");
        let commit = commit_service.get_commit_with_signature_verification(&repo_name, &commit_id).await?;

        Ok(Json(commit))
    }

    /// List commits in a repository
    ///
    /// GET /api/repos/:repo/commits
    pub async fn list_commits(
        State(commit_service): State<Arc<CommitService>>,
        Path(repo_name): Path<String>,
        Query(params): Query<CommitListParams>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["commit", "list"]);

        let limit = params.limit.unwrap_or(20);
        let page = params.page.unwrap_or(0);

        debug!("Listing commits for repo {repo_name} (limit={limit}, page={page})");
        let commits = commit_service.list_commits(&repo_name, limit, page)?;

        Ok(Json(commits))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request;
    use axum::body::Body;
    use tower::ServiceExt;
    use proptest::prelude::*;
    use http_body_util::BodyExt;
    use axum::routing::{get, post};
    use axum::{Router, Json};
    use crate::service::repository::RepositoryService;
    use crate::data::git::Git;
    use crate::config::RepositoryConfig;
    use tempfile::TempDir;
    use std::sync::Arc;
    use std::path::PathBuf;

    /// Create a test service
    fn create_test_service() -> (Router, TempDir) {
        // Create a temporary directory
        let temp_dir = TempDir::new().unwrap();
        let repo_dir = temp_dir.path().to_path_buf();

        // Create a repository config
        let config = RepositoryConfig {
            repo_dir: repo_dir.clone(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
            verify_commit_signatures: true,
            gpg_homedir: None,
            trusted_gpg_keys: Vec::new(),
            trusted_ssh_keys: Vec::new(),
        };

        // Create the Git service
        let git = Arc::new(Git::new(&config).unwrap());

        // Create the repository service
        let repository_service = Arc::new(RepositoryService::new(git.clone(), repo_dir));

        // Create the commit service
        let commit_service = Arc::new(CommitService::new(git, repository_service));

        // Create the router
        let app = Router::new()
            .route("/api/repos/:repo/commits/:id", get(CommitApiHandler::get_commit))
            .route("/api/repos/:repo/commits/:id/signature", get(CommitApiHandler::get_commit_signature))
            .route("/api/repos/:repo/commits", get(CommitApiHandler::list_commits))
            .with_state(commit_service);

        (app, temp_dir)
    }

    proptest! {
        #[test]
        fn test_get_commit_signature_endpoint(
            repo_name in r"[a-zA-Z0-9_-]{1,32}",
            commit_id in r"[a-f0-9]{7,40}"
        ) {
            // Create the test service
            let (app, _temp_dir) = create_test_service();

            // Create the request
            let request = Request::builder()
                .uri(&format!("/api/repos/{}/commits/{}/signature", repo_name, commit_id))
                .method("GET")
                .body(Body::empty())
                .unwrap();

            // Make the request
            let response = pollster::block_on(app.oneshot(request)).unwrap();

            // Even though the repository doesn't exist, the endpoint itself should be accessible
            // It should return a 404, but the endpoint itself should be valid
            assert!(response.status() == StatusCode::NOT_FOUND ||
                   response.status() == StatusCode::OK);
        }
    }
}
