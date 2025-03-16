#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{CacheConfig, DatabaseConfig};
    use crate::data::cache::Cache;
    use tempfile::{tempdir, TempDir};
    use std::fs;

    // Helper function to create a test database
    fn create_test_db() -> Result<(Database, TempDir)> {
        let temp_dir = tempdir()?;
        let db_path = temp_dir.path().join("test.db");

        let config = DatabaseConfig {
            path: db_path.clone(),
            pool_size: 5,
        };

        let db = Database::new(&config)?;

        Ok((db, temp_dir))
    }

    #[test]
    fn test_database_init() -> Result<()> {
        let (db, _temp_dir) = create_test_db()?;

        // Check if the database is initialized correctly
        let conn = db.get_connection()?;

        // Try to execute a simple query to verify the connection works
        let count: i64 = conn.query_row("SELECT 1", [], |row| row.get(0))?;
        assert_eq!(count, 1);

        // Check if tables were created by querying the sqlite_master table
        let exists: i64 = conn.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='repositories'",
            [],
            |row| row.get(0)
        )?;
        assert_eq!(exists, 1, "repositories table should exist");

        Ok(())
    }

    #[test]
    fn test_database_stats() -> Result<()> {
        let (db, _temp_dir) = create_test_db()?;
        let conn = db.get_connection()?;

        // Insert a test repository
        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed, commit_count, branch_count, tag_count)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                "test-repo",
                "/path/to/repo",
                chrono::Utc::now().timestamp(),
                100,
                5,
                3
            ],
        )?;

        // Get repository stats
        let stats = db.get_repository_stats("test-repo")?;

        // Verify the stats
        assert_eq!(stats.name, "test-repo");
        assert_eq!(stats.path, "/path/to/repo");
        assert_eq!(stats.commit_count, 100);
        assert_eq!(stats.branch_count, 5);
        assert_eq!(stats.tag_count, 3);

        // Try to get stats for a non-existent repository
        let result = db.get_repository_stats("non-existent");
        assert!(result.is_err());

        Ok(())
    }

    #[test]
    fn test_database_search_repository() -> Result<()> {
        let (db, _temp_dir) = create_test_db()?;
        let conn = db.get_connection()?;

        // Insert multiple test repositories
        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed, commit_count)
             VALUES (?1, ?2, ?3, ?4)",
            params!["repo1", "/path/to/repo1", chrono::Utc::now().timestamp(), 10],
        )?;

        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed, commit_count)
             VALUES (?1, ?2, ?3, ?4)",
            params!["repo2", "/path/to/repo2", chrono::Utc::now().timestamp(), 20],
        )?;

        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed, commit_count)
             VALUES (?1, ?2, ?3, ?4)",
            params!["test-repo", "/path/to/test", chrono::Utc::now().timestamp(), 30],
        )?;

        // Search for repositories
        let repos = db.search_repositories("repo")?;
        assert_eq!(repos.len(), 3);

        // Search for a specific repository
        let repos = db.search_repositories("test")?;
        assert_eq!(repos.len(), 1);
        assert_eq!(repos[0].name, "test-repo");

        // Search with no results
        let repos = db.search_repositories("nonexistent")?;
        assert_eq!(repos.len(), 0);

        Ok(())
    }

    #[test]
    fn test_database_index_and_search_commits() -> Result<()> {
        let (db, _temp_dir) = create_test_db()?;
        let conn = db.get_connection()?;

        // Create a repository
        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed)
             VALUES (?1, ?2, ?3)",
            params!["test-repo", "/path/to/repo", chrono::Utc::now().timestamp()],
        )?;

        // Get the repository ID
        let repo_id: i64 = conn.query_row(
            "SELECT id FROM repositories WHERE name = ?1",
            params!["test-repo"],
            |row| row.get(0)
        )?;

        // Index some test commits
        let commit1 = CommitInfo {
            id: "abc123".to_string(),
            short_id: "abc123".to_string(),
            author: "Test User".to_string(),
            email: "test@example.com".to_string(),
            message: "Initial commit".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            parent_ids: vec![],
        };

        let commit2 = CommitInfo {
            id: "def456".to_string(),
            short_id: "def456".to_string(),
            author: "Another User".to_string(),
            email: "another@example.com".to_string(),
            message: "Add feature X".to_string(),
            timestamp: chrono::Utc::now().timestamp() + 100,
            parent_ids: vec!["abc123".to_string()],
        };

        db.index_commit("test-repo", commit1.clone())?;
        db.index_commit("test-repo", commit2.clone())?;

        // Search for commits
        let result = db.search_commits("test-repo", "feature", None, 10)?;
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, "def456");

        let result = db.search_commits("test-repo", "initial", None, 10)?;
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, "abc123");

        // Get all commits
        let result = db.get_commits("test-repo", None, 10)?;
        assert_eq!(result.len(), 2);

        // Get commits with limit
        let result = db.get_commits("test-repo", None, 1)?;
        assert_eq!(result.len(), 1);

        Ok(())
    }

    #[test]
    fn test_database_with_cache() -> Result<()> {
        let (db, _temp_dir) = create_test_db()?;

        // Create a cache
        let cache_config = CacheConfig { max_size: 10, ttl: 60 };
        let cache = Cache::<String, RepositoryStats>::new(&cache_config);

        let conn = db.get_connection()?;

        // Insert a test repository
        conn.execute(
            "INSERT INTO repositories (name, path, last_indexed, commit_count, branch_count, tag_count)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                "cached-repo",
                "/path/to/cached",
                chrono::Utc::now().timestamp(),
                100,
                5,
                3
            ],
        )?;

        // Get stats without cache
        let stats1 = db.get_repository_stats("cached-repo")?;

        // Put stats in cache
        cache.insert("cached-repo".to_string(), stats1.clone()).await;

        // Verify cache has the item
        let cached_stats = cache.get(&"cached-repo".to_string()).await;
        assert!(cached_stats.is_some());
        assert_eq!(cached_stats.unwrap().name, "cached-repo");

        // Update database but not cache
        conn.execute(
            "UPDATE repositories SET commit_count = 200 WHERE name = ?1",
            params!["cached-repo"],
        )?;

        // Get from cache - should have old value
        let cached_stats = cache.get(&"cached-repo".to_string()).await;
        assert!(cached_stats.is_some());
        assert_eq!(cached_stats.unwrap().commit_count, 100); // Old value

        // Get fresh from DB
        let stats2 = db.get_repository_stats("cached-repo")?;
        assert_eq!(stats2.commit_count, 200); // Updated value

        Ok(())
    }
}
