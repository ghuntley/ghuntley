# Art: API and Web Services

## Overview

Art provides a web server that offers both HTML views and API endpoints for Git repository browsing. This document outlines the server architecture, routes, and service implementation.

## Architecture

Art uses a layered architecture for its web server implementation:

```
┌─────────────────────────────────────────────────────┐
│                  HTTP Router                         │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │   HTML Routes   │    │     API Routes      │     │
│  │  (Server-side)  │    │                     │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                 Template Engine                      │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │  Page Templates │    │  Partial Templates  │     │
│  │                 │    │                     │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                Service Layer                         │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │ Repository Svc  │    │    Git Services     │     │
│  │                 │    │                     │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                 Data Access Layer                    │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────────┐     │
│  │   In-Memory     │    │   SQLite Database   │     │
│  │     Cache       │    │     (Metadata)      │     │
│  └─────────────────┘    └─────────────────────┘     │
└─────────────────────────────────────────────────────┘
                          ▲
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                   Data Sources                       │
│                                                     │
│  ┌─────────────────┐                                │
│  │ Git Repository  │                                │
│  │  (gitoxide)     │                                │
│  └─────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

## Web Server Implementation

Art uses a lightweight, asynchronous web server based on the following:

- **HTTP Server**: Hyper or similar async HTTP server
- **Routing**: Custom routing layer built on top of Hyper or tower-http
- **Template Engine**: Askama for server-side template rendering (as used in rgit)
- **Static Files**: Embedded static assets for CSS and basic functionality
- **Security**: Proper security headers, sanitization, and input validation

### Server Configuration

The web server is configured with the following parameters:

- **Host**: Default `localhost` (configurable)
- **Port**: Default `3000` (configurable)
- **TLS**: Optional TLS support with cert/key file paths
- **Workers**: Default number of worker threads equals available CPU cores
- **Max Request Size**: Default 10MB for most requests
- **Request Timeouts**: Default 30s for most operations

## HTML Routes (Server-Side Rendered)

All HTML routes in Art are server-side rendered with NO JavaScript, delivering pure HTML/CSS content to the browser.

### Repository Listing

- **Route**: `/`
- **Method**: `GET`
- **Description**: Lists all available repositories
- **Query Parameters**:
  - `sort`: Sort repositories by name, last updated, etc.
  - `filter`: Filter repositories by name
  - `page`: Page number for pagination
  - `per_page`: Items per page

### Repository View

- **Route**: `/{repo}`
- **Method**: `GET`
- **Description**: Repository overview, shows README and recent commits
- **Parameters**:
  - `repo`: Repository name or ID

### Branches and Tags

- **Route**: `/{repo}/refs`
- **Method**: `GET`
- **Description**: Lists all branches and tags
- **Parameters**:
  - `repo`: Repository name or ID
  - `type`: Optional filter for 'branch' or 'tag'

### Tree View

- **Route**: `/{repo}/tree/{ref}/{path}`
- **Method**: `GET`
- **Description**: Shows directory contents
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
  - `path`: Optional path within repository

### File View

- **Route**: `/{repo}/blob/{ref}/{path}`
- **Method**: `GET`
- **Description**: Shows file content with syntax highlighting
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
  - `path`: Path to the file
- **Query Parameters**:
  - `plain`: If set, shows raw content without HTML markup
  - `highlight`: If set to "off", disables syntax highlighting

### Commit History

- **Route**: `/{repo}/commits/{ref}`
- **Method**: `GET`
- **Description**: Shows commit history
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
- **Query Parameters**:
  - `page`: Page number for pagination
  - `per_page`: Commits per page

### Commit Detail

- **Route**: `/{repo}/commit/{commit}`
- **Method**: `GET`
- **Description**: Shows commit details including diff
- **Parameters**:
  - `repo`: Repository name or ID
  - `commit`: Commit hash (full or short)

### Diff View

- **Route**: `/{repo}/diff/{from}..{to}`
- **Method**: `GET`
- **Description**: Shows diff between two commits or references
- **Parameters**:
  - `repo`: Repository name or ID
  - `from`: Starting commit or reference
  - `to`: Ending commit or reference

### Blame View

- **Route**: `/{repo}/blame/{ref}/{path}`
- **Method**: `GET`
- **Description**: Shows blame information for a file
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
  - `path`: Path to the file

## API Routes

API routes return JSON responses for programmatic access.

### API Overview

- **Route**: `/api`
- **Method**: `GET`
- **Description**: API documentation and version information
- **Response**: JSON describing available endpoints and API version

### Repository List API

- **Route**: `/api/repositories`
- **Method**: `GET`
- **Description**: Lists all available repositories
- **Query Parameters**:
  - `sort`: Sort repositories by name, last updated, etc.
  - `filter`: Filter repositories by name
  - `page`: Page number for pagination
  - `per_page`: Items per page
- **Response**: JSON array of repository information

### Repository Info API

- **Route**: `/api/repositories/{repo}`
- **Method**: `GET`
- **Description**: Repository metadata
- **Parameters**:
  - `repo`: Repository name or ID
- **Response**: JSON object with repository details

### Commits API

- **Route**: `/api/repositories/{repo}/commits`
- **Method**: `GET`
- **Description**: Lists commits
- **Parameters**:
  - `repo`: Repository name or ID
- **Query Parameters**:
  - `ref`: Branch, tag, or commit reference
  - `path`: Limit commits to those affecting this path
  - `page`: Page number for pagination
  - `per_page`: Commits per page
- **Response**: JSON array of commit information

### Commit Detail API

- **Route**: `/api/repositories/{repo}/commits/{commit}`
- **Method**: `GET`
- **Description**: Commit details including changed files
- **Parameters**:
  - `repo`: Repository name or ID
  - `commit`: Commit hash
- **Response**: JSON object with commit details and file changes

### References API

- **Route**: `/api/repositories/{repo}/refs`
- **Method**: `GET`
- **Description**: Lists branches and tags
- **Parameters**:
  - `repo`: Repository name or ID
- **Query Parameters**:
  - `type`: Filter by 'branch' or 'tag'
- **Response**: JSON array of reference information

### Tree API

- **Route**: `/api/repositories/{repo}/tree/{ref}/{path}`
- **Method**: `GET`
- **Description**: Lists directory contents
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
  - `path`: Optional path within repository
- **Response**: JSON array of file and directory information

### File Content API

- **Route**: `/api/repositories/{repo}/blob/{ref}/{path}`
- **Method**: `GET`
- **Description**: Gets file content
- **Parameters**:
  - `repo`: Repository name or ID
  - `ref`: Branch, tag, or commit reference
  - `path`: Path to the file
- **Response**: JSON object with file content and metadata

## Health and Metrics Endpoints

Art provides comprehensive health check and metrics endpoints for monitoring, inspired by rgit's observability approach.

### Health Check

- **Route**: `/health`
- **Method**: `GET`
- **Description**: Service health check
- **Response**:
```json
{
    "status": "ok",
    "version": "1.0.0",
    "uptime_seconds": 3600,
    "git_version": "2.39.1",
    "database_connected": true,
    "repository_count": 42,
    "cpu_usage": 0.5,
    "memory_usage_mb": 128.5,
    "repository_index_count": 123,
    "repository_index_errors": 0,
    "last_index_timestamp": "2023-07-02T15:30:45Z",
    "cache_size_mb": 75.2,
    "cache_item_count": 8432
  }
  ```

### Prometheus Metrics

- **Route**: `/metrics`
- **Method**: `GET`
- **Description**: Prometheus metrics endpoint
- **Response**: Prometheus-formatted metrics
- **Metrics Categories**:
  - **System metrics**: CPU, memory, disk usage, thread count, open file descriptors
  - **HTTP metrics**: Request count, latencies, status codes by path and method
  - **Cache metrics**: Hit rate, size, evictions, invalidations by cache type
  - **Git operation metrics**: Operation count, duration, errors by operation type
  - **Database metrics**: Query count, duration, errors, connection pool stats
  - **Repository metrics**: Count, size, commit frequency, index performance
  - **Custom labels**: Repository name, operation type, path patterns for detailed analysis

### Ready Check

- **Route**: `/ready`
- **Method**: `GET`
- **Description**: Service readiness check
- **Response**:
```json
{
    "ready": true,
    "services": {
      "database": true,
      "git": true,
      "cache": true,
      "index": true,
      "web_server": true
    },
    "startup_time_ms": 1245,
    "service_checks": [
      {"name": "database", "status": "ok", "latency_ms": 3.2},
      {"name": "git", "status": "ok", "latency_ms": 5.8},
      {"name": "cache", "status": "ok", "latency_ms": 0.5},
      {"name": "index", "status": "ok", "latency_ms": 2.1},
      {"name": "web_server", "status": "ok", "latency_ms": 0.8}
    ]
  }
  ```

## Application Metrics

Art collects and exposes detailed metrics to help with monitoring, alerting, and capacity planning.

### System Metrics

- **CPU Usage**: Percentage of CPU usage by the Art process
- **Memory Usage**: Memory consumption in MB
- **Disk Usage**: Storage usage for repositories and database
- **Open File Descriptors**: Number of open file descriptors
- **Thread Count**: Number of active threads
- **Goroutine Count**: Number of active goroutines

### HTTP Metrics

- **Request Rate**: Requests per second
- **Request Duration**: Response time histograms with percentiles (50th, 90th, 95th, 99th)
- **Status Codes**: Count of responses by status code and endpoint
- **Request Size**: Size of incoming requests
- **Response Size**: Size of outgoing responses
- **Active Connections**: Number of active HTTP connections
- **Connection Duration**: Duration of HTTP connections

### Cache Metrics

- **Cache Size**: Current cache size in MB
- **Cache Item Count**: Number of items in cache
- **Cache Hit Rate**: Percentage of cache hits
- **Cache Miss Rate**: Percentage of cache misses
- **Cache Eviction Rate**: Items evicted per second
- **Cache Invalidation Rate**: Items invalidated per second
- **Cache Entry Age**: Distribution of cache entry ages
- **Cache Shard Distribution**: Item distribution across shards

### Git Operation Metrics

- **Git Operation Count**: Number of Git operations by type
- **Git Operation Duration**: Duration of Git operations
- **Git Error Rate**: Rate of failed Git operations
- **Repository Access Count**: Number of repository accesses
- **Pack File Operations**: Count and duration of pack file operations
- **Object Read/Write Rate**: Rate of Git object reads and writes
- **Repository Size Distribution**: Distribution of repository sizes
- **Clone/Fetch Durations**: Time taken for clone/fetch operations

### Database Metrics

- **Query Rate**: Queries per second
- **Query Duration**: Query execution time histograms
- **Transaction Rate**: Transactions per second
- **Connection Pool Utilization**: Percentage of connection pool in use
- **Index Usage**: Statistics on index usage
- **Write Operation Rate**: Rate of write operations
- **Schema Version**: Current database schema version
- **Migration Status**: Status of any pending migrations

### Repository Metrics

- **Repository Count**: Total number of repositories
- **Repository Size**: Size distribution of repositories
- **Commit Count**: Total and per-repository commit counts
- **Branch Count**: Total and per-repository branch counts
- **Push Rate**: Rate of Git push operations
- **Clone Rate**: Rate of Git clone operations
- **Indexing Duration**: Time taken for repository indexing
- **Repository Health**: Metrics on repository integrity

### Example Prometheus Metrics

```
# HELP art_http_requests_total Total number of HTTP requests
# TYPE art_http_requests_total counter
art_http_requests_total{method="GET",route="/",status="200"} 1234

# HELP art_http_request_duration_seconds HTTP request duration in seconds
# TYPE art_http_request_duration_seconds histogram
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.005"} 123
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.01"} 456
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.025"} 789
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.05"} 1010
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.1"} 1131
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.25"} 1222
art_http_request_duration_seconds_bucket{method="GET",route="/",le="0.5"} 1233
art_http_request_duration_seconds_bucket{method="GET",route="/",le="1"} 1234
art_http_request_duration_seconds_bucket{method="GET",route="/",le="+Inf"} 1234
art_http_request_duration_seconds_sum{method="GET",route="/"} 12.34
art_http_request_duration_seconds_count{method="GET",route="/"} 1234

# HELP art_cache_hits_total Total number of cache hits
# TYPE art_cache_hits_total counter
art_cache_hits_total{cache_type="file_content"} 5678

# HELP art_cache_misses_total Total number of cache misses
# TYPE art_cache_misses_total counter
art_cache_misses_total{cache_type="file_content"} 1234

# HELP art_cache_size_bytes Current cache size in bytes
# TYPE art_cache_size_bytes gauge
art_cache_size_bytes{cache_type="file_content"} 12345678

# HELP art_git_operations_total Total number of Git operations
# TYPE art_git_operations_total counter
art_git_operations_total{operation="read_commit"} 9012

# HELP art_git_operation_duration_seconds Git operation duration in seconds
# TYPE art_git_operation_duration_seconds histogram
art_git_operation_duration_seconds_sum{operation="read_commit"} 45.67
art_git_operation_duration_seconds_count{operation="read_commit"} 9012

# HELP art_db_queries_total Total number of database queries
# TYPE art_db_queries_total counter
art_db_queries_total{query_type="select"} 5678

# HELP art_repository_count Number of repositories
# TYPE art_repository_count gauge
art_repository_count 42

# HELP art_memory_usage_bytes Memory usage in bytes
# TYPE art_memory_usage_bytes gauge
art_memory_usage_bytes 134217728

# HELP art_uptime_seconds Uptime in seconds
# TYPE art_uptime_seconds counter
art_uptime_seconds 3600

# HELP art_repository_size_bytes Repository size in bytes
# TYPE art_repository_size_bytes gauge
art_repository_size_bytes{repository="main"} 543210987

# HELP art_cache_invalidations_total Total number of cache invalidations
# TYPE art_cache_invalidations_total counter
art_cache_invalidations_total{reason="git_push"} 42
```

## Metrics Implementation

Art implements metrics collection using the `metrics` crate with a Prometheus recorder:

```rust
fn setup_metrics() -> Result<(), Error> {
    // Create a new Prometheus registry
    let registry = Registry::new();

    // Create a recorder with the registry
    let recorder = PrometheusRecorder::new(&registry);

    // Install the recorder as the global metrics recorder
    metrics::set_recorder(recorder)?;

    // Register metrics with appropriate labels
    metrics::register_counter!("art_http_requests_total", "Total number of HTTP requests");
    metrics::register_histogram!("art_http_request_duration_seconds", "HTTP request duration in seconds");
    metrics::register_counter!("art_cache_hits_total", "Total number of cache hits");
    metrics::register_counter!("art_cache_misses_total", "Total number of cache misses");
    metrics::register_gauge!("art_cache_size_bytes", "Current cache size in bytes");
    metrics::register_counter!("art_git_operations_total", "Total number of Git operations");
    metrics::register_histogram!("art_git_operation_duration_seconds", "Git operation duration in seconds");
    metrics::register_counter!("art_db_queries_total", "Total number of database queries");
    metrics::register_gauge!("art_repository_count", "Number of repositories");
    metrics::register_gauge!("art_memory_usage_bytes", "Memory usage in bytes");
    metrics::register_counter!("art_uptime_seconds", "Uptime in seconds");

    Ok(())
}
```

## Metrics Collection Middleware

Art uses middleware to collect HTTP metrics:

```rust
pub struct MetricsMiddleware<S> {
    service: S,
}

impl<S, B, ReqBody> Service<Request<ReqBody>> for MetricsMiddleware<S>
where
    S: Service<Request<ReqBody>, Response = Response<B>>,
    S::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
    B: http_body::Body,
{
    type Response = S::Response;
    type Error = Box<dyn std::error::Error + Send + Sync>;
    type Future = MetricsFuture<S::Future>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.service.poll_ready(cx).map_err(Into::into)
    }

    fn call(&mut self, req: Request<ReqBody>) -> Self::Future {
        // Extract route pattern from request extensions
        let route = req
            .extensions()
            .get::<RoutePattern>()
            .map(|p| p.as_str())
            .unwrap_or("unknown");

        // Record request metrics
        metrics::counter!("art_http_requests_total", "method" => req.method().as_str(), "route" => route).increment(1);

        // Start timing the request
        let start = Instant::now();

        // Call the inner service
        let future = self.service.call(req);

        // Return a future that will record metrics when the response is ready
        MetricsFuture {
            future,
            start,
            route: route.to_string(),
            method: req.method().as_str().to_string(),
        }
    }
}
```

## Template Rendering

Art uses the Askama template engine for server-side rendering of HTML.

### Template Structure

```
templates/
├── base.html
├── components/
│   ├── commit_list.html
│   ├── file_list.html
│   ├── file_view.html
│   ├── header.html
│   ├── footer.html
│   └── navigation.html
├── pages/
│   ├── index.html
│   ├── repository.html
│   ├── tree.html
│   ├── blob.html
│   ├── commit.html
│   ├── commits.html
│   └── blame.html
└── error.html
```

### Template Implementation

- Pure HTML/CSS templates with no JavaScript
- Responsive design using CSS only
- Template inheritance for consistent layout
- Component-based design for reuse
- Carefully sanitized dynamic content

Example base template structure:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Art Git Browser{% endblock %}</title>
    <style>
        /* Embedded Critical CSS */
    </style>
    <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
    <header>
        {% include "components/header.html" %}
    </header>

    <nav>
        {% include "components/navigation.html" %}
    </nav>

    <main>
        {% block content %}{% endblock %}
    </main>

    <footer>
        {% include "components/footer.html" %}
    </footer>
</body>
</html>
```

## Server Implementations

### Main Server

The main server implementation configures and starts the HTTP server:

```rust
pub async fn run_server(config: ServerConfig) -> Result<(), Error> {
    // Initialize services
    let repo_service = RepositoryService::new(config.repository_path, config.db_pool.clone())?;
    let git_service = GitService::new(config.repository_path.clone())?;
    let template_engine = TemplateEngine::new()?;
    let cache = Cache::new(config.cache_size_mb);

    // Create router
    let router = build_router(
        repo_service,
        git_service,
        template_engine,
        cache,
        config.clone(),
    )?;

    // Build server
    let addr = SocketAddr::new(config.host.parse()?, config.port);
    let server = Server::bind(&addr).serve(router.into_make_service());

    info!("Server listening on {}", addr);

    // Start server
    if let Err(e) = server.await {
        error!("Server error: {}", e);
        return Err(Error::from(e));
    }

    Ok(())
}
```

### Router Configuration

The router maps HTTP requests to appropriate handlers:

```rust
fn build_router(
    repo_service: RepositoryService,
    git_service: GitService,
    template_engine: TemplateEngine,
    cache: Cache,
    config: ServerConfig,
) -> Result<Router, Error> {
    let services = Arc::new(Services {
        repo_service,
        git_service,
        template_engine,
        cache,
        config,
    });

    let router = Router::new()
        // HTML routes
        .route("/", get(handlers::index))
        .route("/:repo", get(handlers::repository))
        .route("/:repo/tree/:ref/*path", get(handlers::tree))
        .route("/:repo/blob/:ref/*path", get(handlers::blob))
        .route("/:repo/commits/:ref", get(handlers::commits))
        .route("/:repo/commit/:commit", get(handlers::commit))
        .route("/:repo/diff/:from..:to", get(handlers::diff))
        .route("/:repo/blame/:ref/*path", get(handlers::blame))

        // API routes
        .route("/api", get(api::index))
        .route("/api/repositories", get(api::repositories))
        .route("/api/repositories/:repo", get(api::repository))
        .route("/api/repositories/:repo/commits", get(api::commits))
        .route("/api/repositories/:repo/commits/:commit", get(api::commit))
        .route("/api/repositories/:repo/refs", get(api::refs))
        .route("/api/repositories/:repo/tree/:ref/*path", get(api::tree))
        .route("/api/repositories/:repo/blob/:ref/*path", get(api::blob))

        // Health and metrics
        .route("/health", get(health::health_check))
        .route("/ready", get(health::ready_check))
        .route("/metrics", get(metrics::metrics))

        // Static files
        .nest_service("/static", static_files_service())

        // Fallback
        .fallback(handlers::not_found)

        // Layer for common middleware
        .layer(
            ServiceBuilder::new()
                .layer(ConcurrencyLimitLayer::new(config.max_concurrent_requests))
                .layer(TimeoutLayer::new(config.request_timeout))
                .layer(CompressionLayer::new())
                .layer(TraceLayer::new_for_http())
        )
        .with_state(services);

    Ok(router)
}
```

### Handler Implementation

Example of a handler for the repository overview page:

```rust
async fn repository(
    State(services): State<Arc<Services>>,
    Path(repo_name): Path<String>,
) -> Result<Response, Error> {
    // Get repository from database
    let repo = services.repo_service.get_repository_by_name(&repo_name).await?;

    // Get README content if available
    let readme = services.git_service
        .get_readme(&repo, &repo.default_branch)
        .await
        .ok();

    // Get recent commits
    let commits = services.git_service
        .get_commits(&repo, &repo.default_branch, 0, 10)
        .await?;

    // Render template
    let context = RepositoryContext {
        repository: repo,
        readme,
        commits,
    };

    let html = services.template_engine.render("pages/repository.html", &context)?;

    // Return response
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "text/html; charset=utf-8")
        .body(Body::from(html))?)
}
```

## Configuration

The server configuration is loaded from environment variables or a configuration file:

```rust
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub repository_path: PathBuf,
    pub db_pool: SqlitePool,
    pub cache_size_mb: usize,
    pub max_concurrent_requests: usize,
    pub request_timeout: Duration,
    pub log_level: String,
    pub tls_enabled: bool,
    pub tls_cert_path: Option<PathBuf>,
    pub tls_key_path: Option<PathBuf>,
}

impl ServerConfig {
    pub async fn from_env() -> Result<Self, Error> {
        let host = env::var("ART_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
        let port = env::var("ART_PORT")
            .unwrap_or_else(|_| "3000".to_string())
            .parse::<u16>()?;
        let repository_path = PathBuf::from(
            env::var("ART_REPOSITORY_PATH").unwrap_or_else(|_| "./repositories".to_string()),
        );
        let db_path = PathBuf::from(
            env::var("ART_DB_PATH").unwrap_or_else(|_| "./art.db".to_string()),
        );
        let cache_size_mb = env::var("ART_CACHE_SIZE_MB")
            .unwrap_or_else(|_| "100".to_string())
            .parse::<usize>()?;
        let max_concurrent_requests = env::var("ART_MAX_CONCURRENT_REQUESTS")
            .unwrap_or_else(|_| "100".to_string())
            .parse::<usize>()?;
        let request_timeout_secs = env::var("ART_REQUEST_TIMEOUT_SECS")
            .unwrap_or_else(|_| "30".to_string())
            .parse::<u64>()?;
        let log_level = env::var("ART_LOG_LEVEL").unwrap_or_else(|_| "info".to_string());
        let tls_enabled = env::var("ART_TLS_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse::<bool>()?;
        let tls_cert_path = if tls_enabled {
            Some(PathBuf::from(env::var("ART_TLS_CERT_PATH")?))
        } else {
            None
        };
        let tls_key_path = if tls_enabled {
            Some(PathBuf::from(env::var("ART_TLS_KEY_PATH")?))
        } else {
            None
        };

        let db_pool = SqlitePool::connect_with(
            SqliteConnectOptions::new()
                .filename(db_path)
                .create_if_missing(true)
                .journal_mode(SqliteJournalMode::Wal)
                .synchronous(SqliteSynchronous::Normal)
        )
        .await?;

        Ok(Self {
            host,
            port,
            repository_path,
            db_pool,
            cache_size_mb,
            max_concurrent_requests,
            request_timeout: Duration::from_secs(request_timeout_secs),
            log_level,
            tls_enabled,
            tls_cert_path,
            tls_key_path,
        })
  }
}
```

## Command-Line Interface

Art provides a command-line interface to start the server:

```rust
#[derive(Debug, clap::Parser)]
#[clap(about, version, author)]
struct Cli {
    /// Path to the configuration file
    #[clap(short, long)]
    config: Option<PathBuf>,

    /// Path to the repositories directory
    #[clap(short, long)]
    repo_path: Option<PathBuf>,

    /// Port to listen on
    #[clap(short, long)]
    port: Option<u16>,

    /// Host address to bind to
    #[clap(short, long)]
    host: Option<String>,

    /// Database file path
    #[clap(short, long)]
    db_path: Option<PathBuf>,

    /// Log level (debug, info, warn, error)
    #[clap(short, long)]
    log_level: Option<String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Parse command line arguments
    let cli = Cli::parse();

    // Load configuration
    let mut config = ServerConfig::from_env().await?;

    // Override with command line arguments if provided
    if let Some(repo_path) = cli.repo_path {
        config.repository_path = repo_path;
    }

    if let Some(port) = cli.port {
        config.port = port;
    }

    if let Some(host) = cli.host {
        config.host = host;
    }

    if let Some(log_level) = cli.log_level {
        config.log_level = log_level;
    }

    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(&config.log_level)
        .init();

    // Log startup information
    info!("Starting Art server");
    info!("Repository path: {}", config.repository_path.display());
    info!("Listening on: {}:{}", config.host, config.port);

    // Start server
    run_server(config).await?;

    Ok(())
}
```

## Security Considerations

The server implements various security measures:

### Input Validation

- Repository names and paths are validated to prevent directory traversal attacks
- Query parameters are validated for proper format and range
- Strict parsing of Git references to prevent command injection

### Output Sanitization

- All dynamic content is sanitized before rendering in templates
- Proper HTML escaping for content displayed in web pages
- Sanitization of file content for XSS prevention

### Rate Limiting

- Rate limiting for API endpoints to prevent abuse
- Gradual backoff for repeated requests from the same client
- Configurable limits for different endpoint types

### Request Limiting

- Maximum request size limits to prevent resource exhaustion
- Request timeout to prevent long-running operations
- Concurrent request limiting to manage server load

### Authentication and Authorization (Optional)

Although not required for basic use, Art can be configured with authentication:

- HTTP Basic Authentication for simple setups
- Token-based authentication for API access
- Repository-level access control

### Network Security

- TLS support for encrypted connections
- Proper HTTP security headers
- Optional CORS configuration for API endpoints

## Testing and Quality Assurance

The server code includes comprehensive tests:

- Unit tests for individual components
- Integration tests for API endpoints
- Load tests for performance verification
- Security tests to validate protection measures

## Deployment Considerations

The server is designed for various deployment scenarios:

- Stand-alone binary with embedded resources
- Docker container for easy deployment
- Reverse proxy integration instructions for Nginx/Apache
- Systemd service configuration examples
- Kubernetes deployment examples
