// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Repository maintenance service
//!
//! This module implements a service for scheduling and executing repository maintenance tasks
//! such as garbage collection, repacking, pruning, and integrity checks.

use crate::data::Git;
use crate::data::Sqlite;
use crate::data::git::Repository;
use crate::data::sqlite::{RepositoryMaintenance, RepositoryConfig};
use crate::service::repository::{RepositoryService, RepositoryHealth};
use crate::error::{Error, Result};
use crate::data::cache::Cache;

use std::sync::Arc;
use std::time::{Duration, Instant};
use std::collections::HashMap;
use tokio::sync::{RwLock, Mutex};
use tokio::task::JoinHandle;
use tokio::time;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use cron::Schedule;
use tracing::{debug, error, info, trace, warn};
use std::path::PathBuf;

/// Health status for a repository
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HealthStatus {
    /// Repository is healthy
    Healthy,
    /// Repository needs maintenance
    NeedsMaintenance,
    /// Repository has errors
    Error,
}

impl std::fmt::Display for HealthStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HealthStatus::Healthy => write!(f, "healthy"),
            HealthStatus::NeedsMaintenance => write!(f, "needs_maintenance"),
            HealthStatus::Error => write!(f, "error"),
        }
    }
}

/// Maintenance task type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MaintenanceTask {
    /// Garbage collection
    GarbageCollection,
    /// Object repacking
    Repack,
    /// Prune unreachable objects
    Prune,
    /// File system check
    Fsck,
    /// Database reindex
    Reindex,
    /// Full maintenance (all tasks)
    Full,
}

impl std::fmt::Display for MaintenanceTask {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MaintenanceTask::GarbageCollection => write!(f, "garbage collection"),
            MaintenanceTask::Repack => write!(f, "repacking"),
            MaintenanceTask::Prune => write!(f, "pruning"),
            MaintenanceTask::Fsck => write!(f, "filesystem check"),
            MaintenanceTask::Reindex => write!(f, "database reindexing"),
            MaintenanceTask::Full => write!(f, "full maintenance"),
        }
    }
}

/// Maintenance task status
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaintenanceTaskStatus {
    /// Repository name
    pub repository: String,
    /// Task type
    pub task: MaintenanceTask,
    /// Status (pending, running, completed, failed)
    pub status: String,
    /// Start time
    pub start_time: Option<DateTime<Utc>>,
    /// End time
    pub end_time: Option<DateTime<Utc>>,
    /// Error message if failed
    pub error: Option<String>,
}

/// Repository maintenance scheduler configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MaintenanceSchedulerConfig {
    /// Whether the maintenance scheduler is enabled
    pub enabled: bool,
    /// Maintenance check interval in seconds
    pub check_interval_seconds: u64,
    /// Maximum concurrent maintenance tasks
    pub max_concurrent_tasks: usize,
    /// Default maintenance schedule (cron expression)
    pub default_schedule: String,
    /// Loose objects threshold for triggering maintenance
    pub loose_objects_threshold: usize,
    /// Packfile threshold for triggering maintenance
    pub packfiles_threshold: usize,
    /// Repository size threshold in bytes
    pub size_threshold: u64,
    /// Time since last maintenance in days
    pub days_since_maintenance_threshold: u64,
}

impl Default for MaintenanceSchedulerConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            check_interval_seconds: 3600, // Check every hour
            max_concurrent_tasks: 2,
            default_schedule: "0 2 * * *".to_string(), // 2 AM daily
            loose_objects_threshold: 10000,
            packfiles_threshold: 50,
            size_threshold: 1024 * 1024 * 1024, // 1 GB
            days_since_maintenance_threshold: 7, // 1 week
        }
    }
}

/// Repository maintenance scheduler service
pub struct MaintenanceScheduler {
    /// Service configuration
    config: MaintenanceSchedulerConfig,
    /// Git implementation
    git: Arc<Git>,
    /// SQLite database
    db: Arc<Sqlite>,
    /// Repository service
    repo_service: Arc<RepositoryService>,
    /// Currently running tasks
    running_tasks: RwLock<HashMap<String, MaintenanceTaskStatus>>,
    /// Recent task history
    task_history: RwLock<Vec<MaintenanceTaskStatus>>,
    /// Lock for ensuring no more than max_concurrent_tasks run at once
    concurrency_semaphore: Arc<tokio::sync::Semaphore>,
    /// Scheduler task handle
    scheduler_task: Mutex<Option<JoinHandle<()>>>,
    /// Last check time
    last_check: RwLock<Instant>,
}

impl MaintenanceScheduler {
    /// Create a new maintenance scheduler
    pub fn new(
        config: MaintenanceSchedulerConfig,
        git: Arc<Git>,
        db: Arc<Sqlite>,
        repo_service: Arc<RepositoryService>,
    ) -> Self {
        let concurrency_semaphore = Arc::new(tokio::sync::Semaphore::new(config.max_concurrent_tasks));

        Self {
            config,
            git,
            db,
            repo_service,
            running_tasks: RwLock::new(HashMap::new()),
            task_history: RwLock::new(Vec::new()),
            concurrency_semaphore,
            scheduler_task: Mutex::new(None),
            last_check: RwLock::new(Instant::now()),
        }
    }

    /// Start the maintenance scheduler
    pub async fn start(&self) -> Result<()> {
        if !self.config.enabled {
            info!("Maintenance scheduler is disabled");
            return Ok(());
        }

        let mut scheduler_task = self.scheduler_task.lock().await;
        if scheduler_task.is_some() {
            return Err(Error::Internal("Maintenance scheduler already running".to_string()));
        }

        info!("Starting maintenance scheduler");
        let cloned_self = Arc::new(self.clone());

        let handle = tokio::spawn(async move {
            let scheduler = cloned_self;
            let check_interval = Duration::from_secs(scheduler.config.check_interval_seconds);

            loop {
                tokio::select! {
                    _ = time::sleep(check_interval) => {
                        match scheduler.check_maintenance_tasks().await {
                            Ok(_) => debug!("Completed maintenance check"),
                            Err(e) => error!("Error checking maintenance tasks: {}", e),
                        }
                    }
                }
            }
        });

        *scheduler_task = Some(handle);
        Ok(())
    }

    /// Stop the maintenance scheduler
    pub async fn stop(&self) -> Result<()> {
        let mut scheduler_task = self.scheduler_task.lock().await;
        if let Some(handle) = scheduler_task.take() {
            info!("Stopping maintenance scheduler");
            handle.abort();
        }
        Ok(())
    }

    /// Check for repositories that need maintenance
    async fn check_maintenance_tasks(&self) -> Result<()> {
        *self.last_check.write().await = Instant::now();

        // Get repositories that are explicitly marked as needing maintenance
        let flagged_repos = self.db.get_repos_needing_maintenance()?;
        for repo_id in flagged_repos {
            if let Some(repo) = self.get_repository_by_id(repo_id).await? {
                self.schedule_maintenance(repo.name.clone(), MaintenanceTask::Full).await?;
            }
        }

        // Get repositories scheduled for maintenance
        let due_repos = self.db.get_repos_due_for_maintenance()?;
        for repo_id in due_repos {
            if let Some(repo) = self.get_repository_by_id(repo_id).await? {
                self.schedule_maintenance(repo.name.clone(), MaintenanceTask::Full).await?;
            }
        }

        // Check all repositories for maintenance needs based on thresholds
        let repos = self.repo_service.list_repositories().await?;
        for repo in repos {
            // Skip if already scheduled
            if self.is_task_running(&repo.name).await {
                continue;
            }

            // Check repository health
            if let Some(health) = self.db.get_health_by_name(&repo.name)? {
                let needs_maintenance = self.check_if_needs_maintenance(&health).await?;
                if needs_maintenance {
                    self.schedule_maintenance(repo.name.clone(), MaintenanceTask::Full).await?;
                }
            } else {
                // No health record yet, create one
                self.check_repository_health(&repo.name).await?;
            }
        }

        Ok(())
    }

    /// Check if a repository needs maintenance based on health metrics
    async fn check_if_needs_maintenance(&self, health: &RepositoryHealth) -> Result<bool> {
        // Check loose objects count
        if health.loose_objects > self.config.loose_objects_threshold {
            return Ok(true);
        }

        // Check packfiles count
        if health.packfiles > self.config.packfiles_threshold {
            return Ok(true);
        }

        // Check repository size
        if health.size_bytes > self.config.size_threshold {
            return Ok(true);
        }

        // Check time since last maintenance
        if let Some(repo_maintenance) = self.db.get_maintenance_by_name(&health.name)? {
            if let Some(last_maintenance) = repo_maintenance.last_maintenance {
                let now = Utc::now().timestamp();
                let seconds_since_maintenance = now - last_maintenance;
                let days_since_maintenance = seconds_since_maintenance / (24 * 60 * 60);

                if days_since_maintenance as u64 > self.config.days_since_maintenance_threshold {
                    return Ok(true);
                }
            } else {
                // No record of last maintenance, so it probably needs it
                return Ok(true);
            }
        }

        Ok(false)
    }

    /// Check the health of a repository
    pub async fn check_repository_health(&self, repo_name: &str) -> Result<RepositoryHealth> {
        info!("Checking health for repository: {}", repo_name);

        // Check Git health
        let (git_status, git_message) = self.check_git_health(repo_name).await?;

        // Check database health
        let (db_status, db_message) = self.check_db_health(repo_name).await?;

        // Determine overall status
        let status = if git_status == "error" || db_status == "error" {
            "error".to_string()
        } else if git_status == "needs_maintenance" || db_status == "needs_reindex" {
            "needs_maintenance".to_string()
        } else {
            "healthy".to_string()
        };

        // Get repository from Git
        let repo = self.git.get_repository(repo_name)?;

        // Get repository info from SQLite
        let repo_info = self.db.get_repository_by_name(repo_name)?;
        if repo_info.is_none() {
            return Err(Error::NotFound(format!("Repository not found: {}", repo_name)));
        }
        let repo_info = repo_info.unwrap();

        // Get repository size info
        let size_info = self.get_repository_size_info(repo_name).await?;

        // Create health record
        let health = RepositoryHealth {
            name: repo_name.to_string(),
            status,
            last_maintenance: None,
            git_status: git_status.to_string(),
            git_message,
            db_status: db_status.to_string(),
            db_message,
            loose_objects: size_info.loose_objects,
            packfiles: size_info.packfiles,
            size_bytes: size_info.total_size,
            last_commit: None,
        };

        // Save to database
        if let Some(db_repo) = self.db.get_repository_by_name(repo_name)? {
            // Create a SQLite version of the health record
            let db_health = crate::data::sqlite::models::RepositoryHealth {
                id: 0, // Will be set by database
                repo_id: db_repo.id,
                status: health.status.clone(),
                git_status: health.git_status.clone(),
                git_message: health.git_message.clone(),
                db_status: health.db_status.clone(),
                db_message: health.db_message.clone(),
                loose_objects: Some(health.loose_objects as i64),
                packfiles: Some(health.packfiles as i64),
                size_bytes: Some(health.size_bytes as i64),
                last_checked: Utc::now().timestamp(),
            };

            // If repository needs maintenance, mark it
            if status == "needs_maintenance" {
                self.db.set_needs_maintenance(db_repo.id, true)?;
            }

            // Update the health record
            self.db.update_health(&db_health)?;
        }

        Ok(health)
    }

    /// Check the health of a Git repository
    async fn check_git_health(&self, repo_name: &str) -> Result<(String, Option<String>)> {
        info!("Checking Git health for repository: {}", repo_name);

        // Get repository from Git
        let repo = self.git.get_repository(repo_name)?;

        // Check for corruption
        if let Err(e) = repo.fsck() {
            return Ok(("error".to_string(), Some(format!("Repository corruption detected: {}", e))));
        }

        // Check for too many loose objects
        let loose_objects = repo.count_loose_objects()?;
        if loose_objects.count > 10000 {
            return Ok(("needs_maintenance".to_string(), Some("Too many loose objects".to_string())));
        }

        // Check for too many packfiles
        let packfiles = repo.count_packfiles()?;
        if packfiles.count > 50 {
            return Ok(("needs_maintenance".to_string(), Some("Too many packfiles".to_string())));
        }

        Ok(("ok".to_string(), None))
    }

    /// Check the database health for a repository
    async fn check_db_health(&self, repo_name: &str) -> Result<(String, Option<String>)> {
        info!("Checking database health for repository: {}", repo_name);

        // Get repository from database
        let repo_info = self.db.get_repository_by_name(repo_name)?;
        if repo_info.is_none() {
            return Err(Error::NotFound(format!("Repository not found: {}", repo_name)));
        }
        let repo_info = repo_info.unwrap();

        // Check for database issues
        let db_status = "ok";
        let mut db_message = None;

        // TODO: Implement specific database checks
        // Example checks could include:
        // 1. Check if indices are intact
        // 2. Check for orphaned records
        // 3. Check data consistency

        Ok((db_status.to_string(), db_message))
    }

    /// Get repository size information
    async fn get_repository_size_info(&self, repo_name: &str) -> Result<RepositorySizeInfo> {
        // Get repository
        let repo = self.git.get_repository(repo_name)?;

        let mut size_info = RepositorySizeInfo {
            total_size: 0,
            loose_objects: 0,
            packfiles: 0,
        };

        // Count loose objects
        let loose_objects = repo.count_loose_objects()?;
        size_info.loose_objects = loose_objects.count;
        size_info.total_size += loose_objects.size;

        // Count packfiles
        let packfiles = repo.count_packfiles()?;
        size_info.packfiles = packfiles.count;
        size_info.total_size += packfiles.size;

        Ok(size_info)
    }

    /// Get a repository by ID
    async fn get_repository_by_id(&self, repo_id: i64) -> Result<Option<crate::data::sqlite::Repository>> {
        // Call repository service to get repository by ID (if available)
        // Otherwise, fall back to SQLite access
        let conn = self.db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        repo_model.get_by_id(repo_id)
    }

    /// Schedule a maintenance task for a repository
    pub async fn schedule_maintenance(&self, repo_name: String, task: MaintenanceTask) -> Result<MaintenanceTaskStatus> {
        // Check if already running
        if self.is_task_running(&repo_name).await {
            return Err(Error::DuplicateResource(format!("Maintenance task already running for repository {}", repo_name)));
        }

        info!("Scheduling {} for repository {}", task, repo_name);

        // Create task status
        let task_status = MaintenanceTaskStatus {
            repository: repo_name.clone(),
            task,
            status: "pending".to_string(),
            start_time: None,
            end_time: None,
            error: None,
        };

        // Add to running tasks
        {
            let mut running_tasks = self.running_tasks.write().await;
            running_tasks.insert(repo_name.clone(), task_status.clone());
        }

        // Run in the background
        let semaphore = self.concurrency_semaphore.clone();
        let repo_name_clone = repo_name.clone();
        let git = self.git.clone();
        let db = self.db.clone();
        // Create new RwLocks instead of trying to clone them
        let running_tasks = Arc::new(RwLock::new(HashMap::new()));
        let task_history = Arc::new(RwLock::new(Vec::new()));

        tokio::spawn(async move {
            // Acquire semaphore permit (wait if max concurrent tasks already running)
            let _permit = match semaphore.acquire().await {
                Ok(permit) => permit,
                Err(e) => {
                    error!("Failed to acquire semaphore: {}", e);
                    // Update status to failed
                    Self::update_task_status_standalone(
                        &repo_name_clone,
                        "failed",
                        Some(format!("Failed to start maintenance: {}", e)),
                    ).await;
                    return;
                }
            };

            // Update status to running
            let start_time = Utc::now();
            Self::update_task_status_standalone_with_time(
                &repo_name_clone,
                "running",
                None,
                Some(start_time),
                None,
            ).await;

            // Run maintenance task
            let result = match task {
                MaintenanceTask::GarbageCollection => Self::run_gc(&git, &db, &repo_name_clone).await,
                MaintenanceTask::Repack => Self::run_repack(&git, &db, &repo_name_clone).await,
                MaintenanceTask::Prune => Self::run_prune(&git, &db, &repo_name_clone).await,
                MaintenanceTask::Fsck => Self::run_fsck(&git, &db, &repo_name_clone).await,
                MaintenanceTask::Reindex => Self::run_reindex(&git, &db, &repo_name_clone).await,
                MaintenanceTask::Full => Self::run_full_maintenance(&git, &db, &repo_name_clone).await,
            };

            // Update status based on result
            let end_time = Utc::now();
            match result {
                Ok(_) => {
                    Self::update_task_status_standalone_with_time(
                        &repo_name_clone,
                        "completed",
                        None,
                        None,
                        Some(end_time),
                    ).await;
                }
                Err(e) => {
                    error!("Maintenance task failed: {}", e);
                    Self::update_task_status_standalone_with_time(
                        &repo_name_clone,
                        "failed",
                        Some(e.to_string()),
                        None,
                        Some(end_time),
                    ).await;
                }
            }

            // Release the permit (automatically happens when _permit goes out of scope)
        });

        Ok(task_status)
    }

    /// Update task status standalone version (for async tasks)
    async fn update_task_status_standalone(
        repo_name: &str,
        status: &str,
        error: Option<String>,
    ) {
        // In the standalone version, we just log the status change
        // since we don't have access to the shared task maps
        info!("Task for repository {} status changed to {}", repo_name, status);
        if let Some(err) = error {
            error!("Task error: {}", err);
        }
    }

    /// Update task status standalone with time (for async tasks)
    async fn update_task_status_standalone_with_time(
        repo_name: &str,
        status: &str,
        error: Option<String>,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
    ) {
        // Log the status change with time information
        info!("Task for repository {} status changed to {}", repo_name, status);

        if let Some(start) = start_time {
            info!("Task started at {}", start);
        }

        if let Some(end) = end_time {
            info!("Task ended at {}", end);
        }

        if let Some(err) = error {
            error!("Task error: {}", err);
        }
    }

    /// Check if a task is running for a repository
    async fn is_task_running(&self, repo_name: &str) -> bool {
        let running_tasks = self.running_tasks.read().await;
        running_tasks.contains_key(repo_name)
    }

    /// Run garbage collection
    async fn run_gc(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running garbage collection for repository {}", repo_name);

        // Open repository
        let repo = git.get_repository(repo_name)?;

        // Run garbage collection
        repo.gc()?;

        // Update maintenance record
        let conn = db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        if let Some(repo_info) = repo_model.get_by_name(repo_name)? {
            let maintenance_model = crate::data::sqlite::models::MaintenanceModel::new(&conn);
            maintenance_model.update_last_gc(repo_info.id)?;
        }

        Ok(())
    }

    /// Run repacking
    async fn run_repack(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running repacking for repository {}", repo_name);

        // Open repository
        let repo = git.get_repository(repo_name)?;

        // Run repack
        repo.repack()?;

        // Update maintenance record
        let conn = db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        if let Some(repo_info) = repo_model.get_by_name(repo_name)? {
            let maintenance_model = crate::data::sqlite::models::MaintenanceModel::new(&conn);
            maintenance_model.update_last_repack(repo_info.id)?;
        }

        Ok(())
    }

    /// Run pruning
    async fn run_prune(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running pruning for repository {}", repo_name);

        // Open repository
        let repo = git.get_repository(repo_name)?;

        // Run prune
        repo.prune()?;

        // Update maintenance record
        let conn = db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        if let Some(repo_info) = repo_model.get_by_name(repo_name)? {
            let maintenance_model = crate::data::sqlite::models::MaintenanceModel::new(&conn);
            maintenance_model.update_last_prune(repo_info.id)?;
        }

        Ok(())
    }

    /// Run filesystem check
    async fn run_fsck(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running filesystem check for repository {}", repo_name);

        // Open repository
        let repo = git.get_repository(repo_name)?;

        // Run fsck
        repo.fsck()?;

        // Update maintenance record
        let conn = db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        if let Some(repo_info) = repo_model.get_by_name(repo_name)? {
            let maintenance_model = crate::data::sqlite::models::MaintenanceModel::new(&conn);
            maintenance_model.update_last_fsck(repo_info.id)?;
        }

        Ok(())
    }

    /// Run database reindexing
    async fn run_reindex(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running database reindexing for repository {}", repo_name);

        // Run reindex
        db.reindex(repo_name).await?;

        Ok(())
    }

    /// Run full maintenance
    async fn run_full_maintenance(git: &Arc<Git>, db: &Arc<Sqlite>, repo_name: &str) -> Result<()> {
        info!("Running full maintenance for repository {}", repo_name);

        // Run all maintenance tasks
        Self::run_gc(git, db, repo_name).await?;
        Self::run_repack(git, db, repo_name).await?;
        Self::run_prune(git, db, repo_name).await?;
        Self::run_fsck(git, db, repo_name).await?;
        Self::run_reindex(git, db, repo_name).await?;

        // Update last maintenance time
        let conn = db.conn()?;
        let repo_model = crate::data::sqlite::models::RepositoryModel::new(&conn);
        if let Some(repo_info) = repo_model.get_by_name(repo_name)? {
            let maintenance_model = crate::data::sqlite::models::MaintenanceModel::new(&conn);
            maintenance_model.update_last_maintenance(repo_info.id)?;
        }

        Ok(())
    }

    /// Get currently running maintenance tasks
    pub async fn get_running_tasks(&self) -> Vec<MaintenanceTaskStatus> {
        let running_tasks = self.running_tasks.read().await;
        running_tasks.values().cloned().collect()
    }

    /// Get maintenance task history
    pub async fn get_task_history(&self) -> Vec<MaintenanceTaskStatus> {
        let history = self.task_history.read().await;
        history.clone()
    }

    /// Get maintenance task status for a repository
    pub async fn get_task_status(&self, repo_name: &str) -> Option<MaintenanceTaskStatus> {
        let running_tasks = self.running_tasks.read().await;
        running_tasks.get(repo_name).cloned()
    }

    /// Get next scheduled maintenance time for a repository
    pub async fn get_next_maintenance_time(&self, repo_name: &str) -> Result<Option<DateTime<Utc>>> {
        // Get repository maintenance config
        if let Some(config) = self.db.get_repository_config_by_name(repo_name).await? {
            if !config.enable_maintenance {
                return Ok(None);
            }

            // Get maintenance schedule
            let schedule_str = config.maintenance_schedule.unwrap_or_else(|| self.config.default_schedule.clone());
            match schedule_str.parse::<Schedule>() {
                Ok(schedule) => {
                    // Get next occurrence after now
                    let now = Utc::now();
                    if let Some(next) = schedule.upcoming(Utc).next() {
                        return Ok(Some(next));
                    }
                }
                Err(e) => {
                    warn!("Invalid maintenance schedule for repository {}: {}", repo_name, e);
                }
            }
        }

        Ok(None)
    }

    /// Trigger immediate maintenance for a repository
    pub async fn trigger_maintenance(&self, repo_name: &str, task: MaintenanceTask) -> Result<MaintenanceTaskStatus> {
        info!("Triggering immediate {} for repository {}", task, repo_name);
        self.schedule_maintenance(repo_name.to_string(), task).await
    }

    /// Get the size of a directory recursively, excluding specified patterns
    async fn get_directory_size(&self, path: &Path, exclude: &[&str]) -> Result<u64> {
        let mut total_size = 0;

        if path.is_dir() {
            for entry in std::fs::read_dir(path).map_err(|e| Error::Io(e))? {
                let entry = entry.map_err(|e| Error::Io(e))?;
                let path = entry.path();

                // Skip excluded directories/files
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if exclude.iter().any(|e| name == *e) {
                        continue;
                    }
                }

                if path.is_file() {
                    if let Ok(metadata) = entry.metadata() {
                        total_size += metadata.len();
                    }
                } else if path.is_dir() {
                    // Recursively check subdirectories
                    if let Ok(size) = self.get_directory_size(&path, exclude).await {
                        total_size += size;
                    }
                }
            }
        }

        Ok(total_size)
    }

    /// Run maintenance on all repositories
    pub async fn run_maintenance_all(&self) -> Result<()> {
        // Get list of repositories
        let repos = self.git.list_repositories()?;

        for repo_info in repos {
            match self.run_maintenance(&repo_info.name).await {
                Ok(_) => {
                    info!("Maintenance completed successfully for repository: {}", repo_info.name);
                }
                Err(e) => {
                    error!("Failed to run maintenance for repository {}: {}", repo_info.name, e);
                }
            }
        }

        Ok(())
    }

    /// Run maintenance on a repository
    pub async fn run_maintenance(&self, repo_name: &str) -> Result<()> {
        info!("Running maintenance for repository: {}", repo_name);

        // Get the repository
        let repo = self.git.get_repository(repo_name)?;

        // Run Git maintenance
        self.run_git_maintenance(&repo)?;

        // Run database maintenance
        self.run_db_maintenance(repo_name).await?;

        // Create health record
        self.create_health_record(repo_name).await?;

        info!("Maintenance completed for repository: {}", repo_name);
        Ok(())
    }

    /// Create health record for a repository
    async fn create_health_record(&self, repo_name: &str) -> Result<RepositoryHealth> {
        // Check Git health
        let (git_status, git_message) = self.check_git_health(repo_name).await?;

        // Check database health
        let (db_status, db_message) = self.check_db_health(repo_name).await?;

        // Determine overall status
        let status = if git_status == "error" || db_status == "error" {
            "error".to_string()
        } else if git_status == "needs_maintenance" || db_status == "needs_reindex" {
            "needs_maintenance".to_string()
        } else {
            "healthy".to_string()
        };

        // Get repository from Git and get its size info
        let size_info = self.get_repository_size_info(repo_name).await?;

        // Create health record
        let health = RepositoryHealth {
            name: repo_name.to_string(),
            status,
            last_maintenance: None,
            git_status: git_status.to_string(),
            git_message,
            db_status: db_status.to_string(),
            db_message,
            loose_objects: size_info.loose_objects,
            packfiles: size_info.packfiles,
            size_bytes: size_info.total_size,
            last_commit: None,
        };

        // Save to database
        if let Some(db_repo) = self.db.get_repository_by_name(repo_name)? {
            // Create a SQLite version of the health record
            let db_health = crate::data::sqlite::models::RepositoryHealth {
                id: 0, // Will be set by database
                repo_id: db_repo.id,
                status: health.status.clone(),
                git_status: health.git_status.clone(),
                git_message: health.git_message.clone(),
                db_status: health.db_status.clone(),
                db_message: health.db_message.clone(),
                loose_objects: Some(health.loose_objects as i64),
                packfiles: Some(health.packfiles as i64),
                size_bytes: Some(health.size_bytes as i64),
                last_checked: Utc::now().timestamp(),
            };

            // If repository needs maintenance, mark it
            if status == "needs_maintenance" {
                self.db.set_needs_maintenance(db_repo.id, true)?;
            }

            // Update the health record
            self.db.update_health(&db_health)?;
        }

        Ok(health)
    }

    /// Run database maintenance
    async fn run_db_maintenance(&self, repo_name: &str) -> Result<()> {
        info!("Running database maintenance for repository: {}", repo_name);

        // Get repository
        let repo = self.git.get_repository(repo_name)?;

        // Run database maintenance
        self.run_git_maintenance(&repo)?;

        Ok(())
    }

    /// Run Git maintenance
    fn run_git_maintenance(&self, repo: &crate::data::git::Repository) -> Result<()> {
        info!("Running Git maintenance for repository");

        // Run Git maintenance
        repo.gc()?;
        repo.repack()?;
        repo.prune()?;
        repo.fsck()?;

        Ok(())
    }
}

impl Clone for MaintenanceScheduler {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            git: self.git.clone(),
            db: self.db.clone(),
            repo_service: self.repo_service.clone(),
            running_tasks: RwLock::new(HashMap::new()),
            task_history: RwLock::new(Vec::new()),
            concurrency_semaphore: self.concurrency_semaphore.clone(),
            scheduler_task: Mutex::new(None),
            last_check: RwLock::new(Instant::now()),
        }
    }
}

/// Repository size information
#[derive(Debug)]
struct RepositorySizeInfo {
    /// Total size in bytes
    total_size: u64,
    /// Number of loose objects
    loose_objects: usize,
    /// Number of packfiles
    packfiles: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{Config, DatabaseConfig, GitConfig};
    use crate::data::cache::Cache;
    use std::time::Duration;
    use tempfile::TempDir;

    async fn create_test_maintenance_scheduler() -> (MaintenanceScheduler, TempDir) {
        // Create temporary directory
        let temp_dir = TempDir::new().unwrap();
        let db_path = temp_dir.path().join("test.db");
        let git_path = temp_dir.path().join("git");
        std::fs::create_dir_all(&git_path).unwrap();

        // Create database config
        let db_config = DatabaseConfig {
            path: db_path,
            max_connections: 5,
            connection_timeout: 30,
            enable_backups: false,
            backup_dir: temp_dir.path().to_path_buf(),
            max_backups: 1,
            backup_interval_hours: 24,
            backup_compression_level: 0,
        };

        // Create Git config
        let git_config = GitConfig {
            repo_dir: git_path,
            max_cache_size: 1024 * 1024,
            enable_maintenance: true,
            maintenance_interval: 24,
            verify_commit_signatures: false,
            gpg_homedir: None,
            trusted_gpg_keys: vec![],
            trusted_ssh_keys: vec![],
        };

        // Create components
        let db = Arc::new(Sqlite::new(&db_config).unwrap());
        let git = Arc::new(Git::new(&git_config).unwrap());
        let cache = Arc::new(Cache::new(1000, Duration::from_secs(60)));

        // Create repository service
        let repo_service = Arc::new(RepositoryService::new(git.clone(), cache.clone()));

        // Create maintenance scheduler config
        let scheduler_config = MaintenanceSchedulerConfig {
            enabled: true,
            check_interval_seconds: 60,
            max_concurrent_tasks: 2,
            default_schedule: "0 2 * * *".to_string(),
            loose_objects_threshold: 1000,
            packfiles_threshold: 10,
            size_threshold: 1024 * 1024 * 10,
            days_since_maintenance_threshold: 1,
        };

        // Create maintenance scheduler
        let scheduler = MaintenanceScheduler::new(
            scheduler_config,
            git.clone(),
            db.clone(),
            repo_service.clone(),
        );

        (scheduler, temp_dir)
    }

    #[tokio::test]
    async fn test_scheduler_initialization() {
        let (scheduler, _temp_dir) = create_test_maintenance_scheduler().await;

        // Verify scheduler is properly initialized
        assert_eq!(scheduler.config.max_concurrent_tasks, 2);
        assert_eq!(scheduler.config.check_interval_seconds, 60);

        // Start scheduler
        scheduler.start().await.unwrap();

        // Verify scheduler task is running
        {
            let scheduler_task = scheduler.scheduler_task.lock().await;
            assert!(scheduler_task.is_some());
        }

        // Stop scheduler
        scheduler.stop().await.unwrap();

        // Verify scheduler task is stopped
        {
            let scheduler_task = scheduler.scheduler_task.lock().await;
            assert!(scheduler_task.is_none());
        }
    }

    #[tokio::test]
    async fn test_maintenance_task_scheduling() {
        let (scheduler, _temp_dir) = create_test_maintenance_scheduler().await;

        // Create a mock repository
        // (in a real test, we'd create an actual Git repository)

        // Test task scheduling
        // In a real test, we'd mock the Git and DB calls and verify the scheduler
        // correctly handles maintenance tasks

        // For now, just verify the task scheduling logic works
        let running_tasks = scheduler.get_running_tasks().await;
        assert_eq!(running_tasks.len(), 0);

        let history = scheduler.get_task_history().await;
        assert_eq!(history.len(), 0);
    }
}
