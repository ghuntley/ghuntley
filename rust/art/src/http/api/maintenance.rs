// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Maintenance API endpoints
//!
//! Provides endpoints for managing repository maintenance tasks.

use crate::service::repository::maintenance::{MaintenanceScheduler, MaintenanceTask, MaintenanceTaskStatus};
use crate::error::{Error, Result};
use crate::http::ServerState;

use axum::{
    extract::{Extension, Path, Query},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{error, info};

/// Task query parameters
#[derive(Debug, Deserialize)]
pub struct TaskQuery {
    /// Task type (gc, repack, prune, fsck, reindex, full)
    pub task: Option<String>,

    /// Whether to run the task immediately (true) or schedule it (false)
    #[serde(default)]
    pub immediate: bool,
}

/// Maintenance status response
#[derive(Debug, Serialize)]
pub struct MaintenanceStatusResponse {
    /// Repository name
    pub repository: String,

    /// Currently running tasks
    pub running_tasks: Vec<MaintenanceTaskStatus>,

    /// Recent task history
    pub task_history: Vec<MaintenanceTaskStatus>,

    /// Next scheduled maintenance time
    pub next_scheduled: Option<String>,
}

/// Repository health response
#[derive(Debug, Serialize)]
pub struct RepositoryHealthResponse {
    /// Repository name
    pub repository: String,

    /// Overall health status (ok, needs_maintenance, error)
    pub status: String,

    /// Git status (ok, needs_maintenance, error)
    pub git_status: String,

    /// Git status message
    pub git_message: Option<String>,

    /// Database status (ok, needs_reindex, error)
    pub db_status: String,

    /// Database status message
    pub db_message: Option<String>,

    /// Repository size in bytes
    pub size_bytes: Option<i64>,

    /// Number of loose objects
    pub loose_objects: Option<i64>,

    /// Number of packfiles
    pub packfiles: Option<i64>,

    /// Last health check time
    pub last_checked: i64,
}

/// List of running maintenance tasks
pub async fn get_running_tasks_handler(
    Extension(state): Extension<ServerState>,
) -> Result<impl IntoResponse, StatusCode> {
    let maintenance_scheduler = state.maintenance_scheduler()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    let running_tasks = maintenance_scheduler.get_running_tasks().await;

    Ok(Json(running_tasks))
}

/// Get maintenance history
pub async fn get_maintenance_history_handler(
    Extension(state): Extension<ServerState>,
) -> Result<impl IntoResponse, StatusCode> {
    let maintenance_scheduler = state.maintenance_scheduler()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    let task_history = maintenance_scheduler.get_task_history().await;

    Ok(Json(task_history))
}

/// Get repository maintenance status
pub async fn get_repository_maintenance_status_handler(
    Path(repo_name): Path<String>,
    Extension(state): Extension<ServerState>,
) -> Result<impl IntoResponse, StatusCode> {
    let maintenance_scheduler = state.maintenance_scheduler()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    // Get running task for repository (if any)
    let task_status = maintenance_scheduler.get_task_status(&repo_name).await;

    // Get task history for repository
    let task_history = maintenance_scheduler.get_task_history().await
        .into_iter()
        .filter(|task| task.repository == repo_name)
        .collect::<Vec<_>>();

    // Get next scheduled maintenance time
    let next_scheduled = match maintenance_scheduler.get_next_maintenance_time(&repo_name).await {
        Ok(Some(time)) => Some(time.to_rfc3339()),
        _ => None,
    };

    let response = MaintenanceStatusResponse {
        repository: repo_name,
        running_tasks: task_status.into_iter().collect(),
        task_history,
        next_scheduled,
    };

    Ok(Json(response))
}

/// Check repository health
pub async fn check_repository_health_handler(
    Path(repo_name): Path<String>,
    Extension(state): Extension<ServerState>,
) -> Result<impl IntoResponse, StatusCode> {
    let maintenance_scheduler = state.maintenance_scheduler()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    match maintenance_scheduler.check_repository_health(&repo_name).await {
        Ok(health) => {
            let response = RepositoryHealthResponse {
                repository: repo_name,
                status: health.status,
                git_status: health.git_status,
                git_message: health.git_message,
                db_status: health.db_status,
                db_message: health.db_message,
                size_bytes: health.size_bytes,
                loose_objects: health.loose_objects,
                packfiles: health.packfiles,
                last_checked: health.last_checked,
            };

            Ok(Json(response))
        },
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

/// Trigger maintenance task
pub async fn trigger_maintenance_handler(
    Path(repo_name): Path<String>,
    Query(params): Query<TaskQuery>,
    Extension(state): Extension<ServerState>,
) -> Result<impl IntoResponse, StatusCode> {
    let maintenance_scheduler = state.maintenance_scheduler()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    // Parse task type
    let task = match params.task.as_deref() {
        Some("gc") => MaintenanceTask::GarbageCollection,
        Some("repack") => MaintenanceTask::Repack,
        Some("prune") => MaintenanceTask::Prune,
        Some("fsck") => MaintenanceTask::Fsck,
        Some("reindex") => MaintenanceTask::Reindex,
        Some("full") | None => MaintenanceTask::Full,
        Some(unknown) => {
            error!("Unknown maintenance task: {}", unknown);
            return Err(StatusCode::BAD_REQUEST);
        }
    };

    // Trigger maintenance task
    match maintenance_scheduler.trigger_maintenance(&repo_name, task).await {
        Ok(status) => {
            info!("Triggered maintenance task for repository {}: {:?}", repo_name, task);
            Ok(Json(status))
        },
        Err(err) => {
            error!("Failed to trigger maintenance task: {}", err);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Create maintenance routes
pub fn maintenance_routes(maintenance_scheduler: Arc<MaintenanceScheduler>) -> axum::Router {
    use axum::routing::{get, post};

    axum::Router::new()
        .route("/tasks", get(get_running_tasks_handler))
        .route("/history", get(get_maintenance_history_handler))
        .route("/repositories/:repo_name", get(get_repository_maintenance_status_handler))
        .route("/repositories/:repo_name/health", get(check_repository_health_handler))
        .route("/repositories/:repo_name/trigger", post(trigger_maintenance_handler))
        .layer(axum::extract::Extension(maintenance_scheduler))
}

/// Register maintenance routes
pub fn register_maintenance_routes(router: &mut axum::Router) {
    use axum::routing::{get, post};

    let maintenance_routes = axum::Router::new()
        .route("/tasks", get(get_running_tasks_handler))
        .route("/history", get(get_maintenance_history_handler))
        .route("/repositories/:repo_name", get(get_repository_maintenance_status_handler))
        .route("/repositories/:repo_name/health", get(check_repository_health_handler))
        .route("/repositories/:repo_name/trigger", post(trigger_maintenance_handler));

    *router = std::mem::take(router)
        .nest("/api/maintenance", maintenance_routes);
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request;
    use axum::body::Body;
    use tower::ServiceExt;
    use crate::service::repository::maintenance::MaintenanceSchedulerConfig;
    use crate::data::{Git, Sqlite};
    use crate::service::repository::RepositoryService;
    use crate::config::{DatabaseConfig, GitConfig};
    use crate::data::cache::Cache;
    use std::time::Duration;
    use tempfile::TempDir;

    async fn setup_test_app() -> (axum::Router, TempDir) {
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

        // Create maintenance scheduler
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

        let maintenance_scheduler = Arc::new(MaintenanceScheduler::new(
            scheduler_config,
            git.clone(),
            db.clone(),
            repo_service.clone(),
        ));

        // Create router with maintenance routes
        let mut router = axum::Router::new();
        register_maintenance_routes(&mut router);

        // Add state extension
        let router = router.layer(axum::extract::Extension(ServerState {
            maintenance_scheduler: Some(maintenance_scheduler),
        }));

        (router, temp_dir)
    }

    #[tokio::test]
    async fn test_get_running_tasks() {
        let (app, _temp_dir) = setup_test_app().await;

        let response = app
            .oneshot(Request::get("/api/maintenance/tasks").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_get_maintenance_history() {
        let (app, _temp_dir) = setup_test_app().await;

        let response = app
            .oneshot(Request::get("/api/maintenance/history").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_get_repository_maintenance_status() {
        let (app, _temp_dir) = setup_test_app().await;

        let response = app
            .oneshot(Request::get("/api/maintenance/repositories/test-repo").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }
}
