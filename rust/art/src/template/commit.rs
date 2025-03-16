//! Commit templates for displaying commit information.

use crate::data::git::{CommitInfo, RepositoryInfo};
use crate::template::BasePage;
use crate::util::time;
use askama::Template;

/// Template for displaying a list of commits in a repository
#[derive(Template)]
#[template(path = "commit/list.html")]
pub struct CommitListTemplate<'a> {
    /// Repository information
    pub repo: &'a RepositoryInfo,
    /// Current Git reference (branch/tag/commit)
    pub current_ref: &'a str,
    /// List of commits to display
    pub commits: Vec<CommitInfo>,
    /// Page title
    pub title: String,
}

impl<'a> BasePage for CommitListTemplate<'a> {
    fn get_title(&self) -> &str {
        &self.title
    }

    fn get_content(&self) -> String {
        // Return commit list content
        format!("Commit history for {}", self.repo.name)
    }

    fn body_classes(&self) -> Option<String> {
        Some("commit-list-page".to_string())
    }

    fn head(&self) -> Option<String> {
        None
    }
}

/// Template for displaying detailed information about a commit
#[derive(Template)]
#[template(path = "commit/detail.html")]
pub struct CommitDetailTemplate<'a> {
    /// Repository information
    pub repo: &'a RepositoryInfo,
    /// Commit information
    pub commit: &'a CommitInfo,
    /// Child commits (commits that reference this commit as a parent)
    pub children: Vec<CommitInfo>,
    /// HTML diff of the commit changes (if available)
    pub diff_html: Option<String>,
    /// Formatted commit time
    pub formatted_time: String,
    /// Page title
    pub title: String,
}

impl<'a> CommitDetailTemplate<'a> {
    /// Create a new commit detail template
    pub fn new(
        repo: &'a RepositoryInfo,
        commit: &'a CommitInfo,
        children: Vec<CommitInfo>,
        diff_html: Option<String>,
    ) -> Self {
        // Format the commit time
        let formatted_time = time::format_timestamp(commit.time);
        // Generate the title
        let title = format!("{} - Commit {}", repo.name, &commit.id[..7]);

        Self {
            repo,
            commit,
            children,
            diff_html,
            formatted_time,
            title,
        }
    }
}

impl<'a> BasePage for CommitDetailTemplate<'a> {
    fn get_title(&self) -> &str {
        &self.title
    }

    fn get_content(&self) -> String {
        // Return commit detail content
        format!("Commit {} by {}", self.commit.id, self.commit.author)
    }

    fn body_classes(&self) -> Option<String> {
        Some("commit-detail-page".to_string())
    }

    fn head(&self) -> Option<String> {
        None
    }
}
