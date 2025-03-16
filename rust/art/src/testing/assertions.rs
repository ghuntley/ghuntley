// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Test assertions for Art
//!
//! This module provides assertion helpers for unit and integration testing.

use crate::prelude::*;
use crate::service::repository::Repository;
use crate::data::git::Commit;
use crate::service::observability::{LogEntry, HealthResponse};
use std::time::Duration;
use futures::Future;
use std::path::PathBuf;

/// Assert that a result is Ok and return the inner value
pub fn assert_ok<T, E: std::fmt::Debug>(result: Result<T, E>) -> T {
    match result {
        Ok(value) => value,
        Err(err) => {
            panic!("Expected Ok, got Err: {:?}", err);
        }
    }
}

/// Assert that a result is Err and return the inner error
pub fn assert_err<T: std::fmt::Debug, E>(result: Result<T, E>) -> E {
    match result {
        Ok(value) => {
            panic!("Expected Err, got Ok: {:?}", value);
        }
        Err(err) => err,
    }
}

/// Assert that a repository exists
pub fn assert_repository_exists(repo: &Repository) {
    assert!(!repo.name.is_empty(), "Repository name should not be empty");
    assert!(repo.path.exists(), "Repository path should exist");
    assert!(
        repo.path.join(".git").exists() || repo.path.join("objects").exists(),
        "Repository should have Git data"
    );
}

/// Assert that a commit has valid properties
pub fn assert_valid_commit(commit: &Commit) {
    assert!(!commit.hash.is_empty(), "Commit hash should not be empty");
    assert!(!commit.message.is_empty(), "Commit message should not be empty");
    assert!(!commit.author.name.is_empty(), "Author name should not be empty");
    assert!(!commit.author.email.is_empty(), "Author email should not be empty");
}

/// Assert that a future completes within a time limit
pub async fn assert_completes_within<F, T>(future: F, timeout: Duration) -> T
where
    F: Future<Output = T>,
{
    let result = tokio::time::timeout(timeout, future).await;
    match result {
        Ok(value) => value,
        Err(_) => {
            panic!("Future did not complete within timeout of {:?}", timeout);
        }
    }
}

/// Assert that a path exists with the expected content
pub fn assert_file_content(path: impl AsRef<std::path::Path>, expected: &str) {
    let path = path.as_ref();
    assert!(path.exists(), "File does not exist: {:?}", path);

    let content = std::fs::read_to_string(path).unwrap_or_else(|e| {
        panic!("Failed to read file {:?}: {}", path, e);
    });

    assert_eq!(content, expected, "File content does not match expected");
}

/// Assert that a log entry has the expected properties
pub fn assert_log_entry(log: &LogEntry, level: &str, contains_message: &str) {
    assert_eq!(
        log.level.to_string().to_lowercase(),
        level.to_lowercase(),
        "Log level does not match"
    );
    assert!(
        log.message.contains(contains_message),
        "Log message '{}' does not contain '{}'",
        log.message,
        contains_message
    );
    assert!(!log.timestamp.to_rfc3339().is_empty(), "Timestamp should not be empty");
}

/// Assert that a health response indicates a healthy system
pub fn assert_healthy(health: &HealthResponse) {
    assert_eq!(health.status, "ok", "Health status should be 'ok'");
    assert!(health.uptime > 0, "Uptime should be greater than 0");
    assert!(!health.version.is_empty(), "Version should not be empty");

    // Check that all components are healthy
    for (component, status) in &health.components {
        assert_eq!(
            status.status, "ok",
            "Component '{}' is not healthy: {:?}",
            component, status
        );
    }

    // Check that system metrics are present and reasonable
    if let Some(metrics) = &health.system_metrics {
        assert!(metrics.cpu_usage >= 0.0 && metrics.cpu_usage <= 100.0,
            "CPU usage should be between 0% and 100%");
        assert!(metrics.memory_usage > 0,
            "Memory usage should be greater than 0");
    }
}

/// Assert that a collection contains an expected item
pub fn assert_contains<T, I>(collection: I, expected: &T)
where
    T: PartialEq + std::fmt::Debug,
    I: IntoIterator<Item = T>,
{
    let items: Vec<T> = collection.into_iter().collect();
    assert!(
        items.iter().any(|item| item == expected),
        "Collection {:?} does not contain expected item {:?}",
        items,
        expected
    );
}

/// Assert that a string contains an expected substring
pub fn assert_contains_str(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "String '{}' does not contain '{}'",
        haystack,
        needle
    );
}

/// Assert that a string doesn't contain a forbidden substring
pub fn assert_not_contains_str(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "String '{}' should not contain '{}'",
        haystack,
        needle
    );
}

/// Assert that a path is a valid Git repository
pub fn assert_git_repo(path: impl AsRef<std::path::Path>) {
    let path = path.as_ref();
    assert!(path.exists(), "Repository path does not exist");

    // Check for .git directory (normal repos) or objects directory (bare repos)
    let is_repo = path.join(".git").exists() || path.join("objects").exists();
    assert!(is_repo, "Path is not a valid Git repository: {:?}", path);

    // Try to run git status
    let status = std::process::Command::new("git")
        .arg("status")
        .current_dir(path)
        .output();

    assert!(status.is_ok(), "Failed to run git status in repository");
    assert!(status.unwrap().status.success(), "git status failed in repository");
}

/// Assert that a future execution time is within expected bounds
pub async fn assert_execution_time<F, T>(future: F, min: Duration, max: Duration) -> T
where
    F: Future<Output = T>,
{
    let start = std::time::Instant::now();
    let result = future.await;
    let elapsed = start.elapsed();

    assert!(
        elapsed >= min,
        "Execution time {:?} is less than minimum {:?}",
        elapsed,
        min
    );

    assert!(
        elapsed <= max,
        "Execution time {:?} exceeds maximum {:?}",
        elapsed,
        max
    );

    result
}

/// Assert that the DB connection is working
pub async fn assert_db_connected<DB: DatabaseConnection>(db: &DB) {
    let result = db.is_connected().await;
    assert!(result.is_ok(), "Database connection failed: {:?}", result.err());
}

/// Trait for database connections used by assertions
#[async_trait::async_trait]
pub trait DatabaseConnection {
    /// Check if the database is connected
    async fn is_connected(&self) -> Result<()>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::repository::Repository;
    use std::collections::HashMap;
    use std::path::Path;
    use tempfile::tempdir;

    #[test]
    fn test_assert_ok() {
        let result: Result<i32, &str> = Ok(42);
        let value = assert_ok(result);
        assert_eq!(value, 42);

        // Should panic
        //let result: Result<i32, &str> = Err("error");
        //assert_ok(result);
    }

    #[test]
    fn test_assert_err() {
        let result: Result<i32, &str> = Err("error");
        let err = assert_err(result);
        assert_eq!(err, "error");

        // Should panic
        //let result: Result<i32, &str> = Ok(42);
        //assert_err(result);
    }

    #[test]
    fn test_assert_contains_str() {
        assert_contains_str("hello world", "world");

        // Should panic
        //assert_contains_str("hello world", "moon");
    }

    #[test]
    fn test_assert_not_contains_str() {
        assert_not_contains_str("hello world", "moon");

        // Should panic
        //assert_not_contains_str("hello world", "world");
    }

    #[test]
    fn test_assert_file_content() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test.txt");
        std::fs::write(&file_path, "hello world").unwrap();

        assert_file_content(&file_path, "hello world");

        // Should panic
        //assert_file_content(&file_path, "wrong content");
    }

    #[tokio::test]
    async fn test_assert_completes_within() {
        let future = async {
            tokio::time::sleep(Duration::from_millis(10)).await;
            42
        };

        let result = assert_completes_within(future, Duration::from_millis(100)).await;
        assert_eq!(result, 42);

        // Should panic
        //assert_completes_within(future, Duration::from_millis(5)).await;
    }
}
