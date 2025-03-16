use std::path::Path;

use anyhow::Result;
use git2::{Diff, DiffOptions, Object, ObjectType, Repository};

use crate::error::Error;

/// Represents a file difference in a Git diff
#[derive(Debug, Clone)]
pub struct FileDiff {
    pub old_path: String,
    pub new_path: String,
    pub status: DiffStatus,
    pub additions: usize,
    pub deletions: usize,
    pub binary: bool,
    pub diff_content: Vec<DiffHunk>,
}

/// Represents a hunk of changes in a diff
#[derive(Debug, Clone)]
pub struct DiffHunk {
    pub header: String,
    pub old_start: usize,
    pub old_lines: usize,
    pub new_start: usize,
    pub new_lines: usize,
    pub lines: Vec<DiffLine>,
}

/// Represents a line in a diff hunk
#[derive(Debug, Clone)]
pub struct DiffLine {
    pub origin: char,  // '+', '-', ' ', etc.
    pub content: String,
    pub line_number_old: Option<usize>,
    pub line_number_new: Option<usize>,
}

/// Represents the status of a file in a diff
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffStatus {
    Added,
    Deleted,
    Modified,
    Renamed,
    Copied,
    Unmodified,
    Untracked,
    Ignored,
    Conflicted,
}

impl From<git2::Delta> for DiffStatus {
    fn from(delta: git2::Delta) -> Self {
        match delta {
            git2::Delta::Added => DiffStatus::Added,
            git2::Delta::Deleted => DiffStatus::Deleted,
            git2::Delta::Modified => DiffStatus::Modified,
            git2::Delta::Renamed => DiffStatus::Renamed,
            git2::Delta::Copied => DiffStatus::Copied,
            git2::Delta::Unmodified => DiffStatus::Unmodified,
            git2::Delta::Untracked => DiffStatus::Untracked,
            git2::Delta::Ignored => DiffStatus::Ignored,
            git2::Delta::Conflicted => DiffStatus::Conflicted,
            _ => DiffStatus::Modified, // Default case
        }
    }
}

/// Generate a diff between two commits
pub fn diff_commits(repo: &Repository, old_commit: &str, new_commit: &str) -> Result<Vec<FileDiff>, Error> {
    let old_obj = repo
        .revparse_single(old_commit)
        .map_err(|e| Error::Git(format!("Failed to resolve commit '{}': {}", old_commit, e)))?;

    let new_obj = repo
        .revparse_single(new_commit)
        .map_err(|e| Error::Git(format!("Failed to resolve commit '{}': {}", new_commit, e)))?;

    let old_tree = old_obj
        .as_commit()
        .and_then(|c| c.tree().ok())
        .ok_or_else(|| Error::Git(format!("Failed to get tree for commit '{}'", old_commit)))?;

    let new_tree = new_obj
        .as_commit()
        .and_then(|c| c.tree().ok())
        .ok_or_else(|| Error::Git(format!("Failed to get tree for commit '{}'", new_commit)))?;

    let diff = repo
        .diff_tree_to_tree(Some(&old_tree), Some(&new_tree), None)
        .map_err(|e| Error::Git(format!("Failed to generate diff: {}", e)))?;

    process_diff(diff)
}

/// Generate a diff for a specific file between two commits
pub fn diff_file(
    repo: &Repository,
    old_commit: &str,
    new_commit: &str,
    path: &str,
) -> Result<FileDiff, Error> {
    let old_obj = repo
        .revparse_single(old_commit)
        .map_err(|e| Error::Git(format!("Failed to resolve commit '{}': {}", old_commit, e)))?;

    let new_obj = repo
        .revparse_single(new_commit)
        .map_err(|e| Error::Git(format!("Failed to resolve commit '{}': {}", new_commit, e)))?;

    let old_tree = old_obj
        .as_commit()
        .and_then(|c| c.tree().ok())
        .ok_or_else(|| Error::Git(format!("Failed to get tree for commit '{}'", old_commit)))?;

    let new_tree = new_obj
        .as_commit()
        .and_then(|c| c.tree().ok())
        .ok_or_else(|| Error::Git(format!("Failed to get tree for commit '{}'", new_commit)))?;

    let mut opts = DiffOptions::new();
    opts.pathspec(path);

    let diff = repo
        .diff_tree_to_tree(Some(&old_tree), Some(&new_tree), Some(&mut opts))
        .map_err(|e| Error::Git(format!("Failed to generate diff: {}", e)))?;

    let diffs = process_diff(diff)?;

    diffs
        .into_iter()
        .find(|d| d.new_path == path || d.old_path == path)
        .ok_or_else(|| Error::Git(format!("File '{}' not found in diff", path)))
}

/// Process a git2::Diff into our FileDiff format
fn process_diff(diff: Diff) -> Result<Vec<FileDiff>, Error> {
    let mut file_diffs = Vec::new();

    // For each file change in the diff
    for delta in (0..diff.deltas().len()).filter_map(|i| diff.get_delta(i)) {
        let mut file_diff = FileDiff {
            old_path: delta
                .old_file()
                .path()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default(),
            new_path: delta
                .new_file()
                .path()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default(),
            status: delta.status().into(),
            additions: 0,
            deletions: 0,
            binary: delta.new_file().is_binary() || delta.old_file().is_binary(),
            diff_content: Vec::new(),
        };

        // If it's binary, don't try to get line changes
        if file_diff.binary {
            file_diffs.push(file_diff);
            continue;
        }

        // Process each hunk in the file change
        diff.print(
            |delta, _hunk_idx, hunk| {
                let mut diff_hunk = DiffHunk {
                    header: hunk.header().to_owned(),
                    old_start: hunk.old_start(),
                    old_lines: hunk.old_lines(),
                    new_start: hunk.new_start(),
                    new_lines: hunk.new_lines(),
                    lines: Vec::new(),
                };

                // Continue to next line processing callback
                true
            },
            |_delta, _hunk_idx, line| {
                let origin = char::from(line.origin());
                let content = line.content().to_owned();

                // Count additions and deletions
                match origin {
                    '+' => file_diff.additions += 1,
                    '-' => file_diff.deletions += 1,
                    _ => {}
                }

                if let Some(hunk) = file_diff.diff_content.last_mut() {
                    // Create a diff line
                    let diff_line = DiffLine {
                        origin,
                        content,
                        line_number_old: match origin {
                            '-' | ' ' => Some(hunk.old_start + hunk.lines.iter().filter(|l| l.origin == '-' || l.origin == ' ').count()),
                            _ => None,
                        },
                        line_number_new: match origin {
                            '+' | ' ' => Some(hunk.new_start + hunk.lines.iter().filter(|l| l.origin == '+' || l.origin == ' ').count()),
                            _ => None,
                        },
                    };

                    hunk.lines.push(diff_line);
                }

                true
            },
        )
        .map_err(|e| Error::Git(format!("Failed to process diff: {}", e)))?;

        file_diffs.push(file_diff);
    }

    Ok(file_diffs)
}
