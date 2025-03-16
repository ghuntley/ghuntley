//! Git commit operations

use crate::error::{Error, Result};
use chrono::{DateTime, Utc, TimeZone};
use super::repository::Repository;

/// Git commit wrapper
#[derive(Clone)]
pub struct Commit {
    /// Commit ID (SHA-1 hash)
    id: String,

    /// Commit information
    info: CommitInfo,
}

/// Commit information
#[derive(Debug, Clone)]
pub struct CommitInfo {
    /// Commit ID (SHA-1 hash)
    pub id: String,

    /// Commit author
    pub author: Author,

    /// Commit message
    pub message: String,

    /// Commit timestamp
    pub time: DateTime<Utc>,

    /// Parent commit IDs
    pub parents: Vec<String>,
}

/// Author information
#[derive(Debug, Clone)]
pub struct Author {
    /// Author name
    pub name: String,

    /// Author email
    pub email: String,
}

impl Commit {
    /// Create a commit from an object ID
    pub fn from_oid(repo: &Repository, id: &str) -> Result<Option<Self>> {
        // Parse the object ID
        let oid = gix::ObjectId::from_hex(id.as_bytes())
            .map_err(|_| Error::NotFound(format!("Invalid commit ID: {}", id)))?;

        // Get the commit object
        let obj = match repo.inner().find_object(oid) {
            Ok(obj) => obj,
            Err(_) => return Ok(None),
        };

        // Ensure it's a commit
        let commit = obj.into_commit()
            .map_err(|_| Error::NotFound(format!("Object is not a commit: {}", id)))?;

        // Get author information
        let author = commit.author();
        let author_info = Author {
            name: author.name.to_string(),
            email: author.email.to_string(),
        };

        // Get commit time
        let time_secs = author.time.seconds;
        let time = Utc.timestamp_opt(time_secs, 0).single()
            .ok_or_else(|| Error::Internal(format!("Invalid timestamp: {}", time_secs)))?;

        // Get commit message
        let message = commit.message().ok()
            .and_then(|m| m.title())
            .map(|s| s.to_string())
            .unwrap_or_default();

        // Get parent commit IDs
        let parents = commit.parents()
            .map(|oid| oid.to_string())
            .collect();

        // Create commit information
        let info = CommitInfo {
            id: id.to_string(),
            author: author_info,
            message,
            time,
            parents,
        };

        Ok(Some(Self {
            id: id.to_string(),
            info,
        }))
    }

    /// Get commit ID
    pub fn id(&self) -> &str {
        &self.id
    }

    /// Get commit information
    pub fn info(&self) -> &CommitInfo {
        &self.info
    }

    /// Get commit time
    pub fn time(&self) -> DateTime<Utc> {
        self.info.time
    }

    /// Get commit message
    pub fn message(&self) -> &str {
        &self.info.message
    }

    /// Get commit author
    pub fn author(&self) -> &Author {
        &self.info.author
    }

    /// Get parent commit IDs
    pub fn parents(&self) -> &[String] {
        &self.info.parents
    }
}
