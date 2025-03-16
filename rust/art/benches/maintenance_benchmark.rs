use art::config::{Config, RepositoryConfig};
use art::service::git::GitService;
use art::service::repository::maintenance::{
    MaintenanceScheduler, RepositoryHealth, HealthStatus, MaintenanceTask
};
use art::error::Result;

use criterion::{criterion_group, criterion_main, Criterion, BenchmarkId};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use tempfile::TempDir;
use chrono::Utc;

/// Set up test repositories for benchmarks
fn setup_test_repositories(count: usize) -> Result<(TempDir, Vec<String>)> {
    let temp_dir = TempDir::new()?;
    let mut repo_names = Vec::with_capacity(count);

    for i in 0..count {
        let repo_name = format!("benchmark-repo-{}", i);
        let repo_path = temp_dir.path().join(&repo_name);

        repo_names.push(repo_name.clone());

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

        // Create initial content and commit
        fs::write(repo_path.join("README.md"), format!("# {}\n\nBenchmark repository", repo_name))?;

        Command::new("git")
            .args(&["add", "."])
            .current_dir(&repo_path)
            .output()?;

        Command::new("git")
            .args(&["commit", "-m", "Initial commit"])
            .current_dir(&repo_path)
            .output()?;

        // Add more files based on repository index (to create different sizes)
        let file_count = (i % 10) * 5 + 5; // 5 to 50 files

        for j in 0..file_count {
            fs::write(
                repo_path.join(format!("file_{}.txt", j)),
                format!("Content for benchmark file {}\n", j)
            )?;
        }

        // Commit all files
        Command::new("git")
            .args(&["add", "."])
            .current_dir(&repo_path)
            .output()?;

        Command::new("git")
            .args(&["commit", "-m", "Add benchmark files"])
            .current_dir(&repo_path)
            .output()?;
    }

    Ok((temp_dir, repo_names))
}

/// Create a test configuration for benchmarks
fn create_benchmark_config(temp_dir: &TempDir, repo_names: &[String]) -> Config {
    let mut config = Config::default();

    for repo_name in repo_names {
        let repo_path = temp_dir.path().join(repo_name);
        config.repositories.push(RepositoryConfig {
            name: repo_name.clone(),
            path: repo_path.to_string_lossy().to_string(),
            description: Some(format!("Benchmark repository {}", repo_name)),
            owner: Some("Test User".to_string()),
            ..Default::default()
        });
    }

    // Configure maintenance settings
    config.maintenance.enabled = true;
    config.maintenance.check_interval_seconds = 3600; // High value to prevent auto-scheduling during benchmarks
    config.maintenance.max_concurrent_tasks = 4;

    config
}

/// Create a maintenance scheduler for benchmarks
fn create_scheduler(config: &Config) -> MaintenanceScheduler {
    let git_service = Arc::new(GitService::new(config.clone()));

    MaintenanceScheduler::new(
        config.clone(),
        git_service
    )
}

/// Benchmark health check performance
fn bench_health_check(c: &mut Criterion) {
    let mut group = c.benchmark_group("repository_health_check");

    // Test different repository counts
    for repo_count in [5, 10, 20].iter() {
        // Set up test repositories
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let (temp_dir, repo_names) = runtime.block_on(async {
            setup_test_repositories(*repo_count).unwrap()
        });

        let config = create_benchmark_config(&temp_dir, &repo_names);
        let scheduler = create_scheduler(&config);

        // Benchmark health check performance
        group.bench_with_input(
            BenchmarkId::new("health_check", repo_count),
            repo_count,
            |b, _| {
                let scheduler_clone = scheduler.clone();
                b.to_async(&runtime).iter(move || {
                    let s = scheduler_clone.clone();
                    async move {
                        let _ = s.check_repositories_health().await.unwrap();
                    }
                });
            }
        );
    }

    group.finish();
}

/// Benchmark task prioritization performance
fn bench_task_prioritization(c: &mut Criterion) {
    let mut group = c.benchmark_group("task_prioritization");

    // Test different task counts
    for task_count in [10, 50, 100].iter() {
        // Create sample health reports and tasks
        let health_reports: Vec<RepositoryHealth> = (0..*task_count)
            .map(|i| {
                let status = match i % 3 {
                    0 => HealthStatus::Good,
                    1 => HealthStatus::Warning,
                    _ => HealthStatus::Critical,
                };

                let loose_objects = match status {
                    HealthStatus::Good => 500,
                    HealthStatus::Warning => 3000,
                    HealthStatus::Critical => 6000,
                    _ => 0,
                };

                let days_since_gc = match status {
                    HealthStatus::Good => 10,
                    HealthStatus::Warning => 40,
                    HealthStatus::Critical => 100,
                    _ => 0,
                };

                RepositoryHealth {
                    repository_name: format!("benchmark-repo-{}", i),
                    object_count: 10000,
                    loose_object_count: loose_objects,
                    ref_count: 50,
                    repository_size_kb: 5000,
                    days_since_gc,
                    status,
                    issues: Vec::new(),
                    last_checked: Utc::now(),
                }
            })
            .collect();

        let tasks: Vec<MaintenanceTask> = (0..*task_count)
            .map(|i| {
                let task_type = match i % 5 {
                    0 => "gc",
                    1 => "repack",
                    2 => "prune",
                    3 => "fsck",
                    _ => "reflog",
                };

                MaintenanceTask {
                    id: format!("task-{}", i),
                    repository_name: format!("benchmark-repo-{}", i),
                    task_type: task_type.to_string(),
                    status: art::service::repository::maintenance::MaintenanceTaskStatus::Pending,
                    priority: 0,
                    created_at: Utc::now(),
                    started_at: None,
                    completed_at: None,
                    result: None,
                    error: None,
                }
            })
            .collect();

        // Set up a runtime and scheduler
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let (temp_dir, repo_names) = runtime.block_on(async {
            setup_test_repositories(10).unwrap() // Just need a few real repos for the scheduler
        });

        let config = create_benchmark_config(&temp_dir, &repo_names);
        let scheduler = create_scheduler(&config);

        // Benchmark task prioritization
        group.bench_with_input(
            BenchmarkId::new("prioritize_tasks", task_count),
            task_count,
            |b, _| {
                let scheduler_clone = scheduler.clone();
                let tasks_clone = tasks.clone();
                let health_reports_clone = health_reports.clone();

                b.to_async(&runtime).iter(move || {
                    let s = scheduler_clone.clone();
                    let t = tasks_clone.clone();
                    let h = health_reports_clone.clone();

                    async move {
                        let _ = s.prioritize_tasks(&t, &h).await;
                    }
                });
            }
        );
    }

    group.finish();
}

/// Benchmark task scheduling performance
fn bench_task_scheduling(c: &mut Criterion) {
    let mut group = c.benchmark_group("task_scheduling");

    // Set up test repositories
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let (temp_dir, repo_names) = runtime.block_on(async {
        setup_test_repositories(10).unwrap()
    });

    let config = create_benchmark_config(&temp_dir, &repo_names);
    let scheduler = create_scheduler(&config);

    // Test scheduling performance for different task types
    for task_type in ["gc", "repack", "fsck", "prune", "reflog"].iter() {
        group.bench_with_input(
            BenchmarkId::new("schedule_task", task_type),
            task_type,
            |b, &task_type| {
                let scheduler_clone = scheduler.clone();
                let repo_name = repo_names[0].clone();

                b.to_async(&runtime).iter(move || {
                    let s = scheduler_clone.clone();
                    let r = repo_name.clone();
                    let t = task_type.to_string();

                    async move {
                        let _ = s.schedule_task(&r, t).await.unwrap();
                    }
                });
            }
        );
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_health_check,
    bench_task_prioritization,
    bench_task_scheduling
);
criterion_main!(benches);
