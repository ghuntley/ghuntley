# API Specification

This document outlines the REST API endpoints that will be implemented in the Art cgit re-implementation.

## API Overview

All API endpoints are prefixed with `/api/v1/` to allow for future versioning. The API follows RESTful principles and returns JSON responses unless otherwise specified.

## Authentication

Authentication is handled through HTTP Basic Auth or Bearer token. Some endpoints require authentication, while others are publicly accessible depending on repository visibility settings.

### Authentication Headers

- **Basic Auth**: `Authorization: Basic <base64-encoded-credentials>`
- **Token Auth**: `Authorization: Bearer <token>`

## Common Response Formats

### Success Response

```json
{
  "status": "success",
  "data": { ... }
}
```

### Error Response

```json
{
  "status": "error",
  "error": {
    "code": "error_code",
    "message": "Human readable error message"
  }
}
```

## Endpoints

### Repository Management

#### List Repositories

```
GET /api/v1/repositories
```

Returns a list of repositories the authenticated user has access to, or public repositories for unauthenticated users.

**Query Parameters:**
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)
- `sort`: Sort field (name, last_updated, etc.)
- `order`: Sort order (asc, desc)
- `filter`: Filter by name, description, etc.

**Response:**
```json
{
  "status": "success",
  "data": {
    "repositories": [
      {
        "id": 1,
        "name": "example-repo",
        "description": "Example repository",
        "owner": "username",
        "is_public": true,
        "last_updated": "2023-06-15T10:30:00Z",
        "clone_url": "https://example.com/git/example-repo",
        "default_branch": "main"
      },
      ...
    ],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total_items": 45,
      "total_pages": 3
    }
  }
}
```

#### Get Repository

```
GET /api/v1/repositories/:name
```

Returns detailed information about a specific repository.

**Response:**
```json
{
  "status": "success",
  "data": {
    "id": 1,
    "name": "example-repo",
    "description": "Example repository",
    "owner": "username",
    "is_public": true,
    "created_at": "2023-01-15T08:40:00Z",
    "last_updated": "2023-06-15T10:30:00Z",
    "clone_url": "https://example.com/git/example-repo",
    "default_branch": "main",
    "branches_count": 3,
    "tags_count": 5,
    "commits_count": 120,
    "readme": "# Example Repository\n\nThis is an example repository."
  }
}
```

### Commit Operations

#### List Commits

```
GET /api/v1/repositories/:name/commits
```

Returns a list of commits for a repository.

**Query Parameters:**
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)
- `branch`: Branch name (default: repository's default branch)
- `path`: Filter commits affecting a specific file path
- `author`: Filter by author email
- `since`: Return commits more recent than this date
- `until`: Return commits older than this date

**Response:**
```json
{
  "status": "success",
  "data": {
    "commits": [
      {
        "hash": "0123456789abcdef",
        "short_hash": "0123456",
        "author": {
          "name": "Author Name",
          "email": "author@example.com"
        },
        "committer": {
          "name": "Committer Name",
          "email": "committer@example.com"
        },
        "message": "Commit message",
        "timestamp": "2023-06-15T10:30:00Z",
        "parent_hashes": ["fedcba9876543210"]
      },
      ...
    ],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total_items": 120,
      "total_pages": 6
    }
  }
}
```

#### Get Commit

```
GET /api/v1/repositories/:name/commits/:hash
```

Returns detailed information about a specific commit.

**Response:**
```json
{
  "status": "success",
  "data": {
    "hash": "0123456789abcdef",
    "short_hash": "0123456",
    "author": {
      "name": "Author Name",
      "email": "author@example.com"
    },
    "committer": {
      "name": "Committer Name",
      "email": "committer@example.com"
    },
    "message": "Commit message",
    "timestamp": "2023-06-15T10:30:00Z",
    "parent_hashes": ["fedcba9876543210"],
    "files_changed": [
      {
        "path": "src/main.rs",
        "status": "modified",
        "additions": 10,
        "deletions": 5
      },
      ...
    ]
  }
}
```

#### Get Commit Diff

```
GET /api/v1/repositories/:name/commits/:hash/diff
```

Returns the diff for a specific commit.

**Query Parameters:**
- `context`: Number of context lines around changes (default: 3)
- `path`: Filter diff to a specific file path
- `format`: Output format (json, raw)

**Response (JSON):**
```json
{
  "status": "success",
  "data": {
    "hash": "0123456789abcdef",
    "files": [
      {
        "path": "src/main.rs",
        "old_path": "src/main.rs",
        "status": "modified",
        "additions": 10,
        "deletions": 5,
        "chunks": [
          {
            "old_start": 10,
            "old_lines": 7,
            "new_start": 10,
            "new_lines": 12,
            "lines": [
              { "type": "context", "content": "fn main() {" },
              { "type": "deletion", "content": "    println!(\"Hello, world!\");" },
              { "type": "addition", "content": "    println!(\"Hello, Art!\");" },
              ...
            ]
          },
          ...
        ]
      },
      ...
    ]
  }
}
```

### Branch Operations

#### List Branches

```
GET /api/v1/repositories/:name/branches
```

Returns a list of branches for a repository.

**Query Parameters:**
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)
- `sort`: Sort field (name, last_updated, etc.)
- `order`: Sort order (asc, desc)

**Response:**
```json
{
  "status": "success",
  "data": {
    "branches": [
      {
        "name": "main",
        "head_commit": "0123456789abcdef",
        "is_default": true,
        "last_updated": "2023-06-15T10:30:00Z"
      },
      ...
    ],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total_items": 3,
      "total_pages": 1
    }
  }
}
```

#### Get Branch

```
GET /api/v1/repositories/:name/branches/:branch
```

Returns detailed information about a specific branch.

**Response:**
```json
{
  "status": "success",
  "data": {
    "name": "main",
    "head_commit": {
      "hash": "0123456789abcdef",
      "short_hash": "0123456",
      "author": {
        "name": "Author Name",
        "email": "author@example.com"
      },
      "committer": {
        "name": "Committer Name",
        "email": "committer@example.com"
      },
      "message": "Commit message",
      "timestamp": "2023-06-15T10:30:00Z"
    },
    "is_default": true,
    "last_updated": "2023-06-15T10:30:00Z",
    "ahead_of_default": 0,
    "behind_default": 0
  }
}
```

### Tag Operations

#### List Tags

```
GET /api/v1/repositories/:name/tags
```

Returns a list of tags for a repository.

**Query Parameters:**
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)
- `sort`: Sort field (name, timestamp, etc.)
- `order`: Sort order (asc, desc)

**Response:**
```json
{
  "status": "success",
  "data": {
    "tags": [
      {
        "name": "v1.0.0",
        "target_hash": "0123456789abcdef",
        "tagger": {
          "name": "Tagger Name",
          "email": "tagger@example.com"
        },
        "message": "Version 1.0.0",
        "timestamp": "2023-06-15T10:30:00Z"
      },
      ...
    ],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total_items": 5,
      "total_pages": 1
    }
  }
}
```

#### Get Tag

```
GET /api/v1/repositories/:name/tags/:tag
```

Returns detailed information about a specific tag.

**Response:**
```json
{
  "status": "success",
  "data": {
    "name": "v1.0.0",
    "target_hash": "0123456789abcdef",
    "target_commit": {
      "hash": "0123456789abcdef",
      "short_hash": "0123456",
      "author": {
        "name": "Author Name",
        "email": "author@example.com"
      },
      "committer": {
        "name": "Committer Name",
        "email": "committer@example.com"
      },
      "message": "Commit message",
      "timestamp": "2023-06-15T10:30:00Z"
    },
    "tagger": {
      "name": "Tagger Name",
      "email": "tagger@example.com"
    },
    "message": "Version 1.0.0",
    "timestamp": "2023-06-15T10:30:00Z"
  }
}
```

### File Operations

#### List Files

```
GET /api/v1/repositories/:name/tree/:ref
```

Returns a list of files and directories for a repository at a specific ref (commit hash, branch name, or tag name).

**Query Parameters:**
- `path`: Directory path to list (default: repository root)
- `recursive`: Whether to list files recursively (default: false)

**Response:**
```json
{
  "status": "success",
  "data": {
    "path": "/",
    "ref": "main",
    "commit_hash": "0123456789abcdef",
    "items": [
      {
        "name": "src",
        "path": "src",
        "type": "directory",
        "size": null,
        "last_commit": {
          "hash": "0123456789abcdef",
          "short_hash": "0123456",
          "message": "Update source files",
          "timestamp": "2023-06-15T10:30:00Z"
        }
      },
      {
        "name": "README.md",
        "path": "README.md",
        "type": "file",
        "size": 1024,
        "mime_type": "text/markdown",
        "last_commit": {
          "hash": "0123456789abcdef",
          "short_hash": "0123456",
          "message": "Update README",
          "timestamp": "2023-06-15T10:30:00Z"
        }
      },
      ...
    ]
  }
}
```

#### Get File

```
GET /api/v1/repositories/:name/blob/:ref/:path
```

Returns the content of a specific file.

**Query Parameters:**
- `format`: Output format (raw, html, json)
- `highlight`: Whether to syntax highlight the file (default: true)

**Response (JSON):**
```json
{
  "status": "success",
  "data": {
    "path": "src/main.rs",
    "ref": "main",
    "commit_hash": "0123456789abcdef",
    "size": 1024,
    "mime_type": "text/x-rust",
    "is_binary": false,
    "content": "fn main() {\n    println!(\"Hello, Art!\");\n}",
    "html_content": "<pre><code><span class=\"keyword\">fn</span> <span class=\"function\">main</span>() {\n    <span class=\"macro\">println!</span>(<span class=\"string\">\"Hello, Art!\"</span>);\n}</code></pre>",
    "last_commit": {
      "hash": "0123456789abcdef",
      "short_hash": "0123456",
      "message": "Update main.rs",
      "timestamp": "2023-06-15T10:30:00Z"
    }
  }
}
```

#### Get File Blame

```
GET /api/v1/repositories/:name/blame/:ref/:path
```

Returns blame information for a specific file.

**Query Parameters:**
- `format`: Output format (json, html)

**Response (JSON):**
```json
{
  "status": "success",
  "data": {
    "path": "src/main.rs",
    "ref": "main",
    "commit_hash": "0123456789abcdef",
    "lines": [
      {
        "line_number": 1,
        "content": "fn main() {",
        "commit": {
          "hash": "0123456789abcdef",
          "short_hash": "0123456",
          "author": {
            "name": "Author Name",
            "email": "author@example.com"
          },
          "timestamp": "2023-06-15T10:30:00Z"
        }
      },
      {
        "line_number": 2,
        "content": "    println!(\"Hello, Art!\");",
        "commit": {
          "hash": "fedcba9876543210",
          "short_hash": "fedcba9",
          "author": {
            "name": "Another Author",
            "email": "another@example.com"
          },
          "timestamp": "2023-06-14T15:20:00Z"
        }
      },
      ...
    ]
  }
}
```

### Git HTTP Operations

#### Smart HTTP Git Protocol

```
POST /git/:name/git-upload-pack
POST /git/:name/git-receive-pack
GET /git/:name/info/refs?service=git-upload-pack
GET /git/:name/info/refs?service=git-receive-pack
```

These endpoints implement the Smart HTTP Git protocol to allow cloning, fetching, and pushing via HTTP(S). They follow the Git protocol specification and are not typical JSON API endpoints.

### User Management

#### Authenticate User

```
POST /api/v1/auth/login
```

Authenticates a user and returns a token.

**Request:**
```json
{
  "username": "example_user",
  "password": "secure_password"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "token": "jwt_token_here",
    "user": {
      "id": 1,
      "username": "example_user",
      "email": "user@example.com",
      "is_admin": false
    }
  }
}
```

#### Get Current User

```
GET /api/v1/user
```

Returns information about the authenticated user.

**Response:**
```json
{
  "status": "success",
  "data": {
    "id": 1,
    "username": "example_user",
    "email": "user@example.com",
    "is_admin": false,
    "created_at": "2023-01-01T00:00:00Z",
    "last_login": "2023-06-15T10:30:00Z"
  }
}
```

### System Operations

#### Get System Stats

```
GET /api/v1/admin/stats
```

Returns system statistics (admin only).

**Response:**
```json
{
  "status": "success",
  "data": {
    "repositories_count": 25,
    "users_count": 10,
    "total_commits": 5432,
    "indexer_status": "running",
    "last_reindex": "2023-06-15T10:30:00Z",
    "uptime": 86400,
    "version": "1.0.0"
  }
}
```

## Pagination

All endpoints that return lists support pagination using the following query parameters:

- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)

Pagination information is included in the response:

```json
{
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total_items": 45,
    "total_pages": 3
  }
}
```

## Error Codes

| Code                | Description                                |
|---------------------|--------------------------------------------|
| `unauthorized`      | Authentication required                    |
| `forbidden`         | Insufficient permissions                   |
| `not_found`         | Resource not found                         |
| `validation_error`  | Invalid request parameters                 |
| `rate_limited`      | Too many requests                          |
| `internal_error`    | Internal server error                      |
| `bad_request`       | Malformed request                          |
| `conflict`          | Resource conflict                          |

## Rate Limiting

API requests are rate limited to prevent abuse. Rate limit information is included in the response headers:

- `X-RateLimit-Limit`: Maximum number of requests allowed per hour
- `X-RateLimit-Remaining`: Number of requests remaining in the current time window
- `X-RateLimit-Reset`: Time when the rate limit window resets (UNIX timestamp)

When rate limited, the API returns a 429 Too Many Requests response with a `rate_limited` error code.
