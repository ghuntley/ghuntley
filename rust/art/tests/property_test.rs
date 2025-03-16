use art::util::{
    normalize_path,
    mime_type_for_path,
    highlight_syntax,
    format_timestamp,
    is_binary_content,
    get_file_extension,
    sanitize_branch_name,
    parent_path,
};
use art::config::Config;
use art::error::Result;
use art::service::repository::maintenance::{
    RepositoryHealth,
    MaintenanceTask,
    MaintenanceTaskStatus,
    HealthStatus,
    MaintenanceScheduler
};

use chrono::{DateTime, Utc, TimeZone};
use proptest::prelude::*;
use std::path::PathBuf;

proptest! {
    // Test that normalize_path behaves correctly for all inputs
    #[test]
    fn test_normalize_path_prop(path in "(/[a-zA-Z0-9._\\-]+)+") {
        let normalized = normalize_path(&path);

        // Normalized path should never have consecutive slashes
        assert!(!normalized.contains("//"));

        // Normalized path should never end with a slash unless it's just "/"
        if normalized.len() > 1 {
            assert!(!normalized.ends_with('/'));
        }

        // Normalized path should always start with a slash
        assert!(normalized.starts_with('/'));
    }

    // Test that normalize_path handles directory traversal correctly
    #[test]
    fn test_normalize_path_traversal_prop(
        path_components in prop::collection::vec("[a-zA-Z0-9._\\-]+", 0..10),
        parent_dirs in prop::collection::vec("../", 0..5),
    ) {
        let path = path_components.join("/");
        let path_with_traversal = format!("{}{}", parent_dirs.join(""), path);

        let normalized = normalize_path(&path_with_traversal);

        // Normalized path should never contain directory traversal sequences
        assert!(!normalized.contains("../"));

        // Check that path is still valid after normalization
        assert!(normalized.is_empty() || normalized.starts_with('/'));
    }

    // Test that mime_type_for_path returns consistent results
    #[test]
    fn test_mime_type_prop(
        filename in "[a-zA-Z0-9_\\-]+\\.[a-z0-9]{1,5}",
    ) {
        let mime = mime_type_for_path(&filename);

        // MIME type should never be empty
        assert!(!mime.is_empty());

        // MIME type should be in the format type/subtype
        assert!(mime.contains('/'));
        assert_eq!(mime.matches('/').count(), 1);

        let parts: Vec<&str> = mime.split('/').collect();
        assert_eq!(parts.len(), 2);
        assert!(!parts[0].is_empty());
        assert!(!parts[1].is_empty());
    }

    // Test that is_binary_content is consistent
    #[test]
    fn test_binary_detection_prop(
        // Generate a mix of ASCII text and binary data
        content in prop::collection::vec(0u8..=255, 1..1000),
    ) {
        let is_binary = is_binary_content(&content);

        // If content has a null byte (0x00), it should be classified as binary
        let has_null = content.contains(&0u8);
        if has_null {
            assert!(is_binary, "Content with null bytes should be detected as binary");
        }

        // If we have a high ratio of non-ASCII characters, it should be binary
        let non_ascii_count = content.iter().filter(|&&b| b > 127).count();
        let non_ascii_ratio = non_ascii_count as f64 / content.len() as f64;

        if non_ascii_ratio > 0.3 {
            assert!(is_binary, "Content with >30% non-ASCII bytes should be binary");
        }
    }

    // Test that get_file_extension works correctly
    #[test]
    fn test_file_extension_prop(
        filename in "[a-zA-Z0-9_\\-]+\\.[a-z0-9]{1,5}",
    ) {
        let extension = get_file_extension(&filename);

        // Extension should be present if the filename contains a dot
        assert!(extension.is_some());

        // Extension should match what comes after the last dot
        if let Some(ext) = extension {
            let parts: Vec<&str> = filename.split('.').collect();
            assert_eq!(ext, parts.last().unwrap());
        }
    }

    // Test that format_timestamp produces a valid date string
    #[test]
    fn test_timestamp_format_prop(
        // Generate a reasonable range of timestamps (last ~50 years)
        timestamp in 0..1672531200i64, // Up to 2023-01-01
    ) {
        let result = format_timestamp(timestamp);

        // Formatted timestamp should not be empty
        assert!(!result.is_empty());

        // Should contain a year, month, and day separated by dashes or spaces
        let contains_date_format = result.contains('-') || result.contains(' ');
        assert!(contains_date_format);

        // Should be parsable as a date using common date formats
        // (This is difficult to test generally, so we'll just check for basic structure)
        assert!(result.len() >= 8); // At least YYYY-MM-DD
    }

    // Test that sanitize_branch_name properly filters unsafe characters
    #[test]
    fn test_sanitize_branch_name_prop(
        branch_name in ".*",
    ) {
        let sanitized = sanitize_branch_name(&branch_name);

        // Sanitized name should not contain special Git-unfriendly characters
        assert!(!sanitized.contains(|c: char| c == '/' || c == '\\' || c == ':' || c == '?' ||
                                  c == '*' || c == '[' || c == ']' || c == '~' || c == '^' ||
                                  c == '@' || c == '{' || c == '}' || c == '<' || c == '>' ||
                                  c < ' ')); // No control characters

        // Should not end with .lock
        assert!(!sanitized.ends_with(".lock"));

        // Should not be .. or .
        assert!(sanitized != ".." && sanitized != ".");

        // Should not end with a dot
        assert!(!sanitized.ends_with('.'));
    }

    // Test that parent_path calculates correct parent directories
    #[test]
    fn test_parent_path_prop(
        path_segments in prop::collection::vec("[a-zA-Z0-9_\\-]+", 1..10),
    ) {
        let path = format!("/{}", path_segments.join("/"));
        let parent = parent_path(&path);

        if path == "/" || path.trim_start_matches('/').is_empty() {
            // Root should return itself as parent
            assert_eq!(parent, "/");
        } else {
            // Parent should be a prefix of the original path
            assert!(path.starts_with(&parent));

            // Parent should be a valid path (starts with slash)
            assert!(parent.starts_with('/'));

            // Parent should have fewer components than the original path
            let original_components = path.split('/').filter(|s| !s.is_empty()).count();
            let parent_components = parent.split('/').filter(|s| !s.is_empty()).count();
            assert!(parent_components < original_components);
        }
    }

    // Test that highlight_syntax handles various syntaxes without crashing
    #[test]
    fn test_highlight_syntax_prop(
        code in "[\\x20-\\x7E\\n\\t]{1,1000}", // Printable ASCII with newlines and tabs
        extension in prop::sample::select(&["rs", "py", "js", "html", "css", "md", "txt", "json", "yaml", "toml"]),
    ) {
        let filename = format!("test.{}", extension);
        let path = PathBuf::from(&filename);

        // This test just ensures that highlight_syntax doesn't panic
        let _ = highlight_syntax(&path, &code);

        // We can't assert much about the result without knowing the specific syntax highlighter,
        // but we can at least check that it processes input without crashing
    }

    // Test that repository health status is consistent
    #[test]
    fn test_repository_health_status_prop(
        repo_name in "[a-zA-Z0-9_\\-]{1,50}",
        object_count in 1u32..100_000u32,
        loose_object_count in 1u32..10_000u32,
        ref_count in 1u32..500u32,
        repo_size_kb in 1u64..1_000_000u64,
        days_since_gc in 0u32..365u32,
    ) {
        let health = RepositoryHealth {
            repository_name: repo_name.clone(),
            object_count,
            loose_object_count,
            ref_count,
            repository_size_kb: repo_size_kb,
            days_since_gc,
            status: HealthStatus::Unknown, // Will be computed
            issues: Vec::new(),            // Will be populated
            last_checked: Utc::now(),
        };

        // Calculate health status based on inputs
        let analyzed_health = health.analyze();

        // Health status should be consistently derived from inputs
        if loose_object_count > 5_000 || days_since_gc > 90 {
            assert_eq!(analyzed_health.status, HealthStatus::Critical);
            assert!(!analyzed_health.issues.is_empty());
        } else if loose_object_count > 2_000 || days_since_gc > 30 {
            assert_eq!(analyzed_health.status, HealthStatus::Warning);
            assert!(!analyzed_health.issues.is_empty());
        } else {
            assert_eq!(analyzed_health.status, HealthStatus::Good);
        }

        // Repository name should remain unchanged
        assert_eq!(analyzed_health.repository_name, repo_name);
    }

    // Test maintenance task priority calculation
    #[test]
    fn test_maintenance_task_priority_prop(
        repo_name in "[a-zA-Z0-9_\\-]{1,50}",
        task_type in prop::sample::select(&["gc", "repack", "fsck", "prune", "reflog"]),
        loose_object_count in 1u32..10_000u32,
        days_since_last_run in 0u32..365u32,
    ) {
        let health = RepositoryHealth {
            repository_name: repo_name.clone(),
            object_count: 10_000,
            loose_object_count,
            ref_count: 100,
            repository_size_kb: 10_000,
            days_since_gc: days_since_last_run,
            status: HealthStatus::Unknown,
            issues: Vec::new(),
            last_checked: Utc::now(),
        };

        let task = MaintenanceTask {
            id: format!("task-{}", Uuid::new_v4()),
            repository_name: repo_name,
            task_type: task_type.to_string(),
            status: MaintenanceTaskStatus::Pending,
            priority: 0, // Will be calculated
            created_at: Utc::now(),
            started_at: None,
            completed_at: None,
            result: None,
            error: None,
        };

        // Calculate priority based on health
        let prioritized_task = MaintenanceScheduler::calculate_task_priority(&task, &health);

        // Priority should increase with loose object count and days since last run
        assert!(prioritized_task.priority > 0);

        // "gc" tasks should have higher priority with more loose objects
        if task_type == "gc" && loose_object_count > 5_000 {
            assert!(prioritized_task.priority >= 80);
        }

        // Any task should have higher priority if it hasn't been run in a long time
        if days_since_last_run > 90 {
            assert!(prioritized_task.priority >= 70);
        }

        // Task metadata should remain unchanged except for priority
        assert_eq!(prioritized_task.repository_name, task.repository_name);
        assert_eq!(prioritized_task.task_type, task.task_type);
        assert_eq!(prioritized_task.status, task.status);
    }

    // Test task status transitions
    #[test]
    fn test_maintenance_task_status_transitions_prop(
        task_type in prop::sample::select(&["gc", "repack", "fsck", "prune", "reflog"]),
        status in prop::sample::select(&[
            MaintenanceTaskStatus::Pending,
            MaintenanceTaskStatus::Running,
            MaintenanceTaskStatus::Completed,
            MaintenanceTaskStatus::Failed
        ]),
        error_msg in option::of("[a-zA-Z0-9_\\-\\s]{1,50}"),
    ) {
        let mut task = MaintenanceTask {
            id: format!("task-{}", Uuid::new_v4()),
            repository_name: "test-repo".to_string(),
            task_type: task_type.to_string(),
            status,
            priority: 50,
            created_at: Utc::now(),
            started_at: None,
            completed_at: None,
            result: None,
            error: None,
        };

        match status {
            MaintenanceTaskStatus::Pending => {
                // Pending can transition to Running
                task.mark_running();
                assert_eq!(task.status, MaintenanceTaskStatus::Running);
                assert!(task.started_at.is_some());
            },
            MaintenanceTaskStatus::Running => {
                // Running can transition to Completed or Failed
                if error_msg.is_some() {
                    task.mark_failed(error_msg.unwrap());
                    assert_eq!(task.status, MaintenanceTaskStatus::Failed);
                    assert!(task.error.is_some());
                } else {
                    task.mark_completed("Success".to_string());
                    assert_eq!(task.status, MaintenanceTaskStatus::Completed);
                    assert!(task.result.is_some());
                }
                assert!(task.completed_at.is_some());
            },
            MaintenanceTaskStatus::Completed | MaintenanceTaskStatus::Failed => {
                // Terminal states can't transition
                let original_status = task.status;

                // Trying to transition should have no effect or panic
                if let Err(_) = std::panic::catch_unwind(|| {
                    task.mark_running();
                }) {
                    // If it panics, that's also acceptable for invalid transitions
                } else {
                    // If it doesn't panic, status should be unchanged
                    assert_eq!(task.status, original_status);
                }
            }
        }
    }
}

// Test Config serialization and deserialization consistency
#[test]
fn test_config_serde_consistency() -> Result<()> {
    use proptest::arbitrary::any;
    use proptest::strategy::{Strategy, ValueTree};

    proptest!(|(
        host in "[a-zA-Z0-9\\-\\.]+",
        port in 1024..65535u16,
        max_commits in 10..1000u32,
        cache_entries in 100..10000u32,
        cache_ttl in 10..3600u32,
    )| {
        let temp_dir = tempfile::tempdir()?;
        let repo_dir = temp_dir.path().to_path_buf();
        let db_path = temp_dir.path().join("test.db");

        // Create a config with the generated values
        let config = Config {
            server_host: host.clone(),
            server_port: port,
            repository: art::config::RepositoryConfig {
                repo_dir: repo_dir.clone(),
                max_commits: max_commits,
                default_branch: "main".to_string(),
            },
            database: art::config::DatabaseConfig {
                path: db_path.clone(),
                use_cache: true,
                cache_max_entries: cache_entries,
                cache_ttl_seconds: cache_ttl,
            },
            log_level: "debug".to_string(),
        };

        // Serialize the config to TOML
        let config_toml = toml::to_string(&config)?;

        // Deserialize the TOML back to a Config
        let parsed_config: Config = toml::from_str(&config_toml)?;

        // Check that the configs are equivalent
        assert_eq!(config.server_host, parsed_config.server_host);
        assert_eq!(config.server_port, parsed_config.server_port);
        assert_eq!(config.repository.max_commits, parsed_config.repository.max_commits);
        assert_eq!(config.repository.default_branch, parsed_config.repository.default_branch);
        assert_eq!(config.database.use_cache, parsed_config.database.use_cache);
        assert_eq!(config.database.cache_max_entries, parsed_config.database.cache_max_entries);
        assert_eq!(config.database.cache_ttl_seconds, parsed_config.database.cache_ttl_seconds);
        assert_eq!(config.log_level, parsed_config.log_level);

        Ok::<(), art::error::Error>(())
    })?;

    Ok(())
}
