// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Repository statistics module
//!
//! This module provides functionality for collecting and accessing repository statistics
//! including file counts, size information, contributor data, and commit activity metrics.

use crate::error::{Error, Result};
use crate::data::git::{Git, Repository};
use crate::data::cache::Cache;
use crate::service::observability::metrics;

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use chrono::{DateTime, Datelike, TimeZone, Timelike, Utc};
use serde::{Serialize, Deserialize};
use tokio::sync::RwLock;
use tracing::{debug, error, info, trace, warn};

/// Repository statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryStats {
    /// Repository name
    pub name: String,

    /// Repository path
    pub path: String,

    /// Repository description
    pub description: Option<String>,

    /// Total number of files
    pub file_count: usize,

    /// Total size of all files in bytes
    pub total_size_bytes: u64,

    /// Breakdown of files by type (extension)
    pub file_types: HashMap<String, usize>,

    /// Breakdown of files by size range
    pub file_size_distribution: HashMap<String, usize>,

    /// Total number of commits
    pub commit_count: usize,

    /// Number of commits in the last day
    pub commits_last_day: usize,

    /// Number of commits in the last week
    pub commits_last_week: usize,

    /// Number of commits in the last month
    pub commits_last_month: usize,

    /// Number of contributors
    pub contributor_count: usize,

    /// List of top contributors with commit counts
    pub top_contributors: Vec<ContributorStats>,

    /// Age of the repository in days
    pub age_days: u64,

    /// Creation date of the repository
    pub created_at: DateTime<Utc>,

    /// Last update timestamp
    pub last_updated: DateTime<Utc>,

    /// Average number of commits per day
    pub avg_commits_per_day: f64,

    /// Commits by day of week (0 = Sunday, 6 = Saturday)
    pub commits_by_day_of_week: HashMap<u32, usize>,

    /// Commits by hour of day (0-23)
    pub commits_by_hour: HashMap<u32, usize>,

    /// Commit activity by month for the past year
    pub commit_activity_by_month: HashMap<String, usize>,

    /// Branch count
    pub branch_count: usize,

    /// Tag count
    pub tag_count: usize,
}

/// Contributor statistics
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ContributorStats {
    /// Contributor name
    pub name: String,

    /// Contributor email
    pub email: String,

    /// Number of commits
    pub commit_count: usize,

    /// First commit timestamp
    pub first_commit: DateTime<Utc>,

    /// Last commit timestamp
    pub last_commit: DateTime<Utc>,

    /// Days active (days between first and last commit)
    pub days_active: u64,
}

/// Repository statistics service
pub struct RepositoryStatisticsService {
    /// Git data access
    git: Arc<Git>,

    /// Cache
    cache: Arc<Cache<String, String>>,

    /// Statistics for repositories
    stats: RwLock<HashMap<String, RepositoryStats>>,

    /// Last refresh times for repositories
    last_refresh: RwLock<HashMap<String, Instant>>,

    /// Cache TTL
    cache_ttl: Duration,
}

impl RepositoryStatisticsService {
    /// Create a new repository statistics service
    pub fn new(git: Arc<Git>, cache: Arc<Cache<String, String>>) -> Self {
        // Register metrics
        Self::register_metrics();

        Self {
            git,
            cache,
            stats: RwLock::new(HashMap::new()),
            last_refresh: RwLock::new(HashMap::new()),
            cache_ttl: Duration::from_secs(3600), // Default 1 hour
        }
    }

    /// Set the cache TTL
    pub fn with_cache_ttl(mut self, ttl: Duration) -> Self {
        self.cache_ttl = ttl;
        self
    }

    /// Get repository statistics
    pub async fn get_stats(&self, repo_name: &str) -> Result<RepositoryStats> {
        // Check cache first
        let cache_key = format!("stats:{}", repo_name);
        if let Some(cached) = self.cache.get(&cache_key).await {
            return Ok(serde_json::from_str(&cached)
                .map_err(|e| Error::Serialization(format!("Failed to deserialize stats: {}", e)))?);
        }

        // Refresh stats if needed
        self.refresh_stats(repo_name).await?;

        // Return the stats
        let stats = self.stats.read().await;
        match stats.get(repo_name) {
            Some(stats) => Ok(stats.clone()),
            None => Err(Error::NotFound(format!("Repository statistics not found for: {}", repo_name))),
        }
    }

    /// Get statistics for all repositories
    pub async fn get_all_stats(&self) -> Result<Vec<RepositoryStats>> {
        let repos = self.git.list_repositories()?;
        let mut result = Vec::new();

        for repo_info in repos {
            match self.get_stats(&repo_info.name).await {
                Ok(stats) => result.push(stats),
                Err(e) => {
                    warn!("Failed to get stats for repository {}: {}", repo_info.name, e);
                }
            }
        }

        Ok(result)
    }

    /// Force a refresh of repository statistics
    pub async fn refresh_stats(&self, repo_name: &str) -> Result<RepositoryStats> {
        debug!("Refreshing statistics for repository: {}", repo_name);

        // Check cache first
        let cache_key = format!("stats:{}", repo_name);
        if let Some(cached) = self.cache.get(&cache_key).await {
            return Ok(serde_json::from_str(&cached)
                .map_err(|e| Error::Serialization(format!("Failed to deserialize cached stats: {}", e)))?);
        }

        // Get repository
        let repo = self.git.open(repo_name, repo_name)?;

        // Collect statistics
        let stats = self.collect_repository_stats(&repo).await?;

        // Cache the result
        self.cache.insert(
            cache_key,
            serde_json::to_string(&stats)
                .map_err(|e| Error::Serialization(format!("Failed to serialize stats: {}", e)))?,
        ).await;

        // Update in-memory stats
        let mut stats_map = self.stats.write().await;
        stats_map.insert(repo_name.to_string(), stats.clone());

        // Update last refresh time
        let mut last_refresh = self.last_refresh.write().await;
        last_refresh.insert(repo_name.to_string(), Instant::now());

        Ok(stats)
    }

    /// Force a refresh of all repository statistics
    pub async fn refresh_all_stats(&self) -> Result<()> {
        let repos = self.git.list_repositories()?;

        for repo_info in repos {
            match self.refresh_stats(&repo_info.name).await {
                Ok(_) => {
                    debug!("Refreshed statistics for repository: {}", repo_info.name);
                },
                Err(e) => {
                    warn!("Failed to refresh stats for repository {}: {}", repo_info.name, e);
                }
            }
        }

        Ok(())
    }

    /// Collect statistics for a repository
    async fn collect_repository_stats(&self, repo: &Repository) -> Result<RepositoryStats> {
        let start_time = Instant::now();
        let repo_name = repo.name();
        debug!("Collecting statistics for repository: {}", repo_name);

        // Get basic repository info
        let repo_info = repo.info()?;

        // Get the git2 repository for more detailed stats
        let git_repo = git2::Repository::open(repo.path())?;

        // Collect file statistics
        let (file_count, total_size, file_types, file_size_distribution) =
            self.collect_file_stats(&git_repo)?;

        // Collect commit statistics
        let (commit_stats, contributor_stats) = self.collect_commit_stats(&git_repo)?;

        // Calculate averages
        let avg_commits_per_day = if commit_stats.age_days > 0 {
            commit_stats.commit_count as f64 / commit_stats.age_days as f64
        } else {
            0.0
        };

        // Create the stats object
        let stats = RepositoryStats {
            name: repo_name.to_string(),
            path: repo.path().to_string_lossy().to_string(),
            description: repo_info.description,
            file_count,
            total_size_bytes: total_size,
            file_types,
            file_size_distribution,
            commit_count: commit_stats.commit_count,
            commits_last_day: commit_stats.commits_last_day,
            commits_last_week: commit_stats.commits_last_week,
            commits_last_month: commit_stats.commits_last_month,
            contributor_count: contributor_stats.len(),
            top_contributors: contributor_stats.into_iter()
                .take(10)
                .collect(),
            age_days: commit_stats.age_days,
            created_at: commit_stats.first_commit_time,
            last_updated: commit_stats.last_commit_time,
            avg_commits_per_day,
            commits_by_day_of_week: commit_stats.commits_by_day_of_week,
            commits_by_hour: commit_stats.commits_by_hour,
            commit_activity_by_month: commit_stats.commit_activity_by_month,
            branch_count: repo_info.branch_count,
            tag_count: repo_info.tag_count,
        };

        // Record metrics
        metrics::gauge("repository_file_count", file_count as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_size_bytes", total_size as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_commit_count", stats.commit_count as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_contributor_count", stats.contributor_count as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_age_days", stats.age_days as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_branch_count", stats.branch_count as f64, &[("repository", repo_name)]);
        metrics::gauge("repository_tag_count", stats.tag_count as f64, &[("repository", repo_name)]);

        // Record file type metrics
        for (file_type, count) in &stats.file_types {
            metrics::gauge("repository_file_type_count", *count as f64,
                &[("repository", repo_name), ("file_type", file_type)]);
        }

        debug!("Collected statistics for repository {} in {:?}",
            repo_name, start_time.elapsed());

        Ok(stats)
    }

    /// Collect file statistics
    fn collect_file_stats(&self, repo: &git2::Repository) -> Result<(usize, u64, HashMap<String, usize>, HashMap<String, usize>)> {
        let mut file_count = 0;
        let mut total_size: u64 = 0;
        let mut file_types = HashMap::new();
        let mut file_size_distribution = HashMap::new();

        // Get the HEAD commit
        let head = repo.head()?;
        let commit = head.peel_to_commit()?;

        // Get the tree from the commit
        let tree = commit.tree()?;

        // Walk the tree
        fn walk_tree(
            tree: &git2::Tree,
            repo: &git2::Repository,
            file_count: &mut usize,
            total_size: &mut u64,
            file_types: &mut HashMap<String, usize>,
            file_size_distribution: &mut HashMap<String, usize>,
            prefix: &str,
        ) -> Result<()> {
            for entry in tree.iter() {
                let obj = entry.to_object(repo)?;

                if let Some(blob) = obj.as_blob() {
                    // Increment file count
                    *file_count += 1;

                    // Add to total size
                    let size = blob.size() as u64;
                    *total_size += size;

                    // Get file extension
                    let name = entry.name().unwrap_or("");
                    let ext = Path::new(name)
                        .extension()
                        .and_then(|e| e.to_str())
                        .unwrap_or("unknown")
                        .to_lowercase();

                    // Update file type counts
                    *file_types.entry(ext).or_insert(0) += 1;

                    // Update size distribution
                    let size_category = match size {
                        0..=1024 => "0-1KB",
                        1025..=10240 => "1KB-10KB",
                        10241..=102400 => "10KB-100KB",
                        102401..=1048576 => "100KB-1MB",
                        1048577..=10485760 => "1MB-10MB",
                        _ => ">10MB",
                    };

                    *file_size_distribution.entry(size_category.to_string()).or_insert(0) += 1;
                } else if let Some(subtree) = obj.as_tree() {
                    let new_prefix = if prefix.is_empty() {
                        entry.name().unwrap_or("").to_string()
                    } else {
                        format!("{}/{}", prefix, entry.name().unwrap_or(""))
                    };

                    walk_tree(
                        &subtree,
                        repo,
                        file_count,
                        total_size,
                        file_types,
                        file_size_distribution,
                        &new_prefix,
                    )?;
                }
            }

            Ok(())
        }

        // Start tree walk
        walk_tree(&tree, repo, &mut file_count, &mut total_size, &mut file_types, &mut file_size_distribution, "")?;

        Ok((file_count, total_size, file_types, file_size_distribution))
    }

    /// Commit statistics
    #[derive(Debug)]
    struct CommitStats {
        commit_count: usize,
        commits_last_day: usize,
        commits_last_week: usize,
        commits_last_month: usize,
        first_commit_time: DateTime<Utc>,
        last_commit_time: DateTime<Utc>,
        age_days: u64,
        commits_by_day_of_week: HashMap<u32, usize>,
        commits_by_hour: HashMap<u32, usize>,
        commit_activity_by_month: HashMap<String, usize>,
    }

    /// Collect commit statistics
    fn collect_commit_stats(&self, repo: &git2::Repository) -> Result<(CommitStats, Vec<ContributorStats>)> {
        let mut commit_count = 0;
        let mut commits_last_day = 0;
        let mut commits_last_week = 0;
        let mut commits_last_month = 0;
        let mut commits_by_day = HashMap::new();
        let mut commits_by_hour = HashMap::new();
        let mut commit_activity_by_month = HashMap::new();

        // For tracking first and last commit times
        let mut first_commit_time = Utc::now();
        let mut last_commit_time = DateTime::<Utc>::from_utc(
            chrono::NaiveDateTime::from_timestamp_opt(0, 0).unwrap(),
            Utc,
        );

        // For tracking contributors
        let mut contributors = HashMap::<String, ContributorStats>::new();

        // Current time
        let now = chrono::Utc::now();
        let one_day_ago = now - chrono::Duration::days(1);
        let one_week_ago = now - chrono::Duration::days(7);
        let one_month_ago = now - chrono::Duration::days(30);
        let one_year_ago = now - chrono::Duration::days(365);

        // Walk all commits
        let mut revwalk = repo.revwalk()?;
        revwalk.push_head()?;
        revwalk.set_sorting(git2::Sort::TIME)?;

        for oid in revwalk {
            let oid = oid?;
            let commit = repo.find_commit(oid)?;

            // Increment commit count
            commit_count += 1;

            // Get commit time
            let commit_time = commit.time();
            let seconds = commit_time.seconds();
            let commit_dt = chrono::Utc.timestamp_opt(seconds, 0).single().unwrap_or_else(Utc::now);

            // Update first and last commit times
            if commit_dt < first_commit_time {
                first_commit_time = commit_dt;
            }

            if commit_dt > last_commit_time {
                last_commit_time = commit_dt;
            }

            // Check if commit is recent
            if commit_dt > one_day_ago {
                commits_last_day += 1;
            }

            if commit_dt > one_week_ago {
                commits_last_week += 1;
            }

            if commit_dt > one_month_ago {
                commits_last_month += 1;
            }

            // Record day of week and hour
            let day_of_week = commit_dt.weekday().num_days_from_sunday();
            let hour = commit_dt.hour();

            *commits_by_day.entry(day_of_week).or_insert(0) += 1;
            *commits_by_hour.entry(hour).or_insert(0) += 1;

            // Record monthly activity for the past year
            if commit_dt > one_year_ago {
                let month_key = format!("{}-{:02}", commit_dt.year(), commit_dt.month());
                *commit_activity_by_month.entry(month_key).or_insert(0) += 1;
            }

            // Track contributor
            let author = commit.author();
            let author_name = author.name().unwrap_or("Unknown").to_string();
            let author_email = author.email().unwrap_or("unknown@example.com").to_string();
            let contributor_key = format!("{} <{}>", author_name, author_email);

            let contributor = contributors.entry(contributor_key).or_insert_with(|| {
                ContributorStats {
                    name: author_name.clone(),
                    email: author_email.clone(),
                    commit_count: 0,
                    first_commit: commit_dt,
                    last_commit: commit_dt,
                    days_active: 0,
                }
            });

            contributor.commit_count += 1;

            if commit_dt < contributor.first_commit {
                contributor.first_commit = commit_dt;
            }

            if commit_dt > contributor.last_commit {
                contributor.last_commit = commit_dt;
            }
        }

        // Calculate age in days
        let age_days = now.signed_duration_since(first_commit_time).num_days().max(0) as u64;

        // Update days active for contributors
        let mut contributor_stats = contributors.values().cloned().collect::<Vec<_>>();

        for contributor in &mut contributor_stats {
            contributor.days_active = contributor.last_commit
                .signed_duration_since(contributor.first_commit)
                .num_days().max(0) as u64;
        }

        // Sort contributors by commit count
        contributor_stats.sort_by(|a, b| b.commit_count.cmp(&a.commit_count));

        // Create commit stats
        let commit_stats = CommitStats {
            commit_count,
            commits_last_day,
            commits_last_week,
            commits_last_month,
            first_commit_time,
            last_commit_time,
            age_days,
            commits_by_day_of_week: commits_by_day,
            commits_by_hour: commits_by_hour,
            commit_activity_by_month,
        };

        Ok((commit_stats, contributor_stats))
    }

    /// Register metrics
    fn register_metrics() {
        metrics::register_gauge(
            "repository_file_count",
            "Number of files in repository",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_size_bytes",
            "Total size of all files in repository in bytes",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_commit_count",
            "Number of commits in repository",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_contributor_count",
            "Number of contributors to repository",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_age_days",
            "Age of repository in days",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_branch_count",
            "Number of branches in repository",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_tag_count",
            "Number of tags in repository",
            &["repository"],
        );

        metrics::register_gauge(
            "repository_file_type_count",
            "Number of files of each type in repository",
            &["repository", "file_type"],
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use proptest::collection::hash_map;
    use proptest::test_runner::{Config, TestRunner};
    use std::sync::Arc;
    use crate::data::cache::Cache;
    use crate::config::RepositoryConfig;
    use tempfile::TempDir;
    use std::fs;

    // Helper to create a test Git repository
    async fn create_test_repo() -> (TempDir, PathBuf, String) {
        let temp_dir = TempDir::new().unwrap();
        let repo_path = temp_dir.path().join("test-repo");
        let repo_name = "test-repo";

        // Create repo directory
        fs::create_dir_all(&repo_path).unwrap();

        // Initialize Git repository
        let repo = git2::Repository::init(&repo_path).unwrap();

        // Create some example files and commit them
        let file_paths = [
            ("README.md", "# Test Repository\n\nThis is a test repository."),
            ("src/main.rs", "fn main() {\n    println!(\"Hello, world!\");\n}"),
            ("src/lib.rs", "pub fn add(a: i32, b: i32) -> i32 {\n    a + b\n}"),
            ("tests/test.rs", "#[test]\nfn it_works() {\n    assert_eq!(4, 2 + 2);\n}"),
        ];

        // Create files and directories
        fs::create_dir_all(repo_path.join("src")).unwrap();
        fs::create_dir_all(repo_path.join("tests")).unwrap();

        for (path, content) in &file_paths {
            fs::write(repo_path.join(path), content).unwrap();
        }

        // Add and commit files
        let mut index = repo.index().unwrap();
        index.add_all(&["*"], git2::IndexAddOption::DEFAULT, None).unwrap();
        index.write().unwrap();

        let tree_id = index.write_tree().unwrap();
        let tree = repo.find_tree(tree_id).unwrap();

        let signature = git2::Signature::now("Test User", "test@example.com").unwrap();
        repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            "Initial commit",
            &tree,
            &[],
        ).unwrap();

        // Create a branch
        let head = repo.head().unwrap();
        let head_commit = head.peel_to_commit().unwrap();
        repo.branch("test-branch", &head_commit, false).unwrap();

        // Create a tag
        repo.tag("v1.0.0", &head_commit.into_object(), &signature, "Version 1.0.0", false).unwrap();

        (temp_dir, repo_path, repo_name.to_string())
    }

    // Property test for ContributorStats
    proptest! {
        #[test]
        fn test_contributor_stats_serde(
            name in "[a-zA-Z0-9 ]{1,20}",
            email in "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,6}",
            commit_count in 1..1000usize,
            timestamp1 in 1000000000i64..1700000000i64,
            timestamp2 in 1000000000i64..1700000000i64,
        ) {
            // Ensure timestamp2 >= timestamp1
            let earlier_ts = timestamp1.min(timestamp2);
            let later_ts = timestamp1.max(timestamp2);

            let first_commit = chrono::Utc.timestamp_opt(earlier_ts, 0).single().unwrap();
            let last_commit = chrono::Utc.timestamp_opt(later_ts, 0).single().unwrap();
            let days_active = last_commit.signed_duration_since(first_commit).num_days().max(0) as u64;

            let stats = ContributorStats {
                name: name.clone(),
                email: email.clone(),
                commit_count,
                first_commit,
                last_commit,
                days_active,
            };

            // Serialize and deserialize
            let json = serde_json::to_string(&stats).unwrap();
            let deserialized: ContributorStats = serde_json::from_str(&json).unwrap();

            // Verify fields match
            prop_assert_eq!(deserialized.name, name);
            prop_assert_eq!(deserialized.email, email);
            prop_assert_eq!(deserialized.commit_count, commit_count);
            prop_assert_eq!(deserialized.first_commit, first_commit);
            prop_assert_eq!(deserialized.last_commit, last_commit);
            prop_assert_eq!(deserialized.days_active, days_active);
        }
    }

    // Property test for RepositoryStats calculation
    proptest! {
        #[test]
        fn test_repo_stats_calculations(
            file_count in 1..1000usize,
            total_size_bytes in 100..10000000u64,
            commit_count in 1..1000usize,
            age_days in 1..1000u64,
        ) {
            // Create a RepositoryStats with some variations
            let stats = RepositoryStats {
                name: "test-repo".to_string(),
                path: "/path/to/repo".to_string(),
                description: Some("Test repository".to_string()),
                file_count,
                total_size_bytes,
                file_types: HashMap::new(),
                file_size_distribution: HashMap::new(),
                commit_count,
                commits_last_day: (commit_count / 10).max(1),
                commits_last_week: (commit_count / 5).max(2),
                commits_last_month: (commit_count / 2).max(3),
                contributor_count: (commit_count / 50).max(1),
                top_contributors: Vec::new(),
                age_days,
                created_at: chrono::Utc::now() - chrono::Duration::days(age_days as i64),
                last_updated: chrono::Utc::now(),
                avg_commits_per_day: commit_count as f64 / age_days as f64,
                commits_by_day_of_week: HashMap::new(),
                commits_by_hour: HashMap::new(),
                commit_activity_by_month: HashMap::new(),
                branch_count: 1,
                tag_count: 1,
            };

            // Check calculated field
            let expected_avg = commit_count as f64 / age_days as f64;
            prop_assert!((stats.avg_commits_per_day - expected_avg).abs() < 0.001);

            // Age is consistent with created_at
            let expected_age = chrono::Utc::now().signed_duration_since(stats.created_at).num_days() as u64;
            prop_assert!((stats.age_days as i64 - expected_age as i64).abs() <= 1);
        }
    }

    // Integration test for the RepositoryStatisticsService
    #[tokio::test]
    async fn test_repository_statistics_service() -> Result<()> {
        // Create a test repository
        let (temp_dir, repo_path, repo_name) = create_test_repo().await;

        // Create Git instance
        let config = RepositoryConfig {
            repo_dir: temp_dir.path().to_path_buf(),
            max_cache_size: 1024 * 1024,
            enable_maintenance: false,
            maintenance_interval: 0,
            verify_commit_signatures: false,
            gpg_homedir: None,
            trusted_gpg_keys: vec![],
            trusted_ssh_keys: vec![],
        };

        let git = Arc::new(Git::new(&config)?);
        let cache = Arc::new(Cache::new(1000, Duration::from_secs(60)));

        // Create repository statistics service
        let service = RepositoryStatisticsService::new(git.clone(), cache.clone())
            .with_cache_ttl(Duration::from_secs(60));

        // Get statistics for the test repository
        let stats = service.get_stats(&repo_name).await?;

        // Verify basic stats
        assert_eq!(stats.name, repo_name);
        assert_eq!(stats.path, repo_path.to_string_lossy().to_string());
        assert!(stats.file_count >= 4); // Should have at least the 4 files we created
        assert!(stats.total_size_bytes > 0);
        assert!(stats.commit_count >= 1); // Should have at least the initial commit
        assert!(stats.branch_count >= 2); // main + test-branch
        assert!(stats.tag_count >= 1); // v1.0.0

        // Verify file type counts
        assert!(stats.file_types.contains_key("md"));
        assert!(stats.file_types.contains_key("rs"));

        // Verify contributors
        assert!(stats.contributor_count >= 1);
        assert!(!stats.top_contributors.is_empty());
        assert_eq!(stats.top_contributors[0].name, "Test User");
        assert_eq!(stats.top_contributors[0].email, "test@example.com");

        Ok(())
    }

    // Property test for file size categorization
    proptest! {
        #[test]
        fn test_file_size_categorization(size in 0u64..20000000u64) {
            let category = match size {
                0..=1024 => "0-1KB",
                1025..=10240 => "1KB-10KB",
                10241..=102400 => "10KB-100KB",
                102401..=1048576 => "100KB-1MB",
                1048577..=10485760 => "1MB-10MB",
                _ => ">10MB",
            };

            // Verify category is valid
            prop_assert!(
                category == "0-1KB" ||
                category == "1KB-10KB" ||
                category == "10KB-100KB" ||
                category == "100KB-1MB" ||
                category == "1MB-10MB" ||
                category == ">10MB"
            );

            // Verify bounds
            match category {
                "0-1KB" => prop_assert!(size <= 1024),
                "1KB-10KB" => prop_assert!(size > 1024 && size <= 10240),
                "10KB-100KB" => prop_assert!(size > 10240 && size <= 102400),
                "100KB-1MB" => prop_assert!(size > 102400 && size <= 1048576),
                "1MB-10MB" => prop_assert!(size > 1048576 && size <= 10485760),
                ">10MB" => prop_assert!(size > 10485760),
                _ => prop_assert!(false, "Invalid category"),
            }
        }
    }
}
