//! File service for handling file operations in Git repositories.

use crate::data::{Git, GitObject, GitObjectType, GitStats};
use crate::error::{Error, Result};
use crate::service::repository::RepositoryService;
use crate::data::cache::{Cache, CacheKey};

use std::sync::Arc;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::path::Path;
use tracing::{debug, error, info, trace, warn};

/// File or directory information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    /// File or directory path
    pub path: String,

    /// Type: "file", "directory", "symlink"
    pub type_: String,

    /// Size in bytes (for files)
    pub size: Option<u64>,

    /// Last modified by
    pub last_modified_by: Option<String>,

    /// Last modified timestamp (ISO 8601)
    pub last_modified_at: Option<String>,

    /// Content (for files)
    pub content: Option<String>,

    /// Content as binary (base64 encoded)
    pub binary_content: Option<String>,

    /// Is binary file
    pub is_binary: bool,

    /// File extension
    pub extension: Option<String>,

    /// Children (for directories)
    pub children: Option<Vec<FileInfo>>,

    /// Commit ID
    pub commit_id: String,

    /// Reference (branch, tag)
    pub reference: String,
}

/// Stats for a file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileStats {
    /// Number of lines
    pub lines: usize,

    /// Number of bytes
    pub bytes: usize,

    /// Language detected
    pub language: Option<String>,

    /// Number of lines by author
    pub authors: HashMap<String, usize>,
}

/// File blame information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlameInfo {
    /// File path
    pub path: String,

    /// Commit ID
    pub commit_id: String,

    /// Reference (branch, tag)
    pub reference: String,

    /// Blame lines
    pub lines: Vec<BlameLine>,
}

/// Blame line information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlameLine {
    /// Line number (1-based)
    pub line_number: usize,

    /// Commit ID
    pub commit_id: String,

    /// Author name
    pub author: String,

    /// Commit timestamp (ISO 8601)
    pub timestamp: String,

    /// Line content
    pub content: String,
}

/// File service for handling file operations
pub struct FileService {
    /// Git data access
    git: Arc<Git>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// File cache
    cache: Arc<Cache>,
}

impl FileService {
    /// Create a new file service
    pub fn new(git: Arc<Git>, repository_service: Arc<RepositoryService>, cache: Arc<Cache>) -> Self {
        Self { git, repository_service, cache }
    }

    /// Get file or directory information
    pub async fn get_file(&self, repo_name: &str, git_ref: &str, path: &str) -> Result<FileInfo> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let git_ref = self.repository_service.sanitize_git_ref(git_ref)?;
        let path = self.sanitize_path(path)?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("file")
            .with_repo(&repo_name)
            .with_ref(&git_ref)
            .with_path(&path);

        // Try to get from cache
        if let Some(cached) = self.cache.get::<FileInfo>(&cache_key).await {
            debug!("Cache hit for file: {}/{}/{}", repo_name, git_ref, path);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Resolve reference to commit ID
        let commit_id = repo.resolve_reference(&git_ref)
            .map_err(|e| Error::GitReference(format!("Failed to resolve reference: {}", e)))?;

        // Get object at path
        let object = repo.get_object_at_path(&commit_id, &path)
            .map_err(|e| Error::GitObject(format!("Failed to get object: {}", e)))?;

        // Convert to FileInfo
        let info = self.object_to_file_info(repo_name, git_ref, &path, &commit_id, object)?;

        // Cache the result
        self.cache.set(&cache_key, &info).await;

        Ok(info)
    }

    /// Get file stats
    pub async fn get_file_stats(&self, repo_name: &str, git_ref: &str, path: &str) -> Result<FileStats> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let git_ref = self.repository_service.sanitize_git_ref(git_ref)?;
        let path = self.sanitize_path(path)?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("file_stats")
            .with_repo(&repo_name)
            .with_ref(&git_ref)
            .with_path(&path);

        // Try to get from cache
        if let Some(cached) = self.cache.get::<FileStats>(&cache_key).await {
            debug!("Cache hit for file stats: {}/{}/{}", repo_name, git_ref, path);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Resolve reference to commit ID
        let commit_id = repo.resolve_reference(&git_ref)
            .map_err(|e| Error::GitReference(format!("Failed to resolve reference: {}", e)))?;

        // Get stats for the file
        let stats = repo.get_stats(&commit_id, &path)
            .map_err(|e| Error::GitObject(format!("Failed to get stats: {}", e)))?;

        // Convert to FileStats
        let file_stats = self.convert_stats(stats);

        // Cache the result
        self.cache.set(&cache_key, &file_stats).await;

        Ok(file_stats)
    }

    /// Get file blame information
    pub async fn get_blame(&self, repo_name: &str, git_ref: &str, path: &str) -> Result<BlameInfo> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let git_ref = self.repository_service.sanitize_git_ref(git_ref)?;
        let path = self.sanitize_path(path)?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("blame")
            .with_repo(&repo_name)
            .with_ref(&git_ref)
            .with_path(&path);

        // Try to get from cache
        if let Some(cached) = self.cache.get::<BlameInfo>(&cache_key).await {
            debug!("Cache hit for blame: {}/{}/{}", repo_name, git_ref, path);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Resolve reference to commit ID
        let commit_id = repo.resolve_reference(&git_ref)
            .map_err(|e| Error::GitReference(format!("Failed to resolve reference: {}", e)))?;

        // Get blame for the file
        let blame_lines = repo.get_blame(&commit_id, &path)
            .map_err(|e| Error::GitObject(format!("Failed to get blame: {}", e)))?;

        // Convert to BlameInfo
        let blame_info = BlameInfo {
            path: path.to_string(),
            commit_id: commit_id.clone(),
            reference: git_ref.to_string(),
            lines: blame_lines.into_iter().map(|line| BlameLine {
                line_number: line.line_number,
                commit_id: line.commit_id,
                author: line.author,
                timestamp: line.timestamp,
                content: line.content,
            }).collect(),
        };

        // Cache the result
        self.cache.set(&cache_key, &blame_info).await;

        Ok(blame_info)
    }

    /// Convert Git object to FileInfo
    fn object_to_file_info(&self, repo_name: &str, git_ref: &str, path: &str, commit_id: &str, object: GitObject) -> Result<FileInfo> {
        let type_ = match object.object_type {
            GitObjectType::Blob => "file".to_string(),
            GitObjectType::Tree => "directory".to_string(),
            GitObjectType::Symlink => "symlink".to_string(),
        };

        let (content, binary_content, is_binary) = if object.object_type == GitObjectType::Blob {
            if object.is_binary {
                (None, Some(base64::encode(&object.content)), true)
            } else {
                let content = String::from_utf8_lossy(&object.content).to_string();
                (Some(content), None, false)
            }
        } else {
            (None, None, false)
        };

        let extension = if object.object_type == GitObjectType::Blob {
            Path::new(path).extension().and_then(|ext| ext.to_str()).map(|s| s.to_string())
        } else {
            None
        };

        let children = if object.object_type == GitObjectType::Tree {
            let repo = self.git.repository(repo_name)
                .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

            let children = repo.list_objects_at_path(commit_id, path)
                .map_err(|e| Error::GitObject(format!("Failed to list objects: {}", e)))?;

            let mut child_infos = Vec::new();
            for child in children {
                let child_path = if path.is_empty() || path == "." {
                    child.name.clone()
                } else {
                    format!("{}/{}", path, child.name)
                };

                let child_type = match child.object_type {
                    GitObjectType::Blob => "file".to_string(),
                    GitObjectType::Tree => "directory".to_string(),
                    GitObjectType::Symlink => "symlink".to_string(),
                };

                child_infos.push(FileInfo {
                    path: child_path,
                    type_: child_type,
                    size: if child.object_type == GitObjectType::Blob { Some(child.size) } else { None },
                    last_modified_by: Some(child.last_modified_by),
                    last_modified_at: Some(child.last_modified_at),
                    content: None,
                    binary_content: None,
                    is_binary: false,
                    extension: Path::new(&child.name).extension().and_then(|ext| ext.to_str()).map(|s| s.to_string()),
                    children: None,
                    commit_id: commit_id.to_string(),
                    reference: git_ref.to_string(),
                });
            }

            Some(child_infos)
        } else {
            None
        };

        Ok(FileInfo {
            path: path.to_string(),
            type_,
            size: if object.object_type == GitObjectType::Blob { Some(object.size) } else { None },
            last_modified_by: Some(object.last_modified_by),
            last_modified_at: Some(object.last_modified_at),
            content,
            binary_content,
            is_binary: object.is_binary,
            extension,
            children,
            commit_id: commit_id.to_string(),
            reference: git_ref.to_string(),
        })
    }

    /// Convert GitStats to FileStats
    fn convert_stats(&self, stats: GitStats) -> FileStats {
        FileStats {
            lines: stats.lines,
            bytes: stats.bytes,
            language: stats.language,
            authors: stats.authors,
        }
    }

    /// Sanitize file path
    pub fn sanitize_path(&self, path: &str) -> Result<String> {
        // Remove leading and trailing slashes
        let path = path.trim_start_matches('/').trim_end_matches('/');

        // Handle empty path as root
        if path.is_empty() || path == "." {
            return Ok(".".to_string());
        }

        // Check for path traversal attempts
        if path.contains("..") {
            return Err(Error::InvalidPath(format!("Path cannot contain '..': {}", path)));
        }

        // Normalize separators to forward slashes
        let path = path.replace('\\', "/");

        // Validate path components
        for component in path.split('/') {
            if component.starts_with('.') && component != "." {
                return Err(Error::InvalidPath(format!("Path component cannot start with '.': {}", component)));
            }

            // Check for invalid characters
            if component.contains(char::is_control) {
                return Err(Error::InvalidPath(format!("Path contains control characters: {}", path)));
            }
        }

        Ok(path.to_string())
    }

    /// Validate file path
    pub fn validate_path(&self, path: &str) -> Result<()> {
        // Sanitize path and check if it matches the original
        let sanitized = self.sanitize_path(path)?;
        if sanitized != path.trim_start_matches('/').trim_end_matches('/').replace('\\', "/") {
            return Err(Error::InvalidPath(format!("Invalid path: {}", path)));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::data::Sqlite;
    use tempfile::TempDir;

    /// Create a test file service
    async fn create_test_service() -> (FileService, TempDir) {
        // Create a temporary directory
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let temp_path = temp_dir.path().to_string_lossy().to_string();

        // Create Git manager
        let git = Arc::new(Git::new(&temp_path).expect("Failed to create Git manager"));

        // Create SQLite database
        let db_path = format!("{}/test.db", temp_path);
        let db = Arc::new(Sqlite::open(&db_path).expect("Failed to create database"));

        // Create a sample config
        let config = Arc::new(Config {
            port: 3000,
            host: "127.0.0.1".to_string(),
            repositories: vec![],
            cache_size_mb: 10,
            cache_ttl_secs: 60,
            theme: "light".to_string(),
        });

        // Create cache
        let cache = Arc::new(Cache::new(config.clone()).await);

        // Create repository service
        let repo_service = Arc::new(RepositoryService::new(git.clone(), db.clone(), config));

        // Create file service
        let file_service = FileService::new(git, repo_service, cache);

        (file_service, temp_dir)
    }

    #[tokio::test]
    async fn test_sanitize_path() {
        let (service, _temp_dir) = create_test_service().await;

        // Valid paths
        assert_eq!(service.sanitize_path("file.txt").unwrap(), "file.txt");
        assert_eq!(service.sanitize_path("dir/file.txt").unwrap(), "dir/file.txt");
        assert_eq!(service.sanitize_path("/dir/file.txt").unwrap(), "dir/file.txt");
        assert_eq!(service.sanitize_path("dir/file.txt/").unwrap(), "dir/file.txt");
        assert_eq!(service.sanitize_path("/").unwrap(), ".");
        assert_eq!(service.sanitize_path("").unwrap(), ".");
        assert_eq!(service.sanitize_path(".").unwrap(), ".");

        // Invalid paths
        assert!(service.sanitize_path("../file.txt").is_err());
        assert!(service.sanitize_path("dir/../file.txt").is_err());
        assert!(service.sanitize_path("dir/..").is_err());
        assert!(service.sanitize_path("dir/.git").is_err());
    }

    #[tokio::test]
    async fn test_validate_path() {
        let (service, _temp_dir) = create_test_service().await;

        // Valid paths
        assert!(service.validate_path("file.txt").is_ok());
        assert!(service.validate_path("dir/file.txt").is_ok());
        assert!(service.validate_path("/dir/file.txt").is_ok());

        // Invalid paths
        assert!(service.validate_path("../file.txt").is_err());
        assert!(service.validate_path("dir/../file.txt").is_err());
        assert!(service.validate_path("dir/..").is_err());
        assert!(service.validate_path("dir/.git").is_err());
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;

    // Strategy for valid path components (no .. or leading .)
    fn valid_path_component_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Regular filename with extension
            "[a-zA-Z0-9][a-zA-Z0-9_-]{0,20}\\.[a-zA-Z0-9]{1,5}",
            // Directory or file without extension
            "[a-zA-Z0-9][a-zA-Z0-9_-]{0,20}"
        ]
    }

    // Strategy for generating valid file paths
    fn valid_path_strategy() -> impl Strategy<Value = String> {
        // Generate 1-5 valid path components
        prop::collection::vec(valid_path_component_strategy(), 1..=5)
            .prop_map(|components| components.join("/"))
    }

    // Strategy for generating invalid file paths
    fn invalid_path_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Path with ..
            "[a-zA-Z0-9_-]{0,10}/\\.\\.(/[a-zA-Z0-9_-]{0,10})?",
            // Path with component starting with .
            "[a-zA-Z0-9_-]{0,10}/\\.[a-zA-Z0-9_-]{1,10}(/[a-zA-Z0-9_-]{0,10})?",
            // Path with invalid characters
            "[a-zA-Z0-9_-]{0,10}/[\\x00-\\x1F]([a-zA-Z0-9_-]{0,10})?",
        ]
    }

    // Strategy for generating optional leading/trailing slashes
    fn slashes_strategy() -> impl Strategy<Value = (String, String)> {
        (prop_oneof![Just(""), Just("/")], prop_oneof![Just(""), Just("/")])
    }

    proptest! {
        /// Test that valid paths are sanitized correctly
        #[test]
        fn valid_paths_are_sanitized_correctly(
            path in valid_path_strategy(),
            (leading_slash, trailing_slash) in slashes_strategy()
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Compose the path with optional slashes
            let input_path = format!("{}{}{}", leading_slash, path, trailing_slash);

            // Sanitize the path
            let sanitized = service.sanitize_path(&input_path).unwrap();

            // Check that sanitization produces a valid path
            assert!(!sanitized.contains(".."), "Sanitized path should not contain '..'");
            assert!(!sanitized.starts_with('/'), "Sanitized path should not start with '/'");
            assert!(!sanitized.ends_with('/'), "Sanitized path should not end with '/'");

            // Components should never start with . (except for . itself)
            for component in sanitized.split('/') {
                if component != "." {
                    assert!(!component.starts_with('.'), "Path component should not start with '.'");
                }
            }

            // Original valid path components should be preserved
            let expected = path.trim_start_matches('/').trim_end_matches('/');
            assert_eq!(sanitized, expected, "Sanitization should preserve valid path components");
        }

        /// Test that invalid paths are rejected
        #[test]
        fn invalid_paths_are_rejected(path in invalid_path_strategy()) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Try to sanitize the invalid path
            let result = service.sanitize_path(&path);

            // It should return an error
            assert!(result.is_err(), "Invalid path should be rejected: {}", path);

            // The error should be an InvalidPath error
            if let Err(e) = result {
                match e {
                    Error::InvalidPath(_) => {}, // This is the expected error
                    _ => panic!("Expected InvalidPath error, got: {:?}", e),
                }
            }
        }

        /// Test that path validation matches sanitization
        #[test]
        fn path_validation_matches_sanitization(
            path in prop_oneof![valid_path_strategy(), invalid_path_strategy()],
            (leading_slash, trailing_slash) in slashes_strategy()
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Compose the path with optional slashes
            let input_path = format!("{}{}{}", leading_slash, path, trailing_slash);

            // Check both sanitization and validation
            let sanitize_result = service.sanitize_path(&input_path);
            let validate_result = service.validate_path(&input_path);

            // Both should either succeed or fail together
            assert_eq!(sanitize_result.is_ok(), validate_result.is_ok(),
                       "Sanitization and validation should have consistent results for path: {}", input_path);
        }

        /// Test that sanitization is idempotent
        #[test]
        fn path_sanitization_is_idempotent(path in valid_path_strategy()) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // First sanitization
            let first_sanitized = service.sanitize_path(&path).unwrap();

            // Second sanitization of already sanitized path
            let second_sanitized = service.sanitize_path(&first_sanitized).unwrap();

            // Both should be the same
            assert_eq!(first_sanitized, second_sanitized,
                       "Sanitizing an already sanitized path should not change it: {}", path);
        }
    }
}
