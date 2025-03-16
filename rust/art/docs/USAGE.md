# Art Usage Guide

This document provides detailed instructions for using the Art Git repository browser.

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/your-username/art.git
cd art

# Build the application
cargo build --release

# Run the application
./target/release/art
```

### Using Docker

```bash
# Build the Docker image
docker build -t art .

# Run the container
docker run -p 3000:3000 -v $(pwd)/repositories:/app/repositories art
```

### Using Docker Compose

```bash
# Start the application
docker-compose up -d

# Stop the application
docker-compose down
```

## Configuration

Art uses a TOML configuration file. By default, it looks for `config.toml` in the current directory.

### Server Configuration

```toml
[server]
base_url = "http://localhost:3000"  # Base URL for the application
workers = 4                         # Number of worker threads
compress = true                     # Enable gzip compression
cors_origins = []                   # CORS allowed origins (empty means no CORS)
```

### Repository Configuration

```toml
[repository]
repo_dir = "./repositories"         # Directory containing Git repositories
max_commits = 100                   # Maximum number of commits to show in the list
default_branch = "main"             # Default branch to show if not specified
```

### Database Configuration

```toml
[database]
path = "./art.db"                   # Path to the SQLite database file
use_cache = true                    # Enable database caching
cache_max_entries = 1000            # Maximum number of cache entries
cache_ttl_seconds = 300             # Time-to-live for cache entries in seconds
```

### UI Customization

```toml
[ui]
title = "Art Git Browser"           # Application title
description = "A simple Git repository browser"  # Application description
footer = "Powered by Art"           # Footer text (can include HTML)
dark_mode = false                   # Enable dark mode by default
custom_css = null                   # Custom CSS URL (optional)
custom_js = null                    # Custom JavaScript URL (optional)
```

## Command Line Usage

```bash
# Start the server with default settings
art

# Start the server with a custom configuration file
art --config my-config.toml

# Start the server on a specific address
art serve --address 0.0.0.0:8080
```

## Web Interface

### Repositories

- **Repository List**: The home page (`/`) displays a list of all available repositories.
- **Repository Details**: Each repository has a detail page (`/REPO_NAME`), showing branches, tags, and basic information.

### Commits

- **Commit List**: View all commits for a repository (`/REPO_NAME/commits/BRANCH`).
- **Commit Details**: View details of a specific commit (`/REPO_NAME/commit/COMMIT_ID`).

### Files

- **Browse Files**: Browse files in a repository (`/REPO_NAME/tree/BRANCH/PATH`).
- **View File Content**: View the content of a file (`/REPO_NAME/blob/BRANCH/PATH`).
- **Raw File Content**: Get the raw content of a file (`/REPO_NAME/raw/BRANCH/PATH`).

## API Endpoints

Art provides a RESTful API for programmatic access:

- `GET /api/repos`: List all repositories
- `GET /api/repos/:name`: Get repository details
- `GET /api/repos/:name/branches`: List branches
- `GET /api/repos/:name/tags`: List tags
- `GET /api/repos/:name/commits`: List commits
- `GET /api/repos/:name/commits/:id`: Get commit details
- `GET /api/repos/:name/tree/:ref/*path`: Get file or directory content
- `GET /api/repos/:name/blob/:ref/*path`: Get file content
- `GET /api/repos/:name/raw/:ref/*path`: Get raw file content
- `GET /api/health`: Check API health

## Setting Up Repositories

### Using the Setup Script

Art includes a script to set up example repositories:

```bash
# Make the script executable
chmod +x scripts/setup_repositories.sh

# Run the script
./scripts/setup_repositories.sh
```

### Manual Repository Setup

1. Create a directory for your repositories:
```bash
mkdir -p repositories
```

2. Add Git repositories to this directory:
```bash
cd repositories
git clone --mirror https://github.com/example/repo.git
```

3. Make sure the repositories have proper description files:
```bash
echo "Example repository description" > repo/description
```

## Troubleshooting

### Common Issues

1. **Repository not showing**: Make sure the repository is in the configured `repo_dir` and has proper permissions.

2. **Server fails to start**: Check if the port is already in use.

3. **Empty repository list**: Ensure that the repositories directory contains valid Git repositories.

### Logs

Check the application logs for more detailed error information. You can increase the log level by setting the `RUST_LOG` environment variable:

```bash
RUST_LOG=debug ./target/release/art
```

## Contributing

Contributions are welcome! Please see the [CONTRIBUTING.md](CONTRIBUTING.md) file for details.
