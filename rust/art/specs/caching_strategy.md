# Caching Strategy

This document outlines the caching strategy for the Art cgit re-implementation, focusing on performance optimization through effective caching mechanisms.

## Caching Overview

The Art system implements multiple layers of caching to improve performance and reduce load on Git operations. Caching is particularly important for operations that are computationally expensive, such as rendering file contents with syntax highlighting, generating diffs, and processing blame information.

## Cache Layers

```
┌─────────────────────────────────────────────────────┐
│                   Client Browser                     │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │  HTTP Cache     │    │  Browser Storage    │     │
│  │  (ETags, etc.)  │    │  (if applicable)    │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                   Web Server                         │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │  Static Asset   │    │  Response Caching   │     │
│  │     Cache       │    │    (API results)    │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                 Application Layer                    │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │   In-Memory     │    │     Database        │     │
│  │     Cache       │    │       Cache         │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                    Data Sources                      │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │ SQLite Database │    │  Git Repository     │     │
│  │   (Metadata)    │    │   (via gitoxide)    │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

## In-Memory Cache

### Cache Implementation

The in-memory cache will be implemented as a custom Rust component with the following characteristics:

- **Architecture**: Concurrent hash map with sharding to reduce lock contention
- **Eviction Policy**: LRU (Least Recently Used) with size and time-based limits
- **Concurrency**: Lock-free or fine-grained locking for high concurrency
- **Memory Management**: Configurable size limits with automatic eviction

### Cache Key Structure

Cache keys will be structured to ensure uniqueness and efficient lookup:

```
{cache_type}:{repository_id}:{resource_type}:{resource_id}:{parameters_hash}
```

For example:
- `file:42:content:src/main.rs:abcd1234` (for file content)
- `diff:42:commit:0123456789abcdef:fedcba9876543210` (for a diff between two commits)

### Cached Content Types

#### File Content Cache

Stores rendered file content, including syntax highlighting.

- **Key Components**: Repository ID, file path, blob ID, highlighting parameters
- **Value**: HTML-rendered content or raw content based on request parameters
- **Invalidation Triggers**: File modification, syntax highlighter updates
- **TTL**: 24 hours (configurable)

#### Diff Cache

Stores generated diffs between commits, branches, or arbitrary references.

- **Key Components**: Repository ID, from-reference, to-reference, diff parameters
- **Value**: Generated diff in HTML or raw format
- **Invalidation Triggers**: New commits affecting the diff range
- **TTL**: 24 hours (configurable)

#### Blame Cache

Stores blame information for files.

- **Key Components**: Repository ID, file path, reference
- **Value**: Structured blame data with line-by-line attribution
- **Invalidation Triggers**: New commits affecting the file
- **TTL**: 12 hours (configurable)

#### README Rendering Cache

Stores rendered README files for repository homepages.

- **Key Components**: Repository ID, README path, blob ID
- **Value**: HTML-rendered Markdown content
- **Invalidation Triggers**: README file updates
- **TTL**: 24 hours (configurable)

#### Repository Summary Cache

Stores summarized repository information for listing and dashboard views.

- **Key Components**: Repository ID
- **Value**: Summarized repository information (branches, tags, recent commits)
- **Invalidation Triggers**: New commits, branches, or tags
- **TTL**: 15 minutes (configurable)

### Cache Size Management

The in-memory cache will implement size limitations to prevent memory exhaustion:

- **Total Cache Size**: Configurable maximum memory usage (default: 25% of available system memory)
- **Per-Repository Limit**: Configurable maximum cache size per repository (default: 100MB)
- **Per-Cache-Type Limit**: Configurable maximum cache size per cache type (default: 40% for files, 30% for diffs, 20% for blame, 10% for other)

### Cache Statistics and Monitoring

The cache will collect and expose statistics for monitoring and tuning:

- Hit rate (overall and per cache type)
- Miss rate
- Eviction rate
- Average item size
- Cache usage percentage
- Most frequently accessed items

## Database Cache (Metadata)

The SQLite database itself serves as a cache for Git repository metadata, reducing the need for direct Git operations.

### Indexed Metadata

- **Commits**: All commit metadata (author, message, timestamp, etc.)
- **Branches and Tags**: Names, target commits, and metadata
- **File Tree**: Directory structure and file metadata
- **Blame Information**: Pre-calculated blame for frequently accessed files

### Reindexing Strategy

The database cache is refreshed through a reindexing process:

- **Default Interval**: 5 minutes (configurable per repository)
- **Triggered Events**: Also triggered by Git push operations
- **Incremental Updates**: Only index new commits since last reindex
- **Smart Detection**: Skip reindexing if no repository changes detected

### Indexing Process

1. Check repository for new commits since last indexing
2. If new commits exist, extract metadata and update database
3. Update branch and tag references
4. Update file tree information for changed files
5. Invalidate affected in-memory cache entries

## HTTP-Level Caching

The web server implements HTTP caching mechanisms to reduce bandwidth and server load:

### ETag Support

- Generate ETags based on content hash for all resources
- Support conditional requests with If-None-Match headers
- Return 304 Not Modified responses when content hasn't changed

### Cache-Control Headers

Different cache control strategies are applied based on resource type:

- **Static Assets**: `Cache-Control: public, max-age=86400` (1 day)
- **Repository Listings**: `Cache-Control: private, max-age=300` (5 minutes)
- **File Content**: `Cache-Control: public, max-age=3600` (1 hour)
- **Diffs and Blame**: `Cache-Control: private, max-age=3600` (1 hour)
- **Dynamic Content**: `Cache-Control: no-cache`

### Compression

- Implement gzip and brotli compression for all text responses
- Configure compression levels based on content type
- Store compressed versions in cache when possible

## Performance Metrics

The system will track the following performance metrics to evaluate caching effectiveness:

- **Response Time**: Time to generate and serve responses
- **Cache Hit Ratio**: Percentage of requests served from cache
- **Database Query Time**: Time spent on database operations
- **Git Operation Time**: Time spent on direct Git operations
- **Memory Usage**: Memory consumption by the cache system
- **Reindex Duration**: Time taken for metadata reindexing

## Example Scenarios

### Scenario 1: Browsing a File

1. User requests a file from a repository
2. System checks in-memory cache for rendered file
3. If found in cache, serve immediately (< 10ms)
4. If not in cache:
   a. Check database for file metadata
   b. Use gitoxide to fetch file content
   c. Apply syntax highlighting
   d. Cache the rendered result
   e. Serve the response (< 100ms)

### Scenario 2: Viewing a Large Repository

1. User browses a large repository (10,000+ commits)
2. System serves repository summary from cache (< 20ms)
3. User views commit history with pagination
4. System queries paginated commits from SQLite (< 50ms)
5. As user navigates, additional pages are cached

### Scenario 3: After a Git Push

1. User pushes new commits to a repository
2. Push is processed by gitoxide Git server
3. System triggers metadata reindexing for the repository
4. Relevant cache entries are invalidated
5. New metadata is indexed and stored in SQLite
6. Subsequent requests will use the updated data

## Cache Consistency

### Invalidation Strategies

1. **Time-Based Invalidation**: Entries expire after their TTL
2. **Event-Based Invalidation**: Git operations trigger specific invalidations
3. **Manual Invalidation**: Administrators can force cache clearing

### Write-Through Updates

When data is modified through the application:

1. First update the underlying data store (Git repository or database)
2. Then invalidate relevant cache entries
3. Optionally pre-populate cache with new data for hot paths

## Tuning Recommendations

### Memory Allocation

- For servers with 8GB RAM: 2GB maximum cache size
- For servers with 16GB RAM: 4GB maximum cache size
- For servers with 32GB+ RAM: 8GB maximum cache size

### TTL Adjustments

- Increase TTL for static repositories (rarely updated)
- Decrease TTL for active development repositories
- Consider repository-specific TTL settings

### Reindex Interval

- Large, rarely updated repositories: 30+ minutes
- Medium-sized repositories: 5-15 minutes
- Small, frequently updated repositories: 1-5 minutes

## Implementation Notes

### Key Libraries

- **Concurrent Mapping**: dashmap, evmap, or custom implementation
- **LRU Cache**: lru, cached, or moka
- **Compression**: flate2, brotli
- **Metrics**: metrics-rs or prometheus

### Thread Safety

- Ensure thread-safe access to cache with minimal contention
- Use atomic operations for counters and statistics
- Consider read/write splitting for high-throughput scenarios

### Testing Strategy

- Benchmark cache performance with different workloads
- Test cache consistency during concurrent operations
- Measure memory usage under various cache configurations
- Simulate repository updates and verify invalidation
