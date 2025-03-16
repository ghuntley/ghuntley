//! Property-based tests for SQLite database operations

use crate::config::DatabaseConfig;
use crate::data::sqlite::{Sqlite, Repository, Branch, Tag, Commit};
use crate::error::Result;
use tempfile::tempdir;
use proptest::prelude::*;
use std::path::PathBuf;
use proptest::collection::{vec, hash_map};
use proptest::option::of;
use rusqlite::params;
use chrono::Utc;

// Strategy for generating repository test data
fn repository_strategy() -> impl Strategy<Value = (String, String, Option<String>, Option<String>)> {
    (
        // Repository name (alphanumeric with hyphens and underscores)
        "[a-zA-Z][a-zA-Z0-9_-]{1,20}",
        // Repository path (looks like a file path)
        "/[a-zA-Z0-9_-]{1,10}(/[a-zA-Z0-9_-]{1,10}){0,3}",
        // Optional description
        of("[a-zA-Z0-9 .,_-]{0,100}"),
        // Optional owner
        of("[a-zA-Z][a-zA-Z0-9_-]{1,20}"),
    )
}

// Strategy for generating branch test data
fn branch_strategy(repo_id: i64) -> impl Strategy<Value = (i64, String, String)> {
    (
        Just(repo_id),
        // Branch name (alphanumeric with hyphens, underscores, and slashes)
        "[a-zA-Z][a-zA-Z0-9_/-]{1,20}",
        // Commit hash (40 character hex string)
        "[0-9a-f]{40}",
    )
}

// Strategy for generating tag test data
fn tag_strategy(repo_id: i64) -> impl Strategy<Value = (i64, String, String)> {
    (
        Just(repo_id),
        // Tag name (alphanumeric with dots, hyphens, and underscores)
        "v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9_-]+)?",
        // Commit hash (40 character hex string)
        "[0-9a-f]{40}",
    )
}

// Strategy for generating commit test data
fn commit_strategy(repo_id: i64) -> impl Strategy<Value = (String, i64, String, String, String, i64, Vec<String>)> {
    (
        // Commit hash (40 character hex string)
        "[0-9a-f]{40}",
        Just(repo_id),
        // Author name (alphanumeric with spaces)
        "[a-zA-Z][a-zA-Z0-9 ]{1,30}",
        // Email address
        "[a-zA-Z0-9_-]+@[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+",
        // Commit message
        "[a-zA-Z0-9 .,_-]{1,100}",
        // Timestamp (recent past)
        (Utc::now().timestamp() - 86400..Utc::now().timestamp()),
        // Parent commit hashes (0-3 parent commits)
        vec("[0-9a-f]{40}", 0..3),
    )
}

// Helper function to create a test database
fn create_test_db() -> Result<(Sqlite, tempfile::TempDir)> {
    let temp_dir = tempdir()?;
    let db_path = temp_dir.path().join("test.db");

    let config = DatabaseConfig {
        path: db_path,
        max_connections: 5,
        connection_timeout: 5,
    };

    let sqlite = Sqlite::new(&config)?;
    Ok((sqlite, temp_dir))
}

// Test CRUD operations with property-based tests
proptest! {
    /// Test that repositories can be created, read, updated, and deleted
    #[test]
    fn test_repository_crud(
        (name, path, description, owner) in repository_strategy()
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert the repository
        let repo_id = {
            let now = Utc::now().timestamp();
            let result = conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            );
            assert!(result.is_ok(), "Failed to insert repository");
            conn.last_insert_rowid()
        };

        // Read the repository back
        let repo = {
            let mut stmt = conn.prepare("
                SELECT id, name, path, description, owner, last_updated
                FROM repositories
                WHERE id = ?
            ").unwrap();

            let repo_result = stmt.query_row([repo_id], |row| {
                Ok(Repository {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    path: row.get(2)?,
                    description: row.get(3)?,
                    owner: row.get(4)?,
                    last_updated: row.get(5)?,
                })
            });

            assert!(repo_result.is_ok(), "Failed to read repository");
            repo_result.unwrap()
        };

        // Verify the repository data matches what we inserted
        assert_eq!(repo.id, repo_id);
        assert_eq!(repo.name, name);
        assert_eq!(repo.path, path);
        assert_eq!(repo.description, description);
        assert_eq!(repo.owner, owner);

        // Update the repository
        let new_description = Some("Updated description".to_string());
        let result = conn.execute(
            "UPDATE repositories SET description = ? WHERE id = ?",
            params![new_description, repo_id],
        );
        assert!(result.is_ok(), "Failed to update repository");

        // Read the updated repository
        let updated_repo = {
            let mut stmt = conn.prepare("
                SELECT id, name, path, description, owner, last_updated
                FROM repositories
                WHERE id = ?
            ").unwrap();

            let repo_result = stmt.query_row([repo_id], |row| {
                Ok(Repository {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    path: row.get(2)?,
                    description: row.get(3)?,
                    owner: row.get(4)?,
                    last_updated: row.get(5)?,
                })
            });

            assert!(repo_result.is_ok(), "Failed to read updated repository");
            repo_result.unwrap()
        };

        // Verify the description was updated
        assert_eq!(updated_repo.description, new_description);

        // Delete the repository
        let result = conn.execute(
            "DELETE FROM repositories WHERE id = ?",
            params![repo_id],
        );
        assert!(result.is_ok(), "Failed to delete repository");

        // Verify the repository was deleted
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM repositories WHERE id = ?",
            params![repo_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 0, "Repository was not deleted");
    }

    /// Test that branches can be created, read, updated, and deleted
    #[test]
    fn test_branch_crud(
        (name, path, description, owner) in repository_strategy(),
        branch_name in "[a-zA-Z][a-zA-Z0-9_/-]{1,20}",
        commit_id in "[0-9a-f]{40}"
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert a repository first
        let repo_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Insert a branch
        let branch_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO branches (repo_id, name, commit_id, created_at)
                VALUES (?, ?, ?, ?)",
                params![repo_id, branch_name, commit_id, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Read the branch back
        let branch = {
            let mut stmt = conn.prepare("
                SELECT id, repo_id, name, commit_id
                FROM branches
                WHERE id = ?
            ").unwrap();

            let branch_result = stmt.query_row([branch_id], |row| {
                Ok(Branch {
                    id: row.get(0)?,
                    repo_id: row.get(1)?,
                    name: row.get(2)?,
                    commit_id: row.get(3)?,
                })
            });

            assert!(branch_result.is_ok(), "Failed to read branch");
            branch_result.unwrap()
        };

        // Verify the branch data matches what we inserted
        assert_eq!(branch.id, branch_id);
        assert_eq!(branch.repo_id, repo_id);
        assert_eq!(branch.name, branch_name);
        assert_eq!(branch.commit_id, commit_id);

        // Update the branch
        let new_commit_id = "fedcba9876543210fedcba9876543210fedcba98".to_string();
        let result = conn.execute(
            "UPDATE branches SET commit_id = ? WHERE id = ?",
            params![new_commit_id, branch_id],
        );
        assert!(result.is_ok(), "Failed to update branch");

        // Read the updated branch
        let updated_branch = {
            let mut stmt = conn.prepare("
                SELECT id, repo_id, name, commit_id
                FROM branches
                WHERE id = ?
            ").unwrap();

            let branch_result = stmt.query_row([branch_id], |row| {
                Ok(Branch {
                    id: row.get(0)?,
                    repo_id: row.get(1)?,
                    name: row.get(2)?,
                    commit_id: row.get(3)?,
                })
            });

            assert!(branch_result.is_ok(), "Failed to read updated branch");
            branch_result.unwrap()
        };

        // Verify the commit_id was updated
        assert_eq!(updated_branch.commit_id, new_commit_id);

        // Delete the branch
        let result = conn.execute(
            "DELETE FROM branches WHERE id = ?",
            params![branch_id],
        );
        assert!(result.is_ok(), "Failed to delete branch");

        // Verify the branch was deleted
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM branches WHERE id = ?",
            params![branch_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 0, "Branch was not deleted");
    }

    /// Test that tags can be created, read, updated, and deleted
    #[test]
    fn test_tag_crud(
        (name, path, description, owner) in repository_strategy(),
        tag_name in "v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9_-]+)?",
        commit_id in "[0-9a-f]{40}"
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert a repository first
        let repo_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Insert a tag
        let tag_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO tags (repo_id, name, commit_id, created_at)
                VALUES (?, ?, ?, ?)",
                params![repo_id, tag_name, commit_id, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Read the tag back
        let tag = {
            let mut stmt = conn.prepare("
                SELECT id, repo_id, name, commit_id
                FROM tags
                WHERE id = ?
            ").unwrap();

            let tag_result = stmt.query_row([tag_id], |row| {
                Ok(Tag {
                    id: row.get(0)?,
                    repo_id: row.get(1)?,
                    name: row.get(2)?,
                    commit_id: row.get(3)?,
                })
            });

            assert!(tag_result.is_ok(), "Failed to read tag");
            tag_result.unwrap()
        };

        // Verify the tag data matches what we inserted
        assert_eq!(tag.id, tag_id);
        assert_eq!(tag.repo_id, repo_id);
        assert_eq!(tag.name, tag_name);
        assert_eq!(tag.commit_id, commit_id);

        // Delete the tag
        let result = conn.execute(
            "DELETE FROM tags WHERE id = ?",
            params![tag_id],
        );
        assert!(result.is_ok(), "Failed to delete tag");

        // Verify the tag was deleted
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM tags WHERE id = ?",
            params![tag_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 0, "Tag was not deleted");
    }

    /// Test that commits can be created, read, and deleted
    #[test]
    fn test_commit_crud(
        (name, path, description, owner) in repository_strategy(),
        id in "[0-9a-f]{40}",
        author in "[a-zA-Z][a-zA-Z0-9 ]{1,30}",
        email in "[a-zA-Z0-9_-]+@[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+",
        message in "[a-zA-Z0-9 .,_-]{1,100}",
        timestamp in (Utc::now().timestamp() - 86400..Utc::now().timestamp()),
        parent_ids in vec("[0-9a-f]{40}", 0..3)
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert a repository first
        let repo_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Insert a commit
        let parent_ids_str = parent_ids.join(",");
        let result = conn.execute(
            "INSERT INTO commits (id, repo_id, author, email, message, timestamp, parent_ids)
            VALUES (?, ?, ?, ?, ?, ?, ?)",
            params![id, repo_id, author, email, message, timestamp, parent_ids_str],
        );
        assert!(result.is_ok(), "Failed to insert commit");

        // Read the commit back
        let commit = {
            let mut stmt = conn.prepare("
                SELECT id, repo_id, author, email, message, timestamp, parent_ids
                FROM commits
                WHERE id = ? AND repo_id = ?
            ").unwrap();

            let commit_result = stmt.query_row(params![id, repo_id], |row| {
                let parent_ids_str: String = row.get(6)?;
                let parent_ids = parent_ids_str
                    .split(',')
                    .filter(|s| !s.is_empty())
                    .map(String::from)
                    .collect();

                Ok(Commit {
                    id: row.get(0)?,
                    repo_id: row.get(1)?,
                    author: row.get(2)?,
                    email: row.get(3)?,
                    message: row.get(4)?,
                    timestamp: row.get(5)?,
                    parent_ids,
                })
            });

            assert!(commit_result.is_ok(), "Failed to read commit");
            commit_result.unwrap()
        };

        // Verify the commit data matches what we inserted
        assert_eq!(commit.id, id);
        assert_eq!(commit.repo_id, repo_id);
        assert_eq!(commit.author, author);
        assert_eq!(commit.email, email);
        assert_eq!(commit.message, message);
        assert_eq!(commit.timestamp, timestamp);
        assert_eq!(commit.parent_ids, parent_ids);

        // Delete the commit
        let result = conn.execute(
            "DELETE FROM commits WHERE id = ? AND repo_id = ?",
            params![id, repo_id],
        );
        assert!(result.is_ok(), "Failed to delete commit");

        // Verify the commit was deleted
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM commits WHERE id = ? AND repo_id = ?",
            params![id, repo_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 0, "Commit was not deleted");
    }

    /// Test foreign key constraints are enforced
    #[test]
    fn test_foreign_key_constraints(
        (name, path, description, owner) in repository_strategy(),
        branch_name in "[a-zA-Z][a-zA-Z0-9_/-]{1,20}",
        commit_id in "[0-9a-f]{40}"
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert a repository
        let repo_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Insert a branch for the repository
        let branch_id = {
            let now = Utc::now().timestamp();
            conn.execute(
                "INSERT INTO branches (repo_id, name, commit_id, created_at)
                VALUES (?, ?, ?, ?)",
                params![repo_id, branch_name, commit_id, now],
            ).unwrap();
            conn.last_insert_rowid()
        };

        // Verify the branch exists
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM branches WHERE id = ?",
            params![branch_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 1, "Branch was not inserted correctly");

        // Delete the repository - this should cascade to the branch
        let result = conn.execute(
            "DELETE FROM repositories WHERE id = ?",
            params![repo_id],
        );
        assert!(result.is_ok(), "Failed to delete repository");

        // Verify the branch was also deleted due to the foreign key constraint
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM branches WHERE id = ?",
            params![branch_id],
            |row| row.get(0),
        ).unwrap();
        assert_eq!(count, 0, "Branch was not cascade deleted with repository");
    }

    /// Test that inserting a duplicate repository path fails
    #[test]
    fn test_unique_constraints(
        (name1, path, description1, owner1) in repository_strategy(),
        (name2, _, description2, owner2) in repository_strategy()
    ) {
        // Skip if the names are the same (would cause a different constraint violation)
        if name1 == name2 {
            return Ok(());
        }

        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert the first repository
        let now = Utc::now().timestamp();
        let result = conn.execute(
            "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
            VALUES (?, ?, ?, ?, ?, ?)",
            params![name1, path, description1, owner1, now, now],
        );
        assert!(result.is_ok(), "Failed to insert first repository");

        // Try to insert a second repository with the same path
        let result = conn.execute(
            "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
            VALUES (?, ?, ?, ?, ?, ?)",
            params![name2, path, description2, owner2, now, now],
        );

        // This should fail because of the unique constraint on the path column
        assert!(result.is_err(), "Inserting repository with duplicate path should fail");
    }

    /// Test schema initialization with multiple tables
    #[test]
    fn test_schema_initialization() {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Check if all the required tables exist
        let tables = ["repositories", "branches", "tags", "commits"];

        for table in &tables {
            let count: i64 = conn.query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
                params![table],
                |row| row.get(0),
            ).unwrap();

            assert_eq!(count, 1, "Table {} should exist", table);
        }

        // Check if indices exist on the repositories table
        let index_count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='repositories'",
            [],
            |row| row.get(0),
        ).unwrap();

        assert!(index_count > 0, "Repository table should have at least one index");
    }

    /// Test that complex queries work as expected
    #[test]
    fn test_complex_queries(
        repos in vec(repository_strategy(), 1..5)
    ) {
        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let conn = sqlite.conn().unwrap();

        // Insert multiple repositories
        let now = Utc::now().timestamp();
        let mut repo_ids = Vec::new();

        for (name, path, description, owner) in repos {
            conn.execute(
                "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                VALUES (?, ?, ?, ?, ?, ?)",
                params![name, path, description, owner, now, now],
            ).unwrap();

            repo_ids.push(conn.last_insert_rowid());
        }

        // Query all repositories
        let mut stmt = conn.prepare("
            SELECT id, name, path, description, owner, last_updated
            FROM repositories
            ORDER BY name
        ").unwrap();

        let repositories = stmt.query_map([], |row| {
            Ok(Repository {
                id: row.get(0)?,
                name: row.get(1)?,
                path: row.get(2)?,
                description: row.get(3)?,
                owner: row.get(4)?,
                last_updated: row.get(5)?,
            })
        }).unwrap().collect::<Result<Vec<_>, _>>().unwrap();

        // Verify all repositories were retrieved
        assert_eq!(repositories.len(), repo_ids.len(), "All repositories should be returned");

        // Insert branches for the first repository (if any)
        if !repo_ids.is_empty() {
            let repo_id = repo_ids[0];
            let branches = [
                ("main", "abcdef1234567890abcdef1234567890abcdef12"),
                ("develop", "bcdef1234567890abcdef1234567890abcdef123"),
                ("feature", "cdef1234567890abcdef1234567890abcdef1234"),
            ];

            for (name, commit_id) in &branches {
                conn.execute(
                    "INSERT INTO branches (repo_id, name, commit_id, created_at)
                    VALUES (?, ?, ?, ?)",
                    params![repo_id, name, commit_id, now],
                ).unwrap();
            }

            // Query branches for the repository
            let mut stmt = conn.prepare("
                SELECT b.id, b.repo_id, b.name, b.commit_id
                FROM branches b
                JOIN repositories r ON b.repo_id = r.id
                WHERE r.id = ?
                ORDER BY b.name
            ").unwrap();

            let query_branches = stmt.query_map([repo_id], |row| {
                Ok(Branch {
                    id: row.get(0)?,
                    repo_id: row.get(1)?,
                    name: row.get(2)?,
                    commit_id: row.get(3)?,
                })
            }).unwrap().collect::<Result<Vec<_>, _>>().unwrap();

            // Verify all branches were retrieved
            assert_eq!(query_branches.len(), branches.len(), "All branches should be returned");
        }
    }

    /// Test concurrent operations on the database
    #[test]
    fn test_concurrent_operations(
        repos in vec(repository_strategy(), 1..5)
    ) {
        use std::thread;
        use std::sync::{Arc, Barrier};

        // Skip if no repositories to insert
        if repos.is_empty() {
            return Ok(());
        }

        // Create a test database
        let (sqlite, _temp_dir) = create_test_db().unwrap();
        let sqlite = Arc::new(sqlite);

        // Create a barrier to synchronize threads
        let thread_count = repos.len();
        let barrier = Arc::new(Barrier::new(thread_count));

        // Spawn threads to insert repositories concurrently
        let mut handles = Vec::new();

        for (i, (name, path, description, owner)) in repos.into_iter().enumerate() {
            let sqlite_clone = Arc::clone(&sqlite);
            let barrier_clone = Arc::clone(&barrier);

            let handle = thread::spawn(move || {
                // Wait for all threads to be ready
                barrier_clone.wait();

                // Get a connection and insert the repository
                let conn = sqlite_clone.conn().unwrap();
                let now = Utc::now().timestamp();

                let result = conn.execute(
                    "INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)",
                    params![format!("{}-{}", name, i), format!("{}-{}", path, i), description, owner, now, now],
                );

                result.unwrap()
            });

            handles.push(handle);
        }

        // Wait for all threads to complete
        for handle in handles {
            handle.join().unwrap();
        }

        // Verify that all repositories were inserted
        let conn = sqlite.conn().unwrap();
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM repositories",
            [],
            |row| row.get(0),
        ).unwrap();

        assert_eq!(count as usize, thread_count, "All repositories should be inserted");
    }
}
