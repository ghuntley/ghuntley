# Art: Caching and Performance

## Overview

Art combines efficient SQLite metadata caching with a multi-level in-memory cache to deliver exceptional performance, even when browsing large repositories. This document outlines the caching architecture, strategies, and performance optimizations, incorporating insights from rgit's proven approach.

## Caching Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Requests                      │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                   In-Memory Cache Layer                      │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │   Rendered Content      │  │      File Content       │  │
│  │       Cache             │  │        Cache            │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │     Commit Cache        │  │       Tree Cache        │  │
│  │                         │  │                         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                   Metadata Cache Layer                       │
│                                                             │
│                  SQLite Database Cache                      │
│                                                             │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                   Git Repository Layer                       │
│                                                             │
│                     gitoxide access                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Caching Strategy

Based directly on rgit's efficient approach, Art implements a multi-level caching strategy:

1. **In-Memory Cache**
   - Implemented using Moka cache library (as used in rgit)
   - Fast access to frequently used data
   - LRU (Least Recently Used) eviction policy
   - Configurable size limits
   - TTL (Time To Live) for cached items
   - Thread-safe concurrent access
   - Concurrent hash map with reduced lock contention
   - Separate caches for different content types

2. **SQLite Metadata Cache**
   - Repository metadata stored in SQLite (similar to rgit's RocksDB approach)
   - Pre-computed repository information
   - Branch and tag information
   - Commit history and details
   - Incremental updates to avoid full reindexing
   - Automatic background refresh

3. **On-Demand Loading**
   - Files, trees, and diffs loaded directly using gitoxide upon request
   - Results cached for future access
   - Streaming of large files for memory efficiency

## In-Memory Cache Implementation

Following rgit's implementation, Art uses Moka for high-performance concurrent caching:

```rust
pub struct Cache {
    // Commits cache with TTL of 30 seconds (similar to rgit)
    commits: moka::future::Cache<CommitKey, Arc<Commit>>,

    // README rendering cache with TTL of 30 seconds (similar to rgit)
    readme_cache: moka::future::Cache<ReadmeCacheKey, Option<(ReadmeFormat, Arc<str>)>>,

    // File content cache
    file_content: moka::future::Cache<FileKey, Arc<FileContent>>,

    // Tree cache
    tree_cache: moka::future::Cache<TreeKey, Arc<TreeListing>>,

    // Diff cache
    diff_cache: moka::future::Cache<DiffKey, Arc<DiffResult>>,
}

impl Cache {
    pub fn new() -> Self {
        Self {
            commits: moka::future::Cache::builder()
                .time_to_live(Duration::from_secs(30))   // Same as rgit
                .max_capacity(100)                       // Same as rgit
                .build(),

            readme_cache: moka::future::Cache::builder()
                .time_to_live(Duration::from_secs(30))   // Same as rgit
                .max_capacity(100)                       // Same as rgit
                .build(),

            file_content: moka::future::Cache::builder()
                .time_to_live(Duration::from_secs(60))
                .max_capacity(1000)
                .build(),

            tree_cache: moka::future::Cache::builder()
                .time_to_live(Duration::from_secs(30))
                .max_capacity(100)
                .build(),

            diff_cache: moka::future::Cache::builder()
                .time_to_live(Duration::from_secs(60))
                .max_capacity(50)
                .build(),
        }
    }

    // Cache methods...
}
```

### Cache Key Structure

Cache keys follow a structured format similar to rgit's approach:

```rust
// For commit cache
struct CommitKey {
    repository_id: u64,
    commit_hash: String,
    include_diff: bool,
}

// For README cache
struct ReadmeCacheKey {
    repository_id: u64,
    reference: String,
}

// For file content cache
struct FileKey {
    repository_id: u64,
    reference: String,
    path: String,
    highlight: bool,
}

// For tree cache
struct TreeKey {
    repository_id: u64,
    reference: String,
    path: String,
}

// For diff cache
struct DiffKey {
    repository_id: u64,
    from_reference: String,
    to_reference: String,
}
```

## Cache Invalidation Strategy

Art implements a comprehensive cache invalidation strategy:

1. **Time-Based Expiration**
   - Following rgit's approach, most cache entries have 30-60 second TTL
   - High-traffic entries automatically stay in cache longer due to access patterns
   - Low-traffic entries expire automatically

2. **Push-Triggered Invalidation**
   - Git push operations trigger immediate, targeted cache invalidation
   - Post-receive hooks update SQLite database
   - Affected in-memory cache entries are explicitly invalidated
   - Repository maintenance tasks are scheduled if needed

3. **Selective Invalidation**
   - Only invalidate affected parts of the cache
   - Pattern-based invalidation for related items
   - Repository-specific invalidation for isolated changes

4. **Cache Rewarming**
   - Pre-fetch commonly accessed data after invalidation
   - Prioritize popular repositories and branches
   - Background loading to avoid user-facing latency

## Repository Indexing

Art implements a repository indexing approach inspired by rgit:

```rust
pub async fn run_indexer(
    scan_path: PathBuf,
    db_pool: SqlitePool,
    refresh_interval: Duration,
) {
    loop {
        info!("Starting repository indexing...");

        // Discover repositories
        let repos = discover_repositories(&scan_path).await;

        // Process each repository
        for repo in repos {
            if !should_reindex(&repo, &db_pool).await {
                continue;
            }

            // Build repository from discovered path
            match build_repository(&repo, &db_pool).await {
                Ok(_) => info!("Indexed repository: {}", repo.display()),
                Err(e) => error!("Failed to index repository {}: {}", repo.display(), e),
            }
        }

        info!("Repository indexing complete. Next scan in {} seconds", refresh_interval.as_secs());

        // Wait for the next indexing cycle
        tokio::time::sleep(refresh_interval).await;
    }
}

async fn should_reindex(repo_path: &Path, db_pool: &SqlitePool) -> bool {
    // Get repository record from database
    let result = sqlx::query!(
        "SELECT last_indexed FROM repositories WHERE path = ?",
        repo_path.to_string_lossy().as_ref()
    )
    .fetch_optional(db_pool)
    .await;

    if let Ok(Some(record)) = result {
        // Check if repository was modified since last index
        if let Ok(last_commit_time) = get_last_commit_time(repo_path).await {
            return last_commit_time > record.last_indexed;
        }
    }

    // Repository not found or error occurred - reindex
    true
}
```

## Performance Optimizations

### Repository Indexing Performance

Art incorporates techniques directly from rgit to optimize repository indexing:

- **Incremental Indexing**: Only process changes since last indexing
- **Background Processing**: Indexing runs asynchronously in background threads
- **Prioritized Indexing**: Frequently accessed repositories indexed first
- **Batched Database Updates**: Update SQLite in transactions for better performance
- **Smart Reference Handling**: Only update references that have changed

### HTTP Optimizations

- **HTTP Caching Headers**: Proper ETag and Last-Modified headers
- **Compression**: Response compression for text content
- **Streaming**: Streaming responses for large files
- **Connection Pooling**: Reuse connections for efficiency
- **Keep-Alive**: Keep connections open for multiple requests

### Template Rendering

Implementing rgit's approach to template rendering:

- **Compile-Time Templates**: Use Askama for pre-compiled templates (same as rgit)
- **Partial Caching**: Cache rendered template fragments
- **Component-Based Design**: Reusable template components
- **Minimal Template Logic**: Keep templates simple for fast rendering

### Syntax Highlighting

Following rgit's approach to syntax highlighting:

- **On-Demand Syntax Highlighting**: Only highlight when needed
- **Cached Highlighting Results**: Store highlighted content in memory cache
- **Language Detection**: Automatic language detection based on file extension
- **Streaming**: Process large files in chunks to avoid memory pressure

## Example Implementations

### Optimized Git Object Access

Drawing directly from rgit's implementation:

```rust
pub async fn get_commit(&self, repo_id: u64, hash: &str) -> Result<Arc<Commit>> {
    // Try to get from cache first
    let cache_key = (repo_id, hash.to_string(), false);

    if let Some(commit) = self.commits.get(&cache_key).await {
        return Ok(commit);
    }

    // Not in cache, load from Git repository
    let repo = self.get_repository(repo_id).await?;

    // Spawn blocking task for Git operations
    let hash_clone = hash.to_string();
    let commit = tokio::task::spawn_blocking(move || {
        // Get commit object from gitoxide
        let commit_obj = repo.find_commit(hash_clone)?;

        // Convert to our Commit model
        let commit = Commit::from_git_commit(&commit_obj)?;

        Ok::<_, anyhow::Error>(commit)
    })
    .await??;

    // Cache the result
    let commit_arc = Arc::new(commit);
    self.commits.insert(cache_key, commit_arc.clone()).await;

    Ok(commit_arc)
}
```

### README Rendering Cache

Following rgit's approach to README caching:

```rust
pub async fn get_rendered_readme(
    &self,
    repo_id: u64,
    reference: &str,
) -> Result<Option<(ReadmeFormat, Arc<str>)>> {
    // Try to get from cache first
    let cache_key = (repo_id, reference.to_string());

    if let Some(readme) = self.readme_cache.get(&cache_key).await {
        return Ok(readme);
    }

    // Not in cache, try to find and render README
    let repo = self.get_repository(repo_id).await?;
    let reference_clone = reference.to_string();

    let readme = tokio::task::spawn_blocking(move || {
        // Try to find README (various formats)
        for name in ["README.md", "README.markdown", "README.txt", "README"] {
            if let Ok(content) = repo.get_file_content(&reference_clone, name) {
                // Determine format and render
                let (format, rendered) = render_readme(name, &content)?;
                return Ok::<_, anyhow::Error>(Some((format, Arc::from(rendered))))
            }
        }

        Ok(None)
    })
    .await??;

    // Cache the result (even if None)
    self.readme_cache.insert(cache_key, readme.clone()).await;

    Ok(readme)
}
```

## Database Optimization

Art implements database optimizations inspired by rgit's RocksDB usage but tailored for SQLite:

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

## Performance Benchmarks

Drawing from rgit's observed performance, Art establishes these performance targets:

| Operation | Target Response Time | Cache Hit | Cache Miss |
|-----------|---------------------|-----------|------------|
| Repository index | < 100ms | < 50ms | < 200ms |
| File browsing | < 100ms | < 50ms | < 200ms |
| File content | < 100ms | < 30ms | < 300ms |
| Commit list | < 200ms | < 100ms | < 500ms |
| Commit detail | < 200ms | < 100ms | < 400ms |
| Diff view | < 500ms | < 200ms | < 1000ms |
| Blame view | < 500ms | < 200ms | < 1000ms |

These targets are for repositories of moderate size (~5000 commits). Larger repositories may have longer response times, particularly for operations requiring extensive Git data processing.
