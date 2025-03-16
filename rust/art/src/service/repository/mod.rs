//! Repository service for managing Git repositories.

use crate::data::Git;
use crate::data::Sqlite;
use crate::error::{Error, Result};
use crate::data::cache::Cache;

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::collections::HashMap;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, trace, warn};

mod statistics;
pub mod maintenance;

pub use statistics::{RepositoryStats, ContributorStats, RepositoryStatisticsService};

/// Repository information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryInfo {
    /// Repository name
    pub name: String,

    /// Repository path
    pub path: String,

    /// Repository description
    pub description: Option<String>,

    /// Repository owner
    pub owner: Option<String>,

    /// Last update timestamp
    pub last_updated: Option<DateTime<Utc>>,

    /// Number of branches
    pub branch_count: usize,

    /// Number of tags
    pub tag_count: usize,

    /// Number of commits
    pub commit_count: usize,
}

/// Repository configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryConfig {
    /// Repository name
    pub name: String,

    /// Repository description
    pub description: Option<String>,

    /// Repository owner
    pub owner: Option<String>,

    /// Whether to enable maintenance tasks
    pub enable_maintenance: bool,

    /// Maintenance schedule (cron expression)
    pub maintenance_schedule: Option<String>,

    /// Whether to verify commit signatures
    pub verify_commit_signatures: bool,

    /// Maximum object size (bytes)
    pub max_object_size: Option<u64>,

    /// Git configuration overrides
    pub git_config: HashMap<String, String>,
}

/// Repository health status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryHealth {
    /// Repository name
    pub name: String,

    /// Overall health status
    pub status: String,

    /// Last maintenance time
    pub last_maintenance: Option<DateTime<Utc>>,

    /// Git status (ok, needs_maintenance, error)
    pub git_status: String,

    /// Git status message
    pub git_message: Option<String>,

    /// Database status (ok, needs_reindex, error)
    pub db_status: String,

    /// Database status message
    pub db_message: Option<String>,

    /// Repository size in bytes
    pub size_bytes: u64,

    /// Number of loose objects
    pub loose_objects: usize,

    /// Number of packfiles
    pub packfiles: usize,

    /// Last commit time
    pub last_commit: Option<DateTime<Utc>>,
}

/// Repository service for working with Git repositories
pub struct RepositoryService {
    /// Git data access
    git: Arc<Git>,

    /// SQLite database
    db: Arc<Sqlite>,

    /// Cache manager
    cache: Arc<Cache<String, String>>,

    /// Repository statistics service
    stats_service: Option<Arc<RepositoryStatisticsService>>,
}

impl RepositoryService {
    /// Create a new repository service
    pub fn new(git: Arc<Git>, cache: Arc<Cache<String, String>>) -> Self {
        let db = Arc::new(Sqlite::new());

        Self {
            git,
            db,
            cache,
            stats_service: None,
        }
    }

    /// Add repository statistics service
    pub fn with_statistics_service(mut self, stats_service: Arc<RepositoryStatisticsService>) -> Self {
        self.stats_service = Some(stats_service);
        self
    }

    /// Get repository statistics service
    pub fn stats_service(&self) -> Option<&Arc<RepositoryStatisticsService>> {
        self.stats_service.as_ref()
    }

    /// List all repositories
    pub async fn list_repositories(&self) -> Result<Vec<RepositoryInfo>> {
        // Try to get from cache first
        if let Some(cached) = self.cache.get("repos:list").await {
            return Ok(serde_json::from_str(&cached)
                .map_err(|e| Error::Internal(format!("Failed to deserialize cached repositories: {}", e)))?);
        }

        // Otherwise fetch from Git
        let repo_infos = self.git.list_repositories()?;

        let repositories: Vec<RepositoryInfo> = repo_infos.into_iter()
            .map(|info| RepositoryInfo {
                name: info.name.clone(),
                path: info.path.to_string_lossy().to_string(),
                description: info.description.clone(),
                owner: info.owner.clone(),
                last_updated: info.last_commit.map(|c| c),
                branch_count: info.branch_count,
                tag_count: info.tag_count,
                commit_count: info.commit_count,
            })
            .collect();

        // Cache the result
        self.cache.insert(
            "repos:list".to_string(),
            serde_json::to_string(&repositories)
                .map_err(|e| Error::Internal(format!("Failed to serialize repositories: {}", e)))?,
        ).await;

        Ok(repositories)
    }

    /// Get repository information
    pub async fn get_repository(&self, name: &str) -> Result<RepositoryInfo> {
        // Try to get from cache first
        let cache_key = format!("repo:{}", name);
        if let Some(cached) = self.cache.get(&cache_key).await {
            return Ok(serde_json::from_str(&cached)
                .map_err(|e| Error::Internal(format!("Failed to deserialize cached repository: {}", e)))?);
        }

        // Otherwise fetch from Git
        let repo = self.git.open(name, name)
            .map_err(|e| Error::NotFound(format!("Repository '{}' not found: {}", name, e)))?;

        let info = repo.info()
            .map_err(|e| Error::Internal(format!("Failed to get repository info: {}", e)))?;

        let result = RepositoryInfo {
            name: info.name.clone(),
            path: info.path.to_string_lossy().to_string(),
            description: info.description.clone(),
            owner: info.owner.clone(),
            last_updated: info.last_commit.map(|c| c),
            branch_count: info.branch_count,
            tag_count: info.tag_count,
            commit_count: info.commit_count,
        };

        // Cache the result
        self.cache.insert(
            cache_key,
            serde_json::to_string(&result)
                .map_err(|e| Error::Internal(format!("Failed to serialize repository: {}", e)))?,
        ).await;

        Ok(result)
    }

    /// Get repository statistics
    pub async fn get_repository_stats(&self, name: &str) -> Result<RepositoryStats> {
        if let Some(stats_service) = &self.stats_service {
            stats_service.get_stats(name).await
        } else {
            Err(Error::Internal("Repository statistics service not initialized".to_string()))
        }
    }

    /// Refresh repository statistics
    pub async fn refresh_repository_stats(&self, name: &str) -> Result<RepositoryStats> {
        if let Some(stats_service) = &self.stats_service {
            stats_service.refresh_stats(name).await
        } else {
            Err(Error::Internal("Repository statistics service not initialized".to_string()))
        }
    }

    /// Validate a repository name
    pub fn sanitize_repository_name(&self, name: &str) -> Result<String> {
        // Check for path traversal
        if name.contains("..") {
            return Err(Error::InvalidRequest(format!("Invalid repository name: {}", name)));
        }

        // Only allow alphanumeric, dash, underscore, dot, and forward slash
        let name_regex = regex::Regex::new(r"^[a-zA-Z0-9\-_.\/]+$").unwrap();
        if !name_regex.is_match(name) {
            return Err(Error::InvalidRequest(format!("Invalid repository name: {}", name)));
        }

        Ok(name.to_string())
    }

    /// Get repository configuration
    pub async fn get_repository_config(&self, name: &str) -> Result<RepositoryConfig> {
        // Try to get from cache first
        let cache_key = format!("repo_config:{}", name);
        if let Some(cached) = self.cache.get(&cache_key).await {
            return Ok(serde_json::from_str(&cached)
                .map_err(|e| Error::Internal(format!("Failed to deserialize cached config: {}", e)))?);
        }

        // Get from database
        let config = self.db.get_repository_config(name).await?
            .ok_or_else(|| Error::NotFound(format!("Repository config not found: {}", name)))?;

        // Cache the result
        self.cache.insert(
            cache_key,
            serde_json::to_string(&config)
                .map_err(|e| Error::Internal(format!("Failed to serialize repository config: {}", e)))?,
        ).await;

        Ok(config)
    }

    /// Update repository configuration
    pub async fn update_repository_config(&self, name: &str, config: RepositoryConfig) -> Result<()> {
        // Validate the config
        self.validate_repository_config(&config)?;

        // Update in database
        self.db.update_repository_config(name, &config).await?;

        // Invalidate cache
        self.cache.delete(&format!("repo_config:{}", name));

        Ok(())
    }

    /// Validate repository configuration
    fn validate_repository_config(&self, config: &RepositoryConfig) -> Result<()> {
        // Validate name
        self.sanitize_repository_name(&config.name)?;

        // Validate maintenance schedule if present
        if let Some(schedule) = &config.maintenance_schedule {
            if !cron::Schedule::from_str(schedule).is_ok() {
                return Err(Error::InvalidRequest(format!("Invalid maintenance schedule: {}", schedule)));
            }
        }

        // Validate max object size
        if let Some(size) = config.max_object_size {
            if size > 1024 * 1024 * 1024 * 10 { // 10GB max
                return Err(Error::InvalidRequest("Max object size too large".to_string()));
            }
        }

        Ok(())
    }

    /// Get repository health status
    pub async fn get_repository_health(&self, name: &str) -> Result<RepositoryHealth> {
        // Get repository
        let repo = self.git.get_repository(name)?;

        // Get repository info
        let info = repo.info()?;

        // Check Git status
        let (git_status, git_message) = self.check_git_health(name)?;

        // Check database status
        let (db_status, db_message) = self.check_db_health(name).await?;

        // Get repository size info
        let size_info = self.get_repository_size_info(name)?;

        // Get last maintenance time
        let last_maintenance = self.db.get_last_maintenance(name).await?;

        // Determine overall status
        let status = if git_status == "error" || db_status == "error" {
            "error"
        } else if git_status == "needs_maintenance" || db_status == "needs_reindex" {
            "needs_maintenance"
        } else {
            "ok"
        };

        Ok(RepositoryHealth {
            name: name.to_string(),
            status: status.to_string(),
            last_maintenance,
            git_status: git_status.to_string(),
            git_message,
            db_status: db_status.to_string(),
            db_message,
            size_bytes: size_info.total_size,
            loose_objects: size_info.loose_objects,
            packfiles: size_info.packfiles,
            last_commit: info.last_commit,
        })
    }

    /// Check Git repository health
    fn check_git_health(&self, repo_name: &str) -> Result<(String, Option<String>)> {
        // Get repository
        let repo = self.git.get_repository(repo_name)?;

        // Check for corruption
        if let Err(e) = repo.fsck() {
            return Ok(("error".to_string(), Some(format!("Repository corruption detected: {}", e))));
        }

        // Check for too many loose objects
        let size_info = self.get_repository_size_info(repo_name)?;
        if size_info.loose_objects > 10000 {
            return Ok(("needs_maintenance".to_string(), Some("Too many loose objects".to_string())));
        }

        // Check for too many packfiles
        if size_info.packfiles > 50 {
            return Ok(("needs_maintenance".to_string(), Some("Too many packfiles".to_string())));
        }

        Ok(("ok".to_string(), None))
    }

    /// Check database health
    async fn check_db_health(&self, name: &str) -> Result<(String, Option<String>)> {
        // Check if database needs reindexing
        if self.db.needs_reindex(name).await? {
            return Ok(("needs_reindex".to_string(), Some("Database needs reindexing".to_string())));
        }

        // Check for database errors
        if let Err(e) = self.db.check_integrity(name).await {
            return Ok(("error".to_string(), Some(format!("Database error: {}", e))));
        }

        Ok(("ok".to_string(), None))
    }

    /// Get repository size information
    fn get_repository_size_info(&self, repo_name: &str) -> Result<RepositorySizeInfo> {
        // Get repository
        let repo = self.git.get_repository(repo_name)?;

        let mut size_info = RepositorySizeInfo {
            total_size: 0,
            loose_objects: 0,
            packfiles: 0,
        };

        // Count loose objects
        let loose_objects = repo.count_loose_objects()?;
        size_info.loose_objects = loose_objects.count;
        size_info.total_size += loose_objects.size;

        // Count packfiles
        let packfiles = repo.count_packfiles()?;
        size_info.packfiles = packfiles.count;
        size_info.total_size += packfiles.size;

        Ok(size_info)
    }

    /// Run maintenance tasks on a repository
    pub async fn run_maintenance(&self, name: &str) -> Result<()> {
        // Get repository
        let repo = self.git.get_repository(name)?;

        // Run Git maintenance tasks
        self.run_git_maintenance(&repo)?;

        // Run database maintenance
        self.run_db_maintenance(name).await?;

        // Update last maintenance time
        self.db.update_last_maintenance(name).await?;

        // Invalidate caches
        self.cache.delete(&format!("repo:{}", name)).await;
        self.cache.delete(&format!("repo_stats:{}", name)).await;
        self.cache.delete(&format!("repo_config:{}", name)).await;

        Ok(())
    }

    /// Run Git maintenance tasks
    fn run_git_maintenance(&self, repo: &Repository) -> Result<()> {
        // Run garbage collection
        repo.gc()?;

        // Repack objects
        repo.repack()?;

        // Prune loose objects
        repo.prune()?;

        Ok(())
    }

    /// Run database maintenance tasks
    async fn run_db_maintenance(&self, name: &str) -> Result<()> {
        // Reindex if needed
        if self.db.needs_reindex(name).await? {
            self.db.reindex(name).await?;
        }

        // Optimize database
        self.db.optimize(name).await?;

        Ok(())
    }
}

/// Repository size information
#[derive(Debug)]
struct RepositorySizeInfo {
    /// Total size in bytes
    total_size: u64,
    /// Number of loose objects
    loose_objects: usize,
    /// Number of packfiles
    packfiles: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::RepositoryConfig;
    use tempfile::TempDir;
    use std::fs;
    use std::process::Command;
    use proptest::prelude::*;

    // Helper to create a test repository
    fn create_test_repo(temp_dir: &TempDir, name: &str) -> Result<PathBuf> {
        let repo_path = temp_dir.path().join(name);
        fs::create_dir_all(&repo_path)?;

        // Initialize Git repository
        let status = Command::new("git")
            .args(&["init", "--quiet", repo_path.to_str().unwrap()])
            .status()?;

        if !status.success() {
            return Err(Error::Internal("Failed to initialize Git repository".to_string()));
        }

        // Create a file
        fs::write(repo_path.join("README.md"), b"# Test Repository\n")?;

        // Configure Git
        Command::new("git")
            .args(&["-C", repo_path.to_str().unwrap(), "config", "user.name", "Test User"])
            .status()?;

        Command::new("git")
            .args(&["-C", repo_path.to_str().unwrap(), "config", "user.email", "test@example.com"])
            .status()?;

        // Add and commit the file
        Command::new("git")
            .args(&["-C", repo_path.to_str().unwrap(), "add", "README.md"])
            .status()?;

        Command::new("git")
            .args(&["-C", repo_path.to_str().unwrap(), "commit", "-m", "Initial commit"])
            .status()?;

        Ok(repo_path)
    }

    #[tokio::test]
    async fn test_repository_service() -> Result<()> {
        // Create a temporary directory
        let temp_dir = TempDir::new()?;
        let repo_path = create_test_repo(&temp_dir, "test-repo")?;

        // Create Git instance
        let config = RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
            verify_commit_signatures: false,
            gpg_homedir: None,
            trusted_gpg_keys: vec![],
            trusted_ssh_keys: vec![],
        };

        let git = Arc::new(Git::new(&config)?);
        let cache = Arc::new(Cache::new(1000, std::time::Duration::from_secs(60)));
        let stats_service = Arc::new(RepositoryStatisticsService::new(git.clone(), cache.clone()));

        // Create repository service
        let service = RepositoryService::new(git, cache)
            .with_statistics_service(stats_service);

        // List repositories
        let repos = service.list_repositories().await?;
        assert_eq!(repos.len(), 1);
        assert_eq!(repos[0].name, "test-repo");

        // Get repository
        let repo = service.get_repository("test-repo").await?;
        assert_eq!(repo.name, "test-repo");
        assert_eq!(repo.path, repo_path.to_string_lossy().to_string());

        // Get repository stats
        let stats = service.get_repository_stats("test-repo").await?;
        assert_eq!(stats.name, "test-repo");
        assert!(stats.file_count > 0);
        assert!(stats.commit_count > 0);

        Ok(())
    }

    proptest! {
        #[test]
        fn test_sanitize_repository_name(name in "[a-zA-Z0-9\\-_.]{1,32}") {
            let service = RepositoryService::new(
                Arc::new(Git::new(&RepositoryConfig {
                    repo_dir: PathBuf::from("/tmp"),
                    max_cache_size: 1024,
                    enable_maintenance: false,
                    maintenance_interval: 0,
                    verify_commit_signatures: false,
                    gpg_homedir: None,
                    trusted_gpg_keys: vec![],
                    trusted_ssh_keys: vec![],
                }).unwrap()),
                Arc::new(Cache::new(1000, std::time::Duration::from_secs(60))),
            );

            // Valid repository name
            let result = service.sanitize_repository_name(&name);
            assert!(result.is_ok());
            assert_eq!(result.unwrap(), name);
        }

        #[test]
        fn test_sanitize_invalid_repository_name(
            // Generate repository names with invalid characters
            name in ".*[^a-zA-Z0-9\\-_.]+.*"
        ) {
            // Skip empty strings
            if name.is_empty() {
                return Ok(());
            }

            let service = RepositoryService::new(
                Arc::new(Git::new(&RepositoryConfig {
                    repo_dir: PathBuf::from("/tmp"),
                    max_cache_size: 1024,
                    enable_maintenance: false,
                    maintenance_interval: 0,
                    verify_commit_signatures: false,
                    gpg_homedir: None,
                    trusted_gpg_keys: vec![],
                    trusted_ssh_keys: vec![],
                }).unwrap()),
                Arc::new(Cache::new(1000, std::time::Duration::from_secs(60))),
            );

            // Invalid repository name
            let result = service.sanitize_repository_name(&name);
            assert!(result.is_err());
        }
    }
}
