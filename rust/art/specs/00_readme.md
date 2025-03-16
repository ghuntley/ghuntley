# Art - A Modern Git Repository Browser

Art is a command-line tool that provides a high-performance Git repository browser with a web interface, built in Rust. It offers fast, efficient repository browsing with a clean server-side rendered UI and no JavaScript dependencies.

## Key Features

- **Command-line interface** for easy deployment and management
- **Server-side rendered web interface** with no JavaScript
- **SQLite database** for efficient metadata storage
- **Fast repository browsing** powered by gitoxide
- **Syntax highlighting** for a wide range of languages
- **Responsive design** that works well on mobile and desktop
- **Comprehensive Prometheus metrics** for monitoring
- **Efficient caching** with smart invalidation strategies
- **Dark mode support** for comfortable late-night browsing
- **On-demand loading** of files, trees, and diffs

## Project Overview

Art aims to be a lightweight, high-performance alternative to complex Git hosting platforms when you just need to browse repositories. It's inspired by projects like [rgit](https://github.com/w4/rgit) and cgit, but implemented in Rust with modern design principles.

## Specifications

This directory contains the detailed specifications for Art:

1. [Overview](01_overview.md) - High-level project overview and goals
2. [Architecture](03_architecture.md) - System architecture and component design
3. [Git Operations](04_git_operations.md) - Git interaction and operations
4. [Data Storage](05_data_storage.md) - Database schema and data management
5. [Caching & Performance](06_caching_performance.md) - Caching strategy and performance optimizations
6. [API & Services](07_api_services.md) - API endpoints and service interfaces
7. [User Interface](08_user_interface.md) - UI design and principles
8. [Testing & Quality](09_testing_quality.md) - Testing strategy and quality practices

## Core Design Principles

1. **Server-side Rendering**: All content is rendered on the server, with no JavaScript required
2. **Performance First**: Optimized for speed, especially with large repositories
3. **Command-line Focused**: Designed as a CLI tool that provides a web interface
4. **SQLite Metadata**: Efficient SQLite database for storing and querying repository metadata
5. **Observability**: Comprehensive logging and metrics for monitoring
6. **Security**: Proper input validation and output sanitization
7. **Accessibility**: Works with minimal browsers and assistive technologies

## How Art Differs

- **No JavaScript Requirement**: Unlike many modern Git browsers, Art works without client-side JavaScript
- **Rust Implementation**: Built in Rust for performance, safety, and modern development
- **Command-line First**: Designed primarily as a CLI tool with a web interface
- **SQLite Database**: Uses SQLite for efficient metadata storage instead of RocksDB/LevelDB
- **Prometheus Integration**: Built-in metrics and monitoring
- **Smart Cache Invalidation**: Efficient cache management after Git operations

## Comparison With Other Tools

| Feature | Art | GitHub/GitLab | cgit | rgit |
|---------|-----|---------------|------|------|
| Language | Rust | Ruby/Go/JS | C | Rust |
| JavaScript Required | No | Yes | No | No |
| Server-side Rendering | Yes | Partial | Yes | Yes |
| Metadata Storage | SQLite | PostgreSQL | Git files | RocksDB |
| Repository Management | No | Yes | No | No |
| Issues/PRs | No | Yes | No | No |
| Performance Focus | High | Medium | High | High |
| Deployment Complexity | Low | High | Low | Low |
| CLI Interface | Yes | No | No | Partial |
| Prometheus Metrics | Yes | Some | No | No |
| Dark Mode | Yes | Yes | No | Yes |

## Getting Started (Future)

```bash
# Install from cargo
cargo install art-git

# Start the server with default settings
art [::]:3000 /path/to/repositories -d /path/to/art.sqlite

# Open in browser
# http://localhost:3000
```

## Repository Configuration

Art follows Git conventions for repository configuration:

- Set a description by creating a `description` file in the repository
- Set owner information with `[gitweb]` section in the repository config
- Enable clone access by creating a `git-daemon-export-ok` file

## Contributing

This project is in the specification phase. Contributions to the specs are welcome via issues and pull requests.

## License

[LICENSE] - See LICENSE file for details.
