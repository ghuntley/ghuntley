//! Database schema definitions

/// Repositories table schema
pub const REPOSITORIES_TABLE: &str = "
CREATE TABLE IF NOT EXISTS repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    description TEXT,
    owner TEXT,
    last_updated INTEGER NOT NULL,
    created_at INTEGER NOT NULL
)";

/// Branches table schema
pub const BRANCHES_TABLE: &str = "
CREATE TABLE IF NOT EXISTS branches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    commit_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id, name)
)";

/// Tags table schema
pub const TAGS_TABLE: &str = "
CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    commit_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id, name)
)";

/// Commits table schema
pub const COMMITS_TABLE: &str = "
CREATE TABLE IF NOT EXISTS commits (
    id TEXT NOT NULL,
    repo_id INTEGER NOT NULL,
    author TEXT NOT NULL,
    email TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    parents TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (id, repo_id),
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE
)";

/// Files table schema
pub const FILES_TABLE: &str = "
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    path TEXT NOT NULL,
    last_commit_id TEXT NOT NULL,
    last_modified INTEGER NOT NULL,
    size INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id, path)
)";

/// README table schema
pub const README_TABLE: &str = "
CREATE TABLE IF NOT EXISTS readmes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    path TEXT NOT NULL,
    content TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id)
)";

/// Repository stats table schema
pub const REPO_STATS_TABLE: &str = "
CREATE TABLE IF NOT EXISTS repo_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    commit_count INTEGER NOT NULL,
    branch_count INTEGER NOT NULL,
    tag_count INTEGER NOT NULL,
    size INTEGER NOT NULL,
    last_activity INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id)
)";

/// Repository maintenance table schema
pub const REPO_MAINTENANCE_TABLE: &str = "
CREATE TABLE IF NOT EXISTS repo_maintenance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    last_maintenance INTEGER,
    last_gc INTEGER,
    last_repack INTEGER,
    last_prune INTEGER,
    last_fsck INTEGER,
    maintenance_due INTEGER,
    maintenance_schedule TEXT,
    needs_maintenance BOOLEAN NOT NULL DEFAULT 0,
    enable_auto_maintenance BOOLEAN NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id)
)";

/// Repository health table schema
pub const REPO_HEALTH_TABLE: &str = "
CREATE TABLE IF NOT EXISTS repo_health (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    git_status TEXT NOT NULL,
    git_message TEXT,
    db_status TEXT NOT NULL,
    db_message TEXT,
    loose_objects INTEGER,
    packfiles INTEGER,
    size_bytes INTEGER,
    last_checked INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id)
)";

/// Repository configuration table schema
pub const REPO_CONFIG_TABLE: &str = "
CREATE TABLE IF NOT EXISTS repo_config (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    owner TEXT,
    enable_maintenance BOOLEAN NOT NULL DEFAULT 1,
    maintenance_schedule TEXT,
    verify_commit_signatures BOOLEAN NOT NULL DEFAULT 0,
    max_object_size INTEGER,
    git_config TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id) ON DELETE CASCADE,
    UNIQUE (repo_id)
)";
