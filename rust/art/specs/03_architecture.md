# Art: Architecture

## Overview

Art is designed as a command-line application that provides an efficient server-side rendered web interface for browsing Git repositories, inspired by rgit's architecture. This document outlines the high-level architecture and component interactions of the Art system.

## System Context

```
┌─────────────────────────┐      ┌───────────────────────┐
│                         │      │                       │
│     Git Repositories    │◄─────┤        Art CLI        │
│                         │      │                       │
└─────────────────────────┘      └───────────┬───────────┘
                                             │
                                             │
                                             ▼
┌─────────────────────────┐      ┌───────────────────────┐
│                         │      │                       │
│       Web Browser       │◄─────┤      Web Server       │
│                         │      │                       │
└─────────────────────────┘      └───────────┬───────────┘
                                             │
                                             │
                                             ▼
                                  ┌───────────────────────┐
                                  │                       │
                                  │    SQLite Database    │
                                  │                       │
                                  └───────────────────────┘
```

## Command-Line Interface

Art is primarily a command-line application that launches a web server. The command-line interface accepts various parameters such as:

```bash
art [OPTIONS] [PATH]

OPTIONS:
  -b, --bind-address <ADDRESS>     Specify the address to bind to [default: 127.0.0.1:3000]
  -d, --database <FILE>            SQLite database path [default: ~/.art/database.sqlite]
  -i, --interval <SECONDS>         Metadata refresh interval in seconds [default: 300]
  -t, --timeout <SECONDS>          Request timeout in seconds [default: 30]
  -h, --help                       Print help information
  -v, --version                    Print version information

PATH:
  The path to scan for Git repositories [default: current directory]
```

## Component Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                                 Art CLI                                    │
└───────────────────▲─────────────────────────────────────────▲─────────────┘
                    │                                         │
                    │                                         │
┌───────────────────▼───────────────┐    ┌───────────────────▼───────────────┐
│          Web Server               │    │        Indexer                    │
│                                   │    │                                   │
│ - HTTP request handling           │    │ - Repository discovery            │
│ - Template rendering              │    │ - Metadata extraction             │
│ - Static file serving             │    │ - Change detection                │
│ - Git protocol implementation     │    │ - Database updates                │
└───────────────────▲───────────────┘    └───────────────────▲───────────────┘
                    │                                         │
                    │                                         │
┌───────────────────▼───────────────┐    ┌───────────────────▼───────────────┐
│        Git Interface              │    │        Database Interface         │
│                                   │    │                                   │
│ - Repository access               │    │ - Connection pooling              │
│ - Commit/tree/blob retrieval      │    │ - Prepared statements             │
│ - Diff generation                 │    │ - Transaction management          │
│ - Blame computation               │    │ - Migration handling              │
└───────────────────▲───────────────┘    └───────────────────▲───────────────┘
                    │                                         │
                    │                                         │
┌───────────────────▼───────────────────────────────────────▼───────────────┐
│                                Cache                                       │
│                                                                           │
│ - In-memory caching                                                       │
│ - Content-based invalidation                                              │
│ - Tiered cache hierarchy                                                  │
└───────────────────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Command-Line Interface (CLI)

The CLI component is the entry point for the Art application. It's responsible for:

1. Parsing command-line arguments
2. Initializing the database connection
3. Starting the repository indexer
4. Launching the web server
5. Signal handling for graceful shutdown

The CLI is implemented using the Clap Rust library, which provides a declarative and type-safe approach to building command-line interfaces.

```rust
#[derive(Parser, Debug)]
#[clap(about, version, author)]
struct Args {
    /// The path to scan for Git repositories
    #[clap(default_value = ".")]
    scan_path: PathBuf,

    /// SQLite database path
    #[clap(short, long, default_value = "~/.art/database.sqlite")]
    database: PathBuf,

    /// Specify the address to bind to
    #[clap(short, long, default_value = "127.0.0.1:3000")]
    bind_address: String,

    /// Metadata refresh interval in seconds
    #[clap(short, long, default_value = "300")]
    interval: u64,

    /// Request timeout in seconds
    #[clap(short, long, default_value = "30")]
    timeout: u64,
}
```

### Web Server

Following rgit's implementation approach, the web server component is built using Axum, a lightweight and flexible web framework for Rust that builds on top of Tokio, Hyper, and Tower. The web server provides:

1. HTTP endpoint routing and request handling
2. Server-side rendering using the Askama template engine (same as rgit)
3. Static file serving for CSS and images
4. Git HTTP protocol support for clone/pull/push
5. WebSocket support for real-time updates (future feature)

The web server is designed for server-side rendering of all content, with zero JavaScript requirement, making it fast and accessible to a wide range of browsers and clients.

```rust
async fn start_server(
    args: Args,
    db_pool: SqlitePool,
    git_interface: Arc<GitInterface>,
    cache: Arc<Cache>,
) -> Result<()> {
    // Build shared application state
    let state = Arc::new(AppState {
        db_pool,
        git_interface,
        cache,
        config: AppConfig {
            scan_path: args.scan_path,
            bind_address: args.bind_address.clone(),
            request_timeout: Duration::from_secs(args.timeout),
        },
    });

    // Build the router
    let router = Router::new()
        // Index route
        .route("/", get(handlers::index::handle))

        // Repository routes
        .route("/repo/:repo", get(handlers::repo::summary::handle))
        .route("/repo/:repo/tree/:ref/*path", get(handlers::repo::tree::handle))
        .route("/repo/:repo/blob/:ref/*path", get(handlers::repo::blob::handle))
        .route("/repo/:repo/commit/:hash", get(handlers::repo::commit::handle))
        .route("/repo/:repo/commits/:ref", get(handlers::repo::commits::handle))
        .route("/repo/:repo/blame/:ref/*path", get(handlers::repo::blame::handle))
        .route("/repo/:repo/diff/:from..:to/*path", get(handlers::repo::diff::handle))
        .route("/repo/:repo/tags", get(handlers::repo::tags::handle))
        .route("/repo/:repo/branches", get(handlers::repo::branches::handle))

        // Git HTTP protocol routes
        .route("/repo/:repo/git-upload-pack", post(handlers::git::upload_pack))
        .route("/repo/:repo/git-receive-pack", post(handlers::git::receive_pack))

        // API routes for health checks and metrics
        .route("/api/health", get(handlers::api::health))
        .route("/api/metrics", get(handlers::api::metrics))

        // Static file routes
        .route("/static/*path", get(handlers::static_files::handle))

        // With shared state
        .with_state(state);

    // Start the server
    let listener = tokio::net::TcpListener::bind(&args.bind_address).await?;
    info!("Starting server on {}", args.bind_address);
    axum::serve(listener, router).await?;

    Ok(())
}
```

### Template Engine

Art uses the Askama template engine for server-side rendering, the same template engine used by rgit. Askama compiles templates to Rust code at build time, ensuring excellent performance and type safety. Templates are stored in the `templates` directory and have the `.html` extension.

Example template (inspired by rgit's implementation):

```html
{% extends "base.html" %}

{% block title %}{{ repo.name }} - Summary{% endblock %}

{% block content %}
<div class="repo-summary">
    <h1>{{ repo.name }}</h1>

    {% if repo.description %}
    <div class="repo-description">
        {{ repo.description }}
    </div>
    {% endif %}

    <div class="repo-stats">
        <span>{{ stats.branches }} branches</span>
        <span>{{ stats.tags }} tags</span>
        <span>{{ stats.commits }} commits</span>
    </div>

    {% if readme %}
    <div class="repo-readme">
        <h2>README</h2>
        {{ readme|safe }}
    </div>
    {% endif %}

    <div class="recent-commits">
        <h2>Recent Commits</h2>
        <ul class="commit-list">
            {% for commit in commits %}
            <li class="commit-item">
                <a href="/repo/{{ repo.name }}/commit/{{ commit.hash }}">
                    <span class="commit-hash">{{ commit.short_hash }}</span>
                    <span class="commit-message">{{ commit.message_summary }}</span>
                    <span class="commit-author">{{ commit.author }}</span>
                    <span class="commit-date">{{ commit.formatted_date }}</span>
                </a>
            </li>
            {% endfor %}
        </ul>
    </div>
</div>
{% endblock %}
```

### Git Interface

The Git interface component provides a layer of abstraction over the raw Git operations, using the gitoxide (gix) library for low-level Git access. This component is responsible for:

1. Opening and managing Git repositories
2. Retrieving commits, trees, and blobs
3. Generating diffs between commits or refs
4. Computing blame information for files
5. Supporting repository clone, pull, and push operations

The Git interface includes efficient caching mechanisms to reduce the need for repeated Git operations.

### Database Interface

The database interface component manages interactions with the SQLite database, including:

1. Connection pooling for efficient database access
2. Execution of prepared statements for common queries
3. Transaction management for atomic operations
4. Schema migrations for database updates
5. Query optimization for performance

### Cache System

The caching system, inspired directly by rgit's efficient approach, implements a multi-level caching strategy:

1. In-memory cache for frequently accessed data
2. SQLite database cache for repository metadata
3. Time-based expiration for cache entries
4. Smart invalidation based on repository changes
5. Tiered cache hierarchy for different types of data

## Request Flow

A typical request flow in Art looks like this:

1. User starts Art from the command line with a specific repository path
2. Art launches and initiates repository discovery and indexing
3. Art starts the web server and listens for HTTP requests
4. User opens a web browser and navigates to the Art URL
5. Web server receives the request and routes it to the appropriate handler
6. Handler checks the in-memory cache for the requested data
7. If not in cache, handler queries the SQLite database
8. If not in database, handler retrieves data from the Git repository
9. Handler renders the response using the Askama template engine
10. Response is sent back to the browser
11. Browser renders the HTML without any JavaScript execution

## Server-Side Rendering

Art follows rgit's approach of using server-side rendering exclusively, with no JavaScript required in the browser. This has several advantages:

1. **Accessibility**: Works with a wide range of browsers and clients
2. **Performance**: Reduces client-side processing requirements
3. **Security**: Minimizes client-side attack surface
4. **Simplicity**: Eliminates the need for complex JavaScript frameworks
5. **Bandwidth**: Reduces the amount of data transferred to the client

The server-side rendering is implemented using the Askama template engine, which compiles templates to Rust code at build time for optimal performance.

## Future Extensions

While maintaining the core architecture, Art can be extended in several ways:

1. **Authentication**: Add support for user authentication and access control
2. **WebSockets**: Implement real-time updates for collaborative features
3. **Plugin System**: Develop a plugin system for extending functionality
4. **Distributed Mode**: Support for distributed deployment across multiple servers
5. **Advanced Search**: Implement advanced search capabilities using full-text indexing
6. **CI/CD Integration**: Provide hooks for integration with CI/CD systems
