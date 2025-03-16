//! Web routes for repository maintenance

use crate::http::ServerState;
use crate::template::{MaintenanceDashboardTemplate, RepositoryHealthDetailTemplate, TaskDetailTemplate, TemplateMaintenanceTask, TemplateRepositoryHealth};
use crate::error::{Error, Result};
use crate::service::repository::maintenance::MaintenanceTask;
use super::current_year;

use axum::{
    extract::{Path, State, Form},
    response::{Html, Redirect},
    routing::{get, post},
    Router,
};
use serde::Deserialize;
use std::convert::From;

/// Create maintenance web routes
pub fn maintenance_routes() -> Router {
    Router::new()
        .route("/maintenance/dashboard", get(maintenance_dashboard))
        .route("/maintenance/health/:repo", get(repository_health))
        .route("/maintenance/task/:repo/:task", get(task_detail))
        .route("/maintenance/trigger/:repo", post(trigger_maintenance))
        .route("/maintenance/retry/:repo", post(retry_maintenance))
}

/// Maintenance task form data
#[derive(Deserialize)]
pub struct MaintenanceTaskForm {
    /// Task type
    pub task: String,
}

/// Maintenance dashboard handler
async fn maintenance_dashboard(
    State(state): State<ServerState>,
) -> Result<Html<String>> {
    // Check for maintenance scheduler
    let maintenance_scheduler = state.maintenance_scheduler
        .clone()
        .ok_or_else(|| Error::NotFound("Maintenance scheduler not configured".to_string()))?;

    // Get running tasks
    let running_tasks = maintenance_scheduler.get_running_tasks().await;
    let running_tasks: Vec<TemplateMaintenanceTask> = running_tasks.into_iter().map(From::from).collect();

    // Get task history
    let task_history = maintenance_scheduler.get_task_history().await;
    let task_history: Vec<TemplateMaintenanceTask> = task_history.into_iter().map(From::from).collect();

    // Get repository list
    let repositories = state.repository_service.as_ref()
        .ok_or_else(|| Error::NotFound("Repository service not configured".to_string()))?
        .list_repositories().await?;

    // Fetch health for each repository
    let mut repo_health = Vec::new();
    for repo in repositories {
        if let Ok(health) = maintenance_scheduler.check_repository_health(&repo.name).await {
            repo_health.push(TemplateRepositoryHealth::from(health));
        }
    }

    // Count tasks by status
    let active_tasks_count = running_tasks.iter()
        .filter(|t| t.status == "running" || t.status == "pending")
        .count();

    let completed_tasks_count = task_history.iter()
        .filter(|t| t.status == "completed")
        .count();

    let failed_tasks_count = task_history.iter()
        .filter(|t| t.status == "failed")
        .count();

    // Create template
    let template = MaintenanceDashboardTemplate {
        title: "Repository Maintenance Dashboard".to_string(),
        current_path: "/maintenance/dashboard".to_string(),
        active_tasks_count,
        completed_tasks_count,
        failed_tasks_count,
        total_repositories: repo_health.len(),
        running_tasks,
        repositories: repo_health,
        task_history,
        year: current_year(),
    };

    // Render template
    Ok(Html(template.render_to_string()?))
}

/// Repository health handler
async fn repository_health(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
) -> Result<Html<String>> {
    // Check for maintenance scheduler
    let maintenance_scheduler = state.maintenance_scheduler
        .clone()
        .ok_or_else(|| Error::NotFound("Maintenance scheduler not configured".to_string()))?;

    // Get repository health
    let repo_health = maintenance_scheduler.check_repository_health(&repo_name).await?;
    let repo_health = TemplateRepositoryHealth::from(repo_health);

    // Get maintenance history for this repository
    let task_history = maintenance_scheduler.get_task_history().await;
    let maintenance_history: Vec<TemplateMaintenanceTask> = task_history.into_iter()
        .filter(|t| t.repository == repo_name)
        .map(From::from)
        .collect();

    // Create template
    let template = RepositoryHealthDetailTemplate {
        title: format!("Health Report: {}", repo_name),
        current_path: format!("/maintenance/health/{}", repo_name),
        repo: repo_health,
        maintenance_history,
        year: current_year(),
    };

    // Render template
    Ok(Html(template.render_to_string()?))
}

/// Task detail handler
async fn task_detail(
    State(state): State<ServerState>,
    Path((repo_name, task_name)): Path<(String, String)>,
) -> Result<Html<String>> {
    // Check for maintenance scheduler
    let maintenance_scheduler = state.maintenance_scheduler
        .clone()
        .ok_or_else(|| Error::NotFound("Maintenance scheduler not configured".to_string()))?;

    // Get all task history
    let task_history = maintenance_scheduler.get_task_history().await;
    let running_tasks = maintenance_scheduler.get_running_tasks().await;

    // Find the specific task
    let task = running_tasks.iter()
        .find(|t| t.repository == repo_name && format!("{}", t.task) == task_name)
        .cloned()
        .or_else(|| task_history.iter()
            .find(|t| t.repository == repo_name && format!("{}", t.task) == task_name)
            .cloned())
        .ok_or_else(|| Error::NotFound(format!("Task not found: {} for {}", task_name, repo_name)))?;

    let task = TemplateMaintenanceTask::from(task);

    // Get similar tasks for this repository
    let similar_tasks: Vec<TemplateMaintenanceTask> = task_history.into_iter()
        .filter(|t| t.repository == repo_name && format!("{}", t.task) != task_name)
        .take(10)
        .map(From::from)
        .collect();

    // Create template
    let template = TaskDetailTemplate {
        title: format!("Maintenance Task: {} - {}", task_name, repo_name),
        current_path: format!("/maintenance/task/{}/{}", repo_name, task_name),
        task,
        similar_tasks,
        year: current_year(),
    };

    // Render template
    Ok(Html(template.render_to_string()?))
}

/// Trigger maintenance handler
async fn trigger_maintenance(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
    Form(form): Form<MaintenanceTaskForm>,
) -> Result<Redirect> {
    // Check for maintenance scheduler
    let maintenance_scheduler = state.maintenance_scheduler
        .clone()
        .ok_or_else(|| Error::NotFound("Maintenance scheduler not configured".to_string()))?;

    // Parse task type
    let task = match form.task.as_str() {
        "gc" => MaintenanceTask::GarbageCollection,
        "repack" => MaintenanceTask::Repack,
        "prune" => MaintenanceTask::Prune,
        "fsck" => MaintenanceTask::Fsck,
        "reindex" => MaintenanceTask::Reindex,
        "full" => MaintenanceTask::Full,
        _ => return Err(Error::InvalidInput(format!("Invalid task type: {}", form.task))),
    };

    // Trigger maintenance
    maintenance_scheduler.trigger_maintenance(&repo_name, task).await?;

    // Redirect to health page
    Ok(Redirect::to(&format!("/maintenance/health/{}", repo_name)))
}

/// Retry maintenance handler
async fn retry_maintenance(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
    Form(form): Form<MaintenanceTaskForm>,
) -> Result<Redirect> {
    // Check for maintenance scheduler
    let maintenance_scheduler = state.maintenance_scheduler
        .clone()
        .ok_or_else(|| Error::NotFound("Maintenance scheduler not configured".to_string()))?;

    // Parse task type
    let task = match form.task.as_str() {
        "gc" => MaintenanceTask::GarbageCollection,
        "repack" => MaintenanceTask::Repack,
        "prune" => MaintenanceTask::Prune,
        "fsck" => MaintenanceTask::Fsck,
        "reindex" => MaintenanceTask::Reindex,
        "full" => MaintenanceTask::Full,
        _ => return Err(Error::InvalidInput(format!("Invalid task type: {}", form.task))),
    };

    // Trigger maintenance
    maintenance_scheduler.trigger_maintenance(&repo_name, task).await?;

    // Redirect to task detail page
    Ok(Redirect::to(&format!("/maintenance/task/{}/{}", repo_name, form.task)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use http_body_util::BodyExt;
    use tower::ServiceExt;
    use crate::service::repository::maintenance::{MaintenanceScheduler, MaintenanceSchedulerConfig};
    use crate::service::repository::RepositoryService;
    use crate::data::{Git, Sqlite};
    use crate::data::cache::Cache;
    use std::sync::Arc;
    use tempfile::TempDir;

    async fn setup_test_app() -> (Router, TempDir) {
        // Create temporary directory
        let temp_dir = TempDir::new().unwrap();
        let repo_path = temp_dir.path().join("repos");
        std::fs::create_dir_all(&repo_path).unwrap();

        // Create Git instance
        let git = Arc::new(Git::new(repo_path.clone()).unwrap());

        // Create cache
        let cache = Arc::new(Cache::new(100, None));

        // Create repository service
        let repo_service = Arc::new(RepositoryService::new(git.clone(), cache.clone()));

        // Create maintenance scheduler
        let config = MaintenanceSchedulerConfig {
            enabled: true,
            check_interval_seconds: 300,
            max_concurrent_tasks: 2,
            default_schedule: "0 0 * * *".to_string(),
            loose_objects_threshold: 1000,
            packfiles_threshold: 20,
            size_threshold: 100 * 1024 * 1024,
            days_since_maintenance_threshold: 7,
        };

        // Create maintenance scheduler (without starting it)
        let db = Arc::new(Sqlite::new(&crate::data::sqlite::DatabaseConfig::default()).unwrap());
        let maintenance_scheduler = Arc::new(MaintenanceScheduler::new(
            config,
            git.clone(),
            db,
            repo_service.clone(),
        ));

        // Create server state
        let state = ServerState {
            config: Arc::new(crate::config::Config::default()),
            db: Arc::new(Sqlite::new(&crate::data::sqlite::DatabaseConfig::default()).unwrap()),
            git: git.clone(),
            cache: cache.clone(),
            repository_service: Some(repo_service),
            commit_service: None,
            file_service: None,
            format_service: None,
            index_service: None,
            search_service: None,
            status_service: None,
            observability_service: None,
            auth_service: None,
            user_service: None,
            maintenance_scheduler: Some(maintenance_scheduler),
        };

        // Create the router
        let app = Router::new()
            .nest("/", maintenance_routes())
            .with_state(state);

        (app, temp_dir)
    }

    #[tokio::test]
    async fn test_maintenance_dashboard() {
        let (app, _temp_dir) = setup_test_app().await;

        let response = app
            .oneshot(Request::builder().uri("/maintenance/dashboard").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = response.into_body().collect().await.unwrap().to_bytes();
        let body_str = String::from_utf8(body.to_vec()).unwrap();

        assert!(body_str.contains("Repository Maintenance Dashboard"));
        assert!(body_str.contains("Maintenance Overview"));
    }
}
