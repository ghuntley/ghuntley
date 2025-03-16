use art::config::{Config, RepositoryConfig};
use art::service::git::GitService;
use art::service::repository::maintenance::{
    MaintenanceScheduler, RepositoryHealth, HealthStatus, MaintenanceTask, MaintenanceTaskStatus
};
use art::error::Result;

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use tempfile::TempDir;
use chrono::Utc;
use tokio::time::{sleep, Duration};
use tokio::task::JoinHandle;

/// Helper to set up test repositories for maintenance tests
async fn setup_test_repositories() -> Result<(TempDir, Vec<String>)> {
    let temp_dir = TempDir::new()?;
    let repo_names = vec!["maintenance-test-1", "maintenance-test-2", "maintenance-test-large"];

    for repo_name in &repo_names {
        let repo_path = temp_dir.path().join(repo_name);

        // Create repository directory
        fs::create_dir_all(&repo_path)?;

        // Initialize git repository
        Command::new("git")
            .args(&["init"])
            .current_dir(&repo_path)
            .output()?;

        // Configure git user for commits
        Command::new("git")
            .args(&["config", "user.name", "Test User"])
            .current_dir(&repo_path)
            .output()?;

        Command::new("git")
            .args(&["config", "user.email", "test@example.com"])
            .current_dir(&repo_path)
            .output()?;

        // Create initial content
        fs::write(repo_path.join("README.md"), format!("# {}\n\nTest repository for maintenance tests", repo_name))?;

        // Add and commit
        Command::new("git")
            .args(&["add", "."])
            .current_dir(&repo_path)
            .output()?;

        Command::new("git")
            .args(&["commit", "-m", "Initial commit"])
            .current_dir(&repo_path)
            .output()?;

        // Create more files for the large test repository
        if repo_name == "maintenance-test-large" {
            for i in 1..100 {
                fs::write(
                    repo_path.join(format!("file_{}.txt", i)),
                    format!("Content for file {}\n", i)
                )?;

                // Commit every 10 files to create multiple objects
                if i % 10 == 0 {
                    Command::new("git")
                        .args(&["add", "."])
                        .current_dir(&repo_path)
                        .output()?;

                    Command::new("git")
                        .args(&["commit", "-m", &format!("Add files batch {}", i / 10)])
                        .current_dir(&repo_path)
                        .output()?;
                }
            }
        }
    }

    Ok((temp_dir, repo_names))
}

/// Create a test configuration for maintenance tests
fn create_test_config(temp_dir: &TempDir, repo_names: &[String]) -> Config {
    let mut config = Config::default();

    for repo_name in repo_names {
        let repo_path = temp_dir.path().join(repo_name);
        config.repositories.push(RepositoryConfig {
            name: repo_name.clone(),
            path: repo_path.to_string_lossy().to_string(),
            description: Some(format!("Test repository {}", repo_name)),
            owner: Some("Test User".to_string()),
            ..Default::default()
        });
    }

    // Set maintenance configuration
    config.maintenance.enabled = true;
    config.maintenance.check_interval_seconds = 5; // Short interval for testing
    config.maintenance.max_concurrent_tasks = 2;
    config.maintenance.task_timeout_minutes = 1;

    config
}

/// Create a GitService for tests
fn create_git_service(config: &Config) -> Arc<GitService> {
    Arc::new(GitService::new(config.clone()))
}

/// Test that the MaintenanceScheduler can check repository health
#[tokio::test]
async fn test_maintenance_scheduler_health_check() -> Result<()> {
    let (temp_dir, repo_names) = setup_test_repositories().await?;
    let config = create_test_config(&temp_dir, &repo_names);
    let git_service = create_git_service(&config);

    let scheduler = MaintenanceScheduler::new(
        config.clone(),
        git_service.clone()
    );

    // Check health of repositories
    let health_results = scheduler.check_repositories_health().await?;

    // Verify results
    assert_eq!(health_results.len(), repo_names.len());
    for repo_name in &repo_names {
        let health = health_results.iter().find(|h| h.repository_name == *repo_name);
        assert!(health.is_some(), "Missing health for {}", repo_name);

        let health = health.unwrap();
        assert!(health.object_count > 0, "No objects found in {}", repo_name);

        // The large repo should have more objects
        if repo_name == "maintenance-test-large" {
            assert!(health.object_count > 20, "Large repo should have more objects");
        }
    }

    Ok(())
}

/// Test that the MaintenanceScheduler can schedule and run tasks
#[tokio::test]
async fn test_maintenance_scheduler_task_execution() -> Result<()> {
    let (temp_dir, repo_names) = setup_test_repositories().await?;
    let config = create_test_config(&temp_dir, &repo_names);
    let git_service = create_git_service(&config);

    let scheduler = MaintenanceScheduler::new(
        config.clone(),
        git_service.clone()
    );

    // Start the scheduler in the background
    let scheduler_handle = scheduler.clone();
    let handle = tokio::spawn(async move {
        scheduler_handle.start().await
    });

    // Give it time to start and check repositories
    sleep(Duration::from_secs(2)).await;

    // Manually schedule maintenance tasks
    for repo_name in &repo_names {
        scheduler.schedule_task(repo_name, "gc".to_string()).await?;
    }

    // Give tasks time to execute
    sleep(Duration::from_secs(5)).await;

    // Check that tasks were created and ran
    let tasks = scheduler.get_task_history(None).await;
    assert!(!tasks.is_empty(), "No tasks were created");

    // At least some tasks should have run to completion
    let completed_tasks = tasks.iter().filter(|t| t.status == MaintenanceTaskStatus::Completed).count();
    assert!(completed_tasks > 0, "No tasks completed successfully");

    // Stop the scheduler
    scheduler.shutdown().await;
    let _ = handle.await;

    Ok(())
}

/// Test that the MaintenanceScheduler properly prioritizes tasks
#[tokio::test]
async fn test_maintenance_scheduler_prioritization() -> Result<()> {
    let (temp_dir, repo_names) = setup_test_repositories().await?;
    let config = create_test_config(&temp_dir, &repo_names);
    let git_service = create_git_service(&config);

    let scheduler = MaintenanceScheduler::new(
        config.clone(),
        git_service.clone()
    );

    // Create sample repository health reports
    let mut health_reports = Vec::new();

    // Repository with critical health
    health_reports.push(RepositoryHealth {
        repository_name: "maintenance-test-large".to_string(),
        object_count: 5000,
        loose_object_count: 6000, // Critical: loose objects > 5000
        ref_count: 10,
        repository_size_kb: 5000,
        days_since_gc: 100, // Critical: days since GC > 90
        status: HealthStatus::Critical,
        issues: vec!["Too many loose objects".to_string(), "GC needed".to_string()],
        last_checked: Utc::now(),
    });

    // Repository with warning health
    health_reports.push(RepositoryHealth {
        repository_name: "maintenance-test-2".to_string(),
        object_count: 2000,
        loose_object_count: 3000, // Warning: loose objects > 2000
        ref_count: 5,
        repository_size_kb: 2000,
        days_since_gc: 40, // Warning: days since GC > 30
        status: HealthStatus::Warning,
        issues: vec!["Many loose objects".to_string()],
        last_checked: Utc::now(),
    });

    // Repository with good health
    health_reports.push(RepositoryHealth {
        repository_name: "maintenance-test-1".to_string(),
        object_count: 1000,
        loose_object_count: 500,
        ref_count: 3,
        repository_size_kb: 1000,
        days_since_gc: 10,
        status: HealthStatus::Good,
        issues: vec![],
        last_checked: Utc::now(),
    });

    // Create tasks for all repositories
    let mut tasks = Vec::new();
    for health in &health_reports {
        tasks.push(MaintenanceTask {
            id: format!("task-{}", health.repository_name),
            repository_name: health.repository_name.clone(),
            task_type: "gc".to_string(),
            status: MaintenanceTaskStatus::Pending,
            priority: 0, // To be calculated
            created_at: Utc::now(),
            started_at: None,
            completed_at: None,
            result: None,
            error: None,
        });
    }

    // Prioritize tasks using the scheduler
    let prioritized_tasks = scheduler.prioritize_tasks(&tasks, &health_reports).await;

    // Check that tasks are properly prioritized
    assert_eq!(prioritized_tasks.len(), tasks.len());

    // Extract priorities for testing
    let mut priorities = prioritized_tasks.iter()
        .map(|t| (t.repository_name.clone(), t.priority))
        .collect::<Vec<_>>();

    // Sort by priority (descending)
    priorities.sort_by(|a, b| b.1.cmp(&a.1));

    // Critical repository should have highest priority
    assert_eq!(priorities[0].0, "maintenance-test-large");
    // Warning repository should have medium priority
    assert_eq!(priorities[1].0, "maintenance-test-2");
    // Good repository should have lowest priority
    assert_eq!(priorities[2].0, "maintenance-test-1");

    // Verify actual priority values
    assert!(priorities[0].1 > 70, "Critical repo should have high priority: {}", priorities[0].1);
    assert!(priorities[1].1 > 40 && priorities[1].1 < 70, "Warning repo should have medium priority: {}", priorities[1].1);
    assert!(priorities[2].1 < 40, "Good repo should have low priority: {}", priorities[2].1);

    Ok(())
}

/// Test that MaintenanceScheduler properly handles concurrent tasks
#[tokio::test]
async fn test_maintenance_scheduler_concurrency() -> Result<()> {
    let (temp_dir, repo_names) = setup_test_repositories().await?;
    let mut config = create_test_config(&temp_dir, &repo_names);

    // Limit concurrency to just 1 task at a time for this test
    config.maintenance.max_concurrent_tasks = 1;

    let git_service = create_git_service(&config);

    let scheduler = MaintenanceScheduler::new(
        config.clone(),
        git_service.clone()
    );

    // Schedule multiple tasks simultaneously
    for repo_name in &repo_names {
        scheduler.schedule_task(repo_name, "gc".to_string()).await?;
        scheduler.schedule_task(repo_name, "repack".to_string()).await?;
    }

    // Wait a moment for processing to begin
    sleep(Duration::from_secs(1)).await;

    // Check that only one task is running
    let running_tasks = scheduler.get_running_tasks().await;
    assert!(running_tasks.len() <= 1, "Too many concurrent tasks: {}", running_tasks.len());

    // Stop the scheduler and wait for pending tasks to finish
    scheduler.shutdown().await;

    // Check task history
    let all_tasks = scheduler.get_task_history(None).await;

    // We should have at least as many tasks as we scheduled
    assert!(all_tasks.len() >= repo_names.len() * 2);

    // Tasks should have either completed or be pending (none should be in running state)
    for task in &all_tasks {
        assert!(
            task.status == MaintenanceTaskStatus::Completed ||
            task.status == MaintenanceTaskStatus::Pending ||
            task.status == MaintenanceTaskStatus::Failed,
            "Task should not be in running state after shutdown"
        );
    }

    Ok(())
}

/// Test that the MaintenanceScheduler can handle repository health monitoring
#[tokio::test]
async fn test_repository_health_monitoring() -> Result<()> {
    let (temp_dir, repo_names) = setup_test_repositories().await?;
    let config = create_test_config(&temp_dir, &repo_names);
    let git_service = create_git_service(&config);

    let scheduler = MaintenanceScheduler::new(
        config.clone(),
        git_service.clone()
    );

    // Start the scheduler
    let scheduler_handle = scheduler.clone();
    let handle = tokio::spawn(async move {
        scheduler_handle.start().await
    });

    // Give it time to check repository health
    sleep(Duration::from_secs(3)).await;

    // Get health reports
    let health_reports = scheduler.get_repository_health_reports().await;

    // Verify health reports
    assert_eq!(health_reports.len(), repo_names.len());
    for repo_name in &repo_names {
        let health = health_reports.iter().find(|h| h.repository_name == *repo_name);
        assert!(health.is_some(), "Missing health for {}", repo_name);

        // Health status should be calculated
        let health = health.unwrap();
        assert!(health.status != HealthStatus::Unknown, "Health status not calculated for {}", repo_name);
    }

    // Shutdown the scheduler
    scheduler.shutdown().await;
    let _ = handle.await;

    Ok(())
}
