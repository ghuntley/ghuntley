//! Health check service for monitoring system status.

use crate::data::Git;
use crate::data::Sqlite;
use crate::error::{Error, Result};
use crate::config::Config;

use std::sync::Arc;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tracing::{debug, error, info, trace, warn};

/// Health check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    /// Overall system status: "ok", "degraded", or "error"
    pub status: String,

    /// Application version
    pub version: String,

    /// System uptime in seconds
    pub uptime: u64,

    /// Component-specific status
    pub components: HashMap<String, ComponentStatus>,
}

/// Component status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentStatus {
    /// Component status: "ok", "degraded", or "error"
    pub status: String,

    /// Additional details about the component status
    pub details: Option<String>,
}

/// Start time of the application
static mut START_TIME: Option<SystemTime> = None;

/// Health service for checking system status
pub struct HealthService {
    /// Git data access
    git: Arc<Git>,

    /// SQLite database
    db: Arc<Sqlite>,

    /// Configuration
    config: Arc<Config>,
}

impl HealthService {
    /// Create a new health service
    pub fn new(git: Arc<Git>, db: Arc<Sqlite>, config: Arc<Config>) -> Self {
        // Record the start time when the service is first created
        unsafe {
            if START_TIME.is_none() {
                START_TIME = Some(SystemTime::now());
            }
        }

        Self { git, db, config }
    }

    /// Get the health status
    pub async fn check_health(&self) -> Result<HealthStatus> {
        // Check individual components
        let mut components = HashMap::new();

        // Check database
        let db_status = if self.db.check_connection() {
            ComponentStatus {
                status: "ok".to_string(),
                details: None,
            }
        } else {
            ComponentStatus {
                status: "error".to_string(),
                details: Some("Database connection failed".to_string()),
            }
        };
        components.insert("database".to_string(), db_status);

        // Check Git
        let git_status = match self.check_git_status().await {
            Ok(status) => ComponentStatus {
                status: "ok".to_string(),
                details: Some(format!("{} repositories available", status)),
            },
            Err(e) => ComponentStatus {
                status: "error".to_string(),
                details: Some(format!("Git error: {}", e)),
            },
        };
        components.insert("git".to_string(), git_status);

        // Get uptime
        let uptime = self.get_uptime().as_secs();

        // Determine overall status
        let overall_status = self.determine_overall_status(&components);

        // Get application version
        let version = env!("CARGO_PKG_VERSION").to_string();

        Ok(HealthStatus {
            status: overall_status,
            version,
            uptime,
            components,
        })
    }

    /// Check Git status
    async fn check_git_status(&self) -> Result<usize> {
        let repos = self.git.list_repositories()
            .map_err(|e| Error::Internal(format!("Failed to list repositories: {}", e)))?;

        Ok(repos.len())
    }

    /// Get application uptime
    fn get_uptime(&self) -> Duration {
        unsafe {
            match START_TIME {
                Some(start) => start.elapsed().unwrap_or(Duration::from_secs(0)),
                None => {
                    // This should never happen, but just in case
                    START_TIME = Some(SystemTime::now());
                    Duration::from_secs(0)
                }
            }
        }
    }

    /// Determine overall system status based on component status
    fn determine_overall_status(&self, components: &HashMap<String, ComponentStatus>) -> String {
        let mut has_error = false;
        let mut has_degraded = false;

        for (_, status) in components {
            match status.status.as_str() {
                "error" => has_error = true,
                "degraded" => has_degraded = true,
                _ => {}
            }
        }

        if has_error {
            "error".to_string()
        } else if has_degraded {
            "degraded".to_string()
        } else {
            "ok".to_string()
        }
    }

    /// Set the current system time (for testing)
    #[cfg(test)]
    fn set_start_time(time: SystemTime) {
        unsafe {
            START_TIME = Some(time);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use std::path::Path;

    /// Create a test health service
    fn create_test_service() -> (HealthService, TempDir) {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");

        // Create a sample config
        let config = Config {
            port: 3000,
            host: "127.0.0.1".to_string(),
            repositories: vec![],
            cache_size_mb: 100,
            cache_ttl_secs: 300,
            theme: "light".to_string(),
        };

        // Create the Git manager
        let git = Git::new(&temp_dir.path().to_string_lossy().to_string())
            .expect("Failed to create Git manager");

        // Create an in-memory SQLite database
        let db_path = temp_dir.path().join("test.db");
        let db = Sqlite::open(&db_path.to_string_lossy().to_string())
            .expect("Failed to create database");

        // Create the health service
        let service = HealthService::new(
            Arc::new(git),
            Arc::new(db),
            Arc::new(config),
        );

        // Reset the start time for consistent tests
        HealthService::set_start_time(SystemTime::now());

        (service, temp_dir)
    }

    #[tokio::test]
    async fn test_health_check() {
        let (service, _temp_dir) = create_test_service();

        let health = service.check_health().await.expect("Health check failed");

        // Check overall status
        assert_eq!(health.status, "ok", "Overall status should be ok");

        // Check components
        assert!(health.components.contains_key("database"), "Should have database component");
        assert!(health.components.contains_key("git"), "Should have git component");

        // Check version
        assert!(!health.version.is_empty(), "Should have a version");

        // Check uptime
        assert!(health.uptime >= 0, "Uptime should be positive");
    }

    #[tokio::test]
    async fn test_determine_overall_status() {
        let (service, _temp_dir) = create_test_service();

        // All ok
        let mut components = HashMap::new();
        components.insert("c1".to_string(), ComponentStatus {
            status: "ok".to_string(),
            details: None,
        });
        components.insert("c2".to_string(), ComponentStatus {
            status: "ok".to_string(),
            details: None,
        });
        assert_eq!(service.determine_overall_status(&components), "ok");

        // One degraded
        components.insert("c3".to_string(), ComponentStatus {
            status: "degraded".to_string(),
            details: None,
        });
        assert_eq!(service.determine_overall_status(&components), "degraded");

        // One error
        components.insert("c4".to_string(), ComponentStatus {
            status: "error".to_string(),
            details: None,
        });
        assert_eq!(service.determine_overall_status(&components), "error");
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;

    // Generate a component status
    fn component_status_strategy() -> impl Strategy<Value = ComponentStatus> {
        // Generate status string and optional details
        (prop_oneof![
            Just("ok".to_string()),
            Just("degraded".to_string()),
            Just("error".to_string())
        ], option::of("[a-zA-Z0-9 _.-]{1,50}"))
        .prop_map(|(status, details)| {
            ComponentStatus {
                status,
                details: details.map(|s| s.to_string()),
            }
        })
    }

    // Generate a map of component statuses
    fn components_map_strategy() -> impl Strategy<Value = HashMap<String, ComponentStatus>> {
        prop::collection::hash_map("[a-zA-Z][a-zA-Z0-9_-]{1,10}", component_status_strategy(), 1..10)
    }

    proptest! {
        /// Test that overall status is correctly determined from component status
        #[test]
        fn overall_status_determined_correctly(
            components in components_map_strategy()
        ) {
            // Create a health service just for testing the status determination
            let temp_dir = TempDir::new().expect("Failed to create temp dir");
            let config = Config {
                port: 3000,
                host: "127.0.0.1".to_string(),
                repositories: vec![],
                cache_size_mb: 100,
                cache_ttl_secs: 300,
                theme: "light".to_string(),
            };
            let git = Git::new(&temp_dir.path().to_string_lossy().to_string())
                .expect("Failed to create Git manager");
            let db_path = temp_dir.path().join("test.db");
            let db = Sqlite::open(&db_path.to_string_lossy().to_string())
                .expect("Failed to create database");
            let service = HealthService::new(
                Arc::new(git),
                Arc::new(db),
                Arc::new(config),
            );

            // Determine if there are any error or degraded components
            let has_error = components.values().any(|c| c.status == "error");
            let has_degraded = components.values().any(|c| c.status == "degraded");

            // Get the overall status
            let status = service.determine_overall_status(&components);

            // Verify the status follows the expected priority
            if has_error {
                assert_eq!(status, "error", "Status should be 'error' if any component has error status");
            } else if has_degraded {
                assert_eq!(status, "degraded", "Status should be 'degraded' if any component is degraded and none have error");
            } else {
                assert_eq!(status, "ok", "Status should be 'ok' if all components are ok");
            }
        }

        /// Test that HealthStatus struct correctly represents the system state
        #[test]
        fn health_status_represents_system_state(
            components in components_map_strategy(),
            version in "[0-9]+\\.[0-9]+\\.[0-9]+",
            uptime in 0u64..1_000_000u64
        ) {
            // Create a HealthStatus directly
            let status = if components.values().any(|c| c.status == "error") {
                "error".to_string()
            } else if components.values().any(|c| c.status == "degraded") {
                "degraded".to_string()
            } else {
                "ok".to_string()
            };

            let health_status = HealthStatus {
                status: status.clone(),
                version: version.clone(),
                uptime,
                components: components.clone(),
            };

            // Verify all fields are correctly set
            assert_eq!(health_status.status, status, "Overall status field should match expected status");
            assert_eq!(health_status.version, version, "Version field should match the provided version");
            assert_eq!(health_status.uptime, uptime, "Uptime field should match the provided uptime");
            assert_eq!(health_status.components, components, "Components field should match the provided components");

            // Test that JSON serialization works
            let json = serde_json::to_string(&health_status).expect("Failed to serialize health status");

            // The JSON should include all the key fields
            assert!(json.contains(&status), "JSON should include the status");
            assert!(json.contains(&version), "JSON should include the version");
            assert!(json.contains(&uptime.to_string()), "JSON should include the uptime");

            // Each component should be included
            for (key, _) in &components {
                assert!(json.contains(key), "JSON should include component {}", key);
            }

            // Test that JSON deserialization works
            let deserialized: HealthStatus = serde_json::from_str(&json).expect("Failed to deserialize health status");
            assert_eq!(deserialized.status, health_status.status, "Deserialized status should match original");
            assert_eq!(deserialized.version, health_status.version, "Deserialized version should match original");
            assert_eq!(deserialized.uptime, health_status.uptime, "Deserialized uptime should match original");
            assert_eq!(deserialized.components.len(), health_status.components.len(), "Deserialized components should match original");
        }
    }
}
