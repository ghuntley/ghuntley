# Database Schema Specification

This document describes the SQLite database schema for the Art cgit re-implementation. The database is designed to store metadata about Git repositories to enable fast querying and reduce the need for direct Git operations.

## Schema Overview

```
┌────────────────┐     ┌─────────────────┐     ┌───────────────┐
│  repositories  │     │     commits     │     │    branches   │
├────────────────┤     ├─────────────────┤     ├───────────────┤
│ id             │1───∞│ id              │     │ id            │
│ name           │     │ repository_id   │     │ repository_id │
│ path           │     │ hash            │     │ name          │
│ description    │     │ author_name     │     │ head_commit   │
│ owner          │     │ author_email    │     │ is_default    │
│ is_public      │     │ committer_name  │     │ last_updated  │
│ last_indexed   │     │ committer_email │     └───────┬───────┘
└────────────────┘     │ message         │             │
                      │ timestamp       │             │
        ┌──────────────│ parent_hashes   │∞────────────┘
        │             └─────────────────┘
        │                     │
        │                     │
┌───────▼───────┐     ┌──────▼──────┐     ┌───────────────┐
│      tags     │     │    files    │     │     users     │
├───────────────┤     ├─────────────┤     ├───────────────┤
│ id            │     │ id          │     │ id            │
│ repository_id │     │ repository_id│     │ username     │
│ name          │     │ path        │     │ password_hash │
│ target_hash   │     │ blob_id     │     │ email         │
│ tagger_name   │     │ last_commit │     │ is_admin      │
│ tagger_email  │     │ size        │     │ created_at    │
│ message       │     │ is_binary   │     └───────────────┘
│ timestamp     │     └─────────────┘
└───────────────┘
```

## Table Definitions

### repositories

Stores information about each Git repository managed by the system.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| name            | TEXT      | Repository name                                  |
| path            | TEXT      | Path to the Git repository on disk               |
| description     | TEXT      | Repository description (from description file)   |
| owner           | TEXT      | Repository owner                                 |
| is_public       | BOOLEAN   | Whether the repository is publicly accessible    |
| clone_url       | TEXT      | URL for cloning the repository                   |
| last_indexed    | TIMESTAMP | When the repository was last indexed             |
| index_interval  | INTEGER   | Custom reindex interval in seconds (optional)    |
| created_at      | TIMESTAMP | When the repository record was created           |
| updated_at      | TIMESTAMP | When the repository record was last updated      |

**Indexes:**
- PRIMARY KEY (id)
- UNIQUE (path)
- UNIQUE (name)
- INDEX (owner)

### commits

Stores metadata about commits in repositories.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| hash            | TEXT      | Git commit hash                                  |
| author_name     | TEXT      | Name of the commit author                        |
| author_email    | TEXT      | Email of the commit author                       |
| committer_name  | TEXT      | Name of the committer                            |
| committer_email | TEXT      | Email of the committer                           |
| message         | TEXT      | Commit message                                   |
| timestamp       | TIMESTAMP | Commit timestamp                                 |
| parent_hashes   | TEXT      | JSON array of parent commit hashes               |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, hash)
- INDEX (repository_id, timestamp)
- INDEX (author_email)
- INDEX (committer_email)

### branches

Stores information about branches in repositories.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| name            | TEXT      | Branch name                                      |
| head_commit     | TEXT      | Commit hash at the head of the branch            |
| is_default      | BOOLEAN   | Whether this is the default branch               |
| last_updated    | TIMESTAMP | When the branch was last updated                 |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, name)
- INDEX (head_commit)

### tags

Stores information about tags in repositories.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| name            | TEXT      | Tag name                                         |
| target_hash     | TEXT      | Commit hash that the tag points to               |
| tagger_name     | TEXT      | Name of the tagger                               |
| tagger_email    | TEXT      | Email of the tagger                              |
| message         | TEXT      | Tag message                                      |
| timestamp       | TIMESTAMP | When the tag was created                         |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, name)
- INDEX (target_hash)

### files

Stores metadata about files in repositories.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| path            | TEXT      | Path to the file within the repository           |
| blob_id         | TEXT      | Git blob ID for the file                         |
| last_commit     | TEXT      | Hash of the last commit that modified the file   |
| size            | INTEGER   | File size in bytes                               |
| is_binary       | BOOLEAN   | Whether the file is binary                       |
| mime_type       | TEXT      | MIME type of the file (if detectable)            |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, path)
- INDEX (repository_id, last_commit)
- INDEX (blob_id)

### users

Stores user information for authentication and authorization.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| username        | TEXT      | User's username                                  |
| password_hash   | TEXT      | Hashed password                                  |
| email           | TEXT      | User's email address                             |
| is_admin        | BOOLEAN   | Whether the user is an administrator             |
| created_at      | TIMESTAMP | When the user was created                        |
| last_login      | TIMESTAMP | When the user last logged in                     |

**Indexes:**
- PRIMARY KEY (id)
- UNIQUE (username)
- UNIQUE (email)

### repository_permissions

Stores permissions for repository access.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| user_id         | INTEGER   | Foreign key to users.id                          |
| can_read        | BOOLEAN   | Whether the user can read the repository         |
| can_write       | BOOLEAN   | Whether the user can write to the repository     |
| can_admin       | BOOLEAN   | Whether the user can administer the repository   |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- FOREIGN KEY (user_id) REFERENCES users(id)
- UNIQUE (repository_id, user_id)

## Cache Tables

### file_cache

Stores cache information for rendered files and diffs.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| path            | TEXT      | Path to the file within the repository           |
| blob_id         | TEXT      | Git blob ID for the file                         |
| content_hash    | TEXT      | Hash of the rendered content                     |
| cached_at       | TIMESTAMP | When the content was cached                      |
| hit_count       | INTEGER   | Number of times this cache entry has been used   |
| last_accessed   | TIMESTAMP | When the cache entry was last accessed           |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, path, blob_id)
- INDEX (last_accessed)
- INDEX (hit_count)

### diff_cache

Stores cache information for generated diffs.

| Column          | Type      | Description                                      |
|-----------------|-----------|--------------------------------------------------|
| id              | INTEGER   | Primary key, auto-increment                      |
| repository_id   | INTEGER   | Foreign key to repositories.id                   |
| from_commit     | TEXT      | Source commit hash for the diff                  |
| to_commit       | TEXT      | Target commit hash for the diff                  |
| content_hash    | TEXT      | Hash of the rendered diff content                |
| cached_at       | TIMESTAMP | When the content was cached                      |
| hit_count       | INTEGER   | Number of times this cache entry has been used   |
| last_accessed   | TIMESTAMP | When the cache entry was last accessed           |

**Indexes:**
- PRIMARY KEY (id)
- FOREIGN KEY (repository_id) REFERENCES repositories(id)
- UNIQUE (repository_id, from_commit, to_commit)
- INDEX (last_accessed)
- INDEX (hit_count)

## Migrations

The database will be managed using migrations to allow for schema evolution over time. Each migration will be versioned and applied sequentially to ensure data integrity.

## Query Examples

### Get Repository Information

```sql
SELECT r.*, COUNT(DISTINCT c.id) AS commit_count, COUNT(DISTINCT b.id) AS branch_count
FROM repositories r
LEFT JOIN commits c ON r.id = c.repository_id
LEFT JOIN branches b ON r.id = b.repository_id
WHERE r.name = 'example-repo'
GROUP BY r.id;
```

### Get Latest Commits for a Repository

```sql
SELECT c.*
FROM commits c
JOIN repositories r ON c.repository_id = r.id
WHERE r.name = 'example-repo'
ORDER BY c.timestamp DESC
LIMIT 20;
```

### Get Files Changed in a Commit

```sql
SELECT f.*
FROM files f
JOIN repositories r ON f.repository_id = r.id
WHERE r.name = 'example-repo' AND f.last_commit = '0123456789abcdef';
```

### Check User Repository Access

```sql
SELECT p.*
FROM repository_permissions p
JOIN repositories r ON p.repository_id = r.id
JOIN users u ON p.user_id = u.id
WHERE r.name = 'example-repo' AND u.username = 'example-user';
```
