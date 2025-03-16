# Art: Data Storage

## Overview

Art uses SQLite as its primary data store for efficient metadata caching and retrieval. The database is designed for performance and scalability, with a schema optimized for Git repository browsing. This document describes the data storage architecture, schema design, and query patterns used by Art.

## SQLite Database Design

Art uses a single SQLite database file to store metadata about Git repositories. The database schema is designed for efficient retrieval and update operations, with careful consideration of query patterns and indexing needs.

### Schema Design

The SQLite schema is inspired by rgit's efficient database approach, but optimized for SQLite instead of RocksDB:

```sql
-- Repositories table
CREATE TABLE repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    owner TEXT,
    last_modified INTEGER NOT NULL,
    last_indexed INTEGER NOT NULL,
    default_branch TEXT DEFAULT 'main',
    is_bare BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    clone_url TEXT
);

-- Branches table
CREATE TABLE branches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    target_commit TEXT NOT NULL, -- commit hash
    last_commit_timestamp INTEGER NOT NULL,
    UNIQUE(repository_id, name),
    FOREIGN KEY(repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Tags table
CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    target_commit TEXT NOT NULL, -- commit hash
    tagger TEXT,
    tag_timestamp INTEGER,
    tag_message TEXT,
    UNIQUE(repository_id, name),
    FOREIGN KEY(repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Commits table (stores just enough metadata for listing without full content)
CREATE TABLE commits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    hash TEXT NOT NULL,
    author TEXT NOT NULL,
    author_email TEXT,
    author_time INTEGER NOT NULL,
    committer TEXT,
    committer_email TEXT,
    commit_time INTEGER NOT NULL,
    message TEXT,
    parent_hashes TEXT, -- Semicolon separated list for multiple parents
    UNIQUE(repository_id, hash),
    FOREIGN KEY(repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Files table (for tracking which files exist in which commits)
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    commit_hash TEXT NOT NULL,
    path TEXT NOT NULL,
    object_id TEXT NOT NULL, -- Git blob hash
    file_mode INTEGER NOT NULL,
    file_size INTEGER NOT NULL,
    is_binary BOOLEAN NOT NULL,
    UNIQUE(repository_id, commit_hash, path),
    FOREIGN KEY(repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Cache invalidations (for tracking cache invalidation events)
CREATE TABLE cache_invalidations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    reason TEXT,
    FOREIGN KEY(repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);

-- Create indexes for common query patterns
CREATE INDEX idx_repositories_path ON repositories(path);
CREATE INDEX idx_branches_repository_id ON branches(repository_id);
CREATE INDEX idx_tags_repository_id ON tags(repository_id);
CREATE INDEX idx_commits_repository_id ON commits(repository_id);
CREATE INDEX idx_commits_repository_hash ON commits(repository_id, hash);
CREATE INDEX idx_commits_author_time ON commits(repository_id, author_time DESC);
CREATE INDEX idx_files_repository_commit ON files(repository_id, commit_hash);
CREATE INDEX idx_files_repository_path ON files(repository_id, path);
CREATE INDEX idx_cache_invalidations_timestamp ON cache_invalidations(repository_id, timestamp DESC);
```

### SQLite Optimization

The SQLite database is configured for optimal performance using WAL (Write-Ahead Logging) mode and other performance-focused settings:

```rust
// Configure SQLite for performance
let pool = sqlx::sqlite::SqlitePoolOptions::new()
    .max_connections(num_cpus::get() as u32 * 2)
    .connect_with(
        sqlx::sqlite::SqliteConnectOptions::new()
            .filename(db_path)
            .create_if_missing(true)
            .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
            .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
            .pragma("cache_size", "10000")
            .pragma("foreign_keys", "ON")
            .pragma("mmap_size", "268435456") // 256MB
    )
    .await?;
```

### Query Patterns

Art follows a consistent pattern for database queries, utilizing prepared statements and connection pooling for optimal performance:

```rust
// Example query for retrieving repository information
pub async fn get_repository_by_name(name: &str, db_pool: &SqlitePool) -> Result<Repository> {
    let record = sqlx::query_as!(
        RepositoryRecord,
        r#"
        SELECT id, path, name, description, owner, last_modified, last_indexed, default_branch, is_bare, is_active, clone_url
        FROM repositories
        WHERE name = ?
        "#,
        name
    )
    .fetch_one(db_pool)
    .await?;

    Ok(Repository::from(record))
}

// Example query for retrieving commit history
pub async fn get_commit_history(
    repository_id: i64,
    branch: &str,
    limit: i64,
    offset: i64,
    db_pool: &SqlitePool,
) -> Result<Vec<CommitSummary>> {
    // First, get the target commit for the branch
    let branch_record = sqlx::query!(
        r#"
        SELECT target_commit
        FROM branches
        WHERE repository_id = ? AND name = ?
        "#,
        repository_id,
        branch
    )
    .fetch_one(db_pool)
    .await?;

    // Get commits reachable from the branch tip
    let commits = sqlx::query_as!(
        CommitRecord,
        r#"
        SELECT id, repository_id, hash, author, author_email, author_time,
               committer, committer_email, commit_time, message, parent_hashes
        FROM commits
        WHERE repository_id = ?
        ORDER BY commit_time DESC
        LIMIT ? OFFSET ?
        "#,
        repository_id,
        limit,
        offset
    )
    .fetch_all(db_pool)
    .await?;

    Ok(commits.into_iter().map(CommitSummary::from).collect())
}
```

## Repository Discovery

Following rgit's approach, Art implements an efficient repository discovery and indexing system:

```rust
/// Discover Git repositories in a given path
pub async fn discover_repositories(
    base_path: &Path,
) -> Vec<PathBuf> {
    let mut repositories = Vec::new();
    let mut dirs_to_scan = VecDeque::new();
    dirs_to_scan.push_back(base_path.to_path_buf());

    while let Some(dir) = dirs_to_scan.pop_front() {
        match tokio::fs::read_dir(&dir).await {
            Ok(mut entries) => {
                let mut is_git_repo = false;
                let mut entries_vec = Vec::new();

                // First pass: check if this is a Git repository
                while let Ok(Some(entry)) = entries.next_entry().await {
                    let path = entry.path();
                    entries_vec.push(path.clone());

                    if path.is_dir() && path.file_name().unwrap_or_default() == ".git" {
                        is_git_repo = true;
                        repositories.push(dir.clone());
                        break;
                    }
                }

                // If not a Git repo, add subdirectories to scan queue
                if !is_git_repo {
                    for path in entries_vec {
                        if path.is_dir() && !path.file_name().unwrap_or_default().to_string_lossy().starts_with('.') {
                            dirs_to_scan.push_back(path);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Error reading directory {}: {}", dir.display(), e);
            }
        }
    }

    repositories
}

/// Build repository metadata from a discovered Git repository path
pub async fn build_repository(
    repo_path: &Path,
    db_pool: &SqlitePool,
) -> Result<i64> {
    // Open the Git repository
    let repo = match tokio::task::spawn_blocking(move || {
        gix::open(repo_path)
    }).await? {
        Ok(repo) => repo,
        Err(e) => {
            error!("Failed to open Git repository at {}: {}", repo_path.display(), e);
            return Err(anyhow::anyhow!("Failed to open Git repository"));
        }
    };

    // Extract repository metadata
    let name = repo_path.file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    let description = tokio::fs::read_to_string(repo_path.join("description"))
        .await
        .unwrap_or_else(|_| "".to_string())
        .trim()
        .to_string();

    let is_bare = repo.is_bare();

    // Find the default branch
    let default_branch = tokio::task::spawn_blocking(move || {
        repo.head_name()
            .ok()
            .and_then(|head| head.parse::<gix::refs::symbolic::Reference>().ok())
            .and_then(|symbolic| symbolic.target_ref().ok())
            .map(|name| name.as_bstr().to_string())
            .unwrap_or_else(|| "refs/heads/main".to_string())
    }).await?;

    let current_time = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    // Insert or update repository record
    let repo_id = sqlx::query!(
        r#"
        INSERT INTO repositories
            (path, name, description, last_modified, last_indexed, default_branch, is_bare, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            name = excluded.name,
            description = excluded.description,
            last_modified = excluded.last_modified,
            last_indexed = excluded.last_indexed,
            default_branch = excluded.default_branch,
            is_bare = excluded.is_bare,
            is_active = excluded.is_active
        RETURNING id
        "#,
        repo_path.to_string_lossy(),
        name,
        description,
        current_time,
        current_time,
        default_branch,
        is_bare,
        true
    )
    .fetch_one(db_pool)
    .await?
    .id;

    // Index branches and tags
    index_repository_refs(repo_id, repo_path, db_pool).await?;

    // Index recent commits
    index_repository_commits(repo_id, repo_path, db_pool).await?;

    Ok(repo_id)
}
```

## Incremental Updates

Art implements an efficient incremental update mechanism to avoid full reindexing of repositories when only minimal changes have occurred:

```rust
/// Determine if a repository needs to be reindexed
pub async fn should_reindex(repo_path: &Path, db_pool: &SqlitePool) -> bool {
    // Check if repository exists in database
    let record = sqlx::query!(
        "SELECT id, last_indexed FROM repositories WHERE path = ?",
        repo_path.to_string_lossy().as_ref()
    )
    .fetch_optional(db_pool)
    .await;

    if let Ok(Some(record)) = record {
        // Get the modification time of the HEAD reference
        let head_path = repo_path.join(".git").join("HEAD");
        let head_path = if head_path.exists() {
            head_path
        } else {
            // Might be a bare repository
            repo_path.join("HEAD")
        };

        if let Ok(metadata) = tokio::fs::metadata(&head_path).await {
            if let Ok(modified) = metadata.modified() {
                if let Ok(secs) = modified.duration_since(SystemTime::UNIX_EPOCH) {
                    // Only reindex if the HEAD file was modified after the last indexing
                    return secs.as_secs() as i64 > record.last_indexed;
                }
            }
        }

        // If we can't determine the HEAD modification time, check the refs directory
        let refs_path = repo_path.join(".git").join("refs");
        let refs_path = if refs_path.exists() {
            refs_path
        } else {
            // Might be a bare repository
            repo_path.join("refs")
        };

        if let Ok(metadata) = tokio::fs::metadata(&refs_path).await {
            if let Ok(modified) = metadata.modified() {
                if let Ok(secs) = modified.duration_since(SystemTime::UNIX_EPOCH) {
                    return secs.as_secs() as i64 > record.last_indexed;
                }
            }
        }

        // Default to reindexing if we can't determine modification times
        return true;
    }

    // Repository not found in database, definitely needs indexing
    true
}
```

## Advanced SQLite Usage

Art leverages advanced SQLite features for optimal performance:

### Transaction Batching

For operations that modify multiple records, transactions are used to ensure atomicity and improve performance:

```rust
pub async fn update_repository_files(
    repository_id: i64,
    commit_hash: &str,
    files: Vec<FileEntry>,
    db_pool: &SqlitePool,
) -> Result<()> {
    let mut transaction = db_pool.begin().await?;

    // First, delete any existing file entries for this commit
    sqlx::query!(
        "DELETE FROM files WHERE repository_id = ? AND commit_hash = ?",
        repository_id,
        commit_hash
    )
    .execute(&mut transaction)
    .await?;

    // Then insert the new files
    for file in files {
        sqlx::query!(
            r#"
            INSERT INTO files
                (repository_id, commit_hash, path, object_id, file_mode, file_size, is_binary)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
            repository_id,
            commit_hash,
            file.path,
            file.object_id,
            file.file_mode,
            file.file_size,
            file.is_binary
        )
        .execute(&mut transaction)
        .await?;
    }

    transaction.commit().await?;
    Ok(())
}
```

### Full-Text Search

For repositories with a large number of files or commits, Art implements SQLite's Full-Text Search (FTS5) capabilities for efficient searching:

```sql
-- FTS virtual table for searching commit messages
CREATE VIRTUAL TABLE commit_search USING fts5(
    message,
    author,
    content='commits',
    content_rowid='id'
);

-- Trigger to keep FTS table in sync with commits table
CREATE TRIGGER commits_ai AFTER INSERT ON commits BEGIN
    INSERT INTO commit_search(rowid, message, author) VALUES (new.id, new.message, new.author);
END;

CREATE TRIGGER commits_ad AFTER DELETE ON commits BEGIN
    INSERT INTO commit_search(commit_search, rowid, message, author) VALUES('delete', old.id, old.message, old.author);
END;

CREATE TRIGGER commits_au AFTER UPDATE ON commits BEGIN
    INSERT INTO commit_search(commit_search, rowid, message, author) VALUES('delete', old.id, old.message, old.author);
    INSERT INTO commit_search(rowid, message, author) VALUES (new.id, new.message, new.author);
END;
```

## Database Maintenance

Inspired by rgit, Art implements a comprehensive database maintenance system to ensure optimal performance:

```rust
pub async fn run_database_maintenance(db_pool: &SqlitePool) -> Result<()> {
    info!("Running database maintenance...");

    // Start a transaction
    let mut tx = db_pool.begin().await?;

    // Run VACUUM to reclaim space and optimize the database
    sqlx::query("VACUUM")
        .execute(&mut tx)
        .await?;

    // Analyze the database to update statistics for the query planner
    sqlx::query("ANALYZE")
        .execute(&mut tx)
        .await?;

    // Remove old cache invalidation records (older than 30 days)
    let thirty_days_ago = SystemTime::now()
        .checked_sub(std::time::Duration::from_secs(30 * 24 * 60 * 60))
        .unwrap()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    sqlx::query!(
        "DELETE FROM cache_invalidations WHERE timestamp < ?",
        thirty_days_ago
    )
    .execute(&mut tx)
    .await?;

    // Clean up any orphaned records
    sqlx::query!(
        "DELETE FROM branches WHERE repository_id NOT IN (SELECT id FROM repositories)"
    )
    .execute(&mut tx)
    .await?;

    sqlx::query!(
        "DELETE FROM tags WHERE repository_id NOT IN (SELECT id FROM repositories)"
    )
    .execute(&mut tx)
    .await?;

    sqlx::query!(
        "DELETE FROM commits WHERE repository_id NOT IN (SELECT id FROM repositories)"
    )
    .execute(&mut tx)
    .await?;

    sqlx::query!(
        "DELETE FROM files WHERE repository_id NOT IN (SELECT id FROM repositories)"
    )
    .execute(&mut tx)
    .await?;

    // Commit the transaction
    tx.commit().await?;

    info!("Database maintenance completed successfully");
    Ok(())
}
```

## Data Migration

Art includes a migration system to handle schema changes and upgrades:

```rust
pub async fn run_migrations(db_pool: &SqlitePool) -> Result<()> {
    info!("Running database migrations...");

    // Check if migrations table exists
    let migrations_table_exists = sqlx::query!(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='migrations'"
    )
    .fetch_optional(db_pool)
    .await?
    .is_some();

    // Create migrations table if it doesn't exist
    if !migrations_table_exists {
        sqlx::query(
            "CREATE TABLE migrations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                version INTEGER NOT NULL UNIQUE,
                applied_at INTEGER NOT NULL
            )"
        )
        .execute(db_pool)
        .await?;
    }

    // Get the current migration version
    let current_version = sqlx::query!(
        "SELECT MAX(version) as version FROM migrations"
    )
    .fetch_one(db_pool)
    .await?
    .version
    .unwrap_or(0);

    // Apply migrations in order
    for (version, migration) in get_migrations().into_iter().filter(|(v, _)| *v > current_version) {
        info!("Applying migration version {}", version);

        // Start a transaction
        let mut tx = db_pool.begin().await?;

        // Run the migration
        sqlx::query(&migration)
            .execute(&mut tx)
            .await?;

        // Record the migration
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        sqlx::query!(
            "INSERT INTO migrations (version, applied_at) VALUES (?, ?)",
            version,
            now
        )
        .execute(&mut tx)
        .await?;

        // Commit the transaction
        tx.commit().await?;

        info!("Migration version {} applied successfully", version);
    }

    info!("Database migrations completed successfully");
    Ok(())
}
```

## Data Safety and Backup

Art implements several features to ensure data safety:

1. **Automatic Backups**: SQLite database files are backed up regularly to prevent data loss.
2. **WAL Mode**: Write-Ahead Logging ensures database integrity in case of crashes.
3. **Journal Files**: SQLite journal files provide additional safety for writes.
4. **Transaction Safety**: All multi-statement operations use transactions to prevent partial updates.
5. **Foreign Key Constraints**: Referential integrity is enforced by SQLite.

## Performance Considerations

The data storage layer is designed for optimal performance:

1. **Indexing Strategy**: Carefully designed indexes for common query patterns.
2. **Connection Pooling**: Reuse database connections for better performance.
3. **Prepared Statements**: Use prepared statements to minimize query parsing overhead.
4. **Transaction Batching**: Group related operations in transactions for better performance.
5. **Asynchronous I/O**: Use asynchronous I/O for database operations to avoid blocking.
6. **Query Optimization**: Carefully crafted queries to minimize data retrieval and processing.
7. **Memory-Mapped I/O**: Use memory-mapped I/O for faster database access.
8. **Smart Caching**: Combine SQLite with in-memory caching for optimal performance.

## SQLite vs RocksDB (used in rgit)

While rgit uses RocksDB as its data store, Art uses SQLite for several reasons:

1. **Simpler Deployment**: SQLite is a file-based database that doesn't require a separate server process, making deployment simpler.
2. **SQL Query Language**: SQLite offers the full power of SQL for complex queries, joins, and aggregations.
3. **ACID Guarantees**: SQLite provides full ACID compliance without additional configuration.
4. **Wide Support**: SQLite has excellent tooling and language support, making it easier to work with.
5. **Single File**: The entire database is contained in a single file, making backups and transfers simpler.
6. **Optimized Performance**: With proper configuration, SQLite can perform exceptionally well for Art's use case.
7. **WAL Mode**: Write-Ahead Logging mode in SQLite provides the performance benefits of log-based databases like RocksDB while maintaining SQL compatibility.

With careful schema design, proper indexing, and connection pooling, SQLite provides excellent performance for Art's git repository browsing use case while offering the flexibility and simplicity of SQL.
