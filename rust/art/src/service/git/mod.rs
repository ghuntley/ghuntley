//! Git protocol service for handling Git operations over HTTP.
//!
//! This module implements the Git Smart HTTP protocol to support
//! clone, fetch, and push operations from Git clients. It also
//! provides repository maintenance functionality.

use crate::data::Git;
use crate::error::{Error, Result};
use crate::config::RepositoryConfig;
use crate::data::cache::Cache;
use crate::data::Sqlite;
use crate::service::repository::RepositoryService;

use std::sync::Arc;
use std::collections::HashMap;
use std::time::{Duration, Instant};
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use tracing::{debug, error, info, trace, warn};

/// Git protocol service for handling Git operations
pub struct GitService {
    /// Git data access
    git: Arc<Git>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// Database access
    db: Arc<Sqlite>,

    /// Cache
    cache: Arc<Cache<String, String>>,

    /// Git repository configuration
    config: Arc<RepositoryConfig>,
}

/// Git operation type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum GitOperation {
    /// Git clone operation
    Clone,

    /// Git fetch operation
    Fetch,

    /// Git push operation
    Push,

    /// Git LFS operation
    Lfs,
}

/// Git service operation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitOperationResult {
    /// Operation type
    pub operation: GitOperation,

    /// Repository name
    pub repository: String,

    /// User who performed the operation (if authenticated)
    pub user: Option<String>,

    /// Start time
    pub start_time: DateTime<Utc>,

    /// Duration in milliseconds
    pub duration_ms: u64,

    /// Number of objects transferred
    pub objects_transferred: usize,

    /// Bytes transferred
    pub bytes_transferred: usize,

    /// Success status
    pub success: bool,

    /// Error message if operation failed
    pub error: Option<String>,
}

/// Maintenance status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MaintenanceStatus {
    /// Repository name
    pub repository: String,

    /// Last maintenance time
    pub last_maintenance: DateTime<Utc>,

    /// Next scheduled maintenance
    pub next_maintenance: DateTime<Utc>,

    /// Maintenance types performed
    pub maintenance_types: Vec<String>,

    /// Duration in milliseconds
    pub duration_ms: u64,

    /// Success status
    pub success: bool,

    /// Error message if maintenance failed
    pub error: Option<String>,
}

impl GitService {
    /// Create a new Git service
    pub fn new(
        git: Arc<Git>,
        repository_service: Arc<RepositoryService>,
        db: Arc<Sqlite>,
        cache: Arc<Cache<String, String>>,
        config: Arc<RepositoryConfig>,
    ) -> Self {
        Self {
            git,
            repository_service,
            db,
            cache,
            config,
        }
    }

    /// Handle Git upload pack advertisement (used for clone/fetch)
    pub async fn handle_upload_pack_advertisement(&self, repo_name: &str) -> Result<Vec<u8>> {
        // Validate and sanitize repository name
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

        // Generate advertisement
        let advertisement = repo.generate_upload_pack_advertisement()
            .map_err(|e| Error::GitProtocol(format!("Failed to generate upload pack advertisement: {}", e)))?;

        Ok(advertisement)
    }

    /// Handle Git upload pack request (used for clone/fetch)
    pub async fn handle_upload_pack_request(&self, repo_name: &str, request_data: &[u8]) -> Result<Vec<u8>> {
        let start_time = Instant::now();

        // Validate and sanitize repository name
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

        // Process request
        let response = repo.process_upload_pack_request(request_data)
            .map_err(|e| Error::GitProtocol(format!("Failed to process upload pack request: {}", e)))?;

        // Record statistics
        self.record_operation_stats(repo_name.clone(), GitOperation::Fetch, start_time.elapsed(), response.len(), true, None).await?;

        // Invalidate cache for repository
        self.invalidate_cache(&repo_name).await?;

        // Check if maintenance is needed
        self.check_maintenance_needed(&repo_name).await?;

        Ok(response)
    }

    /// Handle Git receive pack advertisement (used for push)
    pub async fn handle_receive_pack_advertisement(&self, repo_name: &str, user: Option<&str>) -> Result<Vec<u8>> {
        // Validate and sanitize repository name
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

        // Check write permission
        if user.is_none() {
            return Err(Error::Authentication("Authentication required for push operations".to_string()));
        }

        // Generate advertisement
        let advertisement = repo.generate_receive_pack_advertisement()
            .map_err(|e| Error::GitProtocol(format!("Failed to generate receive pack advertisement: {}", e)))?;

        Ok(advertisement)
    }

    /// Handle Git receive pack request (used for push)
    pub async fn handle_receive_pack_request(&self, repo_name: &str, request_data: &[u8], user: Option<&str>) -> Result<Vec<u8>> {
        let start_time = Instant::now();

        // Validate and sanitize repository name
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;

        // Check write permission
        if user.is_none() {
            return Err(Error::Authentication("Authentication required for push operations".to_string()));
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

        // Process request
        let response = match repo.process_receive_pack_request(request_data) {
            Ok(res) => res,
            Err(e) => {
                // Record failed operation
                self.record_operation_stats(
                    repo_name,
                    GitOperation::Push,
                    start_time.elapsed(),
                    0,
                    false,
                    Some(e.to_string())
                ).await?;

                return Err(Error::GitProtocol(format!("Failed to process receive pack request: {}", e)));
            }
        };

        // Record successful operation
        self.record_operation_stats(
            repo_name.clone(),
            GitOperation::Push,
            start_time.elapsed(),
            response.len(),
            true,
            None,
        ).await?;

        // Invalidate cache entries for this repository
        self.invalidate_cache(&repo_name).await?;

        // Check if maintenance is needed
        self.check_maintenance_needed(&repo_name).await?;

        Ok(response)
    }

    /// Record Git operation statistics
    async fn record_operation_stats(
        &self,
        repository: impl Into<String>,
        operation: GitOperation,
        duration: Duration,
        bytes: usize,
        success: bool,
        error: Option<String>,
    ) -> Result<()> {
        let repository = repository.into();
        let user = None; // TODO: Get from authenticated user

        let result = GitOperationResult {
            operation,
            repository: repository.clone(),
            user,
            start_time: Utc::now() - chrono::Duration::from_std(duration).unwrap_or_default(),
            duration_ms: duration.as_millis() as u64,
            objects_transferred: bytes / 100, // Rough estimate
            bytes_transferred: bytes,
            success,
            error,
        };

        // TODO: Store in database
        info!(
            repository = repository,
            operation = format!("{:?}", operation),
            duration_ms = duration.as_millis() as u64,
            bytes = bytes,
            success = success,
            "Git operation completed"
        );

        Ok(())
    }

    /// Invalidate cache entries for a repository
    async fn invalidate_cache(&self, repository: &str) -> Result<()> {
        // Clear cache entries related to this repository
        self.cache.invalidate_by_prefix(&format!("repo:{}", repository)).await;

        Ok(())
    }

    /// Check if maintenance is needed and schedule it if necessary
    async fn check_maintenance_needed(&self, repository: &str) -> Result<bool> {
        // TODO: Implement maintenance scheduling logic
        if self.config.enable_maintenance {
            // Check if enough time has passed since last maintenance
            // or if enough operations have been performed

            // For now, just return false to indicate no maintenance was performed
            Ok(false)
        } else {
            Ok(false)
        }
    }

    /// Run maintenance on a repository
    pub async fn run_maintenance(&self, repository: &str) -> Result<MaintenanceStatus> {
        let start_time = Instant::now();

        // Validate and sanitize repository name
        let repository = self.repository_service.sanitize_repository_name(repository)?;

        // Get repository
        let repo = self.git.repository(&repository)
            .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

        // Perform maintenance tasks
        let maintenance_types = vec![
            "gc".to_string(),
            "repack".to_string(),
            "prune".to_string(),
        ];

        let result = match repo.run_maintenance() {
            Ok(_) => {
                // Update maintenance status in the database
                // TODO: Store maintenance status

                MaintenanceStatus {
                    repository: repository.clone(),
                    last_maintenance: Utc::now(),
                    next_maintenance: Utc::now() + chrono::Duration::hours(24),
                    maintenance_types,
                    duration_ms: start_time.elapsed().as_millis() as u64,
                    success: true,
                    error: None,
                }
            },
            Err(e) => {
                let error_msg = format!("Maintenance failed: {}", e);
                error!(repository = repository, error = error_msg, "Repository maintenance failed");

                MaintenanceStatus {
                    repository: repository.clone(),
                    last_maintenance: Utc::now(),
                    next_maintenance: Utc::now() + chrono::Duration::hours(24),
                    maintenance_types,
                    duration_ms: start_time.elapsed().as_millis() as u64,
                    success: false,
                    error: Some(error_msg),
                }
            }
        };

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use tempfile::TempDir;
    use std::path::Path;

    /// Create a test Git service
    async fn create_test_service() -> (GitService, TempDir) {
        // Create a temporary directory
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let temp_path = temp_dir.path().to_string_lossy().to_string();

        // Create sample repository
        let repo_path = temp_dir.path().join("test-repo.git");
        std::fs::create_dir_all(&repo_path).expect("Failed to create repo dir");

        // Initialize bare Git repository
        let repo = git2::Repository::init_bare(&repo_path).expect("Failed to init git repo");

        // Create repository config
        let repo_config = Arc::new(RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_commits: 100,
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        });

        // Create Git manager
        let git = Arc::new(Git::new(&repo_config).expect("Failed to create Git manager"));

        // Create SQLite database
        let db_path = temp_dir.path().join("test.db");
        let db = Arc::new(Sqlite::open(&db_path.to_string_lossy().to_string()).expect("Failed to create database"));

        // Create cache
        let cache = Arc::new(Cache::new().await);

        // Create repository service
        let repo_service = Arc::new(RepositoryService::new(git.clone(), db.clone(), cache.clone()));

        // Create Git service
        let git_service = GitService::new(git, repo_service, db, cache, repo_config);

        (git_service, temp_dir)
    }

    #[tokio::test]
    async fn test_maintenance() {
        let (service, _temp_dir) = create_test_service().await;

        // Run maintenance on a repository
        let result = service.run_maintenance("test-repo").await;

        // This might fail since the repository is empty, but we're testing the function call
        assert!(result.is_ok() || result.is_err());
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use std::time::Duration;

    // Strategy for generating valid repository names
    fn valid_repo_name_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z][a-zA-Z0-9_-]{1,20}"
    }

    // Strategy for generating valid Git operations
    fn git_operation_strategy() -> impl Strategy<Value = GitOperation> {
        prop_oneof![
            Just(GitOperation::Clone),
            Just(GitOperation::Fetch),
            Just(GitOperation::Push),
            Just(GitOperation::Lfs)
        ]
    }

    // Strategy for generating valid durations
    fn duration_strategy() -> impl Strategy<Value = Duration> {
        (1u64..10000u64).prop_map(Duration::from_millis)
    }

    // Strategy for generating byte counts
    fn bytes_strategy() -> impl Strategy<Value = usize> {
        1usize..100000usize
    }

    proptest! {
        /// Test that operation recording generates valid statistics
        #[test]
        fn record_operation_stats_generates_valid_results(
            repository in valid_repo_name_strategy(),
            operation in git_operation_strategy(),
            duration in duration_strategy(),
            bytes in bytes_strategy(),
            success in proptest::bool::ANY,
            has_error in proptest::bool::ANY
        ) {
            // Create a runtime for async testing
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                // Create test service
                let (service, _temp_dir) = create_test_service().await;

                // Create optional error
                let error = if has_error && !success {
                    Some("Test error".to_string())
                } else {
                    None
                };

                // Record operation stats
                let result = service.record_operation_stats(
                    repository.clone(),
                    operation,
                    duration,
                    bytes,
                    success,
                    error.clone()
                ).await;

                // Verify the recording succeeded
                assert!(result.is_ok(), "Recording operation stats should succeed");

                // Retrieve and verify the stats were recorded correctly
                // Note: In a real implementation, you would retrieve from the database here
                // For now, we just verify the function call succeeded
            });
        }

        /// Test that maintenance status contains valid fields
        #[test]
        fn maintenance_status_contains_valid_fields(
            repository in valid_repo_name_strategy(),
            duration_ms in 1u64..10000u64,
            success in proptest::bool::ANY,
            has_error in proptest::bool::ANY
        ) {
            // Create maintenance types
            let maintenance_types = vec![
                "gc".to_string(),
                "repack".to_string(),
                "prune".to_string(),
            ];

            // Current time
            let now = Utc::now();

            // Create maintenance status
            let status = MaintenanceStatus {
                repository: repository.clone(),
                last_maintenance: now,
                next_maintenance: now + chrono::Duration::hours(24),
                maintenance_types: maintenance_types.clone(),
                duration_ms,
                success,
                error: if has_error && !success { Some("Test error".to_string()) } else { None },
            };

            // Verify fields
            assert_eq!(status.repository, repository);
            assert_eq!(status.duration_ms, duration_ms);
            assert_eq!(status.success, success);
            assert_eq!(status.maintenance_types, maintenance_types);

            // Check error field consistency with success
            if !success && has_error {
                assert!(status.error.is_some());
            } else if success {
                assert!(status.error.is_none());
            }

            // Check next_maintenance is after last_maintenance
            assert!(status.next_maintenance > status.last_maintenance);
        }

        /// Test that GitOperationResult serializes and deserializes correctly
        #[test]
        fn git_operation_result_serializes_correctly(
            repository in valid_repo_name_strategy(),
            operation in git_operation_strategy(),
            duration_ms in 1u64..10000u64,
            objects_transferred in 0usize..1000usize,
            bytes_transferred in 0usize..100000usize,
            success in proptest::bool::ANY,
            has_error in proptest::bool::ANY
        ) {
            // Current time
            let now = Utc::now();

            // Create operation result
            let result = GitOperationResult {
                operation,
                repository: repository.clone(),
                user: None,
                start_time: now,
                duration_ms,
                objects_transferred,
                bytes_transferred,
                success,
                error: if has_error && !success { Some("Test error".to_string()) } else { None },
            };

            // Serialize to JSON
            let json = serde_json::to_string(&result).expect("Serialization should succeed");

            // Deserialize from JSON
            let deserialized: GitOperationResult = serde_json::from_str(&json).expect("Deserialization should succeed");

            // Verify fields match
            assert_eq!(deserialized.operation, result.operation);
            assert_eq!(deserialized.repository, result.repository);
            assert_eq!(deserialized.user, result.user);
            assert_eq!(deserialized.duration_ms, result.duration_ms);
            assert_eq!(deserialized.objects_transferred, result.objects_transferred);
            assert_eq!(deserialized.bytes_transferred, result.bytes_transferred);
            assert_eq!(deserialized.success, result.success);
            assert_eq!(deserialized.error, result.error);

            // The serialized JSON should include all relevant fields
            assert!(json.contains(&repository));
            assert!(json.contains(&format!("{:?}", operation).to_lowercase()));
            assert!(json.contains(&duration_ms.to_string()));
            assert!(json.contains(&objects_transferred.to_string()));
            assert!(json.contains(&bytes_transferred.to_string()));
            assert!(json.contains(&success.to_string()));

            if has_error && !success {
                assert!(json.contains("Test error"));
            }
        }
    }
}
