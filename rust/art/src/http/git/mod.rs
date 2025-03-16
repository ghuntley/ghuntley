//! Git HTTP protocol implementation
//!
//! This module implements the Git Smart HTTP protocol as described in:
//! https://git-scm.com/docs/http-protocol
//!
//! It supports the following operations:
//! - Git clone
//! - Git fetch
//! - Git push
//!
//! The implementation follows the Git Smart HTTP protocol that uses content
//! negotiation to determine if the client supports the smart protocol.

mod routes;
mod service;
mod auth;
mod info_refs;
mod pack;
mod advertise_refs;
mod receive_pack;
mod upload_pack;
mod lfs;

use crate::error::{Error, Result};
use crate::data::git::Git;
use std::sync::Arc;
use std::path::PathBuf;

pub use routes::git_router;
pub use service::GitService;
pub use auth::{GitAuthService, GitAuthConfig};

/// Configuration for Git HTTP service
#[derive(Debug, Clone)]
pub struct GitHttpConfig {
    /// Whether to enable push (write) operations
    pub enable_push: bool,

    /// Whether to enable fetch/clone (read) operations
    pub enable_fetch: bool,

    /// Whether to enable Git LFS
    pub enable_lfs: bool,

    /// Maximum size of push operations in bytes (0 = no limit)
    pub max_push_size: usize,

    /// Whether to verify commit signatures
    pub verify_signatures: bool,

    /// Path prefix for all Git HTTP operations
    pub path_prefix: String,

    /// Whether to automatically run git gc after receiving packs
    pub auto_gc: bool,

    /// Timeout for Git operations in seconds
    pub operation_timeout: u64,
}

impl Default for GitHttpConfig {
    fn default() -> Self {
        Self {
            enable_push: true,
            enable_fetch: true,
            enable_lfs: false,
            max_push_size: 100 * 1024 * 1024, // 100MB
            verify_signatures: false,
            path_prefix: "/git".to_string(),
            auto_gc: true,
            operation_timeout: 60, // 1 minute
        }
    }
}

/// Git HTTP service implementation
#[derive(Debug, Clone)]
pub struct GitHttp {
    /// Git service
    git: Arc<Git>,

    /// Configuration
    config: GitHttpConfig,

    /// Authentication service
    auth_service: Option<Arc<dyn GitAuthService>>,
}

impl GitHttp {
    /// Create a new Git HTTP service
    pub fn new(git: Arc<Git>, config: GitHttpConfig) -> Self {
        Self {
            git,
            config,
            auth_service: None,
        }
    }

    /// Set the authentication service
    pub fn with_auth(mut self, auth_service: Arc<dyn GitAuthService>) -> Self {
        self.auth_service = Some(auth_service);
        self
    }

    /// Get the Git service
    pub fn git(&self) -> &Arc<Git> {
        &self.git
    }

    /// Get the configuration
    pub fn config(&self) -> &GitHttpConfig {
        &self.config
    }

    /// Get the authentication service if configured
    pub fn auth_service(&self) -> Option<&Arc<dyn GitAuthService>> {
        self.auth_service.as_ref()
    }

    /// Check if the given repository path is allowed
    pub fn is_repository_path_allowed(&self, path: &str) -> bool {
        // No path traversal allowed
        if path.contains("..") {
            return false;
        }

        // Only allow alphanumeric, dash, underscore, dot, and slash
        let path_regex = regex::Regex::new(r"^[a-zA-Z0-9\-_.\/]+$").unwrap();
        if !path_regex.is_match(path) {
            return false;
        }

        true
    }

    /// Get the full repository path for a given repository name
    pub fn get_repo_path(&self, repo_name: &str) -> Result<PathBuf> {
        if !self.is_repository_path_allowed(repo_name) {
            return Err(Error::InvalidRepositoryPath(repo_name.to_string()));
        }

        let repo_dir = self.git.repo_dir().join(repo_name);
        if !repo_dir.exists() {
            return Err(Error::RepositoryNotFound(repo_name.to_string()));
        }

        Ok(repo_dir)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use std::fs;

    fn create_test_repo() -> (TempDir, PathBuf) {
        // Create a temporary directory
        let temp_dir = TempDir::new().unwrap();
        let repo_path = temp_dir.path().join("test-repo");

        // Initialize a Git repository
        fs::create_dir_all(&repo_path).unwrap();
        let repo = git2::Repository::init(&repo_path).unwrap();

        // Create a file and commit it
        let file_path = repo_path.join("README.md");
        fs::write(&file_path, b"# Test Repository\n\nThis is a test repository.").unwrap();

        // Stage the file
        let mut index = repo.index().unwrap();
        index.add_path(std::path::Path::new("README.md")).unwrap();
        let tree_id = index.write_tree().unwrap();
        let tree = repo.find_tree(tree_id).unwrap();

        // Create a signature
        let signature = git2::Signature::now("Test User", "test@example.com").unwrap();

        // Create a commit
        repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            "Initial commit",
            &tree,
            &[],
        ).unwrap();

        (temp_dir, repo_path)
    }

    #[test]
    fn test_git_http_config_default() {
        let config = GitHttpConfig::default();

        assert!(config.enable_push);
        assert!(config.enable_fetch);
        assert!(!config.enable_lfs);
        assert_eq!(config.max_push_size, 100 * 1024 * 1024);
        assert!(!config.verify_signatures);
        assert_eq!(config.path_prefix, "/git");
        assert!(config.auto_gc);
        assert_eq!(config.operation_timeout, 60);
    }

    #[test]
    fn test_is_repository_path_allowed() {
        use crate::config::RepositoryConfig;

        let temp_dir = TempDir::new().unwrap();
        let config = RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_cache_size: 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        };

        let git = Git::new(&config).unwrap();
        let http_config = GitHttpConfig::default();
        let git_http = GitHttp::new(Arc::new(git), http_config);

        // Valid paths
        assert!(git_http.is_repository_path_allowed("valid-repo"));
        assert!(git_http.is_repository_path_allowed("valid/nested/repo"));
        assert!(git_http.is_repository_path_allowed("valid_repo.git"));

        // Invalid paths
        assert!(!git_http.is_repository_path_allowed("../invalid"));
        assert!(!git_http.is_repository_path_allowed("invalid with spaces"));
        assert!(!git_http.is_repository_path_allowed("/absolute/path"));
        assert!(!git_http.is_repository_path_allowed("invalid\ncharacter"));
    }

    #[test]
    fn test_get_repo_path() -> Result<()> {
        use crate::config::RepositoryConfig;

        let temp_dir = TempDir::new().unwrap();
        let repo_name = "test-repo";
        let repo_path = temp_dir.path().join(repo_name);

        // Create test repository
        fs::create_dir_all(&repo_path)?;

        let config = RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_cache_size: 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        };

        let git = Git::new(&config)?;
        let http_config = GitHttpConfig::default();
        let git_http = GitHttp::new(Arc::new(git), http_config);

        // Test valid repository path
        let path = git_http.get_repo_path(repo_name)?;
        assert_eq!(path, repo_path);

        // Test non-existent repository
        let result = git_http.get_repo_path("non-existent");
        assert!(result.is_err());

        // Test invalid repository path
        let result = git_http.get_repo_path("../invalid");
        assert!(result.is_err());

        Ok(())
    }
}
