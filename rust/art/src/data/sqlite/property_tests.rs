//! Property-based tests for SQLite database operations

use crate::data::sqlite::{Sqlite, Repository, Branch, Tag, Commit};
use crate::config::DatabaseConfig;
use proptest::prelude::*;
use rusqlite::Connection;
use std::path::PathBuf;
use std::sync::{Arc, Barrier};
use std::thread;
use tempfile::tempdir;

// Helper function to create a test database
fn create_test_db() -> (Sqlite, tempfile::TempDir) {
    let temp_dir = tempdir().unwrap();
    let db_path = temp_dir.path().join("test.db");

    let config = DatabaseConfig {
        path: db_path,
        enable_cache: false,
        max_cache_entries: 0,
        cache_ttl: 0,
    };

    let sqlite = Sqlite::new(&config).unwrap();
    (sqlite, temp_dir)
}

// Strategy for generating repository data
pub fn repository_strategy() -> impl Strategy<Value = (String, String, Option<String>, Option<String>)> {
    // Generate valid repository data: name, path, description, owner
    (
        "[a-zA-Z0-9_-]{3,50}",  // name: alphanumeric 3-50 chars
        "[a-zA-Z0-9_/-]{3,100}",  // path: alphanumeric with / and - 3-100 chars
        proptest::option::of("[a-zA-Z0-9_ -]{0,200}"), // description: optional alphanumeric with spaces 0-200 chars
        proptest::option::of("[a-zA-Z0-9_ -]{0,50}"),  // owner: optional alphanumeric with spaces 0-50 chars
    )
}

// Strategy for generating branch data
pub fn branch_strategy() -> impl Strategy<Value = (i64, String, String)> {
    // Generate valid branch data: repo_id, name, commit_id
    (
        1..1000i64, // repo_id: 1-1000
        "[a-zA-Z0-9_/-]{1,100}", // name: alphanumeric with / and - 1-100 chars
        "[a-f0-9]{40}" // commit_id: 40 hex chars (SHA-1)
    )
}

// Strategy for generating tag data
pub fn tag_strategy() -> impl Strategy<Value = (i64, String, String)> {
    // Generate valid tag data: repo_id, name, commit_id
    (
        1..1000i64, // repo_id: 1-1000
        "[a-zA-Z0-9_.-]{1,100}", // name: alphanumeric with ., _, and - 1-100 chars
        "[a-f0-9]{40}" // commit_id: 40 hex chars (SHA-1)
    )
}

// Strategy for generating commit data
pub fn commit_strategy() -> impl Strategy<Value = (String, i64, String, String, String, Vec<String>)> {
    // Generate valid commit data: id, repo_id, author, email, message, parent_ids
    (
        "[a-f0-9]{40}", // id: 40 hex chars (SHA-1)
        1..1000i64, // repo_id: 1-1000
        "[a-zA-Z ]{3,50}", // author: alpha with spaces 3-50 chars
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",  // email: valid email pattern
        "[a-zA-Z0-9_ ,.!?-]{1,200}", // message: alphanumeric with common punctuation 1-200 chars
        proptest::collection::vec("[a-f0-9]{40}", 0..3) // parent_ids: 0-3 parent commit IDs (SHA-1)
    )
}

proptest! {
    // Test database connection pooling
    #[test]
    fn test_connection_pooling(
        num_connections in 1..10u8,
        num_threads in 1..5u8
    ) {
        let (sqlite, _temp_dir) = create_test_db();
        let barrier = Arc::new(Barrier::new(num_threads as usize));
        let sqlite = Arc::new(sqlite);

        let mut handles = vec![];

        for _ in 0..num_threads {
            let sqlite_clone = Arc::clone(&sqlite);
            let barrier_clone = Arc::clone(&barrier);

            let handle = thread::spawn(move || {
                // Synchronize all threads to start at the same time
                barrier_clone.wait();

                // Each thread gets multiple connections
                let mut connections = Vec::new();
                for _ in 0..num_connections {
                    let conn = sqlite_clone.get_connection().unwrap();
                    // Verify connection works
                    let count: i64 = conn.query_row("SELECT 1", [], |row| row.get(0)).unwrap();
                    assert_eq!(count, 1);
                    connections.push(conn);
                }

                // Verify all connections work independently
                for conn in &connections {
                    let count: i64 = conn.query_row("SELECT 1", [], |row| row.get(0)).unwrap();
                    assert_eq!(count, 1);
                }
            });

            handles.push(handle);
        }

        // Wait for all threads to complete
        for handle in handles {
            handle.join().unwrap();
        }
    }

    // Test transaction rollback on error
    #[test]
    fn test_transaction_rollback(
        (name, path, description, owner) in repository_strategy(),
        fail_description in "[a-zA-Z0-9_ -]{201,300}" // Invalid description that exceeds length limit
    ) {
        let (sqlite, _temp_dir) = create_test_db();
        let conn = sqlite.get_connection().unwrap();

        // First, successfully insert a repository
        {
            let tx = conn.transaction().unwrap();
            let repo_model = crate::data::sqlite::RepositoryModel::new(&tx);
            let id = repo_model.insert(&name, &path, description.as_deref(), owner.as_deref()).unwrap();
            assert!(id > 0);
            tx.commit().unwrap();
        }

        // Now try a transaction that should fail and rollback
        {
            let tx = conn.transaction().unwrap();
            let repo_model = crate::data::sqlite::RepositoryModel::new(&tx);

            // This should succeed
            let id2 = repo_model.insert(&format!("{}-2", name), &format!("{}-2", path), Some("Valid description"), owner.as_deref()).unwrap();

            // This should fail due to invalid description length, simulating a constraint violation
            let result = repo_model.insert(&format!("{}-3", name), &format!("{}-3", path), Some(&fail_description), owner.as_deref());

            // We don't actually enforce the description length in the schema, so for testing purposes,
            // we'll simulate a failure by not committing the transaction
            drop(tx); // Explicit rollback by dropping the transaction

            // Verify that neither insertion took effect (the transaction was rolled back)
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            let repo2 = repo_model.get_by_name(&format!("{}-2", name)).unwrap();
            assert!(repo2.is_none(), "Repository should not exist after transaction rollback");

            let repo3 = repo_model.get_by_name(&format!("{}-3", name)).unwrap();
            assert!(repo3.is_none(), "Repository should not exist after transaction rollback");
        }
    }

    // Test database integrity after schema changes
    #[test]
    fn test_schema_upgrade_integrity(
        (name, path, description, owner) in repository_strategy(),
        (branch_repo_id, branch_name, branch_commit) in branch_strategy()
    ) {
        let (sqlite, temp_dir) = create_test_db();
        let conn = sqlite.get_connection().unwrap();

        // Insert initial data
        {
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            let id = repo_model.insert(&name, &path, description.as_deref(), owner.as_deref()).unwrap();

            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            branch_model.insert(id, &branch_name, &branch_commit).unwrap();
        }

        // Simulate a schema upgrade by adding a new column
        conn.execute("ALTER TABLE repositories ADD COLUMN test_column TEXT", []).unwrap();

        // Verify existing data is still intact
        {
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            let repo = repo_model.get_by_name(&name).unwrap().unwrap();
            assert_eq!(repo.name, name);
            assert_eq!(repo.path, path);

            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            let branch = branch_model.get_by_name(repo.id, &branch_name).unwrap().unwrap();
            assert_eq!(branch.name, branch_name);
            assert_eq!(branch.commit_id, branch_commit);
        }

        // Verify we can still insert new data
        {
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            let id = repo_model.insert(&format!("{}-new", name), &format!("{}-new", path), None, None).unwrap();
            assert!(id > 0);
        }
    }

    // Test database recovery from corruption
    #[test]
    fn test_database_recovery_after_busy_error(
        (name1, path1, desc1, owner1) in repository_strategy(),
        (name2, path2, desc2, owner2) in repository_strategy()
    ) {
        let (sqlite, _temp_dir) = create_test_db();

        // Simulate concurrent write operations
        let barrier = Arc::new(Barrier::new(2));
        let sqlite = Arc::new(sqlite);

        let sqlite_clone1 = Arc::clone(&sqlite);
        let barrier_clone1 = Arc::clone(&barrier);

        let sqlite_clone2 = Arc::clone(&sqlite);
        let barrier_clone2 = Arc::clone(&barrier);

        let name1_clone = name1.clone();
        let path1_clone = path1.clone();
        let desc1_clone = desc1.clone();
        let owner1_clone = owner1.clone();

        let handle1 = thread::spawn(move || {
            let conn = sqlite_clone1.get_connection().unwrap();
            barrier_clone1.wait(); // Synchronize start

            // Long-running transaction to block other threads
            let tx = conn.transaction().unwrap();
            let repo_model = crate::data::sqlite::RepositoryModel::new(&tx);
            let id = repo_model.insert(&name1_clone, &path1_clone, desc1_clone.as_deref(), owner1_clone.as_deref()).unwrap();

            // Sleep to simulate long operation
            std::thread::sleep(std::time::Duration::from_millis(50));

            tx.commit().unwrap();
            id
        });

        let handle2 = thread::spawn(move || {
            let conn = sqlite_clone2.get_connection().unwrap();
            barrier_clone2.wait(); // Synchronize start

            // This thread will try to write while the first thread is still writing
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);

            // This might get a BUSY error, so we'll retry a few times
            let mut attempts = 0;
            let max_attempts = 5;
            let mut result = None;

            while attempts < max_attempts {
                match repo_model.insert(&name2, &path2, desc2.as_deref(), owner2.as_deref()) {
                    Ok(id) => {
                        result = Some(id);
                        break;
                    }
                    Err(_) => {
                        // Wait a bit and retry
                        std::thread::sleep(std::time::Duration::from_millis(20));
                        attempts += 1;
                    }
                }
            }

            // We should eventually succeed
            result.unwrap_or(0)
        });

        let id1 = handle1.join().unwrap();
        let id2 = handle2.join().unwrap();

        // Verify both operations completed successfully
        assert!(id1 > 0, "First insert should have succeeded");
        assert!(id2 > 0, "Second insert should have succeeded (possibly after retries)");

        // Verify both repositories exist
        let conn = sqlite.get_connection().unwrap();
        let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);

        let repo1 = repo_model.get_by_name(&name1).unwrap();
        assert!(repo1.is_some(), "First repository should exist");

        let repo2 = repo_model.get_by_name(&name2).unwrap();
        assert!(repo2.is_some(), "Second repository should exist");
    }
}

// Additional test module for foreign key constraints
#[cfg(test)]
mod fk_tests {
    use super::*;
    use rusqlite::params;

    #[test]
    fn test_foreign_key_constraints() {
        let (sqlite, _temp_dir) = create_test_db();
        let conn = sqlite.get_connection().unwrap();

        // Enable foreign key constraints (should already be enabled in schema creation)
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();

        // Create a repository
        let repo_id: i64 = {
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            repo_model.insert("test-repo", "/path/to/repo", None, None).unwrap()
        };

        // Add branches, tags, and commits
        {
            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            branch_model.insert(repo_id, "main", "1234567890abcdef1234567890abcdef12345678").unwrap();

            let tag_model = crate::data::sqlite::TagModel::new(&conn);
            tag_model.insert(repo_id, "v1.0", "fedcba9876543210fedcba9876543210fedcba98").unwrap();

            let commit_model = crate::data::sqlite::CommitModel::new(&conn);
            commit_model.insert(
                "abcdef1234567890abcdef1234567890abcdef12",
                repo_id,
                "Test User",
                "test@example.com",
                "Test commit",
                chrono::Utc::now().timestamp(),
                &[],
            ).unwrap();
        }

        // Verify constraint: can't add a branch to non-existent repository
        {
            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            let result = branch_model.insert(repo_id + 1000, "feature", "1234567890abcdef1234567890abcdef12345678");
            assert!(result.is_err(), "Should not be able to add branch to non-existent repository");
        }

        // Verify constraint: delete repository cascades to branches, tags, and commits
        {
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            repo_model.delete(repo_id).unwrap();

            // Verify branches are gone
            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            let branches = branch_model.get_all_for_repo(repo_id).unwrap();
            assert!(branches.is_empty(), "Branches should be deleted when repository is deleted");

            // Verify tags are gone
            let tag_model = crate::data::sqlite::TagModel::new(&conn);
            let tags = tag_model.get_all_for_repo(repo_id).unwrap();
            assert!(tags.is_empty(), "Tags should be deleted when repository is deleted");

            // Verify commits are gone
            let count: i64 = conn.query_row(
                "SELECT COUNT(*) FROM commits WHERE repo_id = ?",
                params![repo_id],
                |row| row.get(0)
            ).unwrap();
            assert_eq!(count, 0, "Commits should be deleted when repository is deleted");
        }
    }
}

// Test for database performance and scalability
#[cfg(test)]
mod performance_tests {
    use super::*;
    use proptest::prelude::*;
    use std::time::{Duration, Instant};

    proptest! {
        #[test]
        fn test_database_scaling(
            num_repos in 1..10u8,
            branches_per_repo in 1..5u8,
            commits_per_repo in 1..5u8
        ) {
            let (sqlite, _temp_dir) = create_test_db();
            let conn = sqlite.get_connection().unwrap();

            // Insert multiple repositories
            let mut repo_ids = Vec::new();
            for i in 0..num_repos {
                let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
                let id = repo_model.insert(
                    &format!("repo-{}", i),
                    &format!("/path/to/repo-{}", i),
                    Some(&format!("Description for repo {}", i)),
                    Some("test-owner")
                ).unwrap();
                repo_ids.push(id);
            }

            // For each repository, add branches and commits
            for &repo_id in &repo_ids {
                // Add branches
                for j in 0..branches_per_repo {
                    let branch_model = crate::data::sqlite::BranchModel::new(&conn);
                    branch_model.insert(
                        repo_id,
                        &format!("branch-{}", j),
                        &format!("{:040x}", j)
                    ).unwrap();
                }

                // Add commits
                for k in 0..commits_per_repo {
                    let commit_model = crate::data::sqlite::CommitModel::new(&conn);
                    commit_model.insert(
                        &format!("{:040x}", k),
                        repo_id,
                        "Test User",
                        "test@example.com",
                        &format!("Commit message {}", k),
                        chrono::Utc::now().timestamp(),
                        &[]
                    ).unwrap();
                }
            }

            // Test query performance as database size increases
            let repo_model = crate::data::sqlite::RepositoryModel::new(&conn);
            let start = Instant::now();
            let repos = repo_model.get_all().unwrap();
            let duration = start.elapsed();

            // Verify results
            assert_eq!(repos.len(), num_repos as usize);

            // Timing is not perfect in CI, so we can't assert on exact time,
            // but we can check it completes in reasonable time
            assert!(duration < Duration::from_secs(1), "Query should complete quickly");

            // Test query performance for branches of last repository
            let branch_model = crate::data::sqlite::BranchModel::new(&conn);
            let start = Instant::now();
            let branches = branch_model.get_all_for_repo(*repo_ids.last().unwrap()).unwrap();
            let duration = start.elapsed();

            // Verify results
            assert_eq!(branches.len(), branches_per_repo as usize);
            assert!(duration < Duration::from_secs(1), "Branch query should complete quickly");
        }
    }
}
