// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Git repository operations

use crate::error::{Error, Result};
use gix::{open as gix_open, Repository as GixRepository};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::collections::HashMap;
use chrono::{DateTime, Utc};
use super::commit::Commit;
use super::file::{FileInfo, FileContent};
use std::process::Command;
use crate::data::git::GitObject;

/// Information about loose objects
#[derive(Debug, Clone)]
pub struct LooseObjectInfo {
    /// Number of loose objects
    pub count: usize,
    /// Total size in bytes
    pub size: u64,
}

/// Information about packfiles
#[derive(Debug, Clone)]
pub struct PackfileInfo {
    /// Number of packfiles
    pub count: usize,
    /// Total size in bytes
    pub size: u64,
}

/// Git repository wrapper
#[derive(Clone)]
pub struct Repository {
    /// Repository name
    name: String,

    /// Repository path
    path: PathBuf,

    /// Gitoxide repository instance
    /// Wrapped in a Mutex to ensure thread safety, as GixRepository is not Send+Sync
    inner: Arc<parking_lot::Mutex<GixRepository>>,
}

/// Repository information
#[derive(Debug, Clone)]
pub struct RepositoryInfo {
    /// Repository name
    pub name: String,

    /// Repository path
    pub path: PathBuf,

    /// Repository description (from description file)
    pub description: Option<String>,

    /// Repository owner (from config)
    pub owner: Option<String>,

    /// Number of commits
    pub commit_count: usize,

    /// Number of branches
    pub branch_count: usize,

    /// Number of tags
    pub tag_count: usize,

    /// Last commit time
    pub last_commit: Option<DateTime<Utc>>,
}

impl Repository {
    /// Open a Git repository
    pub fn open(name: &str, path: &Path) -> Result<Self> {
        let repo = gix_open(path)
            .map_err(Error::Git)?;

        Ok(Self {
            name: name.to_string(),
            path: path.to_path_buf(),
            inner: Arc::new(parking_lot::Mutex::new(repo)),
        })
    }

    /// Get repository information
    pub fn info(&self) -> Result<RepositoryInfo> {
        // Get repository description
        let description = self.description()?;

        // Get repository owner from config
        let owner = self.owner()?;

        // Get commit count (approximate)
        let commit_count = self.commit_count()?;

        // Get branch count
        let branches = self.branches()?;
        let branch_count = branches.len();

        // Get tag count
        let tags = self.tags()?;
        let tag_count = tags.len();

        // Get last commit time
        let last_commit = self.last_commit()?
            .map(|c| c.time());

        Ok(RepositoryInfo {
            name: self.name.clone(),
            path: self.path.clone(),
            description,
            owner,
            commit_count,
            branch_count,
            tag_count,
            last_commit,
        })
    }

    /// Get repository description from description file
    fn description(&self) -> Result<Option<String>> {
        let description_path = self.path.join("description");
        if description_path.exists() {
            let content = std::fs::read_to_string(description_path)
                .map_err(Error::Io)?;

            // Trim and return non-empty description
            let description = content.trim();
            if !description.is_empty() && description != "Unnamed repository; edit this file 'description' to name the repository." {
                return Ok(Some(description.to_string()));
            }
        }

        Ok(None)
    }

    /// Get repository owner from config
    fn owner(&self) -> Result<Option<String>> {
        // Try to get owner from config
        let config = self.inner.lock().config_snapshot();
        let user_name = config.user().name();

        match user_name {
            Ok(Some(name)) => Ok(Some(name.to_string())),
            _ => Ok(None),
        }
    }

    /// Get approximate commit count
    fn commit_count(&self) -> Result<usize> {
        // TODO: Implement proper commit counting
        // For now, just return a placeholder value
        Ok(0)
    }

    /// Get all branches
    pub fn branches(&self) -> Result<HashMap<String, String>> {
        let mut branches = HashMap::new();

        // Get all references
        let inner = self.inner.lock();
        let refs = inner.references()
            .map_err(Error::Git)?;

        // Filter for branches
        for reference in refs.all()
            .map_err(Error::Git)?
        {
            let r = reference
                .map_err(Error::Git)?;

            if let Some(name) = r.name().try_into_branch_name() {
                let branch_name = name.to_string();
                let target = r.target().to_string();

                branches.insert(branch_name, target);
            }
        }

        Ok(branches)
    }

    /// Get all tags
    pub fn tags(&self) -> Result<HashMap<String, String>> {
        let mut tags = HashMap::new();

        // Get all references
        let inner = self.inner.lock();
        let refs = inner.references()
            .map_err(Error::Git)?;

        // Filter for tags
        for reference in refs.all()
            .map_err(Error::Git)?
        {
            let r = reference
                .map_err(Error::Git)?;

            if let Some(name) = r.name().try_into_tag_name() {
                let tag_name = name.to_string();
                let target = r.target().to_string();

                tags.insert(tag_name, target);
            }
        }

        Ok(tags)
    }

    /// Get the last commit
    fn last_commit(&self) -> Result<Option<Commit>> {
        // Try to get HEAD reference
        let inner = self.inner.lock();
        let head = match inner.head() {
            Ok(head) => head,
            Err(_) => return Ok(None),
        };

        // Resolve to a commit
        let oid = head.try_into_id()
            .map_err(Error::Git)?;

        // Get commit
        Commit::from_oid(self, &oid.to_string())
    }

    /// Get a commit by ID
    pub fn commit(&self, id: &str) -> Result<Commit> {
        Commit::from_oid(self, id)
    }

    /// Get a file at a specific revision
    pub fn file(&self, path: &str, revision: &str) -> Result<FileContent> {
        // TODO: Implement file retrieval
        // For now, just return empty content
        Ok(FileContent {
            content: Vec::new(),
            size: 0,
            is_binary: false,
        })
    }

    /// List files at a specific revision
    pub fn list_files(&self, path: &str, revision: &str) -> Result<Vec<FileInfo>> {
        // TODO: Implement file listing
        // For now, just return empty list
        Ok(Vec::new())
    }

    /// Get the gitoxide repository
    pub fn inner(&self) -> parking_lot::MutexGuard<GixRepository> {
        self.inner.lock()
    }

    /// Get the repository name
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Get the repository path
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Generate upload pack advertisement
    pub fn generate_upload_pack_advertisement(&self) -> Result<Vec<u8>> {
        // Implement Git protocol for upload-pack advertisement
        // This is called when a client wants to fetch/clone
        let mut output = Vec::new();

        // Add basic advertisement headers
        output.extend_from_slice(b"001e# service=git-upload-pack\n0000");

        // Add refs
        let inner = self.inner.lock();
        let refs = inner.refs()?;
        for reference in refs {
            let reference = reference?;
            let name = reference.name().to_string();
            let id = reference.id().to_string();

            let line = format!("{} {}\n", id, name);
            let length = line.len() + 4; // 4 for the length prefix
            output.extend_from_slice(format!("{:04x}", length).as_bytes());
            output.extend_from_slice(line.as_bytes());
        }

        // Add terminator
        output.extend_from_slice(b"0000");

        Ok(output)
    }

    /// Process upload pack request (used for fetch/clone)
    pub fn process_upload_pack_request(&self, request_data: &[u8]) -> Result<Vec<u8>> {
        // Simple implementation that returns success
        // In a real implementation, this would parse the request and generate
        // the appropriate packfile according to Git protocol
        let mut response = Vec::new();

        // Add NAK to indicate we processed the request
        response.extend_from_slice(b"0008NAK\n0000");

        Ok(response)
    }

    /// Generate receive pack advertisement
    pub fn generate_receive_pack_advertisement(&self) -> Result<Vec<u8>> {
        // Implement Git protocol for receive-pack advertisement
        // This is called when a client wants to push
        let mut output = Vec::new();

        // Add basic advertisement headers
        output.extend_from_slice(b"001f# service=git-receive-pack\n0000");

        // Add refs
        let inner = self.inner.lock();
        let refs = inner.refs()?;
        for reference in refs {
            let reference = reference?;
            let name = reference.name().to_string();
            let id = reference.id().to_string();

            let capabilities = " report-status side-band-64k";
            let line = format!("{} {}{}\n", id, name, capabilities);
            let length = line.len() + 4; // 4 for the length prefix
            output.extend_from_slice(format!("{:04x}", length).as_bytes());
            output.extend_from_slice(line.as_bytes());
        }

        // Add terminator
        output.extend_from_slice(b"0000");

        Ok(output)
    }

    /// Process receive pack request (used for push)
    pub fn process_receive_pack_request(&self, request_data: &[u8]) -> Result<Vec<u8>> {
        // Simple implementation that returns success
        // In a real implementation, this would parse the request and update refs
        let mut response = Vec::new();

        // Report success
        response.extend_from_slice(b"0019unpack ok\n0019ok refs/heads/main\n0000");

        Ok(response)
    }

    /// Run maintenance on the repository
    pub fn run_maintenance(&self) -> Result<()> {
        // Run basic maintenance tasks on the repository
        self.gc()?;
        self.repack()?;
        self.prune()?;

        Ok(())
    }

    /// Run garbage collection
    pub fn gc(&self) -> Result<()> {
        // Run garbage collection on the repository
        let gc_result = Command::new("git")
            .arg("-C")
            .arg(&self.path)
            .arg("gc")
            .arg("--auto")
            .output()
            .map_err(|e| Error::Io(e))?;

        if !gc_result.status.success() {
            let error_msg = String::from_utf8_lossy(&gc_result.stderr);
            return Err(Error::Git(format!("Git gc failed: {}", error_msg)));
        }

        Ok(())
    }

    /// Run repack to optimize storage
    pub fn repack(&self) -> Result<()> {
        // Run repack to optimize storage
        let repack_result = Command::new("git")
            .arg("-C")
            .arg(&self.path)
            .arg("repack")
            .arg("-d")
            .arg("-l")
            .output()
            .map_err(|e| Error::Io(e))?;

        if !repack_result.status.success() {
            let error_msg = String::from_utf8_lossy(&repack_result.stderr);
            return Err(Error::Git(format!("Git repack failed: {}", error_msg)));
        }

        Ok(())
    }

    /// Prune unreachable objects
    pub fn prune(&self) -> Result<()> {
        // Run prune to remove unreachable objects
        let prune_result = Command::new("git")
            .arg("-C")
            .arg(&self.path)
            .arg("prune")
            .arg("--expire=now")
            .output()
            .map_err(|e| Error::Io(e))?;

        if !prune_result.status.success() {
            let error_msg = String::from_utf8_lossy(&prune_result.stderr);
            return Err(Error::Git(format!("Git prune failed: {}", error_msg)));
        }

        Ok(())
    }

    /// Run filesystem check (fsck)
    pub fn fsck(&self) -> Result<()> {
        // Run fsck to check repository integrity
        let fsck_result = Command::new("git")
            .arg("-C")
            .arg(&self.path)
            .arg("fsck")
            .output()
            .map_err(|e| Error::Io(e))?;

        if !fsck_result.status.success() {
            let error_msg = String::from_utf8_lossy(&fsck_result.stderr);
            return Err(Error::Git(format!("Git fsck failed: {}", error_msg)));
        }

        Ok(())
    }

    /// Count loose objects in the repository
    pub fn count_loose_objects(&self) -> Result<LooseObjectInfo> {
        let mut count = 0;
        let mut size = 0;

        // Check .git/objects directory
        let objects_dir = self.path.join(".git/objects");
        if objects_dir.exists() {
            // Count non-pack objects (excluding 'pack' and 'info' directories)
            for entry in std::fs::read_dir(objects_dir.clone())
                .map_err(|e| Error::Io(e))?
            {
                let entry = entry.map_err(|e| Error::Io(e))?;
                let path = entry.path();

                let name = path.file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or_default();

                if name != "pack" && name != "info" && path.is_dir() {
                    // Count objects in this directory
                    if let Ok(entries) = std::fs::read_dir(path) {
                        for obj_entry in entries {
                            if let Ok(obj_entry) = obj_entry {
                                count += 1;
                                if let Ok(metadata) = obj_entry.metadata() {
                                    size += metadata.len();
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(LooseObjectInfo { count, size })
    }

    /// Count packfiles in the repository
    pub fn count_packfiles(&self) -> Result<PackfileInfo> {
        let mut count = 0;
        let mut size = 0;

        // Check .git/objects/pack directory
        let pack_dir = self.path.join(".git/objects/pack");
        if pack_dir.exists() {
            // Count .pack files
            if let Ok(entries) = std::fs::read_dir(pack_dir) {
                for entry in entries {
                    if let Ok(entry) = entry {
                        let path = entry.path();
                        if path.extension().and_then(|e| e.to_str()) == Some("pack") {
                            count += 1;
                            if let Ok(metadata) = entry.metadata() {
                                size += metadata.len();
                            }
                        }
                    }
                }
            }
        }

        Ok(PackfileInfo { count, size })
    }
}
