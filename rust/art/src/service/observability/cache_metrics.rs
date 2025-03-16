//! Cache metrics collector for observability
//!
//! This module provides functionality for collecting and reporting cache metrics
//! from the analytics system.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tokio::time;
use crate::data::cache::analytics::CacheAnalyticsSnapshot;
use crate::error::{Error, Result};
use tracing::{debug, error, info, trace, warn};
use prometheus::{IntGaugeVec, GaugeVec, Registry};

/// Caches to monitor for metrics
#[derive(Debug)]
pub struct CacheMetricsCollector {
    /// Caches to collect metrics from
    caches: RwLock<HashMap<String, Arc<dyn CacheMetricsProvider + Send + Sync>>>,

    /// Registry for Prometheus metrics
    registry: Registry,

    /// Size gauge (current number of items)
    size_gauge: IntGaugeVec,

    /// Memory usage gauge
    memory_gauge: IntGaugeVec,

    /// Utilization gauge (percentage of capacity)
    utilization_gauge: GaugeVec,

    /// Hit ratio gauge
    hit_ratio_gauge: GaugeVec,

    /// Average access time gauge
    avg_access_time_gauge: GaugeVec,

    /// Collection interval in seconds
    collection_interval_secs: u64,

    /// Whether collection is running
    is_running: std::sync::atomic::AtomicBool,
}

/// Interface for cache metrics providers
#[async_trait::async_trait]
pub trait CacheMetricsProvider {
    /// Get the cache name
    fn name(&self) -> &str;

    /// Get analytics snapshot
    async fn get_analytics_snapshot(&self) -> Option<CacheAnalyticsSnapshot>;
}

impl CacheMetricsCollector {
    /// Create a new cache metrics collector
    pub fn new(registry: Registry, collection_interval_secs: u64) -> Self {
        // Create metrics
        let size_gauge = IntGaugeVec::new(
            prometheus::opts!("art_cache_size", "Current number of items in the cache"),
            &["cache"]
        ).unwrap();

        let memory_gauge = IntGaugeVec::new(
            prometheus::opts!("art_cache_memory_bytes", "Estimated memory usage of the cache"),
            &["cache"]
        ).unwrap();

        let utilization_gauge = GaugeVec::new(
            prometheus::opts!("art_cache_utilization", "Cache utilization as a percentage of capacity"),
            &["cache"]
        ).unwrap();

        let hit_ratio_gauge = GaugeVec::new(
            prometheus::opts!("art_cache_hit_ratio", "Cache hit ratio"),
            &["cache"]
        ).unwrap();

        let avg_access_time_gauge = GaugeVec::new(
            prometheus::opts!("art_cache_avg_access_time_us", "Average cache access time in microseconds"),
            &["cache"]
        ).unwrap();

        // Register metrics
        registry.register(Box::new(size_gauge.clone())).unwrap();
        registry.register(Box::new(memory_gauge.clone())).unwrap();
        registry.register(Box::new(utilization_gauge.clone())).unwrap();
        registry.register(Box::new(hit_ratio_gauge.clone())).unwrap();
        registry.register(Box::new(avg_access_time_gauge.clone())).unwrap();

        Self {
            caches: RwLock::new(HashMap::new()),
            registry,
            size_gauge,
            memory_gauge,
            utilization_gauge,
            hit_ratio_gauge,
            avg_access_time_gauge,
            collection_interval_secs,
            is_running: std::sync::atomic::AtomicBool::new(false),
        }
    }

    /// Register a cache for metrics collection
    pub async fn register_cache<T>(&self, cache: Arc<T>)
    where
        T: CacheMetricsProvider + Send + Sync + 'static
    {
        let mut caches = self.caches.write().await;
        caches.insert(cache.name().to_string(), cache);
    }

    /// Unregister a cache
    pub async fn unregister_cache(&self, name: &str) {
        let mut caches = self.caches.write().await;
        caches.remove(name);
    }

    /// Start collecting metrics
    pub async fn start_collection(&self) -> Result<()> {
        // Check if already running
        if self.is_running.compare_exchange(
            false,
            true,
            std::sync::atomic::Ordering::SeqCst,
            std::sync::atomic::Ordering::SeqCst
        ).is_err() {
            debug!("Cache metrics collection already running");
            return Ok(());
        }

        let collector = self.clone();

        // Spawn collection task
        tokio::spawn(async move {
            info!("Starting cache metrics collection");
            let mut interval = time::interval(Duration::from_secs(collector.collection_interval_secs));

            loop {
                interval.tick().await;

                if let Err(e) = collector.collect_metrics().await {
                    error!("Error collecting cache metrics: {}", e);
                }
            }
        });

        Ok(())
    }

    /// Stop collecting metrics
    pub fn stop_collection(&self) {
        self.is_running.store(false, std::sync::atomic::Ordering::SeqCst);
    }

    /// Collect metrics from all registered caches
    async fn collect_metrics(&self) -> Result<()> {
        let caches = self.caches.read().await;

        for (name, cache) in caches.iter() {
            if let Some(snapshot) = cache.get_analytics_snapshot().await {
                // Update metrics
                self.size_gauge.with_label_values(&[name])
                    .set(snapshot.total_items as i64);

                self.memory_gauge.with_label_values(&[name])
                    .set(snapshot.memory_usage_bytes as i64);

                self.utilization_gauge.with_label_values(&[name])
                    .set((snapshot.total_items as f64 / snapshot.max_capacity as f64) * 100.0);

                self.hit_ratio_gauge.with_label_values(&[name])
                    .set(snapshot.hit_ratio);

                self.avg_access_time_gauge.with_label_values(&[name])
                    .set(snapshot.avg_access_time_us);

                trace!("Updated cache metrics for {}", name);
            }
        }

        Ok(())
    }

    /// Get a summary of cache metrics
    pub async fn get_summary(&self) -> HashMap<String, CacheAnalyticsSnapshot> {
        let caches = self.caches.read().await;
        let mut result = HashMap::new();

        for (name, cache) in caches.iter() {
            if let Some(snapshot) = cache.get_analytics_snapshot().await {
                result.insert(name.clone(), snapshot);
            }
        }

        result
    }
}

impl Clone for CacheMetricsCollector {
    fn clone(&self) -> Self {
        Self {
            caches: RwLock::new(HashMap::new()),
            registry: self.registry.clone(),
            size_gauge: self.size_gauge.clone(),
            memory_gauge: self.memory_gauge.clone(),
            utilization_gauge: self.utilization_gauge.clone(),
            hit_ratio_gauge: self.hit_ratio_gauge.clone(),
            avg_access_time_gauge: self.avg_access_time_gauge.clone(),
            collection_interval_secs: self.collection_interval_secs,
            is_running: std::sync::atomic::AtomicBool::new(
                self.is_running.load(std::sync::atomic::Ordering::SeqCst)
            ),
        }
    }
}

// Implement CacheMetricsProvider for the Cache type
#[async_trait::async_trait]
impl<K, V> CacheMetricsProvider for crate::data::cache::Cache<K, V>
where
    K: Clone + Eq + std::hash::Hash + Send + Sync + 'static,
    V: Clone + Send + Sync + 'static,
{
    fn name(&self) -> &str {
        self.name()
    }

    async fn get_analytics_snapshot(&self) -> Option<CacheAnalyticsSnapshot> {
        self.get_analytics_snapshot()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::CacheConfig;
    use crate::data::cache::Cache;

    #[tokio::test]
    async fn test_cache_metrics_collector() {
        // Create a registry
        let registry = Registry::new();

        // Create a collector
        let collector = CacheMetricsCollector::new(registry, 1);

        // Create a cache with analytics enabled
        let config = CacheConfig {
            max_size: 10,
            ttl: 60,
            name: Some("test_cache".to_string()),
            enable_analytics: true,
            analytics_sampling_interval_secs: Some(1),
            analytics_max_history_samples: Some(10),
            analytics_track_per_key_metrics: Some(true),
        };

        let cache = Arc::new(Cache::<String, String>::new(&config));

        // Register the cache
        collector.register_cache(cache.clone()).await;

        // Perform some operations on the cache
        cache.insert("key1".to_string(), "value1".to_string()).await;
        cache.insert("key2".to_string(), "value2".to_string()).await;

        let _ = cache.get(&"key1".to_string()).await;
        let _ = cache.get(&"key3".to_string()).await; // Miss

        // Collect metrics
        collector.collect_metrics().await.unwrap();

        // Get the summary
        let summary = collector.get_summary().await;

        // Check that metrics were collected
        assert!(summary.contains_key("test_cache"));
        let snapshot = &summary["test_cache"];

        assert_eq!(snapshot.total_gets, 2);
        assert_eq!(snapshot.total_hits, 1);
        assert_eq!(snapshot.total_misses, 1);
        assert_eq!(snapshot.total_inserts, 2);
    }
}
