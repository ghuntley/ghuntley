//! Database models and query methods

use crate::data::sqlite::{Repository, Branch, Tag, Commit};
use crate::error::Result;
use rusqlite::{params, Connection, Row};
use chrono::Utc;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;

/// Convert a Row to a Repository
fn row_to_repository(row: &Row) -> rusqlite::Result<Repository> {
    Ok(Repository {
        id: row.get(0)?,
        name: row.get(1)?,
        path: row.get(2)?,
        description: row.get(3)?,
        owner: row.get(4)?,
        last_updated: row.get(5)?,
    })
}

/// Convert a Row to a Branch
fn row_to_branch(row: &Row) -> rusqlite::Result<Branch> {
    Ok(Branch {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        name: row.get(2)?,
        commit_id: row.get(3)?,
    })
}

/// Convert a Row to a Tag
fn row_to_tag(row: &Row) -> rusqlite::Result<Tag> {
    Ok(Tag {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        name: row.get(2)?,
        commit_id: row.get(3)?,
    })
}

/// Convert a Row to a Commit
fn row_to_commit(row: &Row) -> rusqlite::Result<Commit> {
    let parent_ids_str: String = row.get(6)?;
    let parent_ids = parent_ids_str
        .split(',')
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect();

    Ok(Commit {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        author: row.get(2)?,
        email: row.get(3)?,
        message: row.get(4)?,
        timestamp: row.get(5)?,
        parent_ids,
    })
}

/// Repository maintenance information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryMaintenance {
    /// Maintenance record ID
    pub id: i64,
    /// Repository ID
    pub repo_id: i64,
    /// Last maintenance time
    pub last_maintenance: Option<i64>,
    /// Last garbage collection time
    pub last_gc: Option<i64>,
    /// Last repack time
    pub last_repack: Option<i64>,
    /// Last prune time
    pub last_prune: Option<i64>,
    /// Last fsck time
    pub last_fsck: Option<i64>,
    /// Next scheduled maintenance time
    pub maintenance_due: Option<i64>,
    /// Maintenance schedule (cron expression)
    pub maintenance_schedule: Option<String>,
    /// Whether maintenance is needed
    pub needs_maintenance: bool,
    /// Whether automatic maintenance is enabled
    pub enable_auto_maintenance: bool,
}

/// Convert a Row to a RepositoryMaintenance
fn row_to_maintenance(row: &Row) -> rusqlite::Result<RepositoryMaintenance> {
    Ok(RepositoryMaintenance {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        last_maintenance: row.get(2)?,
        last_gc: row.get(3)?,
        last_repack: row.get(4)?,
        last_prune: row.get(5)?,
        last_fsck: row.get(6)?,
        maintenance_due: row.get(7)?,
        maintenance_schedule: row.get(8)?,
        needs_maintenance: row.get(9)?,
        enable_auto_maintenance: row.get(10)?,
    })
}

/// Repository health information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryHealth {
    /// Health record ID
    pub id: i64,
    /// Repository ID
    pub repo_id: i64,
    /// Overall status
    pub status: String,
    /// Git status
    pub git_status: String,
    /// Git status message
    pub git_message: Option<String>,
    /// Database status
    pub db_status: String,
    /// Database status message
    pub db_message: Option<String>,
    /// Number of loose objects
    pub loose_objects: Option<i64>,
    /// Number of packfiles
    pub packfiles: Option<i64>,
    /// Repository size in bytes
    pub size_bytes: Option<i64>,
    /// Last health check time
    pub last_checked: i64,
}

/// Convert a Row to a RepositoryHealth
fn row_to_health(row: &Row) -> rusqlite::Result<RepositoryHealth> {
    Ok(RepositoryHealth {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        status: row.get(2)?,
        git_status: row.get(3)?,
        git_message: row.get(4)?,
        db_status: row.get(5)?,
        db_message: row.get(6)?,
        loose_objects: row.get(7)?,
        packfiles: row.get(8)?,
        size_bytes: row.get(9)?,
        last_checked: row.get(10)?,
    })
}

/// Repository configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryConfig {
    /// Configuration record ID
    pub id: i64,
    /// Repository ID
    pub repo_id: i64,
    /// Repository name
    pub name: String,
    /// Repository description
    pub description: Option<String>,
    /// Repository owner
    pub owner: Option<String>,
    /// Whether to enable maintenance
    pub enable_maintenance: bool,
    /// Maintenance schedule (cron expression)
    pub maintenance_schedule: Option<String>,
    /// Whether to verify commit signatures
    pub verify_commit_signatures: bool,
    /// Maximum object size (bytes)
    pub max_object_size: Option<i64>,
    /// Git configuration as JSON string
    pub git_config: Option<String>,
}

/// Convert a Row to a RepositoryConfig
fn row_to_config(row: &Row) -> rusqlite::Result<RepositoryConfig> {
    Ok(RepositoryConfig {
        id: row.get(0)?,
        repo_id: row.get(1)?,
        name: row.get(2)?,
        description: row.get(3)?,
        owner: row.get(4)?,
        enable_maintenance: row.get(5)?,
        maintenance_schedule: row.get(6)?,
        verify_commit_signatures: row.get(7)?,
        max_object_size: row.get(8)?,
        git_config: row.get(9)?,
    })
}

/// Repository query methods
pub struct RepositoryModel<'a> {
    conn: &'a Connection,
}

impl<'a> RepositoryModel<'a> {
    /// Create a new RepositoryModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert a new repository
    pub fn insert(
        &self,
        name: &str,
        path: &str,
        description: Option<&str>,
        owner: Option<&str>,
    ) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO repositories (name, path, description, owner, last_updated, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        ")?;

        stmt.execute(params![name, path, description, owner, now, now])?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Get all repositories
    pub fn get_all(&self) -> Result<Vec<Repository>> {
        let mut stmt = self.conn.prepare("
            SELECT id, name, path, description, owner, last_updated
            FROM repositories
            ORDER BY name
        ")?;

        let rows = stmt.query_map([], row_to_repository)?;
        let mut repositories = Vec::new();

        for repo in rows {
            repositories.push(repo?);
        }

        Ok(repositories)
    }

    /// Get a repository by ID
    pub fn get_by_id(&self, id: i64) -> Result<Option<Repository>> {
        let mut stmt = self.conn.prepare("
            SELECT id, name, path, description, owner, last_updated
            FROM repositories
            WHERE id = ?
        ")?;

        let rows = stmt.query_map([id], row_to_repository)?;
        let mut repositories = Vec::new();

        for repo in rows {
            repositories.push(repo?);
        }

        Ok(repositories.into_iter().next())
    }

    /// Get a repository by name
    pub fn get_by_name(&self, name: &str) -> Result<Option<Repository>> {
        let mut stmt = self.conn.prepare("
            SELECT id, name, path, description, owner, last_updated
            FROM repositories
            WHERE name = ?
        ")?;

        let rows = stmt.query_map([name], row_to_repository)?;
        let mut repositories = Vec::new();

        for repo in rows {
            repositories.push(repo?);
        }

        Ok(repositories.into_iter().next())
    }

    /// Update a repository's last updated timestamp
    pub fn update_last_updated(&self, id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repositories
            SET last_updated = ?
            WHERE id = ?
        ")?;

        stmt.execute(params![now, id])?;
        Ok(())
    }

    /// Delete a repository
    pub fn delete(&self, id: i64) -> Result<()> {
        let mut stmt = self.conn.prepare("
            DELETE FROM repositories
            WHERE id = ?
        ")?;

        stmt.execute([id])?;
        Ok(())
    }
}

/// Branch query methods
pub struct BranchModel<'a> {
    conn: &'a Connection,
}

impl<'a> BranchModel<'a> {
    /// Create a new BranchModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert a new branch
    pub fn insert(&self, repo_id: i64, name: &str, commit_id: &str) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO branches (repo_id, name, commit_id, created_at)
            VALUES (?, ?, ?, ?)
        ")?;

        stmt.execute(params![repo_id, name, commit_id, now])?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Get all branches for a repository
    pub fn get_all_for_repo(&self, repo_id: i64) -> Result<Vec<Branch>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, name, commit_id
            FROM branches
            WHERE repo_id = ?
            ORDER BY name
        ")?;

        let rows = stmt.query_map([repo_id], row_to_branch)?;
        let mut branches = Vec::new();

        for branch in rows {
            branches.push(branch?);
        }

        Ok(branches)
    }

    /// Get a branch by name for a repository
    pub fn get_by_name(&self, repo_id: i64, name: &str) -> Result<Option<Branch>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, name, commit_id
            FROM branches
            WHERE repo_id = ? AND name = ?
        ")?;

        let rows = stmt.query_map(params![repo_id, name], row_to_branch)?;
        let mut branches = Vec::new();

        for branch in rows {
            branches.push(branch?);
        }

        Ok(branches.into_iter().next())
    }

    /// Update a branch's commit ID
    pub fn update_commit_id(&self, repo_id: i64, name: &str, commit_id: &str) -> Result<()> {
        let mut stmt = self.conn.prepare("
            UPDATE branches
            SET commit_id = ?
            WHERE repo_id = ? AND name = ?
        ")?;

        stmt.execute(params![commit_id, repo_id, name])?;
        Ok(())
    }

    /// Delete all branches for a repository
    pub fn delete_all_for_repo(&self, repo_id: i64) -> Result<()> {
        let mut stmt = self.conn.prepare("
            DELETE FROM branches
            WHERE repo_id = ?
        ")?;

        stmt.execute([repo_id])?;
        Ok(())
    }
}

/// Tag query methods
pub struct TagModel<'a> {
    conn: &'a Connection,
}

impl<'a> TagModel<'a> {
    /// Create a new TagModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert a new tag
    pub fn insert(&self, repo_id: i64, name: &str, commit_id: &str) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO tags (repo_id, name, commit_id, created_at)
            VALUES (?, ?, ?, ?)
        ")?;

        stmt.execute(params![repo_id, name, commit_id, now])?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Get all tags for a repository
    pub fn get_all_for_repo(&self, repo_id: i64) -> Result<Vec<Tag>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, name, commit_id
            FROM tags
            WHERE repo_id = ?
            ORDER BY name
        ")?;

        let rows = stmt.query_map([repo_id], row_to_tag)?;
        let mut tags = Vec::new();

        for tag in rows {
            tags.push(tag?);
        }

        Ok(tags)
    }

    /// Get a tag by name for a repository
    pub fn get_by_name(&self, repo_id: i64, name: &str) -> Result<Option<Tag>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, name, commit_id
            FROM tags
            WHERE repo_id = ? AND name = ?
        ")?;

        let rows = stmt.query_map(params![repo_id, name], row_to_tag)?;
        let mut tags = Vec::new();

        for tag in rows {
            tags.push(tag?);
        }

        Ok(tags.into_iter().next())
    }

    /// Delete all tags for a repository
    pub fn delete_all_for_repo(&self, repo_id: i64) -> Result<()> {
        let mut stmt = self.conn.prepare("
            DELETE FROM tags
            WHERE repo_id = ?
        ")?;

        stmt.execute([repo_id])?;
        Ok(())
    }
}

/// Commit query methods
pub struct CommitModel<'a> {
    conn: &'a Connection,
}

impl<'a> CommitModel<'a> {
    /// Create a new CommitModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert a new commit
    pub fn insert(
        &self,
        id: &str,
        repo_id: i64,
        author: &str,
        email: &str,
        message: &str,
        timestamp: i64,
        parent_ids: &[String],
    ) -> Result<()> {
        let now = Utc::now().timestamp();
        let parents = parent_ids.join(",");

        let mut stmt = self.conn.prepare("
            INSERT OR REPLACE INTO commits (id, repo_id, author, email, message, timestamp, parents, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ")?;

        stmt.execute(params![id, repo_id, author, email, message, timestamp, parents, now])?;
        Ok(())
    }

    /// Get a commit by ID
    pub fn get_by_id(&self, repo_id: i64, id: &str) -> Result<Option<Commit>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, author, email, message, timestamp, parents
            FROM commits
            WHERE repo_id = ? AND id = ?
        ")?;

        let rows = stmt.query_map(params![repo_id, id], row_to_commit)?;
        let mut commits = Vec::new();

        for commit in rows {
            commits.push(commit?);
        }

        Ok(commits.into_iter().next())
    }

    /// Get recent commits for a repository
    pub fn get_recent(&self, repo_id: i64, limit: usize) -> Result<Vec<Commit>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, author, email, message, timestamp, parents
            FROM commits
            WHERE repo_id = ?
            ORDER BY timestamp DESC
            LIMIT ?
        ")?;

        let rows = stmt.query_map(params![repo_id, limit as i64], row_to_commit)?;
        let mut commits = Vec::new();

        for commit in rows {
            commits.push(commit?);
        }

        Ok(commits)
    }

    /// Delete all commits for a repository
    pub fn delete_all_for_repo(&self, repo_id: i64) -> Result<()> {
        let mut stmt = self.conn.prepare("
            DELETE FROM commits
            WHERE repo_id = ?
        ")?;

        stmt.execute([repo_id])?;
        Ok(())
    }
}

/// Repository maintenance query methods
pub struct MaintenanceModel<'a> {
    conn: &'a Connection,
}

impl<'a> MaintenanceModel<'a> {
    /// Create a new MaintenanceModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Initialize maintenance record for a repository
    pub fn initialize(&self, repo_id: i64) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO repo_maintenance (
                repo_id, last_maintenance, last_gc, last_repack, last_prune, last_fsck,
                maintenance_due, maintenance_schedule, needs_maintenance, enable_auto_maintenance,
                created_at, updated_at
            )
            VALUES (?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 1, ?, ?)
            ON CONFLICT(repo_id) DO NOTHING
        ")?;

        stmt.execute(params![repo_id, now, now])?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Get maintenance record for a repository
    pub fn get_by_repo_id(&self, repo_id: i64) -> Result<Option<RepositoryMaintenance>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, last_maintenance, last_gc, last_repack, last_prune, last_fsck,
                   maintenance_due, maintenance_schedule, needs_maintenance, enable_auto_maintenance
            FROM repo_maintenance
            WHERE repo_id = ?
        ")?;

        let rows = stmt.query_map([repo_id], row_to_maintenance)?;
        let mut maintenance_records = Vec::new();

        for record in rows {
            maintenance_records.push(record?);
        }

        Ok(maintenance_records.into_iter().next())
    }

    /// Get maintenance record for a repository by name
    pub fn get_by_repo_name(&self, repo_name: &str) -> Result<Option<RepositoryMaintenance>> {
        let mut stmt = self.conn.prepare("
            SELECT m.id, m.repo_id, m.last_maintenance, m.last_gc, m.last_repack, m.last_prune, m.last_fsck,
                   m.maintenance_due, m.maintenance_schedule, m.needs_maintenance, m.enable_auto_maintenance
            FROM repo_maintenance m
            JOIN repositories r ON m.repo_id = r.id
            WHERE r.name = ?
        ")?;

        let rows = stmt.query_map([repo_name], row_to_maintenance)?;
        let mut maintenance_records = Vec::new();

        for record in rows {
            maintenance_records.push(record?);
        }

        Ok(maintenance_records.into_iter().next())
    }

    /// Update last maintenance time
    pub fn update_last_maintenance(&self, repo_id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET last_maintenance = ?,
                needs_maintenance = 0,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![now, now, repo_id])?;
        Ok(())
    }

    /// Update last garbage collection time
    pub fn update_last_gc(&self, repo_id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET last_gc = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![now, now, repo_id])?;
        Ok(())
    }

    /// Update last repack time
    pub fn update_last_repack(&self, repo_id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET last_repack = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![now, now, repo_id])?;
        Ok(())
    }

    /// Update last prune time
    pub fn update_last_prune(&self, repo_id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET last_prune = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![now, now, repo_id])?;
        Ok(())
    }

    /// Update last fsck time
    pub fn update_last_fsck(&self, repo_id: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET last_fsck = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![now, now, repo_id])?;
        Ok(())
    }

    /// Set maintenance due time
    pub fn set_maintenance_due(&self, repo_id: i64, due_time: i64) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET maintenance_due = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![due_time, now, repo_id])?;
        Ok(())
    }

    /// Set maintenance schedule
    pub fn set_maintenance_schedule(&self, repo_id: i64, schedule: &str) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET maintenance_schedule = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![schedule, now, repo_id])?;
        Ok(())
    }

    /// Mark repository as needing maintenance
    pub fn set_needs_maintenance(&self, repo_id: i64, needs_maintenance: bool) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET needs_maintenance = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![needs_maintenance, now, repo_id])?;
        Ok(())
    }

    /// Enable or disable automatic maintenance
    pub fn set_enable_auto_maintenance(&self, repo_id: i64, enable: bool) -> Result<()> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            UPDATE repo_maintenance
            SET enable_auto_maintenance = ?,
                updated_at = ?
            WHERE repo_id = ?
        ")?;

        stmt.execute(params![enable, now, repo_id])?;
        Ok(())
    }

    /// Get repositories that need maintenance
    pub fn get_repos_needing_maintenance(&self) -> Result<Vec<i64>> {
        let mut stmt = self.conn.prepare("
            SELECT repo_id
            FROM repo_maintenance
            WHERE needs_maintenance = 1 AND enable_auto_maintenance = 1
        ")?;

        let rows = stmt.query_map([], |row| row.get(0))?;
        let mut repo_ids = Vec::new();

        for id in rows {
            repo_ids.push(id?);
        }

        Ok(repo_ids)
    }

    /// Get repositories due for maintenance
    pub fn get_repos_due_for_maintenance(&self) -> Result<Vec<i64>> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            SELECT repo_id
            FROM repo_maintenance
            WHERE maintenance_due <= ? AND enable_auto_maintenance = 1
        ")?;

        let rows = stmt.query_map([now], |row| row.get(0))?;
        let mut repo_ids = Vec::new();

        for id in rows {
            repo_ids.push(id?);
        }

        Ok(repo_ids)
    }
}

/// Repository health query methods
pub struct HealthModel<'a> {
    conn: &'a Connection,
}

impl<'a> HealthModel<'a> {
    /// Create a new HealthModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert or update health record
    pub fn upsert(&self, health: &RepositoryHealth) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO repo_health (
                repo_id, status, git_status, git_message, db_status, db_message,
                loose_objects, packfiles, size_bytes, last_checked,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(repo_id) DO UPDATE SET
                status = excluded.status,
                git_status = excluded.git_status,
                git_message = excluded.git_message,
                db_status = excluded.db_status,
                db_message = excluded.db_message,
                loose_objects = excluded.loose_objects,
                packfiles = excluded.packfiles,
                size_bytes = excluded.size_bytes,
                last_checked = excluded.last_checked,
                updated_at = excluded.updated_at
        ")?;

        stmt.execute(params![
            health.repo_id, health.status, health.git_status, health.git_message,
            health.db_status, health.db_message, health.loose_objects, health.packfiles,
            health.size_bytes, health.last_checked, now, now
        ])?;

        Ok(self.conn.last_insert_rowid())
    }

    /// Get health record by repository ID
    pub fn get_by_repo_id(&self, repo_id: i64) -> Result<Option<RepositoryHealth>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, status, git_status, git_message, db_status, db_message,
                   loose_objects, packfiles, size_bytes, last_checked
            FROM repo_health
            WHERE repo_id = ?
        ")?;

        let rows = stmt.query_map([repo_id], row_to_health)?;
        let mut health_records = Vec::new();

        for record in rows {
            health_records.push(record?);
        }

        Ok(health_records.into_iter().next())
    }

    /// Get health record by repository name
    pub fn get_by_repo_name(&self, repo_name: &str) -> Result<Option<RepositoryHealth>> {
        let mut stmt = self.conn.prepare("
            SELECT h.id, h.repo_id, h.status, h.git_status, h.git_message, h.db_status, h.db_message,
                   h.loose_objects, h.packfiles, h.size_bytes, h.last_checked
            FROM repo_health h
            JOIN repositories r ON h.repo_id = r.id
            WHERE r.name = ?
        ")?;

        let rows = stmt.query_map([repo_name], row_to_health)?;
        let mut health_records = Vec::new();

        for record in rows {
            health_records.push(record?);
        }

        Ok(health_records.into_iter().next())
    }

    /// Get all repositories with specified health status
    pub fn get_by_status(&self, status: &str) -> Result<Vec<RepositoryHealth>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, status, git_status, git_message, db_status, db_message,
                   loose_objects, packfiles, size_bytes, last_checked
            FROM repo_health
            WHERE status = ?
        ")?;

        let rows = stmt.query_map([status], row_to_health)?;
        let mut health_records = Vec::new();

        for record in rows {
            health_records.push(record?);
        }

        Ok(health_records)
    }
}

/// Repository configuration query methods
pub struct ConfigModel<'a> {
    conn: &'a Connection,
}

impl<'a> ConfigModel<'a> {
    /// Create a new ConfigModel
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    /// Insert or update repository configuration
    pub fn upsert(&self, config: &RepositoryConfig) -> Result<i64> {
        let now = Utc::now().timestamp();
        let mut stmt = self.conn.prepare("
            INSERT INTO repo_config (
                repo_id, name, description, owner, enable_maintenance, maintenance_schedule,
                verify_commit_signatures, max_object_size, git_config,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(repo_id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                owner = excluded.owner,
                enable_maintenance = excluded.enable_maintenance,
                maintenance_schedule = excluded.maintenance_schedule,
                verify_commit_signatures = excluded.verify_commit_signatures,
                max_object_size = excluded.max_object_size,
                git_config = excluded.git_config,
                updated_at = excluded.updated_at
        ")?;

        stmt.execute(params![
            config.repo_id, config.name, config.description, config.owner,
            config.enable_maintenance, config.maintenance_schedule,
            config.verify_commit_signatures, config.max_object_size,
            config.git_config, now, now
        ])?;

        Ok(self.conn.last_insert_rowid())
    }

    /// Get configuration by repository ID
    pub fn get_by_repo_id(&self, repo_id: i64) -> Result<Option<RepositoryConfig>> {
        let mut stmt = self.conn.prepare("
            SELECT id, repo_id, name, description, owner, enable_maintenance, maintenance_schedule,
                   verify_commit_signatures, max_object_size, git_config
            FROM repo_config
            WHERE repo_id = ?
        ")?;

        let rows = stmt.query_map([repo_id], row_to_config)?;
        let mut config_records = Vec::new();

        for record in rows {
            config_records.push(record?);
        }

        Ok(config_records.into_iter().next())
    }

    /// Get configuration by repository name
    pub fn get_by_repo_name(&self, repo_name: &str) -> Result<Option<RepositoryConfig>> {
        let mut stmt = self.conn.prepare("
            SELECT c.id, c.repo_id, c.name, c.description, c.owner, c.enable_maintenance, c.maintenance_schedule,
                   c.verify_commit_signatures, c.max_object_size, c.git_config
            FROM repo_config c
            JOIN repositories r ON c.repo_id = r.id
            WHERE r.name = ?
        ")?;

        let rows = stmt.query_map([repo_name], row_to_config)?;
        let mut config_records = Vec::new();

        for record in rows {
            config_records.push(record?);
        }

        Ok(config_records.into_iter().next())
    }

    /// Parse the Git configuration from JSON
    pub fn parse_git_config(&self, config_json: &str) -> Result<HashMap<String, String>> {
        serde_json::from_str(config_json)
            .map_err(|e| rusqlite::Error::InvalidParameterName(e.to_string()).into())
    }

    /// Serialize Git configuration to JSON
    pub fn serialize_git_config(&self, config: &HashMap<String, String>) -> Result<String> {
        serde_json::to_string(config)
            .map_err(|e| rusqlite::Error::InvalidParameterName(e.to_string()).into())
    }
}
