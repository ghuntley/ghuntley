# Art: Git Repository Browser Specifications

Welcome to the Art project specifications. Art is a modern implementation of a Git repository browser inspired by cgit, built with Rust and using gitoxide as the Git library.

## Specification Structure

The specifications are organized by domain/topic:

| Document | Description |
|----------|-------------|
| [00. README](./00_readme.md) | Project overview and specification structure |
| [01. Overview](./01_overview.md) | Project overview, goals, and vision |
| [02. Architecture](./02_architecture.md) | System architecture, components, and data flow |
| [03. Repository Browsing](./03_repository_browsing.md) | Specifications for browsing repositories and their content |
| [04. Git Operations](./04_git_operations.md) | Git operation support (clone, push) via HTTPS |
| [05. Data Storage](./05_data_storage.md) | Data storage approach, SQLite schema, and gitoxide integration |
| [06. Caching & Performance](./06_caching_performance.md) | Caching strategy and performance optimizations |
| [07. API & Services](./07_api_services.md) | API endpoints and service architecture |
| [08. User Interface](./08_user_interface.md) | User interface design and implementation |
| [09. Testing & Quality](./09_testing_quality.md) | Testing strategy and quality assurance |

## Legacy Specifications

The following specifications are now superseded by the domain-oriented structure above:

- [cgit_reimplementation.md](./cgit_reimplementation.md) - Initial project definition
- [architecture.md](./architecture.md) - Original architecture design
- [database_schema.md](./database_schema.md) - Initial database schema design
- [api_specification.md](./api_specification.md) - Original API specification
- [caching_strategy.md](./caching_strategy.md) - Initial caching strategy

## Key Features

- Modern, responsive web interface for Git repositories
- SQLite-based metadata storage with periodic reindexing
- In-memory caching for improved performance
- File viewing with syntax highlighting
- Commit history and diff visualization
- Git operations (clone, push) over HTTPS
- Support for repository browsing on various devices

## Technology Stack

- **Language**: Rust
- **Git Library**: [gitoxide](https://github.com/GitoxideLabs/gitoxide)
- **Database**: SQLite
- **Web Framework**: TBD (likely axum, actix-web, or warp)
- **Frontend**: HTML with minimal JavaScript, progressive enhancement
- **Caching**: Custom in-memory cache implementation

## Development Status

These specifications are currently in draft status. They define the vision and requirements for the Art project but are subject to change as implementation progresses.
