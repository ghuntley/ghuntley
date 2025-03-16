//! Cache implementation for Art

use crate::config::CacheConfig;
use crate::error::{Error, Result};
use moka::future::Cache as MokaCache;
use std::hash::Hash;
use std::sync::Arc;
use std::time::Duration;

pub mod analytics;
use analytics::{CacheAnalytics, CacheAnalyticsConfig, measure_time};

/// Cache implementation using Moka
pub struct Cache<K, V>
where
    K: Clone + Eq + Hash + Send + Sync + 'static,
    V: Clone + Send + Sync + 'static,
{
    /// Moka cache instance
    cache: MokaCache<K, Arc<V>>,

    /// Time-to-live for cache entries in seconds
    ttl: Option<Duration>,

    /// Analytics tracker if enabled
    analytics: Option<Arc<CacheAnalytics>>,

    /// Cache name for metrics
    name: String,
}

impl<K, V> Cache<K, V>
where
    K: Clone + Eq + Hash + Send + Sync + 'static,
    V: Clone + Send + Sync + 'static,
{
    /// Create a new cache with the specified configuration
    pub fn new(config: &CacheConfig) -> Self {
        let ttl = if config.ttl > 0 {
            Some(Duration::from_secs(config.ttl))
        } else {
            None
        };

        let cache = MokaCache::builder()
            .max_capacity(config.max_size as u64)
            .time_to_live(ttl.unwrap_or(Duration::from_secs(3600)))
            .build();

        // Create analytics if enabled
        let analytics = if config.enable_analytics {
            let analytics_config = CacheAnalyticsConfig {
                enabled: true,
                sampling_interval_secs: config.analytics_sampling_interval_secs.unwrap_or(60),
                max_history_samples: config.analytics_max_history_samples.unwrap_or(60),
                track_per_key_metrics: config.analytics_track_per_key_metrics.unwrap_or(false),
            };

            let name = config.name.clone().unwrap_or_else(|| "default".to_string());
            Some(Arc::new(CacheAnalytics::new(
                name.clone(),
                config.max_size as u64,
                analytics_config,
            )))
        } else {
            None
        };

        let name = config.name.clone().unwrap_or_else(|| "default".to_string());

        Self { cache, ttl, analytics, name }
    }

    /// Get a value from the cache
    pub async fn get(&self, key: &K) -> Option<V> {
        if let Some(analytics) = &self.analytics {
            // Measure time for analytics
            let (result, time_us) = measure_time(|| self.cache.get(key));
            let result = result.await;

            // Track operation in analytics
            let hit = result.is_some();
            analytics.track_get(format!("{:?}", key), hit, time_us);

            result.map(|v| (*v).clone())
        } else {
            self.cache.get(key).await.map(|v| (*v).clone())
        }
    }

    /// Insert a value into the cache
    pub async fn insert(&self, key: K, value: V) {
        if let Some(analytics) = &self.analytics {
            // Track insert operation
            // Estimate size for memory tracking (approximate)
            let size_estimate = std::mem::size_of::<K>() + std::mem::size_of::<V>();
            analytics.track_insert(format!("{:?}", key), Some(size_estimate));
        }

        self.cache.insert(key, Arc::new(value)).await;
    }

    /// Remove a value from the cache
    pub async fn remove(&self, key: &K) {
        if let Some(analytics) = &self.analytics {
            // Track remove operation
            analytics.track_remove(format!("{:?}", key));
        }

        self.cache.remove(key).await;
    }

    /// Clear all values from the cache
    pub async fn clear(&self) {
        if let Some(analytics) = &self.analytics {
            // Track clear operation
            analytics.track_clear();
        }

        self.cache.invalidate_all().await;
    }

    /// Invalidate all cache entries with keys starting with the given prefix
    pub async fn invalidate_by_prefix(&self, prefix: &str) {
        // For a real implementation, you would need to maintain a secondary index
        // of keys by prefix. This is a simplified version that clears the entire cache
        // when we don't have an efficient way to query by prefix.
        if let Some(analytics) = &self.analytics {
            analytics.track_clear();
        }

        // In a production implementation, you would only invalidate matching entries
        // For now, we just clear everything to ensure correctness
        self.cache.invalidate_all().await;
    }

    /// Get or compute a value
    pub async fn get_or_compute<F, E>(&self, key: K, compute_fn: F) -> Result<V>
    where
        F: FnOnce() -> std::result::Result<V, E>,
        E: Into<Error>,
    {
        if let Some(analytics) = &self.analytics {
            // Try to get from cache first
            let key_str = format!("{:?}", key);
            let (result, get_time_us) = measure_time(|| self.get(&key));
            let result = result.await;

            if let Some(value) = result {
                // Cache hit
                analytics.track_get(key_str, true, get_time_us);
                return Ok(value);
            }

            // Cache miss, compute value
            analytics.track_get(key_str, false, get_time_us);

            let (compute_result, compute_time_us) = measure_time(|| compute_fn());
            let value = compute_result.map_err(|e| e.into())?;

            // Insert into cache and track
            let size_estimate = std::mem::size_of::<K>() + std::mem::size_of::<V>();
            analytics.track_insert(key_str, Some(size_estimate));
            self.insert(key, value.clone()).await;

            Ok(value)
        } else {
            // Original implementation without analytics
            if let Some(value) = self.get(&key).await {
                return Ok(value);
            }

            let value = compute_fn().map_err(|e| e.into())?;
            self.insert(key, value.clone()).await;

            Ok(value)
        }
    }

    /// Get or compute a value asynchronously
    pub async fn get_or_compute_async<F, Fut, E>(&self, key: K, compute_fn: F) -> Result<V>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = std::result::Result<V, E>>,
        E: Into<Error>,
    {
        if let Some(analytics) = &self.analytics {
            // Try to get from cache first
            let key_str = format!("{:?}", key);
            let (result, get_time_us) = measure_time(|| self.get(&key));
            let result = result.await;

            if let Some(value) = result {
                // Cache hit
                analytics.track_get(key_str, true, get_time_us);
                return Ok(value);
            }

            // Cache miss, compute value
            analytics.track_get(key_str, false, get_time_us);

            let start = std::time::Instant::now();
            let compute_result = compute_fn().await;
            let compute_time_us = start.elapsed().as_micros() as u64;

            let value = compute_result.map_err(|e| e.into())?;

            // Insert into cache and track
            let size_estimate = std::mem::size_of::<K>() + std::mem::size_of::<V>();
            analytics.track_insert(key_str, Some(size_estimate));
            self.insert(key, value.clone()).await;

            Ok(value)
        } else {
            // Original implementation without analytics
            if let Some(value) = self.get(&key).await {
                return Ok(value);
            }

            let value = compute_fn().await.map_err(|e| e.into())?;
            self.insert(key, value.clone()).await;

            Ok(value)
        }
    }

    /// Get the name of this cache
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Get a snapshot of the analytics
    pub fn get_analytics_snapshot(&self) -> Option<analytics::CacheAnalyticsSnapshot> {
        self.analytics.as_ref().map(|a| a.get_snapshot())
    }

    /// Get Prometheus metrics from the analytics
    pub fn get_prometheus_metrics(&self) -> Option<String> {
        self.analytics.as_ref().map(|a| a.to_prometheus_metrics())
    }

    /// Take a sample of the current cache metrics
    pub fn take_analytics_sample(&self) {
        if let Some(analytics) = &self.analytics {
            analytics.take_sample();
        }
    }

    /// Get the current hit ratio
    pub fn hit_ratio(&self) -> Option<f64> {
        self.analytics.as_ref().map(|a| a.hit_ratio())
    }

    /// Get the average access time in microseconds
    pub fn avg_access_time_us(&self) -> Option<f64> {
        self.analytics.as_ref().map(|a| a.avg_access_time_us())
    }

    /// Remove a key from the cache.
    /// Alias for `remove` for compatibility with other code.
    pub async fn delete(&self, key: &K) {
        self.remove(key).await
    }
}

/// Specialized repository cache
pub mod repository;

/// Specialized commit cache
pub mod commit;

/// Specialized file cache
pub mod file;

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio::time::sleep;

    // Helper to create a test cache configuration
    fn create_test_config(max_size: usize, ttl: u64, enable_analytics: bool) -> CacheConfig {
        CacheConfig {
            max_size,
            ttl,
            name: Some("test_cache".to_string()),
            enable_analytics,
            analytics_sampling_interval_secs: Some(1),
            analytics_max_history_samples: Some(10),
            analytics_track_per_key_metrics: Some(true),
        }
    }

    #[tokio::test]
    async fn test_cache_get_and_insert() {
        // Create a new cache
        let config = create_test_config(10, 60, false);
        let cache = Cache::<String, String>::new(&config);

        // Insert a value
        cache.insert("key1".to_string(), "value1".to_string()).await;

        // Get the value
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "value1");

        // Get a non-existent value
        let result = cache.get(&"non-existent".to_string()).await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_remove() {
        // Create a new cache
        let config = create_test_config(10, 60, false);
        let cache = Cache::<String, String>::new(&config);

        // Insert some values
        cache.insert("key1".to_string(), "value1".to_string()).await;
        cache.insert("key2".to_string(), "value2".to_string()).await;

        // Remove a specific key
        cache.remove(&"key1".to_string()).await;

        // Check that the key was removed
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_none());

        // Check that other keys are still valid
        let result = cache.get(&"key2".to_string()).await;
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "value2");

        // Clear all keys
        cache.clear().await;

        // Check that all keys were removed
        let result = cache.get(&"key2".to_string()).await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_expiration() {
        // Create a new cache with a short TTL
        let config = create_test_config(10, 1, false); // 1 second TTL
        let cache = Cache::<String, String>::new(&config);

        // Insert a value
        cache.insert("key1".to_string(), "value1".to_string()).await;

        // Get the value immediately
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "value1");

        // Wait for the TTL to expire
        sleep(Duration::from_secs(2)).await;

        // Get the value after expiration
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_max_entries() {
        // Create a new cache with a small capacity
        let config = create_test_config(3, 60, false);
        let cache = Cache::<String, String>::new(&config);

        // Insert more values than the capacity
        for i in 0..5 {
            let key = format!("key{}", i);
            let value = format!("value{}", i);
            cache.insert(key, value).await;
        }

        // Check that older entries were evicted
        // Note: This test assumes LRU behavior, which might not be guaranteed by moka
        let result = cache.get(&"key0".to_string()).await;
        assert!(result.is_none(), "Expected older key to be evicted");

        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_none(), "Expected older key to be evicted");

        // Check that newer entries are still there
        let result = cache.get(&"key2".to_string()).await;
        assert!(result.is_some(), "Expected newer key to be present");

        let result = cache.get(&"key3".to_string()).await;
        assert!(result.is_some(), "Expected newer key to be present");

        let result = cache.get(&"key4".to_string()).await;
        assert!(result.is_some(), "Expected newer key to be present");
    }

    #[tokio::test]
    async fn test_cache_update() {
        // Create a new cache
        let config = create_test_config(10, 60, false);
        let cache = Cache::<String, String>::new(&config);

        // Insert a value
        cache.insert("key1".to_string(), "value1".to_string()).await;

        // Update the value
        cache.insert("key1".to_string(), "updated".to_string()).await;

        // Get the updated value
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "updated");
    }

    #[tokio::test]
    async fn test_cache_disabled() {
        // Create a disabled cache
        let config = create_test_config(0, 0, false);
        let cache = Cache::<String, String>::new(&config);

        // Insert a value
        cache.insert("key1".to_string(), "value1".to_string()).await;

        // Get the value (should be None since cache is disabled)
        let result = cache.get(&"key1".to_string()).await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_analytics() {
        // Create a cache with analytics enabled
        let config = create_test_config(10, 60, true);
        let cache = Cache::<String, String>::new(&config);

        // Perform some operations
        cache.insert("key1".to_string(), "value1".to_string()).await;
        cache.insert("key2".to_string(), "value2".to_string()).await;

        let _ = cache.get(&"key1".to_string()).await;
        let _ = cache.get(&"key2".to_string()).await;
        let _ = cache.get(&"key3".to_string()).await; // Miss

        cache.remove(&"key1".to_string()).await;

        // Get analytics snapshot
        let snapshot = cache.get_analytics_snapshot().expect("Analytics should be enabled");

        // Verify basic metrics
        assert_eq!(snapshot.total_gets, 3);
        assert_eq!(snapshot.total_hits, 2);
        assert_eq!(snapshot.total_misses, 1);
        assert_eq!(snapshot.total_inserts, 2);
        assert_eq!(snapshot.total_removes, 1);

        // Check hit ratio
        assert_eq!(snapshot.hit_ratio, 2.0 / 3.0);

        // Check prometheus metrics
        let metrics = cache.get_prometheus_metrics().expect("Prometheus metrics should be available");
        assert!(metrics.contains("art_cache_hit_ratio"));
        assert!(metrics.contains("art_cache_size"));
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use std::sync::{Arc, Mutex};
    use std::collections::HashMap;

    // Create a test cache manager for property-based tests
    fn create_test_cache_manager() -> Arc<CacheManager> {
        Arc::new(CacheManager::new(1024, 300))
    }

    proptest! {
        /// Test that cached values can be stored and retrieved
        #[test]
        fn cache_storage_and_retrieval(
            // Generate a random string to use as a key
            key in "[a-zA-Z0-9_-]{1,50}",
            // Generate a random string to use as a value
            value in "[a-zA-Z0-9_-]{1,1000}",
        ) {
            // Create a cache manager
            let cache_manager = create_test_cache_manager();

            // Cache the value
            cache_manager.set(&key, value.clone());

            // Retrieve the value
            let retrieved = cache_manager.get(&key);

            // The retrieved value should match the original
            assert_eq!(retrieved, Some(value.clone()), "Retrieved value should match stored value");

            // Non-existent keys should return None
            let non_existent_key = format!("{}_nonexistent", key);
            assert_eq!(cache_manager.get(&non_existent_key), None, "Non-existent key should return None");
        }

        /// Test that the cache respects size limits
        #[test]
        fn cache_respects_size_limits(
            // Generate a list of keys and large values
            keys in prop::collection::vec("[a-zA-Z0-9_-]{1,20}", 1..20),
            value_size in 100usize..1000usize,
        ) {
            // Skip empty key lists
            if keys.is_empty() {
                return Ok(());
            }

            // Create a small cache
            let small_size = 5 * 1024; // 5 KB
            let cache_manager = Arc::new(CacheManager::new(small_size, 3600));

            // Generate a large value that will take up a significant portion of the cache
            let large_value = "X".repeat(value_size);

            // Cache multiple items to exceed the cache size
            let mut total_size = 0;
            for (i, key) in keys.iter().enumerate() {
                let key_with_index = format!("{}_{}", key, i);
                cache_manager.set(&key_with_index, large_value.clone());
                total_size += key_with_index.len() + large_value.len();

                // If we've exceeded the cache size, older items should be evicted
                if total_size > small_size {
                    // Check if early items have been evicted
                    let first_key = format!("{}_{}", keys[0], 0);
                    if cache_manager.get(&first_key).is_none() {
                        // At least one item has been evicted, test passes
                        return Ok(());
                    }
                }
            }

            // If we didn't exceed the cache size, just verify no items were evicted
            for (i, key) in keys.iter().enumerate() {
                let key_with_index = format!("{}_{}", key, i);
                assert_eq!(cache_manager.get(&key_with_index), Some(large_value.clone()));
            }

            Ok(())
        }

        /// Test that the cache handles ttl expiration
        #[test]
        fn cache_handles_ttl_expiration(
            // Generate a random key
            key in "[a-zA-Z0-9_-]{1,50}",
            // Generate a random value
            value in "[a-zA-Z0-9_-]{1,100}",
            // Generate a very short TTL (1-5 seconds)
            ttl in 1u64..5u64,
        ) {
            // Create a cache with the specified TTL
            let cache_manager = Arc::new(CacheManager::new(1024 * 1024, ttl as u64));

            // Store the value in the cache
            cache_manager.set(&key, value.clone());

            // Immediately, the value should be retrievable
            assert_eq!(cache_manager.get(&key), Some(value.clone()), "Value should be retrievable immediately");

            // Sleep for slightly longer than the TTL
            std::thread::sleep(std::time::Duration::from_secs(ttl + 1));

            // Run clean (normally this would happen on access, but we'll force it)
            cache_manager.clean();

            // After TTL expires, the value should be gone
            assert_eq!(cache_manager.get(&key), None, "Value should be expired after TTL");
        }

        /// Test that the cache clear method works
        #[test]
        fn cache_clear_removes_all_items(
            // Generate a list of keys and values
            entries in prop::collection::hash_map("[a-zA-Z0-9_-]{1,20}", "[a-zA-Z0-9_-]{1,100}", 1..20),
        ) {
            // Skip empty maps
            if entries.is_empty() {
                return Ok(());
            }

            // Create a cache manager
            let cache_manager = create_test_cache_manager();

            // Cache all the entries
            for (key, value) in &entries {
                cache_manager.set(key, value.clone());
            }

            // Verify all entries are in the cache
            for (key, value) in &entries {
                assert_eq!(cache_manager.get(key), Some(value.clone()), "Entry should be in cache");
            }

            // Clear the cache
            cache_manager.clear();

            // Verify all entries are gone
            for (key, _) in &entries {
                assert_eq!(cache_manager.get(key), None, "Entry should be removed after clear");
            }

            Ok(())
        }

        /// Test that multiple threads can access the cache safely
        #[test]
        fn cache_thread_safety(
            // Generate a list of keys and values
            entries in prop::collection::hash_map("[a-zA-Z0-9_-]{1,20}", "[a-zA-Z0-9_-]{1,100}", 1..10),
        ) {
            // Skip empty maps
            if entries.is_empty() {
                return Ok(());
            }

            // Create a cache manager
            let cache_manager = create_test_cache_manager();

            // Clone the entries to a thread-safe structure
            let entries_arc = Arc::new(entries.clone());

            // Create a mutex to track successful operations
            let success_counter = Arc::new(Mutex::new(0));

            // Create multiple threads that read and write from the cache
            let mut handles = Vec::new();
            let num_threads = 4;

            for _ in 0..num_threads {
                let cache_clone = Arc::clone(&cache_manager);
                let entries_clone = Arc::clone(&entries_arc);
                let counter_clone = Arc::clone(&success_counter);

                let handle = std::thread::spawn(move || {
                    // Each thread writes all entries to the cache
                    for (key, value) in entries_clone.iter() {
                        cache_clone.set(key, value.clone());
                    }

                    // Then reads them back
                    let mut thread_success = 0;
                    for (key, expected_value) in entries_clone.iter() {
                        if let Some(value) = cache_clone.get(key) {
                            if value == *expected_value {
                                thread_success += 1;
                            }
                        }
                    }

                    // Update the success counter
                    let mut counter = counter_clone.lock().unwrap();
                    *counter += thread_success;
                });

                handles.push(handle);
            }

            // Wait for all threads to complete
            for handle in handles {
                handle.join().unwrap();
            }

            // Check that all operations were successful
            let total_successes = *success_counter.lock().unwrap();
            let expected_successes = num_threads * entries.len();

            assert_eq!(total_successes, expected_successes,
                "All thread operations should be successful");

            // Verify all entries are still in the cache
            for (key, value) in &entries {
                assert_eq!(cache_manager.get(key), Some(value.clone()),
                    "Entry should still be in cache after concurrent access");
            }

            Ok(())
        }
    }
}
