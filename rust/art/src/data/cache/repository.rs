//! Repository cache implementation

use crate::config::CacheConfig;
use crate::data::git::{Repository, RepositoryInfo};
use crate::error::Result;
use std::path::PathBuf;
use super::Cache;

/// Repository cache key
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RepositoryKey {
    /// Repository name
    pub name: String,
}

/// Repository cache
pub struct RepositoryCache {
    /// Repository cache instance
    cache: Cache<RepositoryKey, Repository>,

    /// Repository info cache instance
    info_cache: Cache<RepositoryKey, RepositoryInfo>,
}

impl RepositoryCache {
    /// Create a new repository cache
    pub fn new(config: &CacheConfig) -> Self {
        let cache = Cache::new(config);
        let info_cache = Cache::new(config);

        Self { cache, info_cache }
    }

    /// Get a repository from the cache
    pub async fn get_repository(&self, name: &str) -> Option<Repository> {
        let key = RepositoryKey { name: name.to_string() };
        self.cache.get(&key).await
    }

    /// Insert a repository into the cache
    pub async fn insert_repository(&self, name: &str, repository: Repository) {
        let key = RepositoryKey { name: name.to_string() };
        self.cache.insert(key, repository).await;
    }

    /// Get or compute a repository
    pub async fn get_or_compute_repository<F>(&self, name: &str, compute_fn: F) -> Result<Repository>
    where
        F: FnOnce() -> Result<Repository>,
    {
        let key = RepositoryKey { name: name.to_string() };
        self.cache.get_or_compute(key, compute_fn).await
    }

    /// Get repository info from the cache
    pub async fn get_repository_info(&self, name: &str) -> Option<RepositoryInfo> {
        let key = RepositoryKey { name: name.to_string() };
        self.info_cache.get(&key).await
    }

    /// Insert repository info into the cache
    pub async fn insert_repository_info(&self, name: &str, info: RepositoryInfo) {
        let key = RepositoryKey { name: name.to_string() };
        self.info_cache.insert(key, info).await;
    }

    /// Get or compute repository info
    pub async fn get_or_compute_repository_info<F>(&self, name: &str, compute_fn: F) -> Result<RepositoryInfo>
    where
        F: FnOnce() -> Result<RepositoryInfo>,
    {
        let key = RepositoryKey { name: name.to_string() };
        self.info_cache.get_or_compute(key, compute_fn).await
    }

    /// Remove a repository and its info from the cache
    pub async fn remove_repository(&self, name: &str) {
        let key = RepositoryKey { name: name.to_string() };
        self.cache.remove(&key).await;
        self.info_cache.remove(&key).await;
    }

    /// Clear the repository cache
    pub async fn clear(&self) {
        self.cache.clear().await;
        self.info_cache.clear().await;
    }
}
