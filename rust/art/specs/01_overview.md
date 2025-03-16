# Art: Overview

## What is Art?

Art is a modern, high-performance command-line tool for browsing Git repositories through a server-side rendered web interface, drawing significant inspiration from rgit's efficient implementation. Designed with a focus on performance, simplicity, and resource efficiency, Art provides an elegant way to explore Git repositories without the overhead of complex hosting platforms.

When invoked from the command line, Art discovers Git repositories in the specified path, indexes their metadata in SQLite, and launches a lightweight web server that provides a clean, navigable interface for browsing repository contents without requiring any JavaScript in the browser.

## Key Features

- **Command-line first**: Art runs as a command-line application with simple, intuitive options
- **Zero JavaScript requirement**: All pages are server-side rendered using Askama templates (same as rgit)
- **Lightweight and fast**: Efficient implementation with minimal resource usage
- **SQLite metadata storage**: Fast, reliable database for repository metadata (adapted from rgit's RocksDB approach)
- **High-performance caching**: Intelligent multi-level caching for responsive browsing
- **Syntax highlighting**: Beautiful syntax highlighting for source code
- **Mobile-friendly interface**: Responsive design that works well on all devices
- **Incremental indexing**: Smart detection and indexing of repository changes
- **Comprehensive observability** with Prometheus metrics and health endpoints
- **Git protocol support**: Clone, fetch, and push support
- **Smart repository maintenance**: Automatic Git maintenance tasks

## Use Cases

Art is designed for:

- **Developers** who want to browse local Git repositories with a clean web interface
- **Teams** that need a lightweight solution for viewing shared repositories
- **System administrators** managing collections of Git repositories
- **Self-hosted solutions** requiring minimal resources and setup
- **Development workstations** for quick local repository browsing
- **CI/CD pipelines** for artifact generation from Git repositories

## Non-Goals

Art is deliberately not trying to be:

- A full GitHub/GitLab alternative with user management, issue tracking, etc.
- A Git hosting service with authentication and access control
- A CI/CD system
- A code review platform
- A project management tool

## Design Principles

Art adheres to the following design principles:

1. **Simplicity**: Clean architecture, minimal dependencies, and intuitive interfaces
2. **Performance**: Optimize for speed and responsiveness
3. **Resource efficiency**: Minimal memory and CPU usage
4. **Compatibility**: Works with standard Git repositories and commands
5. **Command-line focused**: Core functionality available through command-line interface
6. **Server-side rendering**: Zero JavaScript requirement for the web interface
7. **Security**: Safe handling of Git operations and user input
8. **Reliability**: Robust error handling and recovery
9. **Observability**: Comprehensive metrics and logging
10. **SQLite for metadata**: Efficient storage using SQLite database (inspired by rgit's approach)

## Key Technologies

- **Rust**: For performance, safety, and concurrency
- **gitoxide (gix)**: Pure Rust implementation of Git
- **Axum**: Modern, lightweight web framework (as used in rgit)
- **Askama**: Server-side template rendering (as used in rgit)
- **SQLite**: For efficient metadata storage (adapted from rgit's RocksDB approach)
- **Moka**: High-performance caching library (as used in rgit)
- **tokio**: Asynchronous runtime
- **Prometheus-compatible metrics**: For monitoring and observability
- **syntect**: Syntax highlighting library

## User Interactions

Users interact with Art primarily through:

1. **Command-line interface**: Start Art, configure options, specify repositories
2. **Web browser**: Navigate repository contents and view code
3. **Git client**: Clone, fetch, and push using the Git protocol

## System Requirements

Art is designed to be lightweight and runs on a variety of systems:

- Any modern Linux distribution
- macOS 10.14+
- Windows 10+
- 100MB+ RAM (scales with repository size and number)
- 50MB+ disk space plus repository storage

## Core Design Values

1. **Simplicity**: Focus on doing one thing well - browsing Git repositories
2. **Performance**: Fast and responsive, even with large repositories
3. **Command-line focused**: Primary interaction through command-line
4. **Server-side rendered**: No JavaScript requirement for the web interface
5. **Reliability**: Robust error handling and recovery
6. **SQLite for efficiency**: Metadata stored efficiently in SQLite
7. **Observability**: Comprehensive metrics and logging

## Design Influences

Art is influenced by several existing tools and approaches, most notably:

- **rgit**: Key architectural patterns, SQL data modeling, caching strategies
- **Gitiles**: Simple, focused repository browsing
- **GitHub/GitLab**: UI elements and navigation patterns
- **cgit**: Lightweight design and efficiency

By combining the best aspects of these influences with modern technologies and a focus on server-side rendering with no JavaScript requirement, Art provides a unique, high-performance approach to Git repository browsing that prioritizes simplicity, speed and resource efficiency.
