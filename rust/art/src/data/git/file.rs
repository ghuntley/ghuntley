//! Git file operations

use crate::error::{Error, Result};
use chrono::{DateTime, Utc};
use std::cmp::Ordering;
use std::path::{Path, PathBuf};
use super::repository::Repository;
use git2;
use gix;

/// File information
#[derive(Debug, Clone)]
pub struct FileInfo {
    /// File path
    pub path: PathBuf,

    /// File name
    pub name: String,

    /// File size in bytes
    pub size: usize,

    /// Whether the file is a directory
    pub is_dir: bool,

    /// Last modified timestamp
    pub last_modified: Option<DateTime<Utc>>,

    /// Last commit ID that modified this file
    pub last_commit_id: Option<String>,
}

/// File content
#[derive(Debug, Clone)]
pub struct FileContent {
    /// File content as bytes
    pub content: Vec<u8>,

    /// File size in bytes
    pub size: usize,

    /// Whether the file is binary
    pub is_binary: bool,
}

impl FileContent {
    /// Get file content as UTF-8 string if it's not binary
    pub fn as_text(&self) -> Option<String> {
        if self.is_binary {
            None
        } else {
            String::from_utf8(self.content.clone()).ok()
        }
    }
}

/// Detect if content is likely binary
pub fn is_binary(content: &[u8]) -> bool {
    if content.len() > 8000 {
        // Large files are often binary
        return true;
    }

    // Check for null bytes or high concentration of non-printable characters
    let mut null_count = 0;
    let mut non_printable_count = 0;

    for &byte in content.iter().take(8000) {
        if byte == 0 {
            null_count += 1;
        } else if !byte.is_ascii_graphic() && !byte.is_ascii_whitespace() {
            non_printable_count += 1;
        }
    }

    // If we have null bytes or more than 30% non-printable characters, consider it binary
    null_count > 0 || (non_printable_count as f32 / content.len() as f32) > 0.3
}

/// Get a file from a Git repository at a specific revision
pub fn get_file(repo: &Repository, path: &str, revision: &str) -> Result<FileContent> {
    // Parse object ID
    let oid = gix::ObjectId::from_hex(revision.as_bytes())
        .map_err(|_| Error::NotFound(format!("Invalid revision: {}", revision)))?;

    // Get the tree at this revision
    let obj = repo.inner().find_object(oid)
        .map_err(|_| Error::NotFound(format!("Revision not found: {}", revision)))?;

    let tree = if let Ok(commit) = obj.clone().into_commit() {
        commit.tree()
            .map_err(Error::Git)?
    } else if let Ok(tree) = obj.into_tree() {
        tree
    } else {
        return Err(Error::NotFound(format!("Revision is not a commit or tree: {}", revision)));
    };

    // Find the file in the tree
    let entry = find_file_in_tree(&tree, path)
        .map_err(|_| Error::NotFound(format!("File not found: {}", path)))?;

    // Get the file content
    let obj = repo.inner().find_object(entry.id())
        .map_err(|_| Error::NotFound(format!("Object not found: {}", entry.id())))?;

    let blob = obj.into_blob()
        .map_err(|_| Error::NotFound(format!("Object is not a blob: {}", entry.id())))?;

    let content = blob.data().to_vec();
    let size = content.len();
    let is_binary = is_binary(&content);

    Ok(FileContent {
        content,
        size,
        is_binary,
    })
}

/// List files in a directory at a specific revision
pub fn list_files(repo: &Repository, path: &str, revision: &str) -> Result<Vec<FileInfo>> {
    // Parse object ID
    let oid = gix::ObjectId::from_hex(revision.as_bytes())
        .map_err(|_| Error::NotFound(format!("Invalid revision: {}", revision)))?;

    // Get the tree at this revision
    let obj = repo.inner().find_object(oid)
        .map_err(|_| Error::NotFound(format!("Revision not found: {}", revision)))?;

    let tree = if let Ok(commit) = obj.clone().into_commit() {
        commit.tree()
            .map_err(Error::Git)?
    } else if let Ok(tree) = obj.into_tree() {
        tree
    } else {
        return Err(Error::NotFound(format!("Revision is not a commit or tree: {}", revision)));
    };

    // Find the directory in the tree
    let target_tree = if path.is_empty() || path == "." {
        tree
    } else {
        let entry = find_file_in_tree(&tree, path)
            .map_err(|_| Error::NotFound(format!("Path not found: {}", path)))?;

        if !entry.mode().is_tree() {
            return Err(Error::NotFound(format!("Path is not a directory: {}", path)));
        }

        let obj = repo.inner().find_object(entry.id())
            .map_err(|_| Error::NotFound(format!("Object not found: {}", entry.id())))?;

        obj.into_tree()
            .map_err(|_| Error::NotFound(format!("Object is not a tree: {}", entry.id())))?
    };

    // List entries in the directory
    let mut files = Vec::new();

    for entry in target_tree.iter() {
        let entry = entry.map_err(Error::Git)?;

        let entry_path = if path.is_empty() || path == "." {
            PathBuf::from(entry.filename().to_string_lossy().to_string())
        } else {
            let mut p = PathBuf::from(path);
            p.push(entry.filename().to_string_lossy().to_string());
            p
        };

        let name = entry.filename().to_string_lossy().to_string();
        let is_dir = entry.mode().is_tree();

        // For regular files, get size
        let size = if !is_dir {
            let obj = repo.inner().find_object(entry.id())
                .map_err(|_| Error::NotFound(format!("Object not found: {}", entry.id())))?;

            let blob = obj.into_blob()
                .map_err(|_| Error::NotFound(format!("Object is not a blob: {}", entry.id())))?;

            blob.data().len()
        } else {
            0
        };

        files.push(FileInfo {
            path: entry_path,
            name,
            size,
            is_dir,
            last_modified: None, // Not available directly, would need commit history
            last_commit_id: None, // Not available directly, would need commit history
        });
    }

    // Sort by type (directories first) and then by name
    files.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.cmp(&b.name),
        }
    });

    Ok(files)
}

/// Find a file in a tree by path
fn find_file_in_tree(tree: &gix::Tree<'_>, path: &str) -> Result<gix::tree::Entry> {
    let mut current_tree = tree.clone();
    let mut parts = Path::new(path).components();

    let result = if let Some(first) = parts.next() {
        let first_str = first.as_os_str().to_string_lossy();
        let mut entry = None;

        // Find the first component in the tree
        for item in current_tree.iter() {
            let item = item.map_err(Error::Git)?;
            if item.filename().to_string_lossy() == first_str {
                entry = Some(item);
                break;
            }
        }

        let entry = entry.ok_or_else(|| Error::NotFound(format!("Path not found: {}", first_str)))?;

        // Process remaining components
        let mut current_entry = entry;
        for component in parts {
            let component_str = component.as_os_str().to_string_lossy();

            // Current entry must be a tree to continue
            if !current_entry.mode().is_tree() {
                return Err(Error::NotFound(format!("Not a directory: {}", component_str)));
            }

            // Get the tree object
            let obj = tree.object().repo().find_object(current_entry.id())
                .map_err(|_| Error::NotFound(format!("Object not found: {}", current_entry.id())))?;

            let sub_tree = obj.into_tree()
                .map_err(|_| Error::NotFound(format!("Object is not a tree: {}", current_entry.id())))?;

            // Find the next component in the tree
            let mut found = false;
            for item in sub_tree.iter() {
                let item = item.map_err(Error::Git)?;
                if item.filename().to_string_lossy() == component_str {
                    current_entry = item;
                    found = true;
                    break;
                }
            }

            if !found {
                return Err(Error::NotFound(format!("Path not found: {}", component_str)));
            }
        }

        Ok(current_entry)
    } else {
        // Empty path, return the tree itself
        Err(Error::NotFound("Empty path".to_string()))
    };

    result
}
