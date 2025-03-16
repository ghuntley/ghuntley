//! File cache implementation

use crate::config::CacheConfig;
use crate::data::git::file::{FileContent, FileInfo};
use crate::error::Result;
use std::path::PathBuf;
use super::Cache;

/// File content cache key
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct FileContentKey {
    /// Repository name
    pub repo_name: String,

    /// File path
    pub path: String,

    /// Revision (commit ID or branch/tag name)
    pub revision: String,
}

/// File listing cache key
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct FileListingKey {
    /// Repository name
    pub repo_name: String,

    /// Directory path
    pub path: String,

    /// Revision (commit ID or branch/tag name)
    pub revision: String,
}

/// File cache
pub struct FileCache {
    /// File content cache instance
    content_cache: Cache<FileContentKey, FileContent>,

    /// File listing cache instance
    listing_cache: Cache<FileListingKey, Vec<FileInfo>>,
}

impl FileCache {
    /// Create a new file cache
    pub fn new(config: &CacheConfig) -> Self {
        let content_cache = Cache::new(config);
        let listing_cache = Cache::new(config);

        Self { content_cache, listing_cache }
    }

    /// Get file content from the cache
    pub async fn get_file_content(&self, repo_name: &str, path: &str, revision: &str) -> Option<FileContent> {
        let key = FileContentKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.content_cache.get(&key).await
    }

    /// Insert file content into the cache
    pub async fn insert_file_content(&self, repo_name: &str, path: &str, revision: &str, content: FileContent) {
        let key = FileContentKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.content_cache.insert(key, content).await;
    }

    /// Get or compute file content
    pub async fn get_or_compute_file_content<F>(
        &self,
        repo_name: &str,
        path: &str,
        revision: &str,
        compute_fn: F,
    ) -> Result<FileContent>
    where
        F: FnOnce() -> Result<FileContent>,
    {
        let key = FileContentKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.content_cache.get_or_compute(key, compute_fn).await
    }

    /// Get file listing from the cache
    pub async fn get_file_listing(&self, repo_name: &str, path: &str, revision: &str) -> Option<Vec<FileInfo>> {
        let key = FileListingKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.listing_cache.get(&key).await
    }

    /// Insert file listing into the cache
    pub async fn insert_file_listing(&self, repo_name: &str, path: &str, revision: &str, listing: Vec<FileInfo>) {
        let key = FileListingKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.listing_cache.insert(key, listing).await;
    }

    /// Get or compute file listing
    pub async fn get_or_compute_file_listing<F>(
        &self,
        repo_name: &str,
        path: &str,
        revision: &str,
        compute_fn: F,
    ) -> Result<Vec<FileInfo>>
    where
        F: FnOnce() -> Result<Vec<FileInfo>>,
    {
        let key = FileListingKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.listing_cache.get_or_compute(key, compute_fn).await
    }

    /// Remove file content from the cache
    pub async fn remove_file_content(&self, repo_name: &str, path: &str, revision: &str) {
        let key = FileContentKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.content_cache.remove(&key).await;
    }

    /// Remove file listing from the cache
    pub async fn remove_file_listing(&self, repo_name: &str, path: &str, revision: &str) {
        let key = FileListingKey {
            repo_name: repo_name.to_string(),
            path: path.to_string(),
            revision: revision.to_string(),
        };

        self.listing_cache.remove(&key).await;
    }

    /// Clear both caches
    pub async fn clear(&self) {
        self.content_cache.clear().await;
        self.listing_cache.clear().await;
    }

    /// Clear all cache entries for a repository
    pub async fn clear_repository(&self, _repo_name: &str) {
        // Moka doesn't support partial invalidation by prefix,
        // so we'll have to clear the entire cache.
        // In a real implementation, we might want to track keys by repository
        // to allow more targeted invalidation.
        self.clear().await;
    }

    /// Clear all cache entries for a revision
    pub async fn clear_revision(&self, _repo_name: &str, _revision: &str) {
        // Moka doesn't support partial invalidation by prefix,
        // so we'll have to clear the entire cache.
        // In a real implementation, we might want to track keys by repository/revision
        // to allow more targeted invalidation.
        self.clear().await;
    }
}
