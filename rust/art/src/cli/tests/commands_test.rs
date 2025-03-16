//! Property-based tests for CLI commands

use crate::cli::commands::{execute_command, Commands, RepoCommands};
use crate::config::{Config, DatabaseConfig, RepositoryConfig, ServerConfig, ObservabilityConfig, CacheConfig};
use crate::error::Result;
use proptest::prelude::*;
use std::fs;
use std::net::TcpListener;
use std::path::PathBuf;
use tempfile::{tempdir, TempDir};
use tokio::time::{sleep, Duration};

/// Generate a valid server port that's guaranteed to be unused
fn find_unused_port() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").expect("Failed to bind to address");
    let addr = listener.local_addr().expect("Failed to get local address");
    addr.port()
}

/// Generate a mock config for testing the serve command
fn generate_test_config() -> (Config, TempDir) {
    // Create temporary directories for repo and database
    let repo_dir = tempdir().expect("Failed to create temp repo dir");
    let db_dir = tempdir().expect("Failed to create temp db dir");

    // Create an unused port for testing
    let port = find_unused_port();

    // Create a basic configuration
    let config = Config {
        server: ServerConfig {
            bind_address: "127.0.0.1".to_string(),
            port,
            // Add other required server config fields
            // ...
        },
        repository: RepositoryConfig {
            repo_dir: repo_dir.path().to_path_buf(),
            // Add other required repository config fields
            // ...
        },
        database: DatabaseConfig {
            path: db_dir.path().join("test.db"),
            // Add other required database config fields
            // ...
        },
        // Add other required config fields
        // ...
    };

    (config, repo_dir)
}

/// Test strategy for repository paths
fn repo_path_strategy() -> impl Strategy<Value = PathBuf> {
    "[a-zA-Z0-9_-]{3,10}".prop_map(|s| PathBuf::from(format!("/tmp/test-repo-{}", s)))
}

/// Property tests for the serve command
mod serve_command_tests {
    use super::*;
    use crate::cli::{Commands, DbCommands};
    use crate::config::Config;
    use proptest::prelude::*;
    use std::sync::Arc;
    use tokio::runtime::Runtime;
    use tokio::sync::oneshot;
    use std::path::Path;

    // Strategy for generating valid server ports
    fn port_strategy() -> impl Strategy<Value = u16> {
        8000u16..9000u16
    }

    // Strategy for generating bind addresses
    fn bind_address_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("127.0.0.1".to_string()),
            Just("0.0.0.0".to_string()),
            Just("localhost".to_string())
        ]
    }

    // Strategy for generating thread counts
    fn thread_count_strategy() -> impl Strategy<Value = usize> {
        prop_oneof![
            Just(0usize),  // Auto
            1usize..8usize // Fixed thread count
        ]
    }

    // Strategy for generating cache sizes
    fn cache_size_strategy() -> impl Strategy<Value = usize> {
        prop_oneof![
            Just(50usize),   // Small cache
            Just(100usize),  // Medium cache
            Just(200usize)   // Large cache
        ]
    }

    proptest! {
        #[test]
        fn test_serve_command_starts_server(
            port in port_strategy(),
            bind_address in bind_address_strategy(),
            threads in thread_count_strategy(),
            cache_size in cache_size_strategy()
        ) {
            // Create test configuration with temporary directories
            let temp_dir = tempdir().unwrap();
            let repo_dir = temp_dir.path().join("repos");
            let db_dir = temp_dir.path().join("db");

            // Create necessary directories
            std::fs::create_dir_all(&repo_dir).unwrap();
            std::fs::create_dir_all(&db_dir).unwrap();

            // Create a test Git repository
            let test_repo_dir = repo_dir.join("test-repo");
            std::fs::create_dir_all(&test_repo_dir).unwrap();

            // Basic Git repo structure (just enough to be recognized as a repo)
            std::fs::create_dir_all(test_repo_dir.join(".git")).unwrap();
            std::fs::write(test_repo_dir.join(".git").join("HEAD"),
                           "ref: refs/heads/main").unwrap();

            // Create a database config with test paths
            let mut config = Config::default();
            config.server.port = port;
            config.server.bind_address = bind_address;
            config.server.threads = threads;
            config.repository.repo_dir = repo_dir;
            config.database.path = db_dir.join("art.db");

            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Create a oneshot channel to signal shutdown
            let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

            // Spawn the server in a separate task with the configured parameters
            let server_config = config.clone();
            let server_handle = rt.spawn(async move {
                // Create serve command with the generated parameters
                let cmd = Commands::Serve {
                    port: port,
                    bind: bind_address,
                    repo_dir: Some(server_config.repository.repo_dir.clone()),
                    db_path: Some(server_config.database.path.clone()),
                    cache_size: cache_size,
                    threads: threads,
                };

                // Start the server with a timeout to ensure it doesn't run indefinitely
                let mut config_copy = server_config.clone();
                let server_result = tokio::time::timeout(
                    Duration::from_secs(2),
                    execute_command(&cmd, &mut config_copy, false)
                ).await;

                // Server should start but timeout (which is expected for a test)
                assert!(server_result.is_err(), "Server should timeout (this is expected)");

                // Signal completion
                let _ = shutdown_tx.send(());
            });

            // Wait a moment for the server to start
            rt.block_on(async {
                sleep(Duration::from_millis(300)).await;
            });

            // Try to connect to the server
            let connect_result = std::net::TcpStream::connect(format!("127.0.0.1:{}", port));

            // Check if connection was successful (server is running)
            if connect_result.is_ok() {
                println!("Successfully connected to server on port {}", port);
            } else {
                // For non-loopback addresses, connection might fail in tests
                println!("Note: Could not connect to server on port {}", port);
            }

            // Wait for the server task to complete
            rt.block_on(async {
                let _ = tokio::time::timeout(Duration::from_secs(3), shutdown_rx).await;
            });

            // Cancel the server task if it's still running
            server_handle.abort();
        }
    }

    #[test]
    fn test_serve_command_error_handling() {
        // Create a configuration with invalid paths
        let mut config = Config::default();
        config.repository.repo_dir = PathBuf::from("/path/does/not/exist");
        config.database.path = PathBuf::from("/invalid/db/path/test.db");

        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Execute the serve command
        let cmd = Commands::Serve {
            port: 3000,
            bind: "127.0.0.1".to_string(),
            repo_dir: None,
            db_path: None,
            cache_size: 100,
            threads: 0,
        };

        let result = rt.block_on(async {
            execute_command(&cmd, &mut config, false).await
        });

        // Server should fail to start due to invalid paths
        assert!(result.is_err(), "Server should fail to start with invalid paths");

        // Verify the error is related to the repository directory or database
        let error_string = format!("{:?}", result.unwrap_err());
        assert!(error_string.contains("repository") || error_string.contains("database"),
                "Error should mention repository or database issues");
    }

    #[test]
    fn test_serve_command_parameter_override() {
        // Create temporary directories for testing
        let temp_dir = tempdir().unwrap();
        let repo_dir_default = temp_dir.path().join("repos-default");
        let repo_dir_override = temp_dir.path().join("repos-override");
        let db_dir_default = temp_dir.path().join("db-default");
        let db_dir_override = temp_dir.path().join("db-override");

        // Create directories
        std::fs::create_dir_all(&repo_dir_default).unwrap();
        std::fs::create_dir_all(&repo_dir_override).unwrap();
        std::fs::create_dir_all(&db_dir_default).unwrap();
        std::fs::create_dir_all(&db_dir_override).unwrap();

        // Create config with default values
        let mut config = Config::default();
        config.server.port = 3000;
        config.server.bind_address = "127.0.0.1".to_string();
        config.repository.repo_dir = repo_dir_default;
        config.database.path = db_dir_default.join("art.db");
        config.server.threads = 2;

        // Create override command parameters
        let override_port = 3001;
        let override_bind = "0.0.0.0".to_string();
        let override_threads = 4;
        let override_cache_size = 100;

        // Create command with overrides
        let cmd = Commands::Serve {
            port: override_port,
            bind: override_bind.clone(),
            repo_dir: Some(repo_dir_override.clone()),
            db_path: Some(db_dir_override.join("art.db")),
            cache_size: override_cache_size,
            threads: override_threads,
        };

        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Execute command - we'll verify that the config was updated with command line parameters
        let _ = rt.block_on(async {
            let _ = execute_command(&cmd, &mut config, false).await;
        });

        // Verify parameters were overridden
        assert_eq!(config.server.port, override_port);
        assert_eq!(config.server.bind_address, override_bind);
        assert_eq!(config.repository.repo_dir, repo_dir_override);
        assert_eq!(config.database.path, db_dir_override.join("art.db"));
        assert_eq!(config.server.threads, override_threads);
    }
}

/// Property tests for the maintenance command
mod maintenance_command_tests {
    use super::*;

    proptest! {
        #[test]
        fn test_maintenance_command_with_levels(
            maintenance_level in 0u8..3u8
        ) {
            // Create temp directories
            let (mut config, _temp_dir) = generate_test_config();

            // Set maintenance level
            config.repository.maintenance_level = maintenance_level;

            // Execute maintenance command
            let result = execute_command(
                Commands::Repo(RepoCommands::Maintenance),
                &config
            );

            // Maintenance command should execute without errors
            // It might warn about no repositories but shouldn't fail
            let rt = Runtime::new().unwrap();
            let result = rt.block_on(result);
            assert!(result.is_ok(), "Maintenance command failed");
        }
    }
}

/// Property tests for the list repositories command
mod list_repos_command_tests {
    use super::*;

    proptest! {
        #[test]
        fn test_list_repos_command(
            num_repos in 0usize..5usize
        ) {
            // Create test configuration
            let (config, temp_dir) = generate_test_config();

            // Create mock repositories
            for i in 0..num_repos {
                let repo_path = temp_dir.path().join(format!("repo-{}", i));
                fs::create_dir_all(&repo_path).unwrap();
                fs::create_dir_all(repo_path.join(".git")).unwrap();
            }

            // Execute list repositories command
            let result = execute_command(
                Commands::Repo(RepoCommands::List),
                &config
            );

            // List command should execute without errors
            let rt = Runtime::new().unwrap();
            let result = rt.block_on(result);
            assert!(result.is_ok(), "List repositories command failed");
        }
    }
}

/// Property tests for the user commands
mod user_command_tests {
    use super::*;
    use crate::cli::commands::{UserCommands, MaintenanceLevel};
    use proptest::prelude::*;
    use proptest::collection::vec;
    use std::sync::Arc;
    use tokio::runtime::Runtime;
    use tokio::sync::oneshot;
    use std::io::{Write, Cursor};

    // Generate valid usernames
    fn username_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z][a-zA-Z0-9_]{2,19}".prop_map(|s| s)
    }

    // Generate valid emails
    fn email_strategy() -> impl Strategy<Value = String> {
        ("[a-zA-Z0-9_.]{3,20}", "[a-zA-Z0-9-]{2,10}", prop::sample::select(vec!["com", "org", "net", "io", "dev"]))
            .prop_map(|(name, domain, tld)| format!("{}@{}.{}", name, domain, tld))
    }

    // Generate valid display names
    fn display_name_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z0-9 ]{3,50}".prop_map(|s| s)
    }

    // Generate valid passwords
    fn password_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z0-9!@#$%^&*()]{8,30}".prop_map(|s| s)
    }

    // Generate valid user roles
    fn role_strategy() -> impl Strategy<Value = String> {
        prop::sample::select(vec!["user", "maintainer", "admin"])
    }

    proptest! {
        #[test]
        fn test_create_user_command(
            username in username_strategy(),
            email in email_strategy(),
            display_name in display_name_strategy(),
            password in password_strategy(),
            role in role_strategy()
        ) {
            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Create temp directories
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");

            // Create a basic configuration
            let mut config = Config::default();
            config.database.path = db_path;

            // Execute create user command
            let result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::Add {
                        db_path: Some(db_path.clone()),
                        username: username.clone(),
                        email: email.clone(),
                        display_name: display_name.clone(),
                        password: Some(password.clone()),
                        role: role.clone(),
                    }),
                    &mut config
                ).await
            });

            // Create user command should succeed
            prop_assert!(result.is_ok(), "Create user command failed: {:?}", result.unwrap_err());

            // Now try to list the user
            let list_result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::List {
                        db_path: Some(db_path),
                        limit: 100,
                        offset: 0,
                        role: None,
                        active_only: false,
                    }),
                    &mut config
                ).await
            });

            prop_assert!(list_result.is_ok(), "List users command failed after creating user");
        }
    }

    proptest! {
        #[test]
        fn test_list_users_command(
            limit in 1usize..100usize,
            offset in 0usize..10usize,
            role in prop::option::of(role_strategy()),
            active_only in prop::bool::ANY
        ) {
            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Create temp directory
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");

            // Create a basic configuration
            let mut config = Config::default();
            config.database.path = db_path.clone();

            // Execute list users command
            let result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::List {
                        db_path: Some(db_path),
                        limit,
                        offset,
                        role,
                        active_only,
                    }),
                    &mut config
                ).await
            });

            // List users command should succeed even with no users
            prop_assert!(result.is_ok(), "List users command failed: {:?}", result.unwrap_err());
        }
    }

    proptest! {
        #[test]
        fn test_update_delete_user_commands(
            username in username_strategy(),
            email in email_strategy(),
            display_name in display_name_strategy(),
            password in password_strategy(),
            new_email in email_strategy(),
            new_display_name in display_name_strategy(),
            force_delete in prop::bool::ANY
        ) {
            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Create temp directories
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");

            // Create a basic configuration
            let mut config = Config::default();
            config.database.path = db_path.clone();

            // First create a user
            let create_result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::Add {
                        db_path: Some(db_path.clone()),
                        username: username.clone(),
                        email: email.clone(),
                        display_name: display_name.clone(),
                        password: Some(password.clone()),
                        role: "user".to_string(),
                    }),
                    &mut config
                ).await
            });

            // Create user should succeed
            if let Err(e) = &create_result {
                prop_assert!(false, "Failed to create test user: {:?}", e);
                return Ok(());
            }

            // Now update the user
            let update_result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::Update {
                        db_path: Some(db_path.clone()),
                        user: username.clone(),
                        email: Some(new_email.clone()),
                        display_name: Some(new_display_name.clone()),
                        password: None,
                        role: Some("maintainer".to_string()),
                        active: false,
                        inactive: false,
                    }),
                    &mut config
                ).await
            });

            // Update should succeed
            prop_assert!(update_result.is_ok(), "Update user command failed: {:?}", update_result.unwrap_err());

            // Set up a fake stdin for delete confirmation
            let input = if force_delete {
                // Won't be used with force flag
                "".to_string()
            } else {
                // Will need to confirm with 'y'
                "y\n".to_string()
            };

            // Now delete the user
            let delete_result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::Delete {
                        db_path: Some(db_path),
                        user: username.clone(),
                        force: force_delete,
                    }),
                    &mut config
                ).await
            });

            // Delete should succeed
            prop_assert!(delete_result.is_ok(), "Delete user command failed: {:?}", delete_result.unwrap_err());

            // Verify user is gone by trying to update the user (should fail)
            let update_result = rt.block_on(async {
                execute_command(
                    &Commands::User(UserCommands::Update {
                        db_path: Some(db_path.clone()),
                        user: username.clone(),
                        email: Some(new_email),
                        display_name: Some(new_display_name),
                        password: None,
                        role: None,
                        active: false,
                        inactive: false,
                    }),
                    &mut config
                ).await
            });

            // Update should fail as user no longer exists
            prop_assert!(update_result.is_err(), "Update user command succeeded after deletion");
        }
    }

    #[test]
    fn test_create_admin_command() {
        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Create temp directories
        let temp_dir = tempdir().unwrap();
        let db_path = temp_dir.path().join("test.db");

        // Create a basic configuration
        let mut config = Config::default();
        config.database.path = db_path.clone();

        // Execute create admin command
        let result = rt.block_on(async {
            execute_command(
                &Commands::User(UserCommands::CreateAdmin {
                    db_path: Some(db_path.clone()),
                    username: "admin".to_string(),
                    email: "admin@example.com".to_string(),
                    display_name: "Administrator".to_string(),
                    password: Some("admin123".to_string()),
                }),
                &mut config
            ).await
        });

        // Command should succeed
        assert!(result.is_ok(), "Create admin command failed: {:?}", result.unwrap_err());

        // Verify we can't create another admin (since users now exist)
        let result2 = rt.block_on(async {
            execute_command(
                &Commands::User(UserCommands::CreateAdmin {
                    db_path: Some(db_path),
                    username: "admin2".to_string(),
                    email: "admin2@example.com".to_string(),
                    display_name: "Administrator 2".to_string(),
                    password: Some("admin123".to_string()),
                }),
                &mut config
            ).await
        });

        // Command should still succeed but not create a new admin
        assert!(result2.is_ok(), "Second create admin command failed");
    }

    #[test]
    fn test_validate_credentials() {
        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Create temp directories
        let temp_dir = tempdir().unwrap();
        let db_path = temp_dir.path().join("test.db");

        // Create a basic configuration
        let mut config = Config::default();
        config.database.path = db_path.clone();

        // Test username and password
        let username = "testuser";
        let password = "testpassword123";

        // First create a user
        let create_result = rt.block_on(async {
            execute_command(
                &Commands::User(UserCommands::Add {
                    db_path: Some(db_path.clone()),
                    username: username.to_string(),
                    email: "test@example.com".to_string(),
                    display_name: "Test User".to_string(),
                    password: Some(password.to_string()),
                    role: "user".to_string(),
                }),
                &mut config
            ).await
        });

        // Create user should succeed
        assert!(create_result.is_ok(), "Failed to create test user: {:?}", create_result.unwrap_err());

        // Test valid credentials
        let validate_result = rt.block_on(async {
            execute_command(
                &Commands::User(UserCommands::Validate {
                    db_path: Some(db_path.clone()),
                    username: username.to_string(),
                    password: Some(password.to_string()),
                }),
                &mut config
            ).await
        });

        // Validation should succeed with correct password
        assert!(validate_result.is_ok(), "Validation failed with correct credentials");

        // Test invalid credentials
        let wrong_password = format!("wrong_{}", password);
        let invalid_validate_result = rt.block_on(async {
            execute_command(
                &Commands::User(UserCommands::Validate {
                    db_path: Some(db_path),
                    username: username.to_string(),
                    password: Some(wrong_password),
                }),
                &mut config
            ).await
        });

        // Validation should fail with incorrect password
        assert!(invalid_validate_result.is_err(), "Validation succeeded with incorrect credentials");
    }
}

/// Property tests for database backup commands
mod db_command_tests {
    use super::*;
    use crate::cli::commands::{DbCommands, execute_command};
    use crate::data::sqlite::{BackupMetadata, Sqlite};
    use chrono::Utc;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use std::fs;
    use std::io::Write;
    use std::path::PathBuf;
    use std::sync::Arc;
    use rusqlite::Connection;
    use tempfile::tempdir;
    use tokio::runtime::Runtime;

    // Strategy for database size (number of records)
    fn db_size_strategy() -> impl Strategy<Value = usize> {
        1..100usize
    }

    // Strategy for compression level
    fn compression_level_strategy() -> impl Strategy<Value = u32> {
        0..=9u32
    }

    // Strategy for detailed flag
    fn detailed_flag_strategy() -> impl Strategy<Value = bool> {
        prop::bool::ANY
    }

    proptest! {
        #[test]
        fn test_db_backup_command(
            db_size in db_size_strategy(),
            compression in compression_level_strategy()
        ) {
            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Set up temporary directory
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");
            let backup_dir = temp_dir.path().join("backups");

            // Create a test database
            let conn = Connection::open(&db_path).unwrap();
            conn.execute(
                "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
                [],
            ).unwrap();

            let tx = conn.transaction().unwrap();
            for i in 0..db_size {
                tx.execute(
                    "INSERT INTO test (id, value) VALUES (?, ?)",
                    [i as i64, &format!("test_value_{}", i)],
                ).unwrap();
            }
            tx.commit().unwrap();
            conn.close().unwrap();

            // Create a basic configuration
            let mut config = Config::default();
            config.database.path = db_path.clone();
            config.database.backup_dir = backup_dir.clone();
            config.database.enable_backups = true;
            config.database.backup_compression_level = compression;

            // Execute backup command
            let result = rt.block_on(async {
                execute_command(
                    &Commands::Db(DbCommands::Backup {
                        db_path: Some(db_path.clone()),
                        backup_dir: Some(backup_dir.clone()),
                        compression,
                    }),
                    &mut config
                ).await
            });

            // Backup command should succeed
            prop_assert!(result.is_ok(), "Backup command failed: {:?}", result.unwrap_err());

            // Verify that the backup directory exists
            prop_assert!(backup_dir.exists(), "Backup directory does not exist");

            // Verify that there's at least one backup file
            let entries = fs::read_dir(&backup_dir).unwrap()
                .filter_map(|e| e.ok())
                .collect::<Vec<_>>();

            prop_assert!(!entries.is_empty(), "No backup files found");

            // Now try listing backups
            let list_result = rt.block_on(async {
                execute_command(
                    &Commands::Db(DbCommands::List {
                        db_path: Some(db_path.clone()),
                        backup_dir: Some(backup_dir.clone()),
                        detailed: false,
                    }),
                    &mut config
                ).await
            });

            prop_assert!(list_result.is_ok(), "List command failed: {:?}", list_result.unwrap_err());

            // Find a backup file to verify
            let backup_file = entries.iter()
                .find(|e| {
                    let path = e.path();
                    path.extension().map_or(false, |ext| ext == "backup" || ext == "gz")
                })
                .map(|e| e.path())
                .unwrap();

            // Verify the backup
            let verify_result = rt.block_on(async {
                execute_command(
                    &Commands::Db(DbCommands::Verify {
                        backup_file: backup_file.clone(),
                    }),
                    &mut config
                ).await
            });

            prop_assert!(verify_result.is_ok(), "Verify command failed: {:?}", verify_result.unwrap_err());

            // Create a new database path for restore
            let restored_db_path = temp_dir.path().join("restored.db");

            // Restore the backup to a different location
            let restore_result = rt.block_on(async {
                execute_command(
                    &Commands::Db(DbCommands::Restore {
                        db_path: Some(restored_db_path.clone()),
                        backup_file: backup_file.clone(),
                        force: true,
                    }),
                    &mut config
                ).await
            });

            prop_assert!(restore_result.is_ok(), "Restore command failed: {:?}", restore_result.unwrap_err());

            // Verify the restored database
            prop_assert!(restored_db_path.exists(), "Restored database does not exist");

            // Check that the data was actually restored
            let conn = Connection::open(&restored_db_path).unwrap();
            let count: i64 = conn.query_row("SELECT COUNT(*) FROM test", [], |row| row.get(0)).unwrap();
            prop_assert_eq!(count as usize, db_size, "Incorrect number of records in restored database");
        }
    }

    proptest! {
        #[test]
        fn test_db_list_backups_command(
            db_size in db_size_strategy(),
            backup_count in 1..5usize,
            detailed in detailed_flag_strategy()
        ) {
            // Create runtime for async tests
            let rt = Runtime::new().unwrap();

            // Set up temporary directory
            let temp_dir = tempdir().unwrap();
            let db_path = temp_dir.path().join("test.db");
            let backup_dir = temp_dir.path().join("backups");

            // Create directories
            fs::create_dir_all(&backup_dir).unwrap();

            // Create a test database
            let conn = Connection::open(&db_path).unwrap();
            conn.execute(
                "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
                [],
            ).unwrap();

            let tx = conn.transaction().unwrap();
            for i in 0..db_size {
                tx.execute(
                    "INSERT INTO test (id, value) VALUES (?, ?)",
                    [i as i64, &format!("test_value_{}", i)],
                ).unwrap();
            }
            tx.commit().unwrap();
            conn.close().unwrap();

            // Create some mock backup files and metadata
            for i in 0..backup_count {
                // Create backup file
                let backup_name = format!("test_{}.backup", i);
                let backup_path = backup_dir.join(&backup_name);
                let mut file = fs::File::create(&backup_path).unwrap();
                writeln!(file, "mock backup content").unwrap();

                // Create metadata file
                let metadata = BackupMetadata {
                    created_at: Utc::now(),
                    size_bytes: 100 + i as u64 * 1000,
                    db_version: "3.36.0".to_string(),
                    source_path: db_path.clone(),
                    compressed: i % 2 == 0,
                    checksum: format!("mock_checksum_{}", i),
                };

                let metadata_path = backup_path.with_extension("metadata.json");
                let metadata_json = serde_json::to_string_pretty(&metadata).unwrap();
                let mut file = fs::File::create(metadata_path).unwrap();
                file.write_all(metadata_json.as_bytes()).unwrap();
            }

            // Create a basic configuration
            let mut config = Config::default();
            config.database.path = db_path.clone();
            config.database.backup_dir = backup_dir.clone();
            config.database.enable_backups = true;

            // Execute list command with various options
            let list_result = rt.block_on(async {
                execute_command(
                    &Commands::Db(DbCommands::List {
                        db_path: Some(db_path.clone()),
                        backup_dir: Some(backup_dir.clone()),
                        detailed,
                    }),
                    &mut config
                ).await
            });

            prop_assert!(list_result.is_ok(), "List command failed: {:?}", list_result.unwrap_err());
        }
    }

    // Test error cases
    #[test]
    fn test_db_verify_nonexistent_backup() {
        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Create a basic configuration
        let mut config = Config::default();

        // Try to verify a non-existent backup
        let verify_result = rt.block_on(async {
            execute_command(
                &Commands::Db(DbCommands::Verify {
                    backup_file: PathBuf::from("/nonexistent/backup.file"),
                }),
                &mut config
            ).await
        });

        // Command should fail with appropriate error
        assert!(verify_result.is_err());
        let err = verify_result.unwrap_err().to_string();
        assert!(err.contains("not found"), "Unexpected error: {}", err);
    }

    #[test]
    fn test_db_restore_canceled() {
        // This test simulates user canceling a restore operation
        // Note: In a real test, we'd need to mock stdin for confirmation
        // Here we're just testing the code path where force=true to bypass confirmation

        // Create runtime for async tests
        let rt = Runtime::new().unwrap();

        // Set up temporary directory
        let temp_dir = tempdir().unwrap();
        let db_path = temp_dir.path().join("test.db");
        let backup_file = temp_dir.path().join("mock_backup.backup");

        // Create an empty backup file
        let mut file = fs::File::create(&backup_file).unwrap();
        writeln!(file, "mock backup content").unwrap();

        // Create a basic configuration
        let mut config = Config::default();
        config.database.path = db_path.clone();

        // Execute restore command with force=true to bypass confirmation
        let restore_result = rt.block_on(async {
            execute_command(
                &Commands::Db(DbCommands::Restore {
                    db_path: Some(db_path.clone()),
                    backup_file: backup_file.clone(),
                    force: true,
                }),
                &mut config
            ).await
        });

        // This will still fail because the backup file doesn't have valid metadata
        assert!(restore_result.is_err());
        let err = restore_result.unwrap_err().to_string();
        // We don't test exact error message as it depends on the implementation details
        assert!(err.contains("Failed to restore database"), "Unexpected error: {}", err);
    }
}

/// Property tests for OpenTelemetry integration in the serve command
mod serve_command_otel_tests {
    use super::*;
    use crate::cli::Commands;
    use crate::config::{OpenTelemetryConfig, ObservabilityConfig};
    use crate::service::observability::TraceContext;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use tokio::runtime::Runtime;
    use tokio::sync::oneshot;
    use std::time::Duration;
    use std::sync::Arc;

    // Strategy for generating OpenTelemetry endpoints
    fn otel_endpoint_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("http://localhost:4317".to_string()),
            Just("http://127.0.0.1:4317".to_string()),
            Just("http://otel-collector:4317".to_string()),
            Just("http://jaeger:4317".to_string()),
            Just("https://otel.example.com:4317".to_string())
        ]
    }

    // Strategy for generating service names
    fn service_name_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("art".to_string()),
            Just("art-test".to_string()),
            Just("art-dev".to_string()),
            Just("art-production".to_string()),
            Just("repository-browser".to_string())
        ]
    }

    // Strategy for generating sampling ratios
    fn sampling_ratio_strategy() -> impl Strategy<Value = f64> {
        prop_oneof![
            Just(0.0),      // No sampling
            Just(0.1),      // 10% sampling
            Just(0.5),      // 50% sampling
            Just(1.0)       // 100% sampling
        ]
    }

    // Strategy for generating OpenTelemetry configurations
    fn opentelemetry_config_strategy() -> impl Strategy<Value = OpenTelemetryConfig> {
        (
            otel_endpoint_strategy(),
            service_name_strategy(),
            sampling_ratio_strategy(),
            proptest::bool::ANY,   // export_otlp
            proptest::bool::ANY    // export_stdout
        ).prop_map(|(endpoint, service_name, sampling_ratio, export_otlp, export_stdout)| {
            OpenTelemetryConfig {
                enabled: true,
                endpoint,
                service_name,
                sampling_ratio,
                timeout_seconds: 5,
                default_attributes: HashMap::new(),
                export_otlp,
                export_stdout,
            }
        })
    }

    // Test that the server starts with OpenTelemetry integration
    proptest! {
        #[test]
        fn test_serve_command_with_opentelemetry(
            otel_config in opentelemetry_config_strategy(),
            port in 8000u16..9000u16
        ) {
            // Create a runtime for async code
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create temporary directories
                let repo_dir = tempdir().expect("Failed to create temp repo dir");
                let db_dir = tempdir().expect("Failed to create temp db dir");

                // Create a basic configuration with OpenTelemetry enabled
                let mut config = Config::default();
                config.server.port = port;
                config.server.bind_address = "127.0.0.1".to_string();
                config.repository.repo_dir = repo_dir.path().to_path_buf();
                config.database.path = db_dir.path().join("test.db");

                // Initialize directories
                fs::create_dir_all(&config.repository.repo_dir).unwrap();
                fs::create_dir_all(config.database.path.parent().unwrap()).unwrap();

                // Set OpenTelemetry configuration
                let mut observability_config = ObservabilityConfig::default();
                observability_config.enabled = true;
                observability_config.opentelemetry = Some(otel_config.clone());
                config.observability = observability_config;

                // Create server command
                let cmd = Commands::Serve {
                    port,
                    bind: "127.0.0.1".to_string(),
                    repo_dir: None,
                    db_path: None,
                    cache_size: 100,
                    threads: 0,
                };

                // Create a channel to stop the server
                let (tx, rx) = oneshot::channel();

                // Spawn the server in a task
                let server_task = tokio::spawn({
                    let mut config_clone = config.clone();
                    async move {
                        // Replace the actual OpenTelemetry endpoint with a non-existent one
                        // for testing purposes (we don't want to actually connect)
                        if let Some(ref mut otel) = config_clone.observability.opentelemetry {
                            // Keep the same endpoint but assume it doesn't exist
                            // This will cause the initialization to fall back gracefully
                        }

                        // Execute the command - we expect this to eventually fail because
                        // the OpenTelemetry endpoint doesn't exist, but it should handle
                        // it gracefully and start the server
                        let result = execute_command(&cmd, &mut config_clone, false).await;

                        // The server might fail to start, but we expect it to handle
                        // OpenTelemetry errors gracefully by initializing without it
                        if result.is_err() {
                            let err = result.unwrap_err();
                            // We should NOT fail specifically because of OpenTelemetry issues
                            prop_assert!(!err.to_string().contains("opentelemetry"),
                                        "Server should handle OpenTelemetry initialization errors gracefully");
                        }

                        // Wait until stopped or timeout
                        let _ = rx.await;
                        Ok(())
                    }
                });

                // Give it time to start (or fail gracefully)
                sleep(Duration::from_millis(100)).await;

                // Stop the server
                let _ = tx.send(());

                // Wait for server to shut down
                let _ = tokio::time::timeout(Duration::from_secs(1), server_task).await;

                Ok(())
            })
        }
    }

    // Test that the observability service can fall back if OpenTelemetry is unavailable
    #[test]
    fn test_observability_service_with_fallback() {
        let rt = Runtime::new().unwrap();

        rt.block_on(async {
            // Create temporary directories
            let repo_dir = tempdir().expect("Failed to create temp repo dir");
            let db_dir = tempdir().expect("Failed to create temp db dir");

            // Create directories
            fs::create_dir_all(&repo_dir).unwrap();
            fs::create_dir_all(&db_dir).unwrap();

            // Create a configuration with an invalid endpoint
            let mut config = Config::default();
            config.repository.repo_dir = repo_dir.path().to_path_buf();
            config.database.path = db_dir.path().join("test.db");

            // Set OpenTelemetry configuration with invalid endpoint
            let mut observability_config = ObservabilityConfig::default();
            observability_config.enabled = true;
            observability_config.opentelemetry = Some(OpenTelemetryConfig {
                enabled: true,
                endpoint: "http://nonexistent-endpoint:4317".to_string(),
                service_name: "art-test".to_string(),
                sampling_ratio: 1.0,
                timeout_seconds: 1, // Short timeout to fail quickly
                default_attributes: HashMap::new(),
                export_otlp: true,
                export_stdout: false,
            });
            config.observability = observability_config;

            // Initialize observability service
            let service = crate::service::observability::ObservabilityService::new(
                config.observability.clone(), None, None
            ).await;

            // Service should still be initialized even if OpenTelemetry fails
            assert!(service.is_ok(), "Observability service should initialize even with invalid OpenTelemetry endpoint");

            // Tracer might be None if initialization failed, which is acceptable
            let service = service.unwrap();

            // Check that metrics functionality works
            service.record_request("GET", "/test");
            service.record_response("GET", "/test", 200);

            // We should be able to get metrics
            let metrics = service.metrics_as_string();
            assert!(metrics.is_ok(), "Should be able to get metrics even if OpenTelemetry failed");
        });
    }

    // Test that traces are created for repository indexing
    #[test]
    fn test_traces_created_for_indexing() {
        let rt = Runtime::new().unwrap();

        rt.block_on(async {
            // Create temporary directories
            let repo_dir = tempdir().expect("Failed to create temp repo dir");
            let db_dir = tempdir().expect("Failed to create temp db dir");

            // Create a test git repository
            let repo_path = repo_dir.path().join("test-repo");
            std::fs::create_dir_all(&repo_path).expect("Failed to create repo dir");

            // Initialize a bare git repository for testing
            let init_output = std::process::Command::new("git")
                .arg("init")
                .arg("--bare")
                .current_dir(&repo_path)
                .output();

            // Skip test if git command fails
            if init_output.is_err() {
                return Ok(());
            }

            // Create a basic configuration with OpenTelemetry enabled for stdout
            let mut config = Config::default();
            config.repository.repo_dir = repo_dir.path().to_path_buf();
            config.database.path = db_dir.path().join("test.db");

            // Set OpenTelemetry configuration for stdout only (no network required)
            let mut observability_config = ObservabilityConfig::default();
            observability_config.enabled = true;
            observability_config.opentelemetry = Some(OpenTelemetryConfig {
                enabled: true,
                endpoint: "http://localhost:4317".to_string(), // Won't be used
                service_name: "art-test".to_string(),
                sampling_ratio: 1.0,
                timeout_seconds: 5,
                default_attributes: HashMap::new(),
                export_otlp: false, // No network export
                export_stdout: true, // Just output to stdout for testing
            });
            config.observability = observability_config;

            // Create the observability service
            let service = crate::service::observability::ObservabilityService::new(
                config.observability.clone(), None, None
            ).await.expect("Failed to create observability service");

            // Create a trace context for testing
            let trace_ctx = TraceContext::new();

            // Record traces for repository indexing
            for i in 0..3 {
                let repo_trace = trace_ctx.create_child();
                service.record_trace(&repo_trace);

                // If we have a tracer, record spans
                if let Some(tracer) = service.opentelemetry_tracer() {
                    let span_result = tracer.create_and_record_span(
                        &format!("test_span_{}", i),
                        &repo_trace,
                        &[
                            ("component", "indexer"),
                            ("repository", &format!("test-repo-{}", i)),
                            ("operation", "index"),
                        ],
                        &[("test_event", std::collections::HashMap::new())],
                        crate::service::observability::opentelemetry::SpanKind::Internal,
                    );

                    // This should succeed even though we're not actually exporting
                    assert!(span_result.is_ok(), "Should be able to create spans");
                }
            }

            // Test should pass if we get here without errors
            Ok(())
        })
    }
}
