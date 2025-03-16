# Architecture Specification

## System Architecture Overview

The cgit re-implementation (referred to as "Art") is designed as a modular web application with a clear separation of concerns. This document outlines the architecture and component interactions.

```
                  ┌─────────────────┐
                  │     Client      │
                  │  (Web Browser)  │
                  └────────┬────────┘
                           │
                           ▼
┌──────────────────────────────────────────────┐
│                 Web Server                    │
│                                              │
│  ┌─────────────┐  ┌─────────────────────┐    │
│  │   Static    │  │     API Router      │    │
│  │   Assets    │  │                     │    │
│  └─────────────┘  └──────────┬──────────┘    │
│                              │               │
└──────────────────────────────┼───────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────┐
│                Core Service                   │
│                                              │
│  ┌─────────────┐  ┌─────────────┐            │
│  │ Repository  │  │   Request   │            │
│  │  Manager    │◄─┤  Handlers   │            │
│  └──────┬──────┘  └─────────────┘            │
│         │                                    │
└─────────┼────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────┐
│            Data Access Layer                 │
│                                             │
│  ┌─────────────┐  ┌────────────┐            │
│  │   SQLite    │  │  In-Memory │            │
│  │  Database   │  │    Cache   │            │
│  └──────┬──────┘  └─────┬──────┘            │
│         │               │                   │
└─────────┼───────────────┼───────────────────┘
          │               │
          ▼               ▼
┌─────────────────┐ ┌────────────────┐
│   Repository    │ │ Cached Content │
│   Metadata      │ │                │
└─────────────────┘ └────────────────┘
```

## Component Details

### 1. Web Server

#### HTTP Server
- Built with a Rust web framework (e.g., `axum`, `actix-web`, or `warp`)
- Handles HTTP(S) requests and responses
- Manages connection pooling and request timeouts
- Implements TLS for secure communication

#### Static Assets
- Serves CSS, JavaScript, and other static files
- Implements asset versioning for cache control
- Compresses responses (gzip, brotli) for reduced bandwidth

#### API Router
- Routes incoming requests to appropriate handlers
- Validates request parameters
- Implements middleware for:
  - Authentication
  - Rate limiting
  - Logging
  - Error handling

### 2. Core Service

#### Request Handlers
- Repository listing
- Commit history viewing
- File tree browsing
- Blame information retrieval
- Diff generation
- Git operation processing (clone, push)

#### Repository Manager
- Manages access to Git repositories
- Validates repository paths
- Handles repository configuration
- Implements access control

### 3. Data Access Layer

#### Gitoxide Integration
- Provides a bridge to the gitoxide library
- Translates application requests into gitoxide operations
- Handles errors and exceptions from gitoxide
- Optimizes Git operations for performance

#### SQLite Database
- Stores repository metadata:
  - Commit information
  - Branch and tag data
  - File tree structure
  - User access permissions
- Schema design with indexes for optimal querying
- Migration system for database updates

#### In-Memory Cache
- Caches frequently accessed data:
  - Rendered README files
  - File diffs
  - Syntax-highlighted source code
- Implements LRU (Least Recently Used) eviction policy
- Configurable size limits and TTL (Time To Live) settings

### 4. Background Services

#### Metadata Indexer
- Periodically checks repositories for changes
- Updates SQLite database with new metadata
- Configurable update interval (default: 5 minutes)
- Implements smart detection to avoid unnecessary reindexing

#### Cache Manager
- Monitors cache usage and performance
- Evicts stale entries based on policy
- Preloads frequently accessed content
- Reports cache statistics

## Data Flow Scenarios

### Viewing Repository Files

1. Client requests a file in a repository
2. Web server receives request and routes to file handler
3. File handler requests file content from Repository Manager
4. Repository Manager checks cache for file content
5. If not in cache:
   a. Repository Manager queries SQLite for file metadata
   b. Repository Manager uses gitoxide to fetch file content
   c. Content is syntax highlighted and cached
6. File content returned to client with appropriate metadata

### Viewing Commit History

1. Client requests commit history for a repository
2. Web server routes to commit history handler
3. Handler requests commits from Repository Manager
4. Repository Manager:
   a. Queries SQLite for commit metadata
   b. If metadata is stale, uses gitoxide to fetch updates
   c. Formats commit data for display
5. Paginated commit history returned to client

### Git Push via HTTPS

1. Client initiates Git push over HTTPS
2. Web server authenticates request
3. Server routes to Git operation handler
4. Handler validates permissions
5. Request is passed to gitoxide for processing
6. On successful push:
   a. Metadata indexer is triggered to update database
   b. Relevant cache entries are invalidated
7. Result sent back to client

## Technology Stack

- **Programming Language**: Rust
- **Git Library**: gitoxide
- **Database**: SQLite
- **Web Framework**: TBD (one of: axum, actix-web, warp)
- **Cache Implementation**: Custom in-memory cache or memcached/redis
- **Syntax Highlighting**: syntect or similar Rust library
- **Markdown Rendering**: pulldown-cmark or similar
- **Frontend**: HTML templates with minimal JavaScript
- **CSS Framework**: Minimal custom framework or lightweight option

## Performance Considerations

- **Caching Strategy**: Optimize cache hit ratio through analytics
- **Database Indexing**: Create appropriate indexes for common queries
- **Connection Pooling**: Maintain persistent database connections
- **Asynchronous Processing**: Use async/await for I/O-bound operations
- **Response Compression**: Compress HTTP responses
- **Asset Optimization**: Minify and bundle static assets
- **Pagination**: Implement for large result sets

## Security Considerations

- **Authentication**: Support for HTTP Basic Auth and/or OAuth
- **Authorization**: Granular permission system for repository access
- **Input Validation**: Sanitize all user inputs
- **HTTPS**: Enforce for all connections, especially for Git operations
- **Rate Limiting**: Prevent abuse through request rate restrictions
- **Audit Logging**: Log all sensitive operations
