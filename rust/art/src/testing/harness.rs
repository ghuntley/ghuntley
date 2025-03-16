// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Test harness for Art
//!
//! This module provides the test harness for integration and property-based testing.

use crate::prelude::*;
use crate::config::Config;
use crate::data::{Sqlite, Git};
use crate::data::cache::Cache;
use crate::service::repository::RepositoryService;
use crate::service::observability::ObservabilityService;
use crate::http::serve;
use std::path::PathBuf;
use std::sync::Arc;
use std::net::SocketAddr;
use axum::Router;
use std::time::Duration;
use tokio::net::TcpListener;

/// TestServer provides a harness for testing HTTP handlers
pub struct TestServer {
    /// Base URL of the test server
    pub base_url: String,

    /// Application router
    pub app: Router,

    /// Abort handle for the server task
    abort_handle: tokio::task::JoinHandle<()>,

    /// Repository service
    pub repository_service: Arc<RepositoryService>,

    /// Observability service
    pub observability_service: Arc<ObservabilityService>,

    /// Git repository store
    pub git: Arc<Git>,

    /// Database connection
    pub db: Arc<Sqlite>,

    /// Cache
    pub cache: Arc<Cache>,

    /// Server address
    pub addr: SocketAddr,
}

impl TestServer {
    /// Create a new test server
    pub async fn new() -> Result<Self> {
        // Create a temporary configuration
        let temp_dir = tempfile::tempdir()?;
        let repos_dir = temp_dir.path().join("repos");
        let db_path = temp_dir.path().join("test.db");

        // Create repos directory
        std::fs::create_dir_all(&repos_dir)?;

        // Create basic configuration
        let mut config = Config::default();
        config.repository.repo_dir = repos_dir.to_string_lossy().to_string();
        config.database.path = PathBuf::from(db_path.to_string_lossy().to_string());

        // Set up database
        let db = Arc::new(Sqlite::new(&config.database).await?);

        // Set up Git repository store
        let git = Arc::new(Git::new(&config.repository)?);

        // Set up cache
        let cache = Arc::new(Cache::new(&config.cache));

        // Set up repository service
        let repository_service = Arc::new(RepositoryService::new(
            git.clone(),
            cache.clone(),
        ));

        // Set up observability service
        let observability_service = Arc::new(
            ObservabilityService::new(
                config.observability.clone(),
                None,
                None,
            ).await?
        );

        // Set up HTTP routes
        let app = serve(
            Arc::new(config.clone()),
            repository_service.clone(),
            observability_service.clone(),
            git.clone(),
            None,
            None,
        )?;

        // Start the server on a random port
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let addr = listener.local_addr()?;
        let base_url = format!("http://{}", addr);

        // Start the server in the background
        let app_clone = app.clone();
        let abort_handle = tokio::spawn(async move {
            axum::serve(listener, app_clone.into_make_service_with_connect_info::<SocketAddr>())
                .await
                .unwrap();
        });

        Ok(Self {
            base_url,
            app,
            abort_handle,
            repository_service,
            observability_service,
            git,
            db,
            cache,
            addr,
        })
    }

    /// Make a GET request to the test server
    pub async fn get(&self, path: &str) -> reqwest::Response {
        let client = reqwest::Client::new();
        client.get(format!("{}{}", self.base_url, path))
            .timeout(Duration::from_secs(5))
            .send()
            .await
            .unwrap()
    }

    /// Make a POST request to the test server
    pub async fn post(&self, path: &str, body: impl Into<reqwest::Body>) -> reqwest::Response {
        let client = reqwest::Client::new();
        client.post(format!("{}{}", self.base_url, path))
            .timeout(Duration::from_secs(5))
            .body(body)
            .send()
            .await
            .unwrap()
    }

    /// Create a test repository
    pub async fn create_repository(&self, name: &str) -> Result<PathBuf> {
        // Get the repository directory from the repository service config
        let repo_info = self.repository_service.get_repository(name).await.ok();
        let repo_path = if let Some(info) = repo_info {
            PathBuf::from(&info.path)
        } else {
            // If repository doesn't exist yet, use the repository directory from config
            let config = Config::default();
            PathBuf::from(&config.repository.repo_dir).join(name)
        };

        std::fs::create_dir_all(&repo_path)?;

        // Initialize repository
        let output = std::process::Command::new("git")
            .args(["init", "."])
            .current_dir(&repo_path)
            .output()?;

        if !output.status.success() {
            bail!("Failed to initialize Git repository: {}",
                String::from_utf8_lossy(&output.stderr));
        }

        // Configure git
        let _ = std::process::Command::new("git")
            .args(["config", "user.email", "test@example.com"])
            .current_dir(&repo_path)
            .output()?;

        let _ = std::process::Command::new("git")
            .args(["config", "user.name", "Test User"])
            .current_dir(&repo_path)
            .output()?;

        // Create README.md
        std::fs::write(
            repo_path.join("README.md"),
            "# Test Repository\n\nThis is a test repository."
        )?;

        // Add and commit
        let _ = std::process::Command::new("git")
            .args(["add", "README.md"])
            .current_dir(&repo_path)
            .output()?;

        let output = std::process::Command::new("git")
            .args(["commit", "-m", "Initial commit"])
            .current_dir(&repo_path)
            .output()?;

        if !output.status.success() {
            bail!("Failed to commit to Git repository: {}",
                String::from_utf8_lossy(&output.stderr));
        }

        // Register repository with service
        self.repository_service.add_repository(name, &repo_path).await?;

        Ok(repo_path)
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.abort_handle.abort();
    }
}

/// A mock request context for testing handlers directly
pub struct MockRequestContext {
    /// Method (GET, POST, etc.)
    pub method: String,

    /// Path
    pub path: String,

    /// Query parameters
    pub query: std::collections::HashMap<String, String>,

    /// Headers
    pub headers: std::collections::HashMap<String, String>,

    /// Request body
    pub body: Vec<u8>,

    /// Remote IP address
    pub remote_addr: String,
}

impl MockRequestContext {
    /// Create a new mock request context
    pub fn new(method: &str, path: &str) -> Self {
        Self {
            method: method.to_string(),
            path: path.to_string(),
            query: std::collections::HashMap::new(),
            headers: std::collections::HashMap::new(),
            body: Vec::new(),
            remote_addr: "127.0.0.1".to_string(),
        }
    }

    /// Add a query parameter
    pub fn query(mut self, key: &str, value: &str) -> Self {
        self.query.insert(key.to_string(), value.to_string());
        self
    }

    /// Add a header
    pub fn header(mut self, key: &str, value: &str) -> Self {
        self.headers.insert(key.to_string(), value.to_string());
        self
    }

    /// Set the request body
    pub fn body(mut self, body: impl Into<Vec<u8>>) -> Self {
        self.body = body.into();
        self
    }

    /// Set the remote IP address
    pub fn remote_addr(mut self, addr: &str) -> Self {
        self.remote_addr = addr.to_string();
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_server_creation() {
        let server = TestServer::new().await.unwrap();

        // Test the server is responsive
        let response = server.get("/").await;
        assert_eq!(response.status().as_u16(), 200);

        // Check that the server has the expected components
        assert!(server.repository_service.is_initialized());
        assert!(server.db.is_connected().await.is_ok());
    }

    #[tokio::test]
    async fn test_create_repository() {
        let server = TestServer::new().await.unwrap();
        let repo_path = server.create_repository("test-repo").await.unwrap();

        // Check the repository was created properly
        assert!(repo_path.exists());
        assert!(repo_path.join(".git").exists());
        assert!(repo_path.join("README.md").exists());

        // Check the repository is registered with the service
        let repos = server.repository_service.list_repositories().await.unwrap();
        assert!(repos.iter().any(|r| r.name == "test-repo"));

        // Test repository endpoints
        let response = server.get("/repo/test-repo").await;
        assert_eq!(response.status().as_u16(), 200);

        let response = server.get("/repo/test-repo/tree/master").await;
        assert_eq!(response.status().as_u16(), 200);
    }
}
