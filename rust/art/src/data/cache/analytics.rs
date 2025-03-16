//! Cache analytics module for monitoring cache performance and usage
//!
//! This module provides functionality for tracking detailed metrics about
//! cache usage, including hit/miss ratios, eviction rates, and performance
//! indicators. It extends the basic cache hit/miss monitoring with more
//! detailed analytics to help optimize cache configurations.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::{Duration, Instant, SystemTime};
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use crate::error::Result;

/// Cache analytics configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheAnalyticsConfig {
    /// Whether detailed analytics are enabled
    pub enabled: bool,

    /// How frequently to sample cache statistics (in seconds)
    pub sampling_interval_secs: u64,

    /// Maximum number of historical samples to keep
    pub max_history_samples: usize,

    /// Whether to track per-key metrics (more detailed but higher overhead)
    pub track_per_key_metrics: bool,
}

impl Default for CacheAnalyticsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            sampling_interval_secs: 60, // Sample every minute by default
            max_history_samples: 60,    // Keep an hour's worth of samples
            track_per_key_metrics: false,
        }
    }
}

/// Statistics for a specific cache key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyMetrics {
    /// Number of times this key was requested
    pub access_count: u64,

    /// Number of times this key was found in cache
    pub hit_count: u64,

    /// Number of times this key was evicted
    pub eviction_count: u64,

    /// Average time to retrieve this key (in microseconds)
    pub avg_access_time_us: f64,

    /// Time this key was first inserted
    pub first_inserted_at: DateTime<Utc>,

    /// Time this key was last accessed
    pub last_accessed_at: DateTime<Utc>,

    /// Size of the value in bytes (if available)
    pub value_size_bytes: Option<usize>,
}

/// Sample of cache statistics at a point in time
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStatsSample {
    /// Time when the sample was taken
    pub timestamp: DateTime<Utc>,

    /// Current size of the cache (number of items)
    pub size: usize,

    /// Current estimated memory usage in bytes
    pub memory_usage_bytes: usize,

    /// Total number of hits since last sample
    pub hits: u64,

    /// Total number of misses since last sample
    pub misses: u64,

    /// Total number of evictions since last sample
    pub evictions: u64,

    /// Average access time in microseconds
    pub avg_access_time_us: f64,

    /// Maximum access time in microseconds
    pub max_access_time_us: u64,
}

/// Cache analytics snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheAnalyticsSnapshot {
    /// Cache name/identifier
    pub cache_name: String,

    /// Time when the snapshot was taken
    pub timestamp: DateTime<Utc>,

    /// Total number of items in the cache
    pub total_items: usize,

    /// Configured maximum capacity
    pub max_capacity: u64,

    /// Current memory usage estimate in bytes
    pub memory_usage_bytes: usize,

    /// Total number of get operations
    pub total_gets: u64,

    /// Total number of insert operations
    pub total_inserts: u64,

    /// Total number of remove operations
    pub total_removes: u64,

    /// Total number of clear operations
    pub total_clears: u64,

    /// Total number of hits
    pub total_hits: u64,

    /// Total number of misses
    pub total_misses: u64,

    /// Total number of evictions
    pub total_evictions: u64,

    /// Hit ratio (0.0 to 1.0)
    pub hit_ratio: f64,

    /// Average access time in microseconds
    pub avg_access_time_us: f64,

    /// Maximum access time in microseconds
    pub max_access_time_us: u64,

    /// Top N most accessed keys (if per-key metrics are enabled)
    pub top_accessed_keys: Option<Vec<(String, KeyMetrics)>>,

    /// Average time to live in seconds
    pub avg_ttl_secs: Option<f64>,

    /// Historical samples (most recent first)
    pub history: Vec<CacheStatsSample>,
}

/// Cache analytics tracking
#[derive(Debug)]
pub struct CacheAnalytics {
    /// Cache name/identifier
    cache_name: String,

    /// Configuration
    config: CacheAnalyticsConfig,

    /// Time when analytics collection started
    start_time: Instant,

    /// Last sample time
    last_sample_time: Instant,

    /// Total number of get operations
    total_gets: AtomicU64,

    /// Total number of insert operations
    total_inserts: AtomicU64,

    /// Total number of remove operations
    total_removes: AtomicU64,

    /// Total number of clear operations
    total_clears: AtomicU64,

    /// Total number of hits
    total_hits: AtomicU64,

    /// Total number of misses
    total_misses: AtomicU64,

    /// Total number of evictions
    total_evictions: AtomicU64,

    /// Sum of all access times in microseconds
    total_access_time_us: AtomicU64,

    /// Maximum access time in microseconds
    max_access_time_us: AtomicU64,

    /// Current size of the cache
    current_size: AtomicUsize,

    /// Current memory usage estimate
    current_memory_bytes: AtomicUsize,

    /// Maximum capacity
    max_capacity: u64,

    /// Per-key metrics (if enabled)
    key_metrics: Option<Arc<parking_lot::RwLock<HashMap<String, KeyMetrics>>>>,

    /// Historical samples
    history: Arc<parking_lot::RwLock<Vec<CacheStatsSample>>>,
}

impl CacheAnalytics {
    /// Create a new cache analytics tracker
    pub fn new(cache_name: String, max_capacity: u64, config: CacheAnalyticsConfig) -> Self {
        let key_metrics = if config.track_per_key_metrics {
            Some(Arc::new(parking_lot::RwLock::new(HashMap::new())))
        } else {
            None
        };

        Self {
            cache_name,
            config,
            start_time: Instant::now(),
            last_sample_time: Instant::now(),
            total_gets: AtomicU64::new(0),
            total_inserts: AtomicU64::new(0),
            total_removes: AtomicU64::new(0),
            total_clears: AtomicU64::new(0),
            total_hits: AtomicU64::new(0),
            total_misses: AtomicU64::new(0),
            total_evictions: AtomicU64::new(0),
            total_access_time_us: AtomicU64::new(0),
            max_access_time_us: AtomicU64::new(0),
            current_size: AtomicUsize::new(0),
            current_memory_bytes: AtomicUsize::new(0),
            max_capacity,
            key_metrics,
            history: Arc::new(parking_lot::RwLock::new(Vec::new())),
        }
    }

    /// Track a cache get operation
    pub fn track_get<K: AsRef<str>>(&self, key: K, hit: bool, access_time_us: u64) {
        self.total_gets.fetch_add(1, Ordering::Relaxed);

        if hit {
            self.total_hits.fetch_add(1, Ordering::Relaxed);
        } else {
            self.total_misses.fetch_add(1, Ordering::Relaxed);
        }

        // Update access time metrics
        self.total_access_time_us.fetch_add(access_time_us, Ordering::Relaxed);
        self.update_max_access_time(access_time_us);

        // Maybe take a sample if enough time has passed
        self.maybe_take_sample();

        // Update per-key metrics if enabled
        if let Some(key_metrics) = &self.key_metrics {
            let key_str = key.as_ref().to_string();
            let mut metrics = key_metrics.write();
            let entry = metrics.entry(key_str.clone()).or_insert_with(|| KeyMetrics {
                access_count: 0,
                hit_count: 0,
                eviction_count: 0,
                avg_access_time_us: 0.0,
                first_inserted_at: Utc::now(),
                last_accessed_at: Utc::now(),
                value_size_bytes: None,
            });

            entry.access_count += 1;
            if hit {
                entry.hit_count += 1;
            }
            entry.last_accessed_at = Utc::now();

            // Update avg access time as a running average
            entry.avg_access_time_us = (entry.avg_access_time_us * (entry.access_count - 1) as f64
                + access_time_us as f64) / entry.access_count as f64;
        }
    }

    /// Track a cache insert operation
    pub fn track_insert<K: AsRef<str>>(&self, key: K, value_size_bytes: Option<usize>) {
        self.total_inserts.fetch_add(1, Ordering::Relaxed);
        self.current_size.fetch_add(1, Ordering::Relaxed);

        if let Some(size) = value_size_bytes {
            self.current_memory_bytes.fetch_add(size, Ordering::Relaxed);
        }

        // Update per-key metrics if enabled
        if let Some(key_metrics) = &self.key_metrics {
            let key_str = key.as_ref().to_string();
            let mut metrics = key_metrics.write();
            let now = Utc::now();

            // If key already exists, it's an update
            let entry = metrics.entry(key_str.clone()).or_insert_with(|| KeyMetrics {
                access_count: 0,
                hit_count: 0,
                eviction_count: 0,
                avg_access_time_us: 0.0,
                first_inserted_at: now,
                last_accessed_at: now,
                value_size_bytes: None,
            });

            entry.value_size_bytes = value_size_bytes;
            entry.last_accessed_at = now;
        }

        // Maybe take a sample if enough time has passed
        self.maybe_take_sample();
    }

    /// Track a cache remove operation
    pub fn track_remove<K: AsRef<str>>(&self, key: K) {
        self.total_removes.fetch_add(1, Ordering::Relaxed);

        // Only decrement size if we have items
        let current = self.current_size.load(Ordering::Relaxed);
        if current > 0 {
            self.current_size.fetch_sub(1, Ordering::Relaxed);
        }

        // Update memory usage if we have per-key metrics
        if let Some(key_metrics) = &self.key_metrics {
            let key_str = key.as_ref().to_string();
            let mut metrics = key_metrics.write();

            if let Some(entry) = metrics.get(&key_str) {
                if let Some(size) = entry.value_size_bytes {
                    let current_mem = self.current_memory_bytes.load(Ordering::Relaxed);
                    if current_mem >= size {
                        self.current_memory_bytes.fetch_sub(size, Ordering::Relaxed);
                    }
                }
            }

            // Remove the key from tracking
            metrics.remove(&key_str);
        }

        // Maybe take a sample if enough time has passed
        self.maybe_take_sample();
    }

    /// Track a cache clear operation
    pub fn track_clear(&self) {
        self.total_clears.fetch_add(1, Ordering::Relaxed);
        self.current_size.store(0, Ordering::Relaxed);
        self.current_memory_bytes.store(0, Ordering::Relaxed);

        // Clear per-key metrics if enabled
        if let Some(key_metrics) = &self.key_metrics {
            let mut metrics = key_metrics.write();
            metrics.clear();
        }

        // Maybe take a sample if enough time has passed
        self.maybe_take_sample();
    }

    /// Track a cache eviction
    pub fn track_eviction<K: AsRef<str>>(&self, key: K) {
        self.total_evictions.fetch_add(1, Ordering::Relaxed);

        // Update per-key metrics if enabled
        if let Some(key_metrics) = &self.key_metrics {
            let key_str = key.as_ref().to_string();
            let mut metrics = key_metrics.write();

            if let Some(entry) = metrics.get_mut(&key_str) {
                entry.eviction_count += 1;
            }
        }
    }

    /// Update the current size of the cache
    pub fn update_size(&self, size: usize) {
        self.current_size.store(size, Ordering::Relaxed);
    }

    /// Update the memory usage estimate
    pub fn update_memory_usage(&self, bytes: usize) {
        self.current_memory_bytes.store(bytes, Ordering::Relaxed);
    }

    /// Update the maximum access time if the current time is larger
    fn update_max_access_time(&self, access_time_us: u64) {
        let current_max = self.max_access_time_us.load(Ordering::Relaxed);
        if access_time_us > current_max {
            self.max_access_time_us.store(access_time_us, Ordering::Relaxed);
        }
    }

    /// Take a sample of the current cache metrics if enough time has passed
    fn maybe_take_sample(&self) {
        if !self.config.enabled {
            return;
        }

        let now = Instant::now();
        let elapsed = now.duration_since(self.last_sample_time);
        let interval = Duration::from_secs(self.config.sampling_interval_secs);

        if elapsed >= interval {
            self.take_sample();
        }
    }

    /// Force taking a sample of current cache metrics
    pub fn take_sample(&self) {
        if !self.config.enabled {
            return;
        }

        let mut history = self.history.write();

        // Create the sample
        let sample = CacheStatsSample {
            timestamp: Utc::now(),
            size: self.current_size.load(Ordering::Relaxed),
            memory_usage_bytes: self.current_memory_bytes.load(Ordering::Relaxed),
            hits: self.total_hits.load(Ordering::Relaxed),
            misses: self.total_misses.load(Ordering::Relaxed),
            evictions: self.total_evictions.load(Ordering::Relaxed),
            avg_access_time_us: self.avg_access_time_us(),
            max_access_time_us: self.max_access_time_us.load(Ordering::Relaxed),
        };

        // Add to history
        history.push(sample);

        // Trim history if needed
        if history.len() > self.config.max_history_samples {
            let to_remove = history.len() - self.config.max_history_samples;
            history.drain(0..to_remove);
        }
    }

    /// Get the current hit ratio
    pub fn hit_ratio(&self) -> f64 {
        let hits = self.total_hits.load(Ordering::Relaxed) as f64;
        let total = hits + self.total_misses.load(Ordering::Relaxed) as f64;

        if total > 0.0 {
            hits / total
        } else {
            0.0
        }
    }

    /// Get the average access time in microseconds
    pub fn avg_access_time_us(&self) -> f64 {
        let total_time = self.total_access_time_us.load(Ordering::Relaxed) as f64;
        let total_gets = self.total_gets.load(Ordering::Relaxed) as f64;

        if total_gets > 0.0 {
            total_time / total_gets
        } else {
            0.0
        }
    }

    /// Get a snapshot of the current analytics
    pub fn get_snapshot(&self) -> CacheAnalyticsSnapshot {
        // Take a sample to ensure the snapshot is current
        self.take_sample();

        // Collect top accessed keys if per-key metrics are enabled
        let top_accessed_keys = if let Some(key_metrics) = &self.key_metrics {
            let metrics = key_metrics.read();

            if !metrics.is_empty() {
                // Convert to vector and sort by access count
                let mut keys_vec: Vec<(String, KeyMetrics)> = metrics
                    .iter()
                    .map(|(k, v)| (k.clone(), v.clone()))
                    .collect();

                keys_vec.sort_by(|a, b| b.1.access_count.cmp(&a.1.access_count));

                // Take top 10 keys
                let top_n = keys_vec.into_iter().take(10).collect();
                Some(top_n)
            } else {
                None
            }
        } else {
            None
        };

        // Get history
        let history = self.history.read().clone();

        CacheAnalyticsSnapshot {
            cache_name: self.cache_name.clone(),
            timestamp: Utc::now(),
            total_items: self.current_size.load(Ordering::Relaxed),
            max_capacity: self.max_capacity,
            memory_usage_bytes: self.current_memory_bytes.load(Ordering::Relaxed),
            total_gets: self.total_gets.load(Ordering::Relaxed),
            total_inserts: self.total_inserts.load(Ordering::Relaxed),
            total_removes: self.total_removes.load(Ordering::Relaxed),
            total_clears: self.total_clears.load(Ordering::Relaxed),
            total_hits: self.total_hits.load(Ordering::Relaxed),
            total_misses: self.total_misses.load(Ordering::Relaxed),
            total_evictions: self.total_evictions.load(Ordering::Relaxed),
            hit_ratio: self.hit_ratio(),
            avg_access_time_us: self.avg_access_time_us(),
            max_access_time_us: self.max_access_time_us.load(Ordering::Relaxed),
            top_accessed_keys,
            avg_ttl_secs: None, // Not tracked currently
            history,
        }
    }

    /// Generate Prometheus metrics from the analytics
    pub fn to_prometheus_metrics(&self) -> String {
        let snapshot = self.get_snapshot();
        let mut output = String::new();

        // Basic metrics
        output.push_str(&format!("# HELP art_cache_size Current number of items in the cache\n"));
        output.push_str(&format!("# TYPE art_cache_size gauge\n"));
        output.push_str(&format!("art_cache_size{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_items));

        output.push_str(&format!("# HELP art_cache_memory_bytes Estimated memory usage of the cache\n"));
        output.push_str(&format!("# TYPE art_cache_memory_bytes gauge\n"));
        output.push_str(&format!("art_cache_memory_bytes{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.memory_usage_bytes));

        output.push_str(&format!("# HELP art_cache_capacity Maximum capacity of the cache\n"));
        output.push_str(&format!("# TYPE art_cache_capacity gauge\n"));
        output.push_str(&format!("art_cache_capacity{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.max_capacity));

        output.push_str(&format!("# HELP art_cache_utilization Cache utilization as a percentage of capacity\n"));
        output.push_str(&format!("# TYPE art_cache_utilization gauge\n"));
        let utilization = if snapshot.max_capacity > 0 {
            (snapshot.total_items as f64 / snapshot.max_capacity as f64) * 100.0
        } else {
            0.0
        };
        output.push_str(&format!("art_cache_utilization{{cache=\"{}\"}} {:.2}\n",
            snapshot.cache_name, utilization));

        // Operation counts
        output.push_str(&format!("# HELP art_cache_gets_total Total number of get operations\n"));
        output.push_str(&format!("# TYPE art_cache_gets_total counter\n"));
        output.push_str(&format!("art_cache_gets_total{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_gets));

        output.push_str(&format!("# HELP art_cache_inserts_total Total number of insert operations\n"));
        output.push_str(&format!("# TYPE art_cache_inserts_total counter\n"));
        output.push_str(&format!("art_cache_inserts_total{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_inserts));

        output.push_str(&format!("# HELP art_cache_removes_total Total number of remove operations\n"));
        output.push_str(&format!("# TYPE art_cache_removes_total counter\n"));
        output.push_str(&format!("art_cache_removes_total{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_removes));

        output.push_str(&format!("# HELP art_cache_clears_total Total number of clear operations\n"));
        output.push_str(&format!("# TYPE art_cache_clears_total counter\n"));
        output.push_str(&format!("art_cache_clears_total{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_clears));

        output.push_str(&format!("# HELP art_cache_evictions_total Total number of evictions\n"));
        output.push_str(&format!("# TYPE art_cache_evictions_total counter\n"));
        output.push_str(&format!("art_cache_evictions_total{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.total_evictions));

        // Efficiency metrics
        output.push_str(&format!("# HELP art_cache_hit_ratio Cache hit ratio\n"));
        output.push_str(&format!("# TYPE art_cache_hit_ratio gauge\n"));
        output.push_str(&format!("art_cache_hit_ratio{{cache=\"{}\"}} {:.4}\n",
            snapshot.cache_name, snapshot.hit_ratio));

        // Performance metrics
        output.push_str(&format!("# HELP art_cache_avg_access_time_us Average cache access time in microseconds\n"));
        output.push_str(&format!("# TYPE art_cache_avg_access_time_us gauge\n"));
        output.push_str(&format!("art_cache_avg_access_time_us{{cache=\"{}\"}} {:.2}\n",
            snapshot.cache_name, snapshot.avg_access_time_us));

        output.push_str(&format!("# HELP art_cache_max_access_time_us Maximum cache access time in microseconds\n"));
        output.push_str(&format!("# TYPE art_cache_max_access_time_us gauge\n"));
        output.push_str(&format!("art_cache_max_access_time_us{{cache=\"{}\"}} {}\n",
            snapshot.cache_name, snapshot.max_access_time_us));

        output
    }
}

/// Helper to time operations in microseconds
pub fn measure_time<F, R>(f: F) -> (R, u64)
where
    F: FnOnce() -> R,
{
    let start = Instant::now();
    let result = f();
    let elapsed = start.elapsed();
    let micros = elapsed.as_micros() as u64;

    (result, micros)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    // Helper to create a test analytics instance
    fn create_test_analytics() -> CacheAnalytics {
        let config = CacheAnalyticsConfig {
            enabled: true,
            sampling_interval_secs: 1,
            max_history_samples: 10,
            track_per_key_metrics: true,
        };

        CacheAnalytics::new("test_cache".to_string(), 100, config)
    }

    #[test]
    fn test_basic_analytics() {
        let analytics = create_test_analytics();

        // Track some operations
        analytics.track_get("key1", true, 100);
        analytics.track_get("key2", false, 200);
        analytics.track_insert("key3", Some(1000));
        analytics.track_remove("key2");

        // Get snapshot
        let snapshot = analytics.get_snapshot();

        // Verify counts
        assert_eq!(snapshot.total_gets, 2);
        assert_eq!(snapshot.total_hits, 1);
        assert_eq!(snapshot.total_misses, 1);
        assert_eq!(snapshot.total_inserts, 1);
        assert_eq!(snapshot.total_removes, 1);

        // Verify hit ratio
        assert_eq!(snapshot.hit_ratio, 0.5);

        // Verify avg access time
        assert_eq!(snapshot.avg_access_time_us, 150.0);
    }

    proptest! {
        #[test]
        fn prop_test_analytics_tracking_operations(
            operations in prop::collection::vec(0..4u8, 1..100),
            keys in prop::collection::vec("[a-zA-Z0-9_-]{1,20}", 1..20),
        ) {
            if keys.is_empty() {
                return Ok(());
            }

            let analytics = create_test_analytics();
            let mut expected_gets = 0;
            let mut expected_hits = 0;
            let mut expected_inserts = 0;
            let mut expected_removes = 0;
            let mut expected_clears = 0;

            for op in operations {
                let key = &keys[op as usize % keys.len()];

                match op % 4 {
                    0 => {
                        // Get with hit
                        analytics.track_get(key, true, 100);
                        expected_gets += 1;
                        expected_hits += 1;
                    },
                    1 => {
                        // Get with miss
                        analytics.track_get(key, false, 100);
                        expected_gets += 1;
                    },
                    2 => {
                        // Insert
                        analytics.track_insert(key, Some(100));
                        expected_inserts += 1;
                    },
                    3 => {
                        // Remove
                        analytics.track_remove(key);
                        expected_removes += 1;
                    },
                    _ => {
                        // Clear
                        analytics.track_clear();
                        expected_clears += 1;
                    }
                }
            }

            // Force a sample
            analytics.take_sample();

            // Get snapshot
            let snapshot = analytics.get_snapshot();

            // Verify counts
            prop_assert_eq!(snapshot.total_gets, expected_gets);
            prop_assert_eq!(snapshot.total_hits, expected_hits);
            prop_assert_eq!(snapshot.total_inserts, expected_inserts);
            prop_assert_eq!(snapshot.total_removes, expected_removes);
            prop_assert_eq!(snapshot.total_clears, expected_clears);

            // Check that at least one sample was captured
            prop_assert!(!snapshot.history.is_empty());

            Ok(())
        }

        #[test]
        fn prop_test_analytics_respects_size_limits(
            num_samples in 5..20usize,
            max_history in 3..10usize,
        ) {
            let config = CacheAnalyticsConfig {
                enabled: true,
                sampling_interval_secs: 1,
                max_history_samples: max_history,
                track_per_key_metrics: true,
            };

            let analytics = CacheAnalytics::new("test_cache".to_string(), 100, config);

            // Take more samples than the max history
            for _ in 0..num_samples {
                analytics.take_sample();
            }

            // Get snapshot
            let snapshot = analytics.get_snapshot();

            // Verify we don't exceed max_history_samples
            prop_assert!(snapshot.history.len() <= max_history);

            Ok(())
        }
    }
}
