// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Test fixtures for Art
//!
//! This module provides common test fixtures for testing Art components.

use crate::prelude::*;
use crate::config::Config;
use crate::data::{Sqlite, Git};
use crate::data::cache::Cache;
use crate::service::repository::RepositoryService;
use crate::service::observability::{ObservabilityService, ObservabilityConfig};

use std::path::PathBuf;
use std::sync::Arc;
use tempfile::TempDir;
use tokio::sync::Mutex;

/// A simple fixture that creates temporary resources for testing
///
/// This fixture creates:
/// - A temporary directory for Git repositories
/// - A temporary SQLite database
/// - Minimal test configuration
pub struct TestFixture {
    /// Temporary directory for the test
    pub temp_dir: TempDir,

    /// Path to the Git repositories directory
    pub repos_dir: PathBuf,

    /// Path to the SQLite database
    pub db_path: PathBuf,

    /// Configuration for the test
    pub config: Config,

    /// SQLite database connection
    pub db: Arc<Sqlite>,

    /// Git repository store
    pub git: Arc<Git>,

    /// Cache for the test
    pub cache: Arc<Cache>,

    /// Repository service
    pub repository_service: Arc<RepositoryService>,

    /// Observability service
    pub observability_service: Arc<ObservabilityService>,
}

impl TestFixture {
    /// Create a new test fixture with default configuration
    pub async fn new() -> Result<Self> {
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
                ObservabilityConfig::default(),
                None,
                None,
            ).await?
        );

        Ok(Self {
            temp_dir,
            repos_dir,
            db_path,
            config,
            db,
            git,
            cache,
            repository_service,
            observability_service,
        })
    }

    /// Create a test repository with a single commit
    pub async fn create_test_repository(&self, name: &str) -> Result<PathBuf> {
        let repo_path = self.repos_dir.join(name);
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

/// A thread-safe shared test fixture for use in property-based tests
pub struct SharedTestFixture {
    /// The inner test fixture protected by a mutex
    inner: Mutex<Option<TestFixture>>,
}

impl SharedTestFixture {
    /// Create a new shared test fixture
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    /// Get or create the test fixture
    pub async fn get(&self) -> Result<TestFixture> {
        let mut guard = self.inner.lock().await;

        // Check if we already have a fixture
        if let Some(fixture) = guard.as_ref() {
            // Return a clone of our existing fixture
            return Ok(TestFixture {
                temp_dir: fixture.temp_dir.path().to_path_buf().into(),
                repos_dir: fixture.repos_dir.clone(),
                db_path: fixture.db_path.clone(),
                config: fixture.config.clone(),
                db: fixture.db.clone(),
                git: fixture.git.clone(),
                cache: fixture.cache.clone(),
                repository_service: fixture.repository_service.clone(),
                observability_service: fixture.observability_service.clone(),
            });
        }

        // Create a new fixture
        let fixture = TestFixture::new().await?;
        *guard = Some(fixture);

        Ok(guard.as_ref().unwrap().clone())
    }
}

// Implement Clone for TestFixture to allow sharing across tests
// For reference types, we're cloning the Arc, not the underlying data
impl Clone for TestFixture {
    fn clone(&self) -> Self {
        Self {
            temp_dir: self.temp_dir.path().to_path_buf().into(),
            repos_dir: self.repos_dir.clone(),
            db_path: self.db_path.clone(),
            config: self.config.clone(),
            db: self.db.clone(),
            git: self.git.clone(),
            cache: self.cache.clone(),
            repository_service: self.repository_service.clone(),
            observability_service: self.observability_service.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[tokio::test]
    async fn test_fixture_creation() {
        let fixture = TestFixture::new().await.unwrap();

        assert!(fixture.temp_dir.path().exists());
        assert!(fixture.repos_dir.exists());
        assert!(fixture.db.is_connected().await.is_ok());
    }

    #[tokio::test]
    async fn test_create_test_repository() {
        let fixture = TestFixture::new().await.unwrap();
        let repo_path = fixture.create_test_repository("test-repo").await.unwrap();

        assert!(repo_path.exists());
        assert!(Path::new(&repo_path).join(".git").exists());
        assert!(Path::new(&repo_path).join("README.md").exists());

        // Check if the repository is registered
        let repos = fixture.repository_service.list_repositories().await.unwrap();
        assert!(repos.iter().any(|r| r.name == "test-repo"));
    }

    #[tokio::test]
    async fn test_shared_fixture() {
        let shared = SharedTestFixture::new();

        // Get the fixture twice - should be the same instance
        let fixture1 = shared.get().await.unwrap();
        let fixture2 = shared.get().await.unwrap();

        // Test that they share the same data
        assert_eq!(fixture1.repos_dir, fixture2.repos_dir);
        assert_eq!(fixture1.db_path, fixture2.db_path);

        // Create a test repo in the first fixture
        fixture1.create_test_repository("shared-test-repo").await.unwrap();

        // Check that it's visible in the second fixture
        let repos = fixture2.repository_service.list_repositories().await.unwrap();
        assert!(repos.iter().any(|r| r.name == "shared-test-repo"));
    }
}
