//! Repository templates

use crate::data::git::RepositoryInfo;
use crate::template::BasePage;
use crate::util::time;
use askama::Template;

/// Repository listing template
#[derive(Template)]
#[template(path = "repo/list.html")]
pub struct RepoListTemplate {
    /// List of repositories
    pub repositories: Vec<RepositoryInfo>,
}

impl BasePage for RepoListTemplate {
    fn get_title(&self) -> &str {
        "Git Repositories"
    }

    fn get_content(&self) -> String {
        self.render().unwrap_or_else(|_| String::from("Error rendering template"))
    }

    fn get_body_classes(&self) -> Option<&str> {
        Some("repo-list")
    }
}

/// Repository details template
#[derive(Template)]
#[template(path = "repo/detail.html")]
pub struct RepoDetailTemplate<'a> {
    /// Repository information
    pub repo: &'a RepositoryInfo,

    /// Current branch or revision
    pub current_ref: &'a str,

    /// Last commit time formatted
    pub last_updated: String,

    /// List of branches
    pub branches: Vec<(&'a str, &'a str)>,

    /// List of tags
    pub tags: Vec<(&'a str, &'a str)>,
}

impl<'a> RepoDetailTemplate<'a> {
    /// Create a new repository details template
    pub fn new(
        repo: &'a RepositoryInfo,
        current_ref: &'a str,
        branches: Vec<(&'a str, &'a str)>,
        tags: Vec<(&'a str, &'a str)>,
    ) -> Self {
        // Format last commit time
        let last_updated = if let Some(time) = repo.last_commit {
            time::format_datetime_relative(time)
        } else {
            "Unknown".to_string()
        };

        Self {
            repo,
            current_ref,
            last_updated,
            branches,
            tags,
        }
    }
}

impl<'a> BasePage for RepoDetailTemplate<'a> {
    fn get_title(&self) -> &str {
        &self.repo.name
    }

    fn get_content(&self) -> String {
        self.render().unwrap_or_else(|_| String::from("Error rendering template"))
    }

    fn get_body_classes(&self) -> Option<&str> {
        Some("repo-detail")
    }
}
