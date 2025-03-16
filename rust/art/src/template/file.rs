//! File templates for displaying file content and directory listings.

use crate::data::git::{FileInfo, RepositoryInfo};
use crate::template::BasePage;
use crate::util::time;
use askama::Template;

/// Template for displaying file content with syntax highlighting
#[derive(Template)]
#[template(path = "file/content.html")]
pub struct FileContentTemplate<'a> {
    /// Repository information
    pub repo: &'a RepositoryInfo,
    /// Current Git reference (branch/tag/commit)
    pub git_ref: &'a str,
    /// File path
    pub path: &'a str,
    /// File information
    pub file: &'a FileInfo,
    /// File content as text (if not binary)
    pub content: &'a str,
    /// HTML syntax highlighted content (if available)
    pub content_html: Option<String>,
    /// Last commit ID for this file
    pub last_commit_id: &'a str,
    /// Last commit message for this file
    pub last_commit_message: &'a str,
    /// Last commit author for this file
    pub last_commit_author: &'a str,
    /// Last commit time for this file
    pub last_commit_time: i64,
    /// Formatted last commit time
    pub formatted_time: String,
}

impl<'a> FileContentTemplate<'a> {
    /// Create a new file content template
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        repo: &'a RepositoryInfo,
        git_ref: &'a str,
        path: &'a str,
        file: &'a FileInfo,
        content: &'a str,
        content_html: Option<String>,
        last_commit_id: &'a str,
        last_commit_message: &'a str,
        last_commit_author: &'a str,
        last_commit_time: i64,
    ) -> Self {
        // Format the commit time
        let formatted_time = time::format_timestamp(last_commit_time);

        Self {
            repo,
            git_ref,
            path,
            file,
            content,
            content_html,
            last_commit_id,
            last_commit_message,
            last_commit_author,
            last_commit_time,
            formatted_time,
        }
    }
}

impl<'a> BasePage for FileContentTemplate<'a> {
    fn get_title(&self) -> &str {
        &self.file.name
    }

    fn get_content(&self) -> String {
        self.render().unwrap_or_else(|_| "Failed to render file content template".to_string())
    }

    fn body_classes(&self) -> Option<String> {
        Some("file-content-page".to_string())
    }

    fn head(&self) -> Option<String> {
        Some(r#"<link rel="stylesheet" href="/static/css/highlight.css">"#.to_string())
    }
}

/// Template for displaying a directory listing
#[derive(Template)]
#[template(path = "file/directory.html")]
pub struct DirectoryTemplate<'a> {
    /// Repository information
    pub repo: &'a RepositoryInfo,
    /// Current Git reference (branch/tag/commit)
    pub git_ref: &'a str,
    /// Directory path
    pub path: &'a str,
    /// Files in the directory
    pub files: Vec<FileInfo>,
    /// Last commit ID for this directory
    pub last_commit_id: &'a str,
    /// Last commit message for this directory
    pub last_commit_message: &'a str,
    /// Last commit author for this directory
    pub last_commit_author: &'a str,
    /// Last commit time for this directory
    pub last_commit_time: i64,
    /// Formatted last commit time
    pub formatted_time: String,
}

impl<'a> DirectoryTemplate<'a> {
    /// Create a new directory template
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        repo: &'a RepositoryInfo,
        git_ref: &'a str,
        path: &'a str,
        files: Vec<FileInfo>,
        last_commit_id: &'a str,
        last_commit_message: &'a str,
        last_commit_author: &'a str,
        last_commit_time: i64,
    ) -> Self {
        // Format the commit time
        let formatted_time = time::format_timestamp(last_commit_time);

        Self {
            repo,
            git_ref,
            path,
            files,
            last_commit_id,
            last_commit_message,
            last_commit_author,
            last_commit_time,
            formatted_time,
        }
    }
}

impl<'a> BasePage for DirectoryTemplate<'a> {
    fn get_title(&self) -> &str {
        if self.path.is_empty() {
            "Files"
        } else {
            self.path
        }
    }

    fn get_content(&self) -> String {
        self.render().unwrap_or_else(|_| "Failed to render directory template".to_string())
    }

    fn body_classes(&self) -> Option<String> {
        Some("directory-listing-page".to_string())
    }

    fn head(&self) -> Option<String> {
        None
    }
}
