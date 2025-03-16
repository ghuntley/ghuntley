//! Commit service for handling Git commit operations.

use crate::data::{Git, GitCommit, GitDiff, DiffType};
use crate::error::{Error, Result};
use crate::service::repository::RepositoryService;
use crate::data::cache::{Cache, CacheKey};

use std::sync::Arc;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use tracing::{debug, error, info, trace, warn};

/// Commit information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitInfo {
    /// Commit ID (SHA)
    pub id: String,

    /// Short commit ID (first 7 characters)
    pub short_id: String,

    /// Author name
    pub author: String,

    /// Author email
    pub author_email: String,

    /// Committer name
    pub committer: String,

    /// Committer email
    pub committer_email: String,

    /// Commit message
    pub message: String,

    /// Commit message summary (first line)
    pub summary: String,

    /// Commit timestamp (ISO 8601)
    pub timestamp: String,

    /// Parent commit IDs
    pub parents: Vec<String>,

    /// Files changed
    pub files_changed: usize,

    /// Lines added
    pub lines_added: usize,

    /// Lines removed
    pub lines_removed: usize,

    /// Signature verification status
    pub signature_status: Option<String>,

    /// Signature verification details
    pub signature_verification: Option<SignatureDetails>,
}

/// Signature verification details
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignatureDetails {
    /// Signer name
    pub signer_name: Option<String>,

    /// Signer email
    pub signer_email: Option<String>,

    /// Key ID
    pub key_id: String,

    /// Trust level
    pub trust_level: Option<String>,

    /// Verification message
    pub message: Option<String>,
}

/// Commit list response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitListResponse {
    /// Repository name
    pub repository: String,

    /// Current reference (branch, tag)
    pub reference: String,

    /// Total commits
    pub total: usize,

    /// Commits
    pub commits: Vec<CommitInfo>,

    /// Next page cursor
    pub next_cursor: Option<String>,
}

/// Diff information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffInfo {
    /// From commit ID
    pub from_commit: String,

    /// To commit ID
    pub to_commit: String,

    /// Repository name
    pub repository: String,

    /// Files changed
    pub files_changed: Vec<FileDiff>,

    /// Total insertions
    pub total_insertions: usize,

    /// Total deletions
    pub total_deletions: usize,
}

/// File diff information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDiff {
    /// File path
    pub path: String,

    /// Diff type: "added", "deleted", "modified", "renamed"
    pub diff_type: String,

    /// File status: "A", "D", "M", "R"
    pub status: String,

    /// Old file path (for renames)
    pub old_path: Option<String>,

    /// Insertions
    pub insertions: usize,

    /// Deletions
    pub deletions: usize,

    /// Hunks
    pub hunks: Vec<HunkInfo>,

    /// Binary file
    pub is_binary: bool,
}

/// Hunk information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HunkInfo {
    /// Old start line
    pub old_start: usize,

    /// Old line count
    pub old_lines: usize,

    /// New start line
    pub new_start: usize,

    /// New line count
    pub new_lines: usize,

    /// Hunk header
    pub header: String,

    /// Lines
    pub lines: Vec<LineInfo>,
}

/// Line information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LineInfo {
    /// Line type: "context", "addition", "deletion"
    pub line_type: String,

    /// Line content
    pub content: String,

    /// Line number in old file
    pub old_line_number: Option<usize>,

    /// Line number in new file
    pub new_line_number: Option<usize>,
}

/// Commit service
pub struct CommitService {
    /// Git data access
    git: Arc<Git>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// Cache
    cache: Arc<Cache>,
}

impl CommitService {
    /// Create a new commit service
    pub fn new(git: Arc<Git>, repository_service: Arc<RepositoryService>, cache: Arc<Cache>) -> Self {
        Self { git, repository_service, cache }
    }

    /// Get commit information
    pub async fn get_commit(&self, repo_name: &str, commit_id: &str) -> Result<CommitInfo> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let commit_id = self.sanitize_commit_id(commit_id)?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("commit")
            .with_repo(&repo_name)
            .with_ref(&commit_id);

        // Try to get from cache
        if let Some(cached) = self.cache.get::<CommitInfo>(&cache_key).await {
            debug!("Cache hit for commit: {}/{}", repo_name, commit_id);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Get commit
        let commit = repo.get_commit(&commit_id)
            .map_err(|e| Error::GitCommit(format!("Failed to get commit: {}", e)))?;

        // Convert to CommitInfo
        let info = self.convert_commit(commit);

        // Cache the result
        self.cache.set(&cache_key, &info).await;

        Ok(info)
    }

    /// List commits
    pub async fn list_commits(&self, repo_name: &str, git_ref: &str, limit: usize, cursor: Option<&str>) -> Result<CommitListResponse> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let git_ref = self.repository_service.sanitize_git_ref(git_ref)?;
        let limit = limit.min(100).max(1); // Limit between 1 and 100
        let cursor = cursor.map(|c| self.sanitize_commit_id(c)).transpose()?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("commit_list")
            .with_repo(&repo_name)
            .with_ref(&git_ref)
            .with_limit(limit)
            .with_cursor(cursor.as_deref().unwrap_or(""));

        // Try to get from cache
        if let Some(cached) = self.cache.get::<CommitListResponse>(&cache_key).await {
            debug!("Cache hit for commit list: {}/{}", repo_name, git_ref);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Resolve reference to commit ID if not a commit ID
        let start_commit = match cursor {
            Some(c) => c,
            None => repo.resolve_reference(&git_ref)
                .map_err(|e| Error::GitReference(format!("Failed to resolve reference: {}", e)))?,
        };

        // List commits
        let (commits, next_cursor) = repo.list_commits(&start_commit, limit + 1)
            .map_err(|e| Error::GitCommit(format!("Failed to list commits: {}", e)))?;

        // Check if we have more commits
        let (commits, next_cursor) = if commits.len() > limit {
            // We have more commits, use the last one as cursor
            let next = commits[limit].id.clone();
            (commits[0..limit].to_vec(), Some(next))
        } else {
            // No more commits
            (commits, None)
        };

        // Convert to CommitInfo
        let commit_infos = commits.into_iter().map(|c| self.convert_commit(c)).collect();

        // Create response
        let response = CommitListResponse {
            repository: repo_name.clone(),
            reference: git_ref.clone(),
            total: limit, // This is not the total number of commits, just the number returned
            commits: commit_infos,
            next_cursor,
        };

        // Cache the result
        self.cache.set(&cache_key, &response).await;

        Ok(response)
    }

    /// Get diff between two commits
    pub async fn get_diff(&self, repo_name: &str, from_commit: &str, to_commit: &str) -> Result<DiffInfo> {
        // Validate and sanitize inputs
        let repo_name = self.repository_service.sanitize_repository_name(repo_name)?;
        let from_commit = self.sanitize_commit_id(from_commit)?;
        let to_commit = self.sanitize_commit_id(to_commit)?;

        // Create cache key
        let cache_key = CacheKey::new()
            .with_type("diff")
            .with_repo(&repo_name)
            .with_from(&from_commit)
            .with_to(&to_commit);

        // Try to get from cache
        if let Some(cached) = self.cache.get::<DiffInfo>(&cache_key).await {
            debug!("Cache hit for diff: {}/{}-{}", repo_name, from_commit, to_commit);
            return Ok(cached);
        }

        // Get repository
        let repo = self.git.repository(&repo_name)
            .map_err(|e| Error::Repository(format!("Failed to open repository: {}", e)))?;

        // Get diff
        let diff = repo.get_diff(&from_commit, &to_commit)
            .map_err(|e| Error::GitDiff(format!("Failed to get diff: {}", e)))?;

        // Convert to DiffInfo
        let diff_info = self.convert_diff(repo_name, &from_commit, &to_commit, diff);

        // Cache the result
        self.cache.set(&cache_key, &diff_info).await;

        Ok(diff_info)
    }

    /// Convert GitCommit to CommitInfo
    fn convert_commit(&self, commit: GitCommit) -> CommitInfo {
        CommitInfo {
            id: commit.id,
            short_id: commit.short_id,
            author: commit.author,
            author_email: commit.author_email,
            committer: commit.committer,
            committer_email: commit.committer_email,
            message: commit.message,
            summary: commit.summary,
            timestamp: commit.timestamp,
            parents: commit.parents,
            files_changed: commit.files_changed,
            lines_added: commit.lines_added,
            lines_removed: commit.lines_removed,
            signature_status: None,
            signature_verification: None,
        }
    }

    /// Convert GitDiff to DiffInfo
    fn convert_diff(&self, repo_name: &str, from_commit: &str, to_commit: &str, diff: GitDiff) -> DiffInfo {
        let mut files_changed = Vec::new();
        let mut total_insertions = 0;
        let mut total_deletions = 0;

        for file in diff.files {
            // Convert diff type
            let (diff_type, status) = match file.diff_type {
                DiffType::Added => ("added".to_string(), "A".to_string()),
                DiffType::Deleted => ("deleted".to_string(), "D".to_string()),
                DiffType::Modified => ("modified".to_string(), "M".to_string()),
                DiffType::Renamed => ("renamed".to_string(), "R".to_string()),
            };

            // Convert hunks
            let hunks = file.hunks.into_iter().map(|hunk| {
                // Convert lines
                let lines = hunk.lines.into_iter().map(|line| {
                    let (line_type, old_line_number, new_line_number) = match line.prefix {
                        ' ' => ("context".to_string(), Some(line.old_line_number), Some(line.new_line_number)),
                        '+' => ("addition".to_string(), None, Some(line.new_line_number)),
                        '-' => ("deletion".to_string(), Some(line.old_line_number), None),
                        _ => ("context".to_string(), None, None),
                    };

                    LineInfo {
                        line_type,
                        content: line.content,
                        old_line_number,
                        new_line_number,
                    }
                }).collect();

                HunkInfo {
                    old_start: hunk.old_start,
                    old_lines: hunk.old_lines,
                    new_start: hunk.new_start,
                    new_lines: hunk.new_lines,
                    header: hunk.header,
                    lines,
                }
            }).collect();

            // Add file diff
            files_changed.push(FileDiff {
                path: file.path,
                diff_type,
                status,
                old_path: file.old_path,
                insertions: file.insertions,
                deletions: file.deletions,
                hunks,
                is_binary: file.is_binary,
            });

            // Update totals
            total_insertions += file.insertions;
            total_deletions += file.deletions;
        }

        DiffInfo {
            from_commit: from_commit.to_string(),
            to_commit: to_commit.to_string(),
            repository: repo_name.to_string(),
            files_changed,
            total_insertions,
            total_deletions,
        }
    }

    /// Sanitize commit ID
    fn sanitize_commit_id(&self, commit_id: &str) -> Result<String> {
        // Check for valid characters
        if !commit_id.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(Error::InvalidCommitId(format!("Commit ID contains invalid characters: {}", commit_id)));
        }

        // Check length
        let len = commit_id.len();
        if len < 4 || len > 40 {
            return Err(Error::InvalidCommitId(format!("Commit ID has invalid length: {}", len)));
        }

        Ok(commit_id.to_string())
    }

    /// Validate commit ID
    fn validate_commit_id(&self, commit_id: &str) -> Result<()> {
        // Use sanitize and check if unchanged
        let sanitized = self.sanitize_commit_id(commit_id)?;
        if sanitized != commit_id {
            return Err(Error::InvalidCommitId(format!("Invalid commit ID: {}", commit_id)));
        }

        Ok(())
    }

    /// Get a commit with signature verification
    pub async fn get_commit_with_signature_verification(&self, repo_name: &str, commit_id: &str) -> Result<CommitInfo> {
        // Get the commit info first
        let commit_info = self.get_commit(repo_name, commit_id)?;

        // Verify the signature
        let signature_verification = self.git.verify_commit_signature(repo_name, commit_id).await?;

        // Create the signature details
        let signature_status = Some(signature_verification.status.to_string());
        let signature_details = signature_verification.signer.map(|signer| SignatureDetails {
            signer_name: signer.name,
            signer_email: signer.email,
            key_id: signer.key_id,
            trust_level: signer.trust_level,
            message: signature_verification.message,
        });

        // Create a new commit info with signature verification
        let mut commit_info_with_signature = commit_info;
        commit_info_with_signature.signature_status = signature_status;
        commit_info_with_signature.signature_verification = signature_details;

        Ok(commit_info_with_signature)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::data::Sqlite;
    use tempfile::TempDir;

    /// Create a test commit service
    async fn create_test_service() -> (CommitService, TempDir) {
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

        // Create commit service
        let commit_service = CommitService::new(git, repo_service, cache);

        (commit_service, temp_dir)
    }

    #[tokio::test]
    async fn test_sanitize_commit_id() {
        let (service, _temp_dir) = create_test_service().await;

        // Valid commit IDs
        assert_eq!(service.sanitize_commit_id("1234567890abcdef").unwrap(), "1234567890abcdef");
        assert_eq!(service.sanitize_commit_id("abcd").unwrap(), "abcd");
        assert_eq!(service.sanitize_commit_id("1234567890abcdef1234567890abcdef12345678").unwrap(), "1234567890abcdef1234567890abcdef12345678");

        // Invalid commit IDs
        assert!(service.sanitize_commit_id("123").is_err()); // Too short
        assert!(service.sanitize_commit_id("1234567890abcdef1234567890abcdef123456789").is_err()); // Too long
        assert!(service.sanitize_commit_id("1234567890abcdefg").is_err()); // Invalid character
        assert!(service.sanitize_commit_id("1234-5678").is_err()); // Invalid character
    }

    #[tokio::test]
    async fn test_validate_commit_id() {
        let (service, _temp_dir) = create_test_service().await;

        // Valid commit IDs
        assert!(service.validate_commit_id("1234567890abcdef").is_ok());
        assert!(service.validate_commit_id("abcd").is_ok());
        assert!(service.validate_commit_id("1234567890abcdef1234567890abcdef12345678").is_ok());

        // Invalid commit IDs
        assert!(service.validate_commit_id("123").is_err()); // Too short
        assert!(service.validate_commit_id("1234567890abcdef1234567890abcdef123456789").is_err()); // Too long
        assert!(service.validate_commit_id("1234567890abcdefg").is_err()); // Invalid character
        assert!(service.validate_commit_id("1234-5678").is_err()); // Invalid character
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;

    // Strategy for valid commit IDs
    fn valid_commit_id_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Full SHA-1 (40 characters)
            "[0-9a-f]{40}",
            // Short SHA (4-39 characters)
            "[0-9a-f]{4,39}"
        ]
    }

    // Strategy for invalid commit IDs
    fn invalid_commit_id_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Too short
            "[0-9a-f]{1,3}",
            // Too long
            "[0-9a-f]{41,45}",
            // Invalid characters
            "[0-9a-f]{1,10}[g-zG-Z-_!@#$%]{1,5}[0-9a-f]{1,10}",
        ]
    }

    proptest! {
        /// Test that valid commit IDs are sanitized correctly
        #[test]
        fn valid_commit_ids_are_sanitized_correctly(commit_id in valid_commit_id_strategy()) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Sanitize the commit ID
            let sanitized = service.sanitize_commit_id(&commit_id).unwrap();

            // It should remain unchanged
            assert_eq!(sanitized, commit_id, "Valid commit ID should remain unchanged after sanitization");

            // Validation should pass
            assert!(service.validate_commit_id(&commit_id).is_ok(), "Valid commit ID should pass validation");
        }

        /// Test that invalid commit IDs are rejected
        #[test]
        fn invalid_commit_ids_are_rejected(commit_id in invalid_commit_id_strategy()) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Try to sanitize an invalid commit ID
            let result = service.sanitize_commit_id(&commit_id);

            // It should return an error
            assert!(result.is_err(), "Invalid commit ID should be rejected: {}", commit_id);

            // The error should be an InvalidCommitId error
            if let Err(e) = result {
                match e {
                    Error::InvalidCommitId(_) => {}, // This is the expected error
                    _ => panic!("Expected InvalidCommitId error, got: {:?}", e),
                }
            }

            // Validation should also fail
            assert!(service.validate_commit_id(&commit_id).is_err(), "Invalid commit ID should fail validation");
        }

        /// Test that validation matches sanitization
        #[test]
        fn validation_matches_sanitization(commit_id in prop_oneof![valid_commit_id_strategy(), invalid_commit_id_strategy()]) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Check both sanitization and validation
            let sanitize_result = service.sanitize_commit_id(&commit_id);
            let validate_result = service.validate_commit_id(&commit_id);

            // Both should either succeed or fail together
            assert_eq!(sanitize_result.is_ok(), validate_result.is_ok(),
                       "Sanitization and validation should have consistent results for commit ID: {}", commit_id);
        }

        /// Test that sanitization is idempotent
        #[test]
        fn sanitization_is_idempotent(commit_id in valid_commit_id_strategy()) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // First sanitization
            let first_sanitized = service.sanitize_commit_id(&commit_id).unwrap();

            // Second sanitization of already sanitized ID
            let second_sanitized = service.sanitize_commit_id(&first_sanitized).unwrap();

            // Both should be the same
            assert_eq!(first_sanitized, second_sanitized,
                       "Sanitizing an already sanitized commit ID should not change it: {}", commit_id);
        }

        /// Test commit conversion maintains all fields
        #[test]
        fn commit_conversion_maintains_all_fields(
            id in "[0-9a-f]{40}",
            short_id in "[0-9a-f]{7}",
            author in "[a-zA-Z ]{3,20}",
            author_email in "[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}",
            committer in "[a-zA-Z ]{3,20}",
            committer_email in "[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}",
            message in "[a-zA-Z0-9 ,.]{10,100}",
            timestamp in "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
            files_changed in 0usize..100,
            lines_added in 0usize..1000,
            lines_removed in 0usize..1000
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();
            let (service, _temp_dir) = rt.block_on(create_test_service());

            // Create a parent commit ID
            let parent = "0123456789abcdef0123456789abcdef01234567".to_string();

            // Create a summary (first line of message)
            let summary = message.split_once('\n').map(|(s, _)| s.to_string()).unwrap_or_else(|| message.clone());

            // Create a GitCommit
            let commit = GitCommit {
                id: id.clone(),
                short_id: short_id.clone(),
                author: author.clone(),
                author_email: author_email.clone(),
                committer: committer.clone(),
                committer_email: committer_email.clone(),
                message: message.clone(),
                summary: summary.clone(),
                timestamp: timestamp.clone(),
                parents: vec![parent.clone()],
                files_changed,
                lines_added,
                lines_removed,
            };

            // Convert it
            let commit_info = service.convert_commit(commit);

            // Check all fields are preserved
            assert_eq!(commit_info.id, id, "ID should be preserved");
            assert_eq!(commit_info.short_id, short_id, "Short ID should be preserved");
            assert_eq!(commit_info.author, author, "Author should be preserved");
            assert_eq!(commit_info.author_email, author_email, "Author email should be preserved");
            assert_eq!(commit_info.committer, committer, "Committer should be preserved");
            assert_eq!(commit_info.committer_email, committer_email, "Committer email should be preserved");
            assert_eq!(commit_info.message, message, "Message should be preserved");
            assert_eq!(commit_info.summary, summary, "Summary should be preserved");
            assert_eq!(commit_info.timestamp, timestamp, "Timestamp should be preserved");
            assert_eq!(commit_info.parents, vec![parent], "Parents should be preserved");
            assert_eq!(commit_info.files_changed, files_changed, "Files changed should be preserved");
            assert_eq!(commit_info.lines_added, lines_added, "Lines added should be preserved");
            assert_eq!(commit_info.lines_removed, lines_removed, "Lines removed should be preserved");
        }
    }
}
