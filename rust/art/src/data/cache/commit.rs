//! Commit cache implementation

use crate::config::CacheConfig;
use crate::data::git::Commit;
use crate::error::Result;
use super::Cache;

/// Commit cache key
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct CommitKey {
    /// Repository name
    pub repo_name: String,

    /// Commit ID
    pub commit_id: String,
}

/// Commit cache
pub struct CommitCache {
    /// Commit cache instance
    cache: Cache<CommitKey, Commit>,
}

impl CommitCache {
    /// Create a new commit cache
    pub fn new(config: &CacheConfig) -> Self {
        let cache = Cache::new(config);
        Self { cache }
    }

    /// Get a commit from the cache
    pub async fn get_commit(&self, repo_name: &str, commit_id: &str) -> Option<Commit> {
        let key = CommitKey {
            repo_name: repo_name.to_string(),
            commit_id: commit_id.to_string(),
        };

        self.cache.get(&key).await
    }

    /// Insert a commit into the cache
    pub async fn insert_commit(&self, repo_name: &str, commit: Commit) {
        let key = CommitKey {
            repo_name: repo_name.to_string(),
            commit_id: commit.id().to_string(),
        };

        self.cache.insert(key, commit).await;
    }

    /// Get or compute a commit
    pub async fn get_or_compute_commit<F>(&self, repo_name: &str, commit_id: &str, compute_fn: F) -> Result<Commit>
    where
        F: FnOnce() -> Result<Commit>,
    {
        let key = CommitKey {
            repo_name: repo_name.to_string(),
            commit_id: commit_id.to_string(),
        };

        self.cache.get_or_compute(key, compute_fn).await
    }

    /// Remove a commit from the cache
    pub async fn remove_commit(&self, repo_name: &str, commit_id: &str) {
        let key = CommitKey {
            repo_name: repo_name.to_string(),
            commit_id: commit_id.to_string(),
        };

        self.cache.remove(&key).await;
    }

    /// Clear the commit cache
    pub async fn clear(&self) {
        self.cache.clear().await;
    }

    /// Remove all commits for a repository
    pub async fn clear_repository(&self, repo_name: &str) {
        // Moka doesn't support partial invalidation by prefix,
        // so we'll have to clear the entire cache.
        // In a real implementation, we might want to track keys by repository
        // to allow more targeted invalidation.
        self.clear().await;
    }
}
