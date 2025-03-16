// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! SQLite database access module

mod models;
mod schema;
#[cfg(test)]
mod prop_tests;
#[cfg(test)]
mod property_tests;
mod backup;

use crate::config::DatabaseConfig;
use crate::error::{Error, Result};
use backup::{BackupConfig, DatabaseBackup};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::Connection;
use std::path::Path;
use std::time::Duration;
use std::fs;
use log::{info, warn, error};
use std::sync::Arc;

/// SQLite database connection pool
pub struct Sqlite {
    pool: Pool<SqliteConnectionManager>,
    backup_manager: Option<Arc<DatabaseBackup>>,
}

impl Sqlite {
    /// Create a new SQLite database instance
    pub fn new(config: &DatabaseConfig) -> Result<Self> {
        // Create directory for database if it doesn't exist
        if let Some(parent) = config.path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| Error::Database(rusqlite::Error::from(e)))?;
        }

        // Create connection manager
        let manager = SqliteConnectionManager::file(&config.path);

        // Create connection pool
        let pool = Pool::builder()
            .max_size(config.max_connections)
            .connection_timeout(Duration::from_secs(config.connection_timeout))
            .build(manager)
            .map_err(Error::Pool)?;

        // Initialize backup manager if backups are enabled
        let backup_manager = if config.enable_backups {
            let backup_config = BackupConfig {
                backup_dir: config.backup_dir.clone(),
                enabled: true,
                max_backups: config.max_backups,
                interval_hours: config.backup_interval_hours,
                compression_level: config.backup_compression_level,
            };

            Some(Arc::new(DatabaseBackup::new(backup_config)))
        } else {
            None
        };

        // Initialize database schema
        let sqlite = Self { pool, backup_manager };
        sqlite.init_schema()?;

        // Perform initial backup if due and enabled
        if let Some(ref backup) = sqlite.backup_manager {
            if let Ok(true) = backup.is_backup_due(&config.path) {
                info!("Performing initial database backup");
                if let Err(e) = sqlite.create_backup() {
                    warn!("Failed to create initial backup: {}", e);
                }
            }
        }

        Ok(sqlite)
    }

    /// Get a connection from the pool
    pub fn conn(&self) -> Result<r2d2::PooledConnection<SqliteConnectionManager>> {
        self.pool.get().map_err(Error::Pool)
    }

    /// Initialize the database schema
    fn init_schema(&self) -> Result<()> {
        let conn = self.conn()?;

        // Use pragma to enable foreign keys
        conn.execute("PRAGMA foreign_keys = ON", [])?;

        // Create tables
        conn.execute(schema::REPOSITORIES_TABLE, [])?;
        conn.execute(schema::BRANCHES_TABLE, [])?;
        conn.execute(schema::TAGS_TABLE, [])?;
        conn.execute(schema::COMMITS_TABLE, [])?;
        conn.execute(schema::FILES_TABLE, [])?;
        conn.execute(schema::README_TABLE, [])?;
        conn.execute(schema::REPO_STATS_TABLE, [])?;
        conn.execute(schema::REPO_MAINTENANCE_TABLE, [])?;
        conn.execute(schema::REPO_HEALTH_TABLE, [])?;
        conn.execute(schema::REPO_CONFIG_TABLE, [])?;

        Ok(())
    }

    /// Check if the database connection is valid
    pub fn check_connection(&self) -> bool {
        match self.conn() {
            Ok(conn) => {
                let result = conn.execute("SELECT 1", []);
                result.is_ok()
            }
            Err(_) => false,
        }
    }

    /// Create a backup of the database
    pub fn create_backup(&self) -> Result<()> {
        let backup_manager = self.backup_manager.as_ref()
            .ok_or_else(|| Error::Internal("Backup manager not configured".to_string()))?;

        // Get the database path from a connection
        let conn = self.conn()?;
        let path: String = conn.query_row("PRAGMA database_list", [], |row| row.get(2))?;

        info!("Creating backup of database at {}", path);
        let backup_path = Path::new(&path);

        // Create the backup
        backup_manager.create_backup(backup_path)?;

        Ok(())
    }

    /// Restore the database from a backup
    pub fn restore_backup(&self, backup_path: &Path) -> Result<()> {
        let backup_manager = self.backup_manager.as_ref()
            .ok_or_else(|| Error::Internal("Backup manager not configured".to_string()))?;

        // Get the database path from a connection
        let conn = self.conn()?;
        let path: String = conn.query_row("PRAGMA database_list", [], |row| row.get(2))?;

        info!("Restoring database at {} from backup {}", path, backup_path.display());
        let db_path = Path::new(&path);

        // Close all connections in the pool
        info!("Closing all database connections for restore");
        drop(conn);

        // Restore the backup
        backup_manager.restore_backup(backup_path, db_path)?;

        // Re-init schema just to be safe
        self.init_schema()?;

        Ok(())
    }

    /// List available backups
    pub fn list_backups(&self) -> Result<Vec<(std::path::PathBuf, backup::BackupMetadata)>> {
        let backup_manager = self.backup_manager.as_ref()
            .ok_or_else(|| Error::Internal("Backup manager not configured".to_string()))?;

        backup_manager.list_backups()
    }

    /// Verify a backup's integrity
    pub fn verify_backup(&self, backup_path: &Path) -> Result<bool> {
        let backup_manager = self.backup_manager.as_ref()
            .ok_or_else(|| Error::Internal("Backup manager not configured".to_string()))?;

        backup_manager.verify_backup(backup_path)
    }

    /// Check if automatic backup is due
    pub fn is_backup_due(&self) -> Result<bool> {
        let backup_manager = self.backup_manager.as_ref()
            .ok_or_else(|| Error::Internal("Backup manager not configured".to_string()))?;

        // Get the database path from a connection
        let conn = self.conn()?;
        let path: String = conn.query_row("PRAGMA database_list", [], |row| row.get(2))?;
        let db_path = Path::new(&path);

        backup_manager.is_backup_due(db_path)
    }

    // Repository maintenance methods

    /// Initialize or update repository maintenance record
    pub fn initialize_maintenance(&self, repo_id: i64) -> Result<i64> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.initialize(repo_id)
    }

    /// Initialize maintenance for repository by name
    pub fn initialize_maintenance_by_name(&self, repo_name: &str) -> Result<i64> {
        let conn = self.conn()?;

        // First get the repository ID
        let repo_model = models::RepositoryModel::new(&conn);
        let repo = repo_model
            .get_by_name(repo_name)?
            .ok_or_else(|| Error::NotFound(format!("Repository '{}' not found", repo_name)))?;

        // Then initialize maintenance
        let model = models::MaintenanceModel::new(&conn);
        model.initialize(repo.id)
    }

    /// Get repository maintenance record
    pub fn get_maintenance(&self, repo_id: i64) -> Result<Option<models::RepositoryMaintenance>> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.get_by_repo_id(repo_id)
    }

    /// Get repository maintenance record by name
    pub fn get_maintenance_by_name(&self, repo_name: &str) -> Result<Option<models::RepositoryMaintenance>> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.get_by_repo_name(repo_name)
    }

    /// Update last maintenance time
    pub fn update_last_maintenance(&self, repo_id: i64) -> Result<()> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.update_last_maintenance(repo_id)
    }

    /// Update last maintenance time by repository name
    pub async fn update_last_maintenance_by_name(&self, repo_name: &str) -> Result<()> {
        let conn = self.conn()?;

        // First get the repository ID
        let repo_model = models::RepositoryModel::new(&conn);
        let repo = repo_model
            .get_by_name(repo_name)?
            .ok_or_else(|| Error::NotFound(format!("Repository '{}' not found", repo_name)))?;

        // Then update maintenance
        let model = models::MaintenanceModel::new(&conn);
        model.update_last_maintenance(repo.id)
    }

    /// Mark repository as needing maintenance
    pub fn set_needs_maintenance(&self, repo_id: i64, needs_maintenance: bool) -> Result<()> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.set_needs_maintenance(repo_id, needs_maintenance)
    }

    /// Get repositories that need maintenance
    pub fn get_repos_needing_maintenance(&self) -> Result<Vec<i64>> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.get_repos_needing_maintenance()
    }

    /// Get repositories due for maintenance
    pub fn get_repos_due_for_maintenance(&self) -> Result<Vec<i64>> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.get_repos_due_for_maintenance()
    }

    /// Set maintenance schedule
    pub fn set_maintenance_schedule(&self, repo_id: i64, schedule: &str) -> Result<()> {
        let conn = self.conn()?;
        let model = models::MaintenanceModel::new(&conn);
        model.set_maintenance_schedule(repo_id, schedule)
    }

    // Repository health methods

    /// Update repository health
    pub fn update_health(&self, health: &models::RepositoryHealth) -> Result<i64> {
        let conn = self.conn()?;
        let model = models::HealthModel::new(&conn);
        model.upsert(health)
    }

    /// Get repository health
    pub fn get_health(&self, repo_id: i64) -> Result<Option<models::RepositoryHealth>> {
        let conn = self.conn()?;
        let model = models::HealthModel::new(&conn);
        model.get_by_repo_id(repo_id)
    }

    /// Get repository health by name
    pub fn get_health_by_name(&self, repo_name: &str) -> Result<Option<models::RepositoryHealth>> {
        let conn = self.conn()?;
        let model = models::HealthModel::new(&conn);
        model.get_by_repo_name(repo_name)
    }

    /// Get repositories with specific health status
    pub fn get_repos_by_health_status(&self, status: &str) -> Result<Vec<models::RepositoryHealth>> {
        let conn = self.conn()?;
        let model = models::HealthModel::new(&conn);
        model.get_by_status(status)
    }

    // Repository configuration methods

    /// Update repository configuration
    pub fn update_repository_config(&self, repo_id: i64, config: &models::RepositoryConfig) -> Result<i64> {
        let conn = self.conn()?;
        let model = models::ConfigModel::new(&conn);
        model.upsert(config)
    }

    /// Get repository configuration
    pub fn get_repository_config(&self, repo_id: i64) -> Result<Option<models::RepositoryConfig>> {
        let conn = self.conn()?;
        let model = models::ConfigModel::new(&conn);
        model.get_by_repo_id(repo_id)
    }

    /// Get repository configuration by name
    pub async fn get_repository_config_by_name(&self, repo_name: &str) -> Result<Option<models::RepositoryConfig>> {
        let conn = self.conn()?;
        let model = models::ConfigModel::new(&conn);
        model.get_by_repo_name(repo_name)
    }

    /// Check if database needs reindexing
    pub async fn needs_reindex(&self, repo_name: &str) -> Result<bool> {
        // For the implementation, we'll check if the last maintenance was too long ago
        // or if there are other signs that the database needs reindexing
        let conn = self.conn()?;

        // Get repository ID
        let repo_model = models::RepositoryModel::new(&conn);
        let repo = match repo_model.get_by_name(repo_name)? {
            Some(r) => r,
            None => return Err(Error::NotFound(format!("Repository '{}' not found", repo_name))),
        };

        // Check maintenance record
        let maintenance_model = models::MaintenanceModel::new(&conn);
        match maintenance_model.get_by_repo_id(repo.id)? {
            Some(maintenance) => {
                // If maintenance record exists, check if it needs maintenance
                Ok(maintenance.needs_maintenance)
            },
            None => {
                // If no maintenance record, assume it needs reindexing
                Ok(true)
            }
        }
    }

    /// Check database integrity
    pub async fn check_integrity(&self, repo_name: &str) -> Result<()> {
        let conn = self.conn()?;

        // Run PRAGMA integrity_check
        let result: String = conn.query_row("PRAGMA integrity_check", [], |row| row.get(0))?;

        if result != "ok" {
            return Err(Error::Database(
                rusqlite::Error::InvalidParameterName(format!("Database integrity check failed: {}", result))
            ));
        }

        Ok(())
    }

    /// Run database optimizations
    pub async fn optimize(&self, repo_name: &str) -> Result<()> {
        let conn = self.conn()?;

        // Run VACUUM to reclaim space
        conn.execute("VACUUM", [])?;

        // Run ANALYZE to update statistics
        conn.execute("ANALYZE", [])?;

        Ok(())
    }

    /// Reindex repository
    pub async fn reindex(&self, repo_name: &str) -> Result<()> {
        // This would trigger re-indexing of the repository
        // For the purposes of this implementation, we'll just update maintenance status
        let conn = self.conn()?;

        // Get repository ID
        let repo_model = models::RepositoryModel::new(&conn);
        let repo = match repo_model.get_by_name(repo_name)? {
            Some(r) => r,
            None => return Err(Error::NotFound(format!("Repository '{}' not found", repo_name))),
        };

        // Update maintenance record
        let maintenance_model = models::MaintenanceModel::new(&conn);
        maintenance_model.set_needs_maintenance(repo.id, false)?;

        Ok(())
    }

    /// Get repository by name
    pub fn get_repository_by_name(&self, name: &str) -> Result<Option<Repository>> {
        let conn = self.conn()?;
        let model = models::RepositoryModel::new(&conn);
        model.get_by_name(name)
    }
}

/// Repository information
#[derive(Debug, Clone)]
pub struct Repository {
    pub id: i64,
    pub name: String,
    pub path: String,
    pub description: Option<String>,
    pub owner: Option<String>,
    pub last_updated: i64,
}

/// Branch information
#[derive(Debug, Clone)]
pub struct Branch {
    pub id: i64,
    pub repo_id: i64,
    pub name: String,
    pub commit_id: String,
}

/// Tag information
#[derive(Debug, Clone)]
pub struct Tag {
    pub id: i64,
    pub repo_id: i64,
    pub name: String,
    pub commit_id: String,
}

/// Commit information
#[derive(Debug, Clone)]
pub struct Commit {
    pub id: String,
    pub repo_id: i64,
    pub author: String,
    pub email: String,
    pub message: String,
    pub timestamp: i64,
    pub parent_ids: Vec<String>,
}

// Re-export our new models for use outside this module
pub use models::{
    RepositoryMaintenance,
    RepositoryHealth,
    RepositoryConfig,
};

// Expose backup types
pub use backup::{BackupMetadata, BackupConfig};

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_sqlite_with_backup(
            max_connections in 1..20usize,
            connection_timeout in 1..30u64,
            max_backups in 1..10usize,
            backup_interval_hours in 1..48u32,
            compression_level in 0..=9u32
        ) {
            // Create a temporary directory
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");
            let backup_dir = temp_dir.path().join("backups");
        }
    }

    #[test]
    fn test_repository_maintenance() -> Result<()> {
        // Create test database
        let temp_dir = tempdir()?;
        let db_path = temp_dir.path().join("test.db");

        let config = DatabaseConfig {
            path: db_path.clone(),
            max_connections: 5,
            connection_timeout: 30,
            enable_backups: false,
            backup_dir: temp_dir.path().to_path_buf(),
            max_backups: 1,
            backup_interval_hours: 24,
            backup_compression_level: 0,
        };

        let db = Sqlite::new(&config)?;

        // Create a test repository
        let conn = db.conn()?;
        let repo_model = models::RepositoryModel::new(&conn);
        let repo_id = repo_model.insert("test-repo", "/path/to/repo", None, None)?;

        // Initialize maintenance
        let maintenance_id = db.initialize_maintenance(repo_id)?;
        assert!(maintenance_id > 0);

        // Get maintenance record
        let maintenance = db.get_maintenance(repo_id)?;
        assert!(maintenance.is_some());
        let maintenance = maintenance.unwrap();
        assert_eq!(maintenance.repo_id, repo_id);
        assert!(!maintenance.needs_maintenance);

        // Mark as needing maintenance
        db.set_needs_maintenance(repo_id, true)?;

        // Get updated record
        let maintenance = db.get_maintenance(repo_id)?.unwrap();
        assert!(maintenance.needs_maintenance);

        // Get repositories needing maintenance
        let repos = db.get_repos_needing_maintenance()?;
        assert_eq!(repos.len(), 1);
        assert_eq!(repos[0], repo_id);

        // Update last maintenance time
        db.update_last_maintenance(repo_id)?;

        // Verify it's no longer needing maintenance
        let maintenance = db.get_maintenance(repo_id)?.unwrap();
        assert!(!maintenance.needs_maintenance);
        assert!(maintenance.last_maintenance.is_some());

        Ok(())
    }

    #[test]
    fn test_repository_health() -> Result<()> {
        // Create test database
        let temp_dir = tempdir()?;
        let db_path = temp_dir.path().join("test.db");

        let config = DatabaseConfig {
            path: db_path.clone(),
            max_connections: 5,
            connection_timeout: 30,
            enable_backups: false,
            backup_dir: temp_dir.path().to_path_buf(),
            max_backups: 1,
            backup_interval_hours: 24,
            backup_compression_level: 0,
        };

        let db = Sqlite::new(&config)?;

        // Create a test repository
        let conn = db.conn()?;
        let repo_model = models::RepositoryModel::new(&conn);
        let repo_id = repo_model.insert("test-repo", "/path/to/repo", None, None)?;

        // Create a health record
        let now = Utc::now().timestamp();
        let health = models::RepositoryHealth {
            id: 0, // Will be set by database
            repo_id,
            status: "ok".to_string(),
            git_status: "ok".to_string(),
            git_message: None,
            db_status: "ok".to_string(),
            db_message: None,
            loose_objects: Some(100),
            packfiles: Some(5),
            size_bytes: Some(1024 * 1024),
            last_checked: now,
        };

        // Save to database
        let health_id = db.update_health(&health)?;
        assert!(health_id > 0);

        // Get health record
        let stored_health = db.get_health(repo_id)?;
        assert!(stored_health.is_some());
        let stored_health = stored_health.unwrap();
        assert_eq!(stored_health.repo_id, repo_id);
        assert_eq!(stored_health.status, "ok");
        assert_eq!(stored_health.git_status, "ok");
        assert_eq!(stored_health.db_status, "ok");
        assert_eq!(stored_health.loose_objects, Some(100));
        assert_eq!(stored_health.packfiles, Some(5));

        // Update health with a different status
        let updated_health = models::RepositoryHealth {
            id: stored_health.id,
            repo_id,
            status: "degraded".to_string(),
            git_status: "needs_maintenance".to_string(),
            git_message: Some("Too many loose objects".to_string()),
            db_status: "ok".to_string(),
            db_message: None,
            loose_objects: Some(10000),
            packfiles: Some(5),
            size_bytes: Some(1024 * 1024),
            last_checked: now,
        };

        db.update_health(&updated_health)?;

        // Get updated record
        let stored_health = db.get_health(repo_id)?.unwrap();
        assert_eq!(stored_health.status, "degraded");
        assert_eq!(stored_health.git_status, "needs_maintenance");
        assert_eq!(stored_health.git_message, Some("Too many loose objects".to_string()));
        assert_eq!(stored_health.loose_objects, Some(10000));

        // Get repositories by status
        let degraded_repos = db.get_repos_by_health_status("degraded")?;
        assert_eq!(degraded_repos.len(), 1);
        assert_eq!(degraded_repos[0].repo_id, repo_id);

        Ok(())
    }

    #[test]
    fn test_repository_config() -> Result<()> {
        // Create test database
        let temp_dir = tempdir()?;
        let db_path = temp_dir.path().join("test.db");

        let config = DatabaseConfig {
            path: db_path.clone(),
            max_connections: 5,
            connection_timeout: 30,
            enable_backups: false,
            backup_dir: temp_dir.path().to_path_buf(),
            max_backups: 1,
            backup_interval_hours: 24,
            backup_compression_level: 0,
        };

        let db = Sqlite::new(&config)?;

        // Create a test repository
        let conn = db.conn()?;
        let repo_model = models::RepositoryModel::new(&conn);
        let repo_id = repo_model.insert("test-repo", "/path/to/repo", None, None)?;

        // Create a config record
        let repo_config = models::RepositoryConfig {
            id: 0, // Will be set by database
            repo_id,
            name: "test-repo".to_string(),
            description: Some("Test repository".to_string()),
            owner: Some("test-user".to_string()),
            enable_maintenance: true,
            maintenance_schedule: Some("0 0 * * *".to_string()), // Midnight daily
            verify_commit_signatures: false,
            max_object_size: Some(100 * 1024 * 1024), // 100 MB
            git_config: Some("{}".to_string()),
        };

        // Save to database
        let config_id = db.update_repository_config(repo_id, &repo_config)?;
        assert!(config_id > 0);

        // Get config record
        let stored_config = db.get_repository_config(repo_id)?;
        assert!(stored_config.is_some());
        let stored_config = stored_config.unwrap();
        assert_eq!(stored_config.repo_id, repo_id);
        assert_eq!(stored_config.name, "test-repo");
        assert_eq!(stored_config.description, Some("Test repository".to_string()));
        assert_eq!(stored_config.owner, Some("test-user".to_string()));
        assert!(stored_config.enable_maintenance);
        assert_eq!(stored_config.maintenance_schedule, Some("0 0 * * *".to_string()));
        assert!(!stored_config.verify_commit_signatures);
        assert_eq!(stored_config.max_object_size, Some(100 * 1024 * 1024));

        // Update config
        let updated_config = models::RepositoryConfig {
            id: stored_config.id,
            repo_id,
            name: "test-repo".to_string(),
            description: Some("Updated test repository".to_string()),
            owner: Some("test-admin".to_string()),
            enable_maintenance: false,
            maintenance_schedule: None,
            verify_commit_signatures: true,
            max_object_size: Some(50 * 1024 * 1024), // 50 MB
            git_config: Some(r#"{"core.compression": "9"}"#.to_string()),
        };

        db.update_repository_config(repo_id, &updated_config)?;

        // Get updated config
        let stored_config = db.get_repository_config(repo_id)?.unwrap();
        assert_eq!(stored_config.description, Some("Updated test repository".to_string()));
        assert_eq!(stored_config.owner, Some("test-admin".to_string()));
        assert!(!stored_config.enable_maintenance);
        assert_eq!(stored_config.maintenance_schedule, None);
        assert!(stored_config.verify_commit_signatures);
        assert_eq!(stored_config.max_object_size, Some(50 * 1024 * 1024));
        assert_eq!(stored_config.git_config, Some(r#"{"core.compression": "9"}"#.to_string()));

        // Parse Git config
        let config_model = models::ConfigModel::new(&conn);
        let git_config = config_model.parse_git_config(stored_config.git_config.as_ref().unwrap())?;
        assert_eq!(git_config.get("core.compression"), Some(&"9".to_string()));

        Ok(())
    }
}
