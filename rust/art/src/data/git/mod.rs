// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Git repository access module using gitoxide

mod repository;
mod commit;
mod file;
mod tree;
mod diff;
mod signature;

use crate::config::RepositoryConfig;
use crate::error::{Error, Result};
use std::path::{Path, PathBuf};
use std::fs;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing;

pub use repository::{Repository, RepositoryInfo};
pub use commit::{Commit, CommitInfo, Author};
pub use file::{FileInfo, FileContent};
pub use tree::{Tree, TreeEntry};
pub use diff::{Diff, DiffInfo, FileDiff, DiffHunk};
pub use signature::{SignatureVerifier, SignatureVerification, SignatureStatus, SignerInfo};

/// Git repository manager
pub struct Git {
    /// Directory containing Git repositories
    repo_dir: PathBuf,

    /// Cache of open repositories
    repos: Arc<Mutex<HashMap<String, Repository>>>,

    /// Maximum cache size in bytes
    max_cache_size: usize,

    /// Signature verifier
    signature_verifier: SignatureVerifier,
}

impl Git {
    /// Create a new Git repository manager
    pub fn new(config: &RepositoryConfig) -> Result<Self> {
        let config = Arc::new(config.clone());

        // Create signature verifier with default settings
        let signature_verifier = SignatureVerifier::new(
            None, // Default GPG homedir
            config.verify_commit_signatures, // Use the config setting
        );

        // Create repository directory if it doesn't exist
        if !config.repo_dir.exists() {
            fs::create_dir_all(&config.repo_dir)
                .map_err(Error::Io)?;
        }

        Ok(Self {
            repo_dir: config.repo_dir.clone(),
            repos: Arc::new(Mutex::new(HashMap::new())),
            max_cache_size: config.max_cache_size,
            signature_verifier,
        })
    }

    /// Get signature verifier
    pub fn signature_verifier(&self) -> &SignatureVerifier {
        &self.signature_verifier
    }

    /// Verify a commit signature
    pub async fn verify_commit_signature(&self, repo_name: &str, commit_id: &str) -> Result<SignatureVerification> {
        // Get repository
        let repo = self.get_repository(repo_name)?;

        // Verify signature
        self.signature_verifier.verify_commit(&repo, commit_id).await
    }

    /// Open a Git repository
    pub fn open<P: AsRef<Path>>(&self, name: &str, path: P) -> Result<Repository> {
        let path = path.as_ref();

        // Check if repository is already open
        {
            let repos = self.repos.lock().unwrap();
            if let Some(repo) = repos.get(name) {
                return Ok(repo.clone());
            }
        }

        // Open the repository
        let repo = Repository::open(name, path)?;

        // Cache the repository
        {
            let mut repos = self.repos.lock().unwrap();
            repos.insert(name.to_string(), repo.clone());

            // TODO: Implement cache size management
        }

        Ok(repo)
    }

    /// List all repositories in the repository directory
    pub fn list_repositories(&self) -> Result<Vec<RepositoryInfo>> {
        let mut repositories = Vec::new();

        // Iterate over directories in the repository directory
        for entry in fs::read_dir(&self.repo_dir).map_err(Error::Io)? {
            let entry = entry.map_err(Error::Io)?;
            let path = entry.path();

            // Check if this is a directory and contains a .git directory or is a bare repository
            if path.is_dir() {
                let git_dir = path.join(".git");
                let is_repo = git_dir.exists() || {
                    // Check if this is a bare repository
                    let head = path.join("HEAD");
                    let config = path.join("config");
                    head.exists() && config.exists()
                };

                if is_repo {
                    // Get repository name from directory name
                    let name = path.file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or_default()
                        .to_string();

                    // Open the repository to get more information
                    match self.open(&name, &path) {
                        Ok(repo) => {
                            let info = repo.info()?;
                            repositories.push(info);
                        }
                        Err(e) => {
                            // Log the error but continue processing other repositories
                            tracing::warn!("Failed to open repository at {:?}: {}", path, e);
                        }
                    }
                }
            }
        }

        Ok(repositories)
    }

    /// Check if a path is a valid Git repository
    pub fn is_git_repository<P: AsRef<Path>>(path: P) -> bool {
        let path = path.as_ref();

        // Check if this is a normal repository with a .git directory
        let git_dir = path.join(".git");
        if git_dir.exists() {
            return true;
        }

        // Check if this is a bare repository
        let head = path.join("HEAD");
        let config = path.join("config");
        head.exists() && config.exists()
    }

    /// Get a repository by name
    pub fn repository(&self, name: &str) -> Result<Repository> {
        // Check if repository is already in cache
        {
            let repos = self.repos.lock().unwrap();
            if let Some(repo) = repos.get(name) {
                return Ok(repo.clone());
            }
        }

        // If not in cache, open the repository
        let repo_path = self.repo_dir.join(name);
        if !repo_path.exists() {
            return Err(Error::RepositoryNotFound(name.to_string()));
        }

        self.open(name, repo_path)
    }

    /// Get a repository - alias for repository()
    pub fn get_repository(&self, name: &str) -> Result<Repository> {
        self.repository(name)
    }

    /// Run garbage collection on a repository
    pub fn gc(&self) -> Result<()> {
        // Run GC on all repositories
        let repos = self.list_repositories()?;

        for repo_info in repos {
            let repo = self.repository(&repo_info.name)?;
            if let Err(e) = repo.gc() {
                tracing::warn!("Failed to run GC on repository {}: {}", repo_info.name, e);
            }
        }

        Ok(())
    }

    /// Run garbage collection on a specific repository
    pub fn gc_repository(&self, name: &str) -> Result<()> {
        let repo = self.repository(name)?;
        repo.gc()
    }

    /// Run repack on a repository
    pub fn repack(&self) -> Result<()> {
        // Run repack on all repositories
        let repos = self.list_repositories()?;

        for repo_info in repos {
            let repo = self.repository(&repo_info.name)?;
            if let Err(e) = repo.repack() {
                tracing::warn!("Failed to run repack on repository {}: {}", repo_info.name, e);
            }
        }

        Ok(())
    }

    /// Run repack on a specific repository
    pub fn repack_repository(&self, name: &str) -> Result<()> {
        let repo = self.repository(name)?;
        repo.repack()
    }

    /// Run prune on a repository
    pub fn prune(&self) -> Result<()> {
        // Run prune on all repositories
        let repos = self.list_repositories()?;

        for repo_info in repos {
            let repo = self.repository(&repo_info.name)?;
            if let Err(e) = repo.prune() {
                tracing::warn!("Failed to run prune on repository {}: {}", repo_info.name, e);
            }
        }

        Ok(())
    }

    /// Run prune on a specific repository
    pub fn prune_repository(&self, name: &str) -> Result<()> {
        let repo = self.repository(name)?;
        repo.prune()
    }

    /// Run fsck on a repository
    pub fn fsck(&self) -> Result<()> {
        // Run fsck on all repositories
        let repos = self.list_repositories()?;

        for repo_info in repos {
            let repo = self.repository(&repo_info.name)?;
            if let Err(e) = repo.fsck() {
                tracing::warn!("Failed to run fsck on repository {}: {}", repo_info.name, e);
            }
        }

        Ok(())
    }

    /// Run fsck on a specific repository
    pub fn fsck_repository(&self, name: &str) -> Result<()> {
        let repo = self.repository(name)?;
        repo.fsck()
    }

    /// Run full maintenance on all repositories
    pub fn run_maintenance(&self) -> Result<()> {
        // Run maintenance on all repositories
        let repos = self.list_repositories()?;

        for repo_info in repos {
            let repo = self.repository(&repo_info.name)?;
            if let Err(e) = repo.run_maintenance() {
                tracing::warn!("Failed to run maintenance on repository {}: {}", repo_info.name, e);
            }
        }

        Ok(())
    }

    /// Run full maintenance on a specific repository
    pub fn run_repository_maintenance(&self, name: &str) -> Result<()> {
        let repo = self.repository(name)?;
        repo.run_maintenance()
    }

    /// Count loose objects in a repository
    pub fn count_loose_objects(&self, repo_name: &str) -> Result<LooseObjectInfo> {
        let repo = self.get_repository(repo_name)?;

        let mut count = 0;
        let mut size = 0;

        // Check .git/objects directory
        let objects_dir = repo.path().join(".git/objects");
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

    /// Count packfiles in a repository
    pub fn count_packfiles(&self, repo_name: &str) -> Result<PackfileInfo> {
        let repo = self.get_repository(repo_name)?;

        let mut count = 0;
        let mut size = 0;

        // Check .git/objects/pack directory
        let pack_dir = repo.path().join(".git/objects/pack");
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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use git2::{Repository as Git2Repository, Signature};
    use std::fs;
    use std::process::Command;

    /// Create a test repository with some commits, branches, and tags
    fn create_test_repo(dir: &TempDir, name: &str) -> Result<(PathBuf, PathBuf)> {
        let repo_dir = dir.path().join(name);
        fs::create_dir_all(&repo_dir)?;

        // Initialize git repository
        let repo = Git2Repository::init(&repo_dir)?;

        // Create some files
        fs::write(repo_dir.join("README.md"), "# Test Repository\nThis is a test repository.")?;
        fs::write(repo_dir.join("file1.txt"), "Test file 1")?;
        fs::write(repo_dir.join("file2.txt"), "Test file 2")?;

        // Create a directory with files
        fs::create_dir_all(repo_dir.join("src"))?;
        fs::write(repo_dir.join("src/main.rs"), "fn main() { println!(\"Hello world\"); }")?;

        // Add files to git
        let mut index = repo.index()?;
        index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
        index.write()?;

        // Create initial commit
        let tree_id = index.write_tree()?;
        let tree = repo.find_tree(tree_id)?;
        let sig = Signature::now("Test User", "test@example.com")?;
        repo.commit(Some("HEAD"), &sig, &sig, "Initial commit", &tree, &[])?;

        // Create a new branch
        let head = repo.head()?.peel_to_commit()?;
        repo.branch("dev", &head, false)?;

        // Create a new file and commit on main
        fs::write(repo_dir.join("file3.txt"), "Test file 3")?;
        let mut index = repo.index()?;
        index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
        index.write()?;
        let tree_id = index.write_tree()?;
        let tree = repo.find_tree(tree_id)?;
        let head = repo.head()?.peel_to_commit()?;
        repo.commit(Some("HEAD"), &sig, &sig, "Add file3", &tree, &[&head])?;

        // Create a tag
        let head = repo.head()?.peel_to_commit()?;
        repo.tag("v1.0", &head.into_object(), &sig, "Version 1.0", false)?;

        // Return repo path and the parent directory
        Ok((repo_dir, dir.path().to_path_buf()))
    }

    #[test]
    fn test_git_open_repository() -> Result<()> {
        let temp_dir = TempDir::new()?;
        let (repo_path, repo_dir) = create_test_repo(&temp_dir, "test-repo")?;

        // Create Git instance
        let config = RepositoryConfig {
            repo_dir: repo_dir.clone(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        };
        let git = Git::new(&config)?;

        // Test opening the repository
        let repo = git.open("test-repo", &repo_path)?;
        assert_eq!(repo.name(), "test-repo");
        assert_eq!(repo.path(), &repo_path);

        Ok(())
    }

    #[test]
    fn test_git_list_repositories() -> Result<()> {
        let temp_dir = TempDir::new()?;

        // Create multiple test repositories
        let (_repo1_path, _) = create_test_repo(&temp_dir, "repo1")?;
        let (_repo2_path, _) = create_test_repo(&temp_dir, "repo2")?;

        // Create a non-git directory to verify it's skipped
        fs::create_dir_all(temp_dir.path().join("not-a-repo"))?;
        fs::write(temp_dir.path().join("not-a-repo/file.txt"), "Not a git repo")?;

        // Create Git instance
        let config = RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        };
        let git = Git::new(&config)?;

        // List repositories
        let repos = git.list_repositories()?;

        // Verify results
        assert_eq!(repos.len(), 2);
        let repo_names: Vec<&str> = repos.iter().map(|r| r.name.as_str()).collect();
        assert!(repo_names.contains(&"repo1"));
        assert!(repo_names.contains(&"repo2"));

        Ok(())
    }

    #[test]
    fn test_repository_info() -> Result<()> {
        let temp_dir = TempDir::new()?;
        let (repo_path, repo_dir) = create_test_repo(&temp_dir, "info-repo")?;

        // Create Git instance
        let config = RepositoryConfig {
            repo_dir: repo_dir.clone(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
        };
        let git = Git::new(&config)?;

        // Open repository
        let repo = git.open("info-repo", &repo_path)?;

        // Get repository info
        let info = repo.info()?;

        // Verify info
        assert_eq!(info.name, "info-repo");
        assert_eq!(info.path, repo_path);
        assert_eq!(info.branch_count, 2); // main and dev
        assert_eq!(info.tag_count, 1);    // v1.0
        assert!(info.commit_count >= 2);  // Initial commit + Add file3
        assert!(info.last_commit.is_some());

        Ok(())
    }

    #[test]
    fn test_is_git_repository() -> Result<()> {
        let temp_dir = TempDir::new()?;
        let (repo_path, _) = create_test_repo(&temp_dir, "valid-repo")?;

        // Create a non-git directory
        let non_git_dir = temp_dir.path().join("not-a-repo");
        fs::create_dir_all(&non_git_dir)?;
        fs::write(non_git_dir.join("file.txt"), "Not a git repo")?;

        // Test valid git repository
        assert!(Git::is_git_repository(&repo_path));

        // Test non-git directory
        assert!(!Git::is_git_repository(&non_git_dir));

        // Test non-existent path
        assert!(!Git::is_git_repository(temp_dir.path().join("does-not-exist")));

        Ok(())
    }
}
