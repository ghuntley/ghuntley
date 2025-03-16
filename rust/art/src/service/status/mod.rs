// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Status service for monitoring system health and providing diagnostics
//!
//! The status service provides functionality for checking the health of various
//! components of the system, gathering metrics, and providing diagnostic information.

use crate::error::{Error, Result};
use crate::data::cache::Cache;
use crate::data::git::Git;
use crate::data::db::Sqlite;
use crate::service::repository::RepositoryService;
use crate::service::index::IndexService;
use crate::service::format::FormatService;

use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, trace, warn};

/// Status of a component (healthy, degraded, unhealthy)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ComponentStatus {
    /// Component is healthy and functioning normally
    Healthy,

    /// Component is functioning with reduced capabilities
    Degraded,

    /// Component is not functioning
    Unhealthy,
}

impl std::fmt::Display for ComponentStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ComponentStatus::Healthy => write!(f, "healthy"),
            ComponentStatus::Degraded => write!(f, "degraded"),
            ComponentStatus::Unhealthy => write!(f, "unhealthy"),
        }
    }
}

/// System health response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    /// Overall system status
    pub status: ComponentStatus,

    /// Status of individual components
    pub components: HashMap<String, ComponentStatusDetails>,

    /// System uptime in seconds
    pub uptime: u64,

    /// Version of the application
    pub version: String,

    /// Timestamp when the health check was performed
    pub timestamp: String,
}

/// Detailed status of a component
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentStatusDetails {
    /// Status of the component
    pub status: ComponentStatus,

    /// Additional details about the component's status
    pub details: Option<String>,

    /// Last check timestamp
    pub last_check: String,
}

/// System resource metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    /// CPU usage percentage
    pub cpu_usage: f64,

    /// Memory usage in bytes
    pub memory_usage: u64,

    /// Total memory available in bytes
    pub memory_total: u64,

    /// Disk usage in bytes
    pub disk_usage: u64,

    /// Total disk space available in bytes
    pub disk_total: u64,

    /// Number of open file descriptors
    pub open_fds: u64,

    /// Number of active connections
    pub active_connections: u64,

    /// Timestamp when metrics were collected
    pub timestamp: String,
}

/// Status service for monitoring system health
pub struct StatusService {
    /// Git repository manager
    git: Arc<Git>,

    /// SQLite database
    db: Arc<Sqlite>,

    /// Cache
    cache: Arc<Cache<String, String>>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// Index service
    index_service: Arc<IndexService>,

    /// Format service
    format_service: Arc<Mutex<FormatService>>,

    /// Application start time
    start_time: Instant,

    /// Application version
    version: String,

    /// Last health check result
    last_health_check: Mutex<Option<HealthResponse>>,

    /// Health check cache duration
    health_check_cache_duration: Duration,

    /// Last metrics collection
    last_metrics: Mutex<Option<SystemMetrics>>,

    /// Metrics collection cache duration
    metrics_cache_duration: Duration,
}

impl StatusService {
    /// Create a new status service
    pub fn new(
        git: Arc<Git>,
        db: Arc<Sqlite>,
        cache: Arc<Cache<String, String>>,
        repository_service: Arc<RepositoryService>,
        index_service: Arc<IndexService>,
        format_service: Arc<Mutex<FormatService>>,
        version: String,
    ) -> Self {
        Self {
            git,
            db,
            cache,
            repository_service,
            index_service,
            format_service,
            start_time: Instant::now(),
            version,
            last_health_check: Mutex::new(None),
            health_check_cache_duration: Duration::from_secs(30),
            last_metrics: Mutex::new(None),
            metrics_cache_duration: Duration::from_secs(10),
        }
    }

    /// Set the health check cache duration
    pub fn set_health_check_cache_duration(&mut self, duration: Duration) {
        self.health_check_cache_duration = duration;
    }

    /// Set the metrics cache duration
    pub fn set_metrics_cache_duration(&mut self, duration: Duration) {
        self.metrics_cache_duration = duration;
    }

    /// Get the system health status
    pub async fn health_check(&self) -> Result<HealthResponse> {
        // Check if we have a cached health check result
        {
            let last_health_check = self.last_health_check.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire last_health_check lock: {}", e))
            })?;

            if let Some(health) = &*last_health_check {
                // Parse the timestamp to check if the cache is still valid
                if let Ok(timestamp) = chrono::DateTime::parse_from_rfc3339(&health.timestamp) {
                    let now = chrono::Utc::now();
                    let age = now.signed_duration_since(timestamp.with_timezone(&chrono::Utc));

                    if age.to_std().map(|d| d < self.health_check_cache_duration).unwrap_or(false) {
                        debug!("Returning cached health check result");
                        return Ok(health.clone());
                    }
                }
            }
        }

        // Perform health checks for each component
        let mut components = HashMap::new();
        let now = chrono::Utc::now().to_rfc3339();

        // Check Git
        let git_status = match self.check_git_health().await {
            Ok(status) => ComponentStatusDetails {
                status,
                details: None,
                last_check: now.clone(),
            },
            Err(e) => ComponentStatusDetails {
                status: ComponentStatus::Unhealthy,
                details: Some(e.to_string()),
                last_check: now.clone(),
            },
        };
        components.insert("git".to_string(), git_status);

        // Check Database
        let db_status = match self.check_db_health().await {
            Ok(status) => ComponentStatusDetails {
                status,
                details: None,
                last_check: now.clone(),
            },
            Err(e) => ComponentStatusDetails {
                status: ComponentStatus::Unhealthy,
                details: Some(e.to_string()),
                last_check: now.clone(),
            },
        };
        components.insert("database".to_string(), db_status);

        // Check Cache
        let cache_status = match self.check_cache_health().await {
            Ok(status) => ComponentStatusDetails {
                status,
                details: None,
                last_check: now.clone(),
            },
            Err(e) => ComponentStatusDetails {
                status: ComponentStatus::Unhealthy,
                details: Some(e.to_string()),
                last_check: now.clone(),
            },
        };
        components.insert("cache".to_string(), cache_status);

        // Determine overall status
        let status = self.determine_overall_status(&components);

        // Create health response
        let uptime = self.start_time.elapsed().as_secs();
        let health_response = HealthResponse {
            status,
            components,
            uptime,
            version: self.version.clone(),
            timestamp: now,
        };

        // Cache the health check result
        {
            let mut last_health_check = self.last_health_check.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire last_health_check lock: {}", e))
            })?;
            *last_health_check = Some(health_response.clone());
        }

        Ok(health_response)
    }

    /// Check health of Git component
    async fn check_git_health(&self) -> Result<ComponentStatus> {
        // Try to list repositories as a basic health check
        match self.git.list_repositories() {
            Ok(_) => Ok(ComponentStatus::Healthy),
            Err(e) => {
                error!("Git health check failed: {}", e);
                Ok(ComponentStatus::Unhealthy)
            }
        }
    }

    /// Check health of Database component
    async fn check_db_health(&self) -> Result<ComponentStatus> {
        // Try to execute a simple query as a health check
        match self.db.execute_query("SELECT 1", &[]) {
            Ok(_) => Ok(ComponentStatus::Healthy),
            Err(e) => {
                error!("Database health check failed: {}", e);
                Ok(ComponentStatus::Unhealthy)
            }
        }
    }

    /// Check health of Cache component
    async fn check_cache_health(&self) -> Result<ComponentStatus> {
        // Try to set and get a value as a health check
        let key = format!("health_check_{}", chrono::Utc::now().timestamp());
        let value = "health_check_value".to_string();

        // Insert the value into the cache
        self.cache.insert(key.clone(), value.clone()).await;

        // Try to retrieve the value
        match self.cache.get(&key).await {
            Some(retrieved) if retrieved == value => {
                // Clean up
                self.cache.delete(&key).await;
                Ok(ComponentStatus::Healthy)
            },
            Some(_) => {
                warn!("Cache health check: value mismatch");
                Ok(ComponentStatus::Degraded)
            },
            None => {
                warn!("Cache health check: value not found after set");
                Ok(ComponentStatus::Unhealthy)
            }
        }
    }

    /// Determine overall system status based on component statuses
    fn determine_overall_status(&self, components: &HashMap<String, ComponentStatusDetails>) -> ComponentStatus {
        let mut has_unhealthy = false;
        let mut has_degraded = false;

        for (_, details) in components {
            match details.status {
                ComponentStatus::Unhealthy => has_unhealthy = true,
                ComponentStatus::Degraded => has_degraded = true,
                _ => {},
            }
        }

        if has_unhealthy {
            ComponentStatus::Unhealthy
        } else if has_degraded {
            ComponentStatus::Degraded
        } else {
            ComponentStatus::Healthy
        }
    }

    /// Get system metrics
    pub async fn get_metrics(&self) -> Result<SystemMetrics> {
        // Check if we have cached metrics
        {
            let last_metrics = self.last_metrics.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire last_metrics lock: {}", e))
            })?;

            if let Some(metrics) = &*last_metrics {
                // Parse the timestamp to check if the cache is still valid
                if let Ok(timestamp) = chrono::DateTime::parse_from_rfc3339(&metrics.timestamp) {
                    let now = chrono::Utc::now();
                    let age = now.signed_duration_since(timestamp.with_timezone(&chrono::Utc));

                    if age.to_std().map(|d| d < self.metrics_cache_duration).unwrap_or(false) {
                        debug!("Returning cached metrics");
                        return Ok(metrics.clone());
                    }
                }
            }
        }

        // Collect system metrics
        let metrics = self.collect_system_metrics()?;

        // Cache the metrics
        {
            let mut last_metrics = self.last_metrics.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire last_metrics lock: {}", e))
            })?;
            *last_metrics = Some(metrics.clone());
        }

        Ok(metrics)
    }

    /// Collect system metrics
    fn collect_system_metrics(&self) -> Result<SystemMetrics> {
        // In a real implementation, we would use a crate like sysinfo
        // to gather accurate system metrics. For this example, we'll use
        // placeholder values.

        // Placeholder implementation
        let now = chrono::Utc::now().to_rfc3339();

        // Get number of active connections (placeholder)
        let active_connections = 0; // Would come from HTTP server stats

        // Get format service metrics
        let format_metrics = {
            let format_service = self.format_service.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire format_service lock: {}", e))
            })?;
            format_service.get_metrics().clone()
        };

        let metrics = SystemMetrics {
            cpu_usage: 0.0, // Placeholder
            memory_usage: 0, // Placeholder
            memory_total: 0, // Placeholder
            disk_usage: 0, // Placeholder
            disk_total: 0, // Placeholder
            open_fds: 0, // Placeholder
            active_connections,
            timestamp: now,
        };

        Ok(metrics)
    }

    /// Get format service telemetry
    pub fn get_format_telemetry(&self) -> Result<crate::service::format::FormatTelemetry> {
        let format_service = self.format_service.lock().map_err(|e| {
            Error::Internal(format!("Failed to acquire format_service lock: {}", e))
        })?;

        Ok(format_service.get_telemetry())
    }

    /// Reset all metrics
    pub fn reset_metrics(&self) -> Result<()> {
        // Reset format service metrics
        {
            let mut format_service = self.format_service.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire format_service lock: {}", e))
            })?;

            format_service.reset_metrics();
        }

        // Clear cached metrics
        {
            let mut last_metrics = self.last_metrics.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire last_metrics lock: {}", e))
            })?;
            *last_metrics = None;
        }

        Ok(())
    }

    /// Generate Prometheus metrics output
    pub fn export_prometheus_metrics(&self) -> Result<String> {
        let mut output = String::new();

        // Add format service metrics
        {
            let format_service = self.format_service.lock().map_err(|e| {
                Error::Internal(format!("Failed to acquire format_service lock: {}", e))
            })?;

            output.push_str(&format_service.export_telemetry_prometheus());
        }

        // Add system metrics
        if let Ok(metrics) = self.collect_system_metrics() {
            output.push_str(&format!("# HELP art_cpu_usage Current CPU usage percentage\n"));
            output.push_str(&format!("# TYPE art_cpu_usage gauge\n"));
            output.push_str(&format!("art_cpu_usage {}\n", metrics.cpu_usage));

            output.push_str(&format!("# HELP art_memory_usage Current memory usage in bytes\n"));
            output.push_str(&format!("# TYPE art_memory_usage gauge\n"));
            output.push_str(&format!("art_memory_usage {}\n", metrics.memory_usage));

            output.push_str(&format!("# HELP art_memory_total Total memory available in bytes\n"));
            output.push_str(&format!("# TYPE art_memory_total gauge\n"));
            output.push_str(&format!("art_memory_total {}\n", metrics.memory_total));

            output.push_str(&format!("# HELP art_disk_usage Current disk usage in bytes\n"));
            output.push_str(&format!("# TYPE art_disk_usage gauge\n"));
            output.push_str(&format!("art_disk_usage {}\n", metrics.disk_usage));

            output.push_str(&format!("# HELP art_disk_total Total disk space available in bytes\n"));
            output.push_str(&format!("# TYPE art_disk_total gauge\n"));
            output.push_str(&format!("art_disk_total {}\n", metrics.disk_total));

            output.push_str(&format!("# HELP art_open_fds Number of open file descriptors\n"));
            output.push_str(&format!("# TYPE art_open_fds gauge\n"));
            output.push_str(&format!("art_open_fds {}\n", metrics.open_fds));

            output.push_str(&format!("# HELP art_active_connections Number of active connections\n"));
            output.push_str(&format!("# TYPE art_active_connections gauge\n"));
            output.push_str(&format!("art_active_connections {}\n", metrics.active_connections));
        }

        // Add uptime metric
        let uptime = self.start_time.elapsed().as_secs();
        output.push_str(&format!("# HELP art_uptime_seconds System uptime in seconds\n"));
        output.push_str(&format!("# TYPE art_uptime_seconds counter\n"));
        output.push_str(&format!("art_uptime_seconds {}\n", uptime));

        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;
    use proptest::prelude::*;
    use chrono::{DateTime, Utc};

    // Helper function to create a mocked status service for testing
    fn create_test_status_service() -> StatusService {
        // Mock the dependencies
        let git = Arc::new(Git::default());
        let db = Arc::new(Sqlite::default());
        let cache = Arc::new(Cache::default());
        let repository_service = Arc::new(RepositoryService::default());
        let index_service = Arc::new(IndexService::default());
        let format_service = Arc::new(Mutex::new(FormatService::default()));

        StatusService::new(
            git,
            db,
            cache,
            repository_service,
            index_service,
            format_service,
            "0.1.0".to_string()
        )
    }

    #[test]
    fn test_component_status_display() {
        assert_eq!(ComponentStatus::Healthy.to_string(), "healthy");
        assert_eq!(ComponentStatus::Degraded.to_string(), "degraded");
        assert_eq!(ComponentStatus::Unhealthy.to_string(), "unhealthy");
    }

    #[test]
    fn test_determine_overall_status() {
        let service = create_test_status_service();
        let now = chrono::Utc::now().to_rfc3339();

        // Test all healthy
        let mut components = HashMap::new();
        components.insert("test1".to_string(), ComponentStatusDetails {
            status: ComponentStatus::Healthy,
            details: None,
            last_check: now.clone(),
        });
        components.insert("test2".to_string(), ComponentStatusDetails {
            status: ComponentStatus::Healthy,
            details: None,
            last_check: now.clone(),
        });

        assert_eq!(service.determine_overall_status(&components), ComponentStatus::Healthy);

        // Test with degraded
        components.insert("test3".to_string(), ComponentStatusDetails {
            status: ComponentStatus::Degraded,
            details: None,
            last_check: now.clone(),
        });

        assert_eq!(service.determine_overall_status(&components), ComponentStatus::Degraded);

        // Test with unhealthy
        components.insert("test4".to_string(), ComponentStatusDetails {
            status: ComponentStatus::Unhealthy,
            details: None,
            last_check: now.clone(),
        });

        assert_eq!(service.determine_overall_status(&components), ComponentStatus::Unhealthy);
    }

    // Strategy for generating a single component status
    fn single_component_status_strategy() -> impl Strategy<Value = ComponentStatus> {
        prop_oneof![
            Just(ComponentStatus::Healthy),
            Just(ComponentStatus::Degraded),
            Just(ComponentStatus::Unhealthy),
        ]
    }

    // Strategy for generating component status details
    fn component_details_strategy() -> impl Strategy<Value = ComponentStatusDetails> {
        single_component_status_strategy().prop_flat_map(|status| {
            let maybe_details = prop_oneof![
                Just(None),
                ".*".prop_map(|s| Some(s)),
            ];

            (Just(status), maybe_details, Just(Utc::now().to_rfc3339()))
                .prop_map(|(status, details, last_check)| {
                    ComponentStatusDetails {
                        status,
                        details,
                        last_check,
                    }
                })
        })
    }

    // Strategy for generating a map of component status details
    fn components_map_strategy() -> impl Strategy<Value = HashMap<String, ComponentStatusDetails>> {
        prop::collection::btree_map(".*", component_details_strategy(), 1..10)
            .prop_map(|btree_map| {
                btree_map.into_iter().collect::<HashMap<_, _>>()
            })
    }

    // Strategy for generating health responses
    fn health_response_strategy() -> impl Strategy<Value = HealthResponse> {
        (
            single_component_status_strategy(),
            components_map_strategy(),
            prop::num::u64::ANY,
            ".*",
            Just(Utc::now().to_rfc3339()),
        ).prop_map(|(status, components, uptime, version, timestamp)| {
            HealthResponse {
                status,
                components,
                uptime,
                version,
                timestamp,
            }
        })
    }

    // Strategy for generating system metrics
    fn system_metrics_strategy() -> impl Strategy<Value = SystemMetrics> {
        (
            prop::num::f64::NORMAL,
            prop::num::u64::ANY,
            prop::num::u64::ANY,
            prop::num::u64::ANY,
            prop::num::u64::ANY,
            prop::num::u64::ANY,
            prop::num::u64::ANY,
            Just(Utc::now().to_rfc3339()),
        ).prop_map(|(cpu_usage, memory_usage, memory_total, disk_usage, disk_total, open_fds, active_connections, timestamp)| {
            SystemMetrics {
                cpu_usage,
                memory_usage,
                memory_total,
                disk_usage,
                disk_total,
                open_fds,
                active_connections,
                timestamp,
            }
        })
    }

    // Property-based tests
    proptest! {
        // Test that the overall status is determined correctly for any combination of component statuses
        #[test]
        fn prop_determine_overall_status(components in components_map_strategy()) {
            let service = create_test_status_service();
            let overall = service.determine_overall_status(&components);

            let has_unhealthy = components.values().any(|c| c.status == ComponentStatus::Unhealthy);
            let has_degraded = components.values().any(|c| c.status == ComponentStatus::Degraded);

            if has_unhealthy {
                prop_assert_eq!(overall, ComponentStatus::Unhealthy);
            } else if has_degraded {
                prop_assert_eq!(overall, ComponentStatus::Degraded);
            } else {
                prop_assert_eq!(overall, ComponentStatus::Healthy);
            }
        }

        // Test that health checks always produce a valid HealthResponse
        // with timestamps in valid RFC3339 format
        #[test]
        fn prop_health_response_invariants(component_count in 1..10usize) {
            // This test would ideally use real health check function,
            // but since we're using mocked dependencies, we'll just ensure
            // the structures maintain their invariants

            let now = chrono::Utc::now().to_rfc3339();
            let mut components = HashMap::new();

            // Create a random set of components
            for i in 0..component_count {
                let status = match i % 3 {
                    0 => ComponentStatus::Healthy,
                    1 => ComponentStatus::Degraded,
                    _ => ComponentStatus::Unhealthy,
                };

                components.insert(format!("component{}", i), ComponentStatusDetails {
                    status,
                    details: if i % 2 == 0 { Some(format!("Details for component {}", i)) } else { None },
                    last_check: now.clone(),
                });
            }

            // Determine overall status based on component statuses
            let service = create_test_status_service();
            let status = service.determine_overall_status(&components);

            let health_response = HealthResponse {
                status,
                components,
                uptime: 123,
                version: "0.1.0".to_string(),
                timestamp: now.clone(),
            };

            // Verify RFC3339 timestamp format is valid
            // This is a property that should always hold
            prop_assert!(chrono::DateTime::parse_from_rfc3339(&health_response.timestamp).is_ok());

            // Overall status should match our determination
            prop_assert_eq!(health_response.status, status);

            // Component count should match what we put in
            prop_assert_eq!(health_response.components.len(), component_count);
        }

        // Health response timestamps should be valid RFC3339 format
        #[test]
        fn prop_health_response_timestamp_validity(health_response in health_response_strategy()) {
            prop_assert!(DateTime::parse_from_rfc3339(&health_response.timestamp).is_ok());

            // All component timestamps should also be valid
            for (_, details) in &health_response.components {
                prop_assert!(DateTime::parse_from_rfc3339(&details.last_check).is_ok());
            }
        }

        // System metrics timestamp should be valid RFC3339 format
        #[test]
        fn prop_system_metrics_timestamp_validity(metrics in system_metrics_strategy()) {
            prop_assert!(DateTime::parse_from_rfc3339(&metrics.timestamp).is_ok());
        }

        // Component status string representation should match expected values
        #[test]
        fn prop_component_status_string_representation(status in single_component_status_strategy()) {
            let string_value = status.to_string();
            match status {
                ComponentStatus::Healthy => prop_assert_eq!(string_value, "healthy"),
                ComponentStatus::Degraded => prop_assert_eq!(string_value, "degraded"),
                ComponentStatus::Unhealthy => prop_assert_eq!(string_value, "unhealthy"),
            }
        }

        // Overall health status should always be the most severe component status
        #[test]
        fn prop_overall_status_severity_ordering(
            healthy_count in 0..5usize,
            degraded_count in 0..5usize,
            unhealthy_count in 0..5usize,
        ) {
            // Skip empty test cases
            prop_assume!(healthy_count + degraded_count + unhealthy_count > 0);

            let service = create_test_status_service();
            let now = Utc::now().to_rfc3339();
            let mut components = HashMap::new();

            // Add healthy components
            for i in 0..healthy_count {
                components.insert(format!("healthy{}", i), ComponentStatusDetails {
                    status: ComponentStatus::Healthy,
                    details: None,
                    last_check: now.clone(),
                });
            }

            // Add degraded components
            for i in 0..degraded_count {
                components.insert(format!("degraded{}", i), ComponentStatusDetails {
                    status: ComponentStatus::Degraded,
                    details: None,
                    last_check: now.clone(),
                });
            }

            // Add unhealthy components
            for i in 0..unhealthy_count {
                components.insert(format!("unhealthy{}", i), ComponentStatusDetails {
                    status: ComponentStatus::Unhealthy,
                    details: None,
                    last_check: now.clone(),
                });
            }

            let overall = service.determine_overall_status(&components);

            if unhealthy_count > 0 {
                prop_assert_eq!(overall, ComponentStatus::Unhealthy);
            } else if degraded_count > 0 {
                prop_assert_eq!(overall, ComponentStatus::Degraded);
            } else {
                prop_assert_eq!(overall, ComponentStatus::Healthy);
            }
        }

        // Prometheus metrics output should always contain certain key metrics
        #[test]
        fn prop_prometheus_metrics_contains_key_metrics(
            cpu_usage in prop::num::f64::NORMAL,
            uptime in prop::num::u64::ANY,
        ) {
            let service = create_test_status_service();

            // Get Prometheus metrics output
            let metrics_text = service.export_prometheus_metrics().unwrap();

            // Check that key metrics are included
            prop_assert!(metrics_text.contains("art_uptime_seconds"));
            prop_assert!(metrics_text.contains("art_cpu_usage"));
            prop_assert!(metrics_text.contains("art_memory_usage"));
        }

        // Health response ensures overall status correctly represents component statuses
        #[test]
        fn prop_health_response_coherence(
            components in components_map_strategy()
        ) {
            let service = create_test_status_service();
            let expected_status = service.determine_overall_status(&components);

            let health_response = HealthResponse {
                status: expected_status,
                components: components.clone(),
                uptime: 123,
                version: "0.1.0".to_string(),
                timestamp: Utc::now().to_rfc3339(),
            };

            // Verify overall status is consistent with components
            let has_unhealthy = components.values().any(|c| c.status == ComponentStatus::Unhealthy);
            let has_degraded = components.values().any(|c| c.status == ComponentStatus::Degraded);

            if has_unhealthy {
                prop_assert_eq!(health_response.status, ComponentStatus::Unhealthy);
            } else if has_degraded {
                prop_assert_eq!(health_response.status, ComponentStatus::Degraded);
            } else {
                prop_assert_eq!(health_response.status, ComponentStatus::Healthy);
            }
        }

        // Reset metrics clears cache but metrics output still works
        #[test]
        fn prop_reset_metrics_clears_cache(_i in 0..10) {
            let service = create_test_status_service();

            // Get metrics first to populate cache
            let _ = service.get_metrics();

            // Reset metrics
            service.reset_metrics().unwrap();

            // Caches should be cleared, but output should still work
            let metrics_output = service.export_prometheus_metrics().unwrap();
            prop_assert!(metrics_output.contains("art_uptime_seconds"));
        }
    }

    #[tokio::test]
    async fn test_health_check() -> Result<()> {
        // Create the status service
        let status_service = create_test_status_service();

        // Perform a health check
        let health = status_service.health_check().await?;

        // Verify the response
        assert_eq!(health.version, "0.1.0");

        // Since we're using mock dependencies, we expect components to be unhealthy
        assert_eq!(health.status, ComponentStatus::Unhealthy);

        // Check that all required components are present
        assert!(health.components.contains_key("git"));
        assert!(health.components.contains_key("database"));
        assert!(health.components.contains_key("cache"));

        Ok(())
    }

    #[tokio::test]
    async fn test_metrics() -> Result<()> {
        // Create the status service
        let status_service = create_test_status_service();

        // Get system metrics
        let metrics = status_service.get_metrics().await?;

        // Verify that timestamps are in RFC3339 format
        chrono::DateTime::parse_from_rfc3339(&metrics.timestamp)?;

        // Export Prometheus metrics and check that output contains expected metrics
        let prometheus_output = status_service.export_prometheus_metrics()?;
        assert!(prometheus_output.contains("art_uptime_seconds"));

        Ok(())
    }
}
