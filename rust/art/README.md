# Art: A Git Repository Browser

Art is a lightweight web-based Git repository browser inspired by cgit, providing a clean interface to browse repositories, view commit history, and display files with syntax highlighting.

## Features

- **Repository browsing**: List all available repositories with their descriptions
- **Commit history**: View commit logs with author, date, and message information
- **File browsing**: Browse repository content at any commit or branch
- **Syntax highlighting**: Highlight code files with proper syntax coloring
  - Support for 30+ programming languages
  - Multiple color themes
  - Line numbering and highlighted lines
  - Binary file detection and safe rendering
  - Accessibility features (WCAG compliant color contrast, ARIA attributes)
  - Async loading for large files with chunked responses
  - Incremental formatting for pagination
- **Advanced search**: Search across repositories with rich context
  - Multiple search types (text, symbol, commit, path, regex, semantic)
  - Language-specific filters and code context
  - Search suggestions and related searches
  - Result categorization by language, author, and time period
- **Responsive design**: Works on desktop and mobile devices
- **Dark mode support**: Toggle between light and dark themes
- **Observability**: Comprehensive metrics, logging and diagnostics
  - Prometheus-compatible metrics
  - Structured JSON logging
  - Distributed tracing
  - Health endpoints

## Installation

### Prerequisites

- Rust 1.70+ (with Cargo)
- Git

### Building from source

```bash
# Clone the repository
git clone https://github.com/your-username/art.git
cd art

# Build the application
cargo build --release

# Run the application
./target/release/art
```

## Configuration

Art uses a TOML configuration file. By default, it looks for `config.toml` in the current directory.

```toml
# Sample configuration
[server]
base_url = "http://localhost:3000"
workers = 4
compress = true

[repository]
repo_dir = "./repositories"
max_commits = 100
default_branch = "main"

[database]
path = "./art.db"
use_cache = true

[ui]
title = "Art Git Browser"
description = "A simple Git repository browser"
dark_mode = false
```

See the included `config.toml` file for a complete example with comments.

## Usage

```bash
# Start the server with default settings
art

# Start the server with a custom configuration file
art --config my-config.toml

# Start the server on a specific address
art serve --address 0.0.0.0:8080
```

## Project Structure

- `src/`: Source code
  - `config.rs`: Configuration handling
  - `data/`: Data layer (Git, SQLite, cache)
  - `error.rs`: Error types
  - `http/`: HTTP server and routes
  - `template/`: Template rendering
  - `util/`: Utility functions
- `templates/`: HTML templates
- `static/`: Static assets (CSS, JavaScript)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by [cgit](https://git.zx2c4.com/cgit/)
- Built with [Rust](https://www.rust-lang.org/), [Axum](https://github.com/tokio-rs/axum), and [Askama](https://github.com/djc/askama)

## Testing

Art has a comprehensive test suite including:

### Unit Tests

Run the unit tests with:

```bash
cargo test
```

### Integration Tests

Integration tests that verify the application works as expected:

```bash
cargo test --test '*'
```

### Property-Based Tests

Tests that verify behavior across a wide range of inputs:

```bash
cargo test --test property_test
```

### Security Tests

Tests that verify the application handles potentially malicious inputs safely:

```bash
cargo test --test security_test
```

### Benchmarks

Performance benchmarks to track critical operations:

```bash
cargo bench
```

### Load Testing

A load testing script is included to simulate heavy traffic:

```bash
# Basic load test with default settings
./scripts/load_test.py

# High load test with 200 concurrent clients
./scripts/load_test.py --clients 200 --duration 120

# API-focused load test
./scripts/load_test.py --scenario api --clients 100
```

### Coverage Reports

Generate a test coverage report with:

```bash
./scripts/coverage.sh
```

This requires nightly Rust and the `grcov` tool. The report will be available in `target/coverage/`.

## API

In addition to the web interface, Art provides REST APIs for programmatic access to repositories:

- `GET /api/repos`: List all repositories
- `GET /api/repo/{name}`: Get repository details
- `GET /api/repo/{name}/refs`: Get branches and tags
- `GET /api/repo/{name}/log`: Get commit history
- `GET /api/repo/{name}/tree/{ref}[/{path}]`: Browse files at ref
- `GET /api/repo/{name}/blob/{ref}/{path}`: Get file contents
- `GET /api/repo/{name}/commit/{id}`: Get commit details

## Format Service

The Art application includes a powerful `FormatService` for code formatting and syntax highlighting. This service provides:

### Key Features

- **Syntax Highlighting**: Detects language from file extension and applies appropriate syntax highlighting
- **Caching**: Efficient caching system with automatic cleanup and size management
- **Incremental Formatting**: Process large files in chunks to improve performance
- **Async Processing**: Background processing for large files to keep the UI responsive
- **Accessibility**: WCAG-compliant color contrast checking and screen reader support
- **Security**: HTML sanitization to prevent XSS attacks
- **Binary Detection**: Automatic detection and safe rendering of binary files
- **Telemetry**: Comprehensive metrics for monitoring performance

### Usage Example

```rust
use art::service::format::{FormatService, FormatOptions};

// Create a new format service
let mut format_service = FormatService::new();

// Configure options
let mut options = FormatOptions::default();
options.show_line_numbers = true;
options.wrap_lines = false;
options.theme = Some("Solarized (dark)".to_string());

// Format code
let code = "fn main() {\n    println!(\"Hello, world!\");\n}";
let result = format_service.format_code(code, "example.rs", &options);

match result {
    Ok(formatted) => {
        println!("HTML: {}", formatted.html);
        println!("Language: {:?}", formatted.language);
        println!("Line count: {}", formatted.line_count);
    },
    Err(err) => println!("Error: {}", err),
}
```

### Asynchronous Formatting

For large files, use the async API:

```rust
use art::service::format::{FormatService, FormatOptions};

#[tokio::main]
async fn main() {
    let mut format_service = FormatService::new();
    let mut options = FormatOptions::default();
    options.process_async = true;

    let large_content = "..."; // Very large code file

    // Start async formatting
    let result = format_service.format_code_async(large_content, "large_file.rs", &options).await;

    if let Ok(initial_result) = result {
        println!("Started formatting: {}", initial_result.operation_id);

        // Check status later
        let status = format_service.get_async_format_status(&initial_result.operation_id).await.unwrap();
        println!("Progress: {}%", status.percent_complete);

        // Access any available chunks
        for chunk in &status.chunks {
            println!("Chunk for lines {}-{}: {}", chunk.line_range.0, chunk.line_range.1, chunk.html);
        }
    }
}
```

## Search Service

The Art application includes an advanced `SearchService` for searching across Git repositories, built on top of the `IndexService`. This service provides enhanced search capabilities with rich contextual information.

### Key Features

- **Advanced Search Types**:
  - Full text search
  - Code symbol search (functions, classes, etc.)
  - Commit search (by message, author, etc.)
  - File path search
  - Regular expression search
  - Semantic code search

- **Rich Context**: Enhances search results with:
  - Language detection
  - Code context (lines before/after matches)
  - Recent commits affecting matching files
  - Contributors to files
  - Last modification details for each line

- **Result Categorization**:
  - Breakdowns by language
  - Breakdowns by author
  - Breakdowns by time period

- **Search Assistance**:
  - Auto-complete suggestions
  - Related search suggestions

### Usage Example

```rust
use art::service::search::{SearchService, AdvancedSearchOptions, SearchType};

#[tokio::main]
async fn main() {
    // Assuming you have initialized the required dependencies
    let search_service = SearchService::new(
        index_service,
        repository_service,
        file_service,
        commit_service,
        cache,
    );

    // Configure search options
    let mut options = AdvancedSearchOptions::default();
    options.search_type = SearchType::Text;
    options.context_lines = Some(3);
    options.include_snippets = true;
    options.get_suggestions = true;

    // Perform search
    let results = search_service.search("error handling", &options).await.unwrap();

    // Process results
    println!("Total matches: {}", results.base_result.total_matches);

    // Display repositories with matches
    for repo in &results.repositories {
        println!("Repository: {}", repo.base_matches.repository);
        println!("  Match count: {}", repo.base_matches.matches);

        for file in &repo.files {
            println!("  File: {} ({})", file.base_match.path, file.language.as_deref().unwrap_or("Unknown"));

            for line in &file.lines {
                println!("    Line {}: {}", line.base_match.line_number, line.base_match.content);

                // Show context if available
                if let Some(context) = &line.context_before {
                    println!("      Context before: {} lines", context.len());
                }
            }
        }
    }
}
```

### Specialized Search Methods

The service provides specialized methods for different search types:

```rust
// Symbol search (functions, classes, variables, etc.)
let symbol_results = search_service.symbol_search("class User", &options).await.unwrap();

// Semantic code search
let semantic_results = search_service.semantic_search("authentication logic", &options).await.unwrap();

// Regular expression search
let regex_results = search_service.regex_search(r"function\s+\w+\s*\(\)", &options).await.unwrap();

// File path search
let path_results = search_service.path_search("*.config.js", &options).await.unwrap();

// Commit search
let commit_results = search_service.commit_search("fix security vulnerability", &options).await.unwrap();
```

## License

Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
SPDX-License-Identifier: Proprietary

## Observability

The Art application includes comprehensive observability features for monitoring and troubleshooting:

### Metrics

- **Prometheus Integration**: Metrics exposed at `/metrics` endpoint
- **HTTP Metrics**: Request counts, response status codes, and durations
- **Git Metrics**: Operation counts and durations
- **System Metrics**: Memory usage, active connections, etc.
- **Custom Dashboards**: Pre-configured Grafana dashboards

### Logging

- **Structured JSON Logs**: Machine-parseable logs with contextual data
- **Log Levels**: Configurable verbosity (trace, debug, info, warn, error)
- **Query API**: HTTP endpoint to query logs with filtering
- **Distributed Tracing**: Trace context propagation across components

### Monitoring Setup

A Docker Compose configuration is provided for quick setup of Prometheus and Grafana:

```bash
# Start the monitoring stack
docker-compose -f docker-compose.monitoring.yml up -d

# Access Grafana at http://localhost:3001 (admin/admin)
```

For detailed setup instructions and usage examples, see the [Observability Documentation](./prometheus/README.md).
