# Art: System Architecture

## Architecture Overview

Art is designed as a command-line application that provides a web server with a layered architecture that separates concerns and promotes modularity, testability, and maintainability. The system is organized into several components that interact to provide a complete Git repository browsing experience.

```
┌─────────────────────────────────────────────────────────────┐
│                      HTTP Interface Layer                    │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   API       │  │  Web UI     │  │  Git HTTP Backend   │  │
│  │  Endpoints  │  │  Templates  │  │  (Smart HTTP)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                       Service Layer                          │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Repository  │  │   Commit    │  │  File Content       │  │
│  │  Service    │  │   Service   │  │     Service         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Auth      │  │ Index/Cache │  │ Formatting/Render   │  │
│  │  Service    │  │   Service   │  │     Service         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                                                             │
│  ┌─────────────┐  ┌─────────────────────────────────────┐  │
│  │   Health    │  │           Observability             │  │
│  │  Service    │  │       (Logs and Metrics)            │  │
│  └─────────────┘  └─────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                       Data Access Layer                      │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Git       │  │   SQLite    │  │    Cache            │  │
│  │  Access     │  │   Access    │  │     Manager         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Command-Line Application

Art is designed to run as a command-line application that provides the following capabilities:

- Starting a web server with configurable options
- Managing Git repositories (maintenance, status checking)
- Configuring the application settings
- Viewing logs and metrics

### Command-Line Interface

The application will support various commands and options:

```
art [OPTIONS] <COMMAND>

OPTIONS:
  -c, --config <FILE>       Specify configuration file
  -v, --verbose             Enable verbose logging
  -h, --help                Print help information
  -V, --version             Print version information

COMMANDS:
  serve                     Start the web server
  repo                      Repository management commands
  maintenance               Run maintenance tasks
  status                    Check system status
  help                      Print this message or the help of the given subcommand(s)
```

### Web Server Configuration

When starting the web server, the following options can be configured:

```
art serve [OPTIONS]

OPTIONS:
  -p, --port <PORT>         Specify server port [default: 3000]
  -b, --bind <ADDRESS>      Specify bind address [default: 127.0.0.1]
  --repo-dir <DIRECTORY>    Git repositories directory
  --db-path <FILE>          SQLite database path
  --cache-size <SIZE>       Maximum cache size in MB
  --threads <NUMBER>        Number of worker threads
```

## System Components

### HTTP Interface Layer

This is the entry point for all client interactions and provides three main interfaces:

#### API Endpoints
- RESTful API endpoints serving JSON responses
- Handles all programmatic access to the system
- Supports repository and file operations
- URL format: `/api/v1/[resource]/[operation]`
- Health endpoint at `/health` to report system status
- Metrics endpoint for Prometheus at `/metrics`

#### Web UI Templates
- Serves HTML pages with embedded data
- Renders repository content, commit history, etc.
- Uses server-side templates with NO JavaScript
- Responsive design supporting various devices
- Pure server-side rendering for all pages

#### Git HTTP Backend
- Smart HTTP implementation for Git operations
- Handles git push/pull requests
- Integrates with authentication system
- Compatible with standard Git clients
- Supports cloning repositories via HTTPS

### Service Layer

The service layer contains the business logic and orchestrates operations between the interface and data access layers:

#### Repository Service
- Manages repository metadata
- Handles repository operations (list, get, validate)
- Processes repository configuration
- Performs routine Git maintenance operations (gc, repack)
- Implements Git best practices for performance optimization

#### Commit Service
- Manages commit history and details
- Handles commit operations (list, get, diff)
- Processes branch and tag information

#### File Content Service
- Retrieves and processes file content
- Handles syntax highlighting and formatting
- Manages blame information and file history

#### Auth Service
- Handles authentication and authorization
- Manages user access to repositories
- Integrates with HTTP Basic Auth or other mechanisms

#### Index/Cache Service
- Manages repository indexing and reindexing
- Coordinates cache operations and invalidation
- Optimizes performance for commonly accessed data
- Updates SQLite database after Git push operations
- Expires in-memory cache after Git push operations

#### Formatting/Render Service
- Renders Markdown, READMEs, and other formatted content
- Processes syntax highlighting for code files
- Handles HTML sanitization and safe content display

#### Health Service
- Provides system health information
- Exposes `/health` endpoint
- Reports detailed status of all components
- Includes Git repository health statistics

#### Observability Service
- Manages all logging using the tracing crate
- Collects and exposes metrics for Prometheus
- Tracks key performance indicators
- Monitors system health and resource usage

### Data Access Layer

The data access layer provides interfaces to the underlying data storage systems:

#### Git Access
- Uses gitoxide to interact with Git repositories
- Retrieves commits, files, tags, and branches
- Abstracts Git operations for higher layers
- Performs routine maintenance tasks (gc, repack)
- Implements Git performance best practices

#### SQLite Access
- Manages SQLite database interactions
- Handles schema and migrations
- Provides optimized query interfaces
- Updates database after Git push operations

#### Cache Manager
- Implements the caching strategy
- Manages in-memory cache with LRU policies
- Handles cache invalidation and consistency
- Expires relevant cache entries after Git push operations

## Interactions and Data Flow

### Repository Browsing Flow

1. Client requests repository content
2. HTTP Interface layer receives request and routes to appropriate service
3. Service layer processes request and calls data access components
4. Data access layer retrieves information from Git/SQLite/Cache
5. Service layer processes and formats the data
6. HTTP Interface layer renders and returns the response

### Git Operation Flow

1. Git client initiates push/pull operation
2. Git HTTP Backend receives and authenticates request
3. Auth Service validates permissions
4. Git Access component processes Git operation
5. After push operation completes:
   - Index Service updates SQLite database metadata
   - Cache Manager invalidates affected cache entries
6. Response returns to Git client

### Caching Flow

1. Request for repository data arrives
2. Cache Manager checks if data exists in cache
3. If cached, returns immediately
4. If not cached:
   - Retrieve from Git/SQLite
   - Process data
   - Store in cache with appropriate TTL
   - Return to requester

### Health Check Flow

1. Client requests `/health` endpoint
2. Health Service gathers component status information
3. Health Service checks Git repository status
4. Health Service verifies database connection
5. Health Service evaluates cache status
6. Response indicates overall system health

### Observability Flow

1. System logs events using the tracing crate
2. Metrics are collected continuously
3. Prometheus scrapes the `/metrics` endpoint
4. Logs and metrics provide visibility into system operation

## Cross-cutting Concerns

### Authentication and Authorization
- HTTP Basic Authentication for Git operations
- Optional API token authentication for API endpoints
- Repository-level access control

### Observability
- Structured logging with the tracing crate
- Metrics collection for Prometheus
- Health monitoring and reporting
- Performance tracking and profiling

### Error Handling
- Consistent error response format
- Detailed internal error logging
- User-friendly error messages

### Configuration
- Environment variable configuration
- Repository-specific configuration
- Runtime configuration options

## Deployment Architecture

Art is designed to be deployed as a single service, but can be placed behind a reverse proxy for production environments:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐
│             │     │             │     │                     │
│   Client    ├────►│   Reverse   ├────►│    Art Service      │
│   Browser   │     │    Proxy    │     │                     │
│             │     │ (Optional)  │     │                     │
└─────────────┘     └─────────────┘     └──────────┬──────────┘
                                                   │
                                        ┌──────────▼──────────┐
                                        │                     │
                                        │  Git Repositories   │
                                        │                     │
                                        └──────────┬──────────┘
                                                   │
                                        ┌──────────▼──────────┐
                                        │                     │
                                        │  SQLite Database    │
                                        │                     │
                                        └─────────────────────┘
```

## Performance Considerations

### Hot Path Optimization
- Repository browsing and file viewing optimized with caching
- Frequently accessed metadata stored in memory
- Aggressive caching of rendered content

### Scalability
- Stateless design allowing for horizontal scaling if needed
- Efficient resource utilization
- Proper connection pooling for database access

### Git Repository Maintenance
- Automatic garbage collection and repacking
- Optimized pack file management
- Routine maintenance based on Git best practices
- Performance-focused repository operations

### Resource Management
- Controlled memory usage for cache
- Connection pooling for database access
- File handle management for Git operations

## Security Considerations

### Authentication
- Secure handling of credentials
- Support for HTTP Basic Auth
- Optional integration with external auth systems

### Authorization
- Repository-level access control
- Path-based restrictions
- Operation-based permissions (read vs. write)

### Input Validation
- All user inputs validated and sanitized
- Prevention of path traversal attacks
- Protection against malicious Git payloads

## Technology Choices

### Rust
- Memory safety and performance
- Strong type system
- Excellent concurrency model

### gitoxide
- Pure Rust Git implementation
- Performance and safety
- Modern API design

### SQLite
- Lightweight but powerful database
- No external database dependencies
- Simple operational requirements

### Web Framework
- To be determined (likely axum, actix-web, or warp)
- Focus on performance and simplicity
- Support for async I/O

### Observability
- tracing crate for logging and metrics
- Prometheus integration for metrics collection
- Health monitoring through dedicated endpoints
