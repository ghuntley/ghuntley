//! Maintenance templates for the Art application

use crate::service::repository::maintenance::{MaintenanceTaskStatus, MaintenanceTask};
use crate::service::repository::RepositoryHealth;
use crate::util::format::format_bytes;
use askama::Template;
use chrono::{DateTime, Utc};
use std::time::Duration;

/// Repository maintenance dashboard template
#[derive(Template)]
#[template(path = "maintenance/dashboard.html")]
pub struct MaintenanceDashboardTemplate {
    /// Title for the page
    pub title: String,

    /// Current active path
    pub current_path: String,

    /// Number of active maintenance tasks
    pub active_tasks_count: usize,

    /// Number of completed maintenance tasks
    pub completed_tasks_count: usize,

    /// Number of failed maintenance tasks
    pub failed_tasks_count: usize,

    /// Total number of repositories
    pub total_repositories: usize,

    /// Currently running tasks
    pub running_tasks: Vec<TemplateMaintenanceTask>,

    /// Repository health information
    pub repositories: Vec<TemplateRepositoryHealth>,

    /// Task history
    pub task_history: Vec<TemplateMaintenanceTask>,

    /// Current year (for footer)
    pub year: String,
}

/// Repository health detail template
#[derive(Template)]
#[template(path = "maintenance/health_detail.html")]
pub struct RepositoryHealthDetailTemplate {
    /// Title for the page
    pub title: String,

    /// Current active path
    pub current_path: String,

    /// Repository health information
    pub repo: TemplateRepositoryHealth,

    /// Maintenance history for this repository
    pub maintenance_history: Vec<TemplateMaintenanceTask>,

    /// Current year (for footer)
    pub year: String,
}

/// Task detail template
#[derive(Template)]
#[template(path = "maintenance/task_detail.html")]
pub struct TaskDetailTemplate {
    /// Title for the page
    pub title: String,

    /// Current active path
    pub current_path: String,

    /// The maintenance task
    pub task: TemplateMaintenanceTask,

    /// Similar tasks for this repository
    pub similar_tasks: Vec<TemplateMaintenanceTask>,

    /// Current year (for footer)
    pub year: String,
}

/// Template representation of a maintenance task
#[derive(Clone, Debug)]
pub struct TemplateMaintenanceTask {
    /// Repository name
    pub repository: String,

    /// Task type
    pub task: String,

    /// Status (pending, running, completed, failed)
    pub status: String,

    /// Start time
    pub start_time: Option<String>,

    /// End time
    pub end_time: Option<String>,

    /// Error message if failed
    pub error: Option<String>,

    /// Duration as formatted string
    pub duration: Option<String>,
}

impl From<MaintenanceTaskStatus> for TemplateMaintenanceTask {
    fn from(status: MaintenanceTaskStatus) -> Self {
        let duration = if let (Some(start), Some(end)) = (status.start_time, status.end_time) {
            let duration_seconds = (end - start).num_seconds();
            Some(format_duration(Duration::from_secs(duration_seconds as u64)))
        } else {
            None
        };

        Self {
            repository: status.repository,
            task: format!("{}", status.task),
            status: status.status,
            start_time: status.start_time.map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string()),
            end_time: status.end_time.map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string()),
            error: status.error,
            duration,
        }
    }
}

/// Template representation of repository health
#[derive(Clone, Debug)]
pub struct TemplateRepositoryHealth {
    /// Repository name
    pub name: String,

    /// Overall health status
    pub status: String,

    /// Last maintenance time
    pub last_maintenance: Option<String>,

    /// Git status
    pub git_status: String,

    /// Git status message
    pub git_message: Option<String>,

    /// Database status
    pub db_status: String,

    /// Database status message
    pub db_message: Option<String>,

    /// Repository size in bytes
    pub size_bytes: u64,

    /// Formatted repository size
    pub size_formatted: String,

    /// Number of loose objects
    pub loose_objects: usize,

    /// Number of packfiles
    pub packfiles: usize,

    /// Last commit time
    pub last_commit: Option<String>,

    /// Last push time
    pub last_push: Option<String>,
}

impl From<RepositoryHealth> for TemplateRepositoryHealth {
    fn from(health: RepositoryHealth) -> Self {
        Self {
            name: health.name,
            status: health.status,
            last_maintenance: health.last_maintenance.map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string()),
            git_status: health.git_status,
            git_message: health.git_message,
            db_status: health.db_status,
            db_message: health.db_message,
            size_bytes: health.size_bytes,
            size_formatted: format_bytes(health.size_bytes),
            loose_objects: health.loose_objects,
            packfiles: health.packfiles,
            last_commit: health.last_commit.map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string()),
            last_push: health.last_push.map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string()),
        }
    }
}

/// Format a duration to a human-readable string
fn format_duration(duration: Duration) -> String {
    let total_seconds = duration.as_secs();

    if total_seconds < 60 {
        return format!("{} seconds", total_seconds);
    }

    let minutes = total_seconds / 60;
    let seconds = total_seconds % 60;

    if minutes < 60 {
        return format!("{}m {}s", minutes, seconds);
    }

    let hours = minutes / 60;
    let minutes = minutes % 60;

    format!("{}h {}m {}s", hours, minutes, seconds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn test_format_duration() {
        assert_eq!(format_duration(Duration::from_secs(30)), "30 seconds");
        assert_eq!(format_duration(Duration::from_secs(90)), "1m 30s");
        assert_eq!(format_duration(Duration::from_secs(3600)), "1h 0m 0s");
        assert_eq!(format_duration(Duration::from_secs(3661)), "1h 1m 1s");
    }

    #[test]
    fn test_template_maintenance_task_from() {
        let now = Utc::now();
        let five_minutes_ago = now - chrono::Duration::minutes(5);

        let task_status = MaintenanceTaskStatus {
            repository: "test-repo".to_string(),
            task: MaintenanceTask::GarbageCollection,
            status: "completed".to_string(),
            start_time: Some(five_minutes_ago),
            end_time: Some(now),
            error: None,
        };

        let template_task = TemplateMaintenanceTask::from(task_status);

        assert_eq!(template_task.repository, "test-repo");
        assert_eq!(template_task.task, "GarbageCollection");
        assert_eq!(template_task.status, "completed");
        assert!(template_task.start_time.is_some());
        assert!(template_task.end_time.is_some());
        assert!(template_task.error.is_none());
        assert!(template_task.duration.is_some());
        assert_eq!(template_task.duration.unwrap(), "5m 0s");
    }

    #[test]
    fn test_template_repository_health_from() {
        let now = Utc::now();
        let one_day_ago = now - chrono::Duration::days(1);

        let health = RepositoryHealth {
            name: "test-repo".to_string(),
            status: "ok".to_string(),
            last_maintenance: Some(one_day_ago),
            git_status: "ok".to_string(),
            git_message: None,
            db_status: "ok".to_string(),
            db_message: None,
            size_bytes: 1024 * 1024, // 1 MB
            loose_objects: 42,
            packfiles: 3,
            last_commit: Some(now),
            last_push: Some(now),
        };

        let template_health = TemplateRepositoryHealth::from(health);

        assert_eq!(template_health.name, "test-repo");
        assert_eq!(template_health.status, "ok");
        assert!(template_health.last_maintenance.is_some());
        assert_eq!(template_health.git_status, "ok");
        assert!(template_health.git_message.is_none());
        assert_eq!(template_health.db_status, "ok");
        assert!(template_health.db_message.is_none());
        assert_eq!(template_health.size_bytes, 1024 * 1024);
        assert_eq!(template_health.size_formatted, "1.0 MB");
        assert_eq!(template_health.loose_objects, 42);
        assert_eq!(template_health.packfiles, 3);
        assert!(template_health.last_commit.is_some());
        assert!(template_health.last_push.is_some());
    }
}
