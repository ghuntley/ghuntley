use std::path::Path;

use anyhow::Result;
use git2::{Object, ObjectType, Oid, Repository, Tree};

use crate::error::Error;

/// Represents a Git tree entry with associated metadata
#[derive(Debug, Clone)]
pub struct TreeEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: Option<usize>,
    pub id: String,
}

/// Get a tree from a repository at a specific reference and path
pub fn get_tree<'a>(repo: &'a Repository, reference: &str, path: &str) -> Result<Tree<'a>, Error> {
    // Resolve the reference to a commit
    let commit = repo
        .revparse_single(reference)
        .map_err(|e| Error::Git(format!("Failed to resolve reference '{}': {}", reference, e)))?;

    let commit = commit
        .as_commit()
        .ok_or_else(|| Error::Git(format!("Object '{}' is not a commit", reference)))?;

    // Get the tree from the commit
    let tree = commit.tree().map_err(|e| Error::Git(format!("Failed to get tree: {}", e)))?;

    // If path is empty, return the root tree
    if path.is_empty() || path == "/" {
        return Ok(tree);
    }

    // Get the tree entry at the given path
    let entry = tree
        .get_path(Path::new(path))
        .map_err(|e| Error::Git(format!("Failed to find path '{}': {}", path, e)))?;

    // Ensure the entry is a tree
    if entry.kind() != Some(ObjectType::Tree) {
        return Err(Error::Git(format!("Path '{}' is not a directory", path)));
    }

    // Get the tree object
    let obj = entry
        .to_object(repo)
        .map_err(|e| Error::Git(format!("Failed to get tree object: {}", e)))?;

    let tree = obj
        .as_tree()
        .ok_or_else(|| Error::Git(format!("Object is not a tree")))?;

    Ok(tree)
}

/// List entries in a tree
pub fn list_entries(repo: &Repository, tree: &Tree) -> Result<Vec<TreeEntry>, Error> {
    let mut entries = Vec::new();

    for entry in tree.iter() {
        let name = entry.name().unwrap_or("").to_string();
        let path = entry.name().unwrap_or("").to_string();
        let is_dir = entry.kind() == Some(ObjectType::Tree);

        let size = if !is_dir {
            match entry.to_object(repo) {
                Ok(obj) => Some(obj.size()),
                Err(_) => None,
            }
        } else {
            None
        };

        entries.push(TreeEntry {
            name,
            path,
            is_dir,
            size,
            id: entry.id().to_string(),
        });
    }

    // Sort directories first, then files, both alphabetically
    entries.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    Ok(entries)
}

/// Get a tree entry by path
pub fn get_entry(repo: &Repository, reference: &str, path: &str) -> Result<TreeEntry, Error> {
    let commit = repo
        .revparse_single(reference)
        .map_err(|e| Error::Git(format!("Failed to resolve reference '{}': {}", reference, e)))?;

    let commit = commit
        .as_commit()
        .ok_or_else(|| Error::Git(format!("Object '{}' is not a commit", reference)))?;

    let tree = commit.tree().map_err(|e| Error::Git(format!("Failed to get tree: {}", e)))?;

    if path.is_empty() || path == "/" {
        return Ok(TreeEntry {
            name: "".to_string(),
            path: "".to_string(),
            is_dir: true,
            size: None,
            id: tree.id().to_string(),
        });
    }

    let entry = tree
        .get_path(Path::new(path))
        .map_err(|e| Error::Git(format!("Failed to find path '{}': {}", path, e)))?;

    let is_dir = entry.kind() == Some(ObjectType::Tree);

    let size = if !is_dir {
        match entry.to_object(repo) {
            Ok(obj) => Some(obj.size()),
            Err(_) => None,
        }
    } else {
        None
    };

    let path_obj = Path::new(path);
    let name = path_obj
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string());

    Ok(TreeEntry {
        name,
        path: path.to_string(),
        is_dir,
        size,
        id: entry.id().to_string(),
    })
}
