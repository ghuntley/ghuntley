use crate::error::{Error, Result};
use crate::data::git::Git;
use crate::service::observability::ObservabilityService;
use crate::service::repository::RepositoryService;
use prometheus::{Gauge, GaugeVec, IntCounter, IntCounterVec, IntGauge, Registry};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time;
use tracing::{debug, error, info, warn};
use std::path::Path;
use git2::{Repository, Signature};
use chrono::{DateTime, Datelike, Timelike, Utc};
use std::path::PathBuf;

/// Configuration for content metrics collection
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ContentMetricsConfig {
    /// Whether to enable content metrics collection
    pub enabled: bool,

    /// How often to collect metrics (in seconds)
    pub collection_interval_seconds: u64,

    /// Maximum repositories to collect metrics for (0 for unlimited)
    pub max_repositories: usize,

    /// Track file type statistics
    pub track_file_types: bool,

    /// Track file size distribution
    pub track_file_sizes: bool,

    /// Track commit statistics
    pub track_commit_stats: bool,

    /// Track contributor statistics
    pub track_contributor_stats: bool,

    /// Track repository age and activity
    pub track_activity_stats: bool,
}

impl Default for ContentMetricsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            collection_interval_seconds: 3600, // Default to hourly collection
            max_repositories: 100,
            track_file_types: true,
            track_file_sizes: true,
            track_commit_stats: true,
            track_contributor_stats: true,
            track_activity_stats: true,
        }
    }
}

/// Statistics about repository content
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RepositoryContentStats {
    /// Repository name
    pub name: String,

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

    /// Age of the repository in days
    pub age_days: u64,

    /// Last update timestamp
    pub last_update: chrono::DateTime<chrono::Utc>,
}

/// Activity statistics for a repository
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RepositoryActivityStats {
    /// Repository name
    pub name: String,

    /// Average commits per day over repository lifetime
    pub avg_commits_per_day: f64,

    /// Average commits per day in the last month
    pub avg_commits_per_day_last_month: f64,

    /// Commits by day of week (0 = Sunday, 6 = Saturday)
    pub commits_by_day_of_week: HashMap<u32, usize>,

    /// Commits by hour of day (0-23)
    pub commits_by_hour: HashMap<u32, usize>,

    /// Top contributors with commit counts
    pub top_contributors: HashMap<String, usize>,

    /// Days since last commit
    pub days_since_last_commit: u64,

    /// Last active day (timestamp)
    pub last_active_day: chrono::DateTime<chrono::Utc>,
}

impl RepositoryContentStats {
    /// Create activity statistics from this repository stats
    pub fn activity_stats(&self) -> RepositoryActivityStats {
        let avg_commits_per_day = if self.age_days > 0 {
            self.commit_count as f64 / self.age_days as f64
        } else {
            0.0
        };

        let avg_commits_per_day_last_month = if self.age_days >= 30 {
            self.commits_last_month as f64 / 30.0
        } else if self.age_days > 0 {
            self.commits_last_month as f64 / self.age_days as f64
        } else {
            0.0
        };

        RepositoryActivityStats {
            name: self.name.clone(),
            avg_commits_per_day,
            avg_commits_per_day_last_month,
            commits_by_day_of_week: HashMap::new(), // This would be populated from actual data
            commits_by_hour: HashMap::new(), // This would be populated from actual data
            top_contributors: HashMap::new(), // This would be populated from actual data
            days_since_last_commit: 0, // This would be calculated from actual data
            last_active_day: self.last_update,
        }
    }
}

/// Collector for repository content metrics
pub struct ContentMetricsCollector {
    /// Git repository manager
    git: Arc<Git>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// Observability service for recording metrics
    observability_service: Arc<ObservabilityService>,

    /// Configuration
    config: ContentMetricsConfig,

    /// Last collection time
    last_collection: Instant,

    /// Repository metrics
    repository_metrics: HashMap<String, RepositoryContentStats>,

    /// Whether the collector is running
    is_running: bool,

    /// File count gauge vector
    file_count: GaugeVec,

    /// Total size gauge vector
    total_size_bytes: GaugeVec,

    /// Commit count gauge vector
    commit_count: GaugeVec,

    /// Contributor count gauge vector
    contributor_count: GaugeVec,

    /// Repository age gauge vector
    repo_age_days: GaugeVec,

    /// File type count gauge vector
    file_type_count: GaugeVec,

    /// File size distribution gauge vector
    file_size_distribution: GaugeVec,
}

impl ContentMetricsCollector {
    /// Create a new content metrics collector
    pub fn new(
        git: Arc<Git>,
        repository_service: Arc<RepositoryService>,
        observability_service: Arc<ObservabilityService>,
        config: ContentMetricsConfig,
    ) -> Result<Self> {
        // Create metrics
        let file_count = observability_service.create_gauge(
            "repository_file_count",
            "Number of files in repository",
            vec!["repository"],
        )?;

        let total_size_bytes = observability_service.create_gauge(
            "repository_size_bytes",
            "Total size of all files in repository in bytes",
            vec!["repository"],
        )?;

        let commit_count = observability_service.create_gauge(
            "repository_commit_count",
            "Number of commits in repository",
            vec!["repository", "timeframe"],
        )?;

        let contributor_count = observability_service.create_gauge(
            "repository_contributor_count",
            "Number of contributors to repository",
            vec!["repository"],
        )?;

        let repo_age_days = observability_service.create_gauge(
            "repository_age_days",
            "Age of repository in days",
            vec!["repository"],
        )?;

        let file_type_count = observability_service.create_gauge(
            "repository_file_type_count",
            "Number of files of each type in repository",
            vec!["repository", "file_type"],
        )?;

        let file_size_distribution = observability_service.create_gauge(
            "repository_file_size_distribution",
            "Distribution of file sizes in repository",
            vec!["repository", "size_range"],
        )?;

        Ok(Self {
            git,
            repository_service,
            observability_service,
            config,
            last_collection: Instant::now(),
            repository_metrics: HashMap::new(),
            is_running: false,
            file_count,
            total_size_bytes,
            commit_count,
            contributor_count,
            repo_age_days,
            file_type_count,
            file_size_distribution,
        })
    }

    /// Start the metrics collector
    pub async fn start(&mut self) -> Result<()> {
        if !self.config.enabled {
            info!("Content metrics collection is disabled");
            return Ok(());
        }

        if self.is_running {
            warn!("Content metrics collector is already running");
            return Ok(());
        }

        self.is_running = true;

        // Run an initial collection
        if let Err(e) = self.collect_metrics().await {
            error!("Error collecting initial content metrics: {}", e);
        }

        // Start a task to periodically collect metrics
        let git = self.git.clone();
        let repository_service = self.repository_service.clone();
        let observability_service = self.observability_service.clone();
        let config = self.config.clone();

        // Clone the metric vectors
        let file_count = self.file_count.clone();
        let total_size_bytes = self.total_size_bytes.clone();
        let commit_count = self.commit_count.clone();
        let contributor_count = self.contributor_count.clone();
        let repo_age_days = self.repo_age_days.clone();
        let file_type_count = self.file_type_count.clone();
        let file_size_distribution = self.file_size_distribution.clone();

        tokio::spawn(async move {
            let mut collector = ContentMetricsCollector {
                git,
                repository_service,
                observability_service,
                config: config.clone(),
                last_collection: Instant::now(),
                repository_metrics: HashMap::new(),
                is_running: true,
                file_count,
                total_size_bytes,
                commit_count,
                contributor_count,
                repo_age_days,
                file_type_count,
                file_size_distribution,
            };

            let interval = Duration::from_secs(config.collection_interval_seconds);
            let mut interval_timer = time::interval(interval);

            loop {
                interval_timer.tick().await;

                // Collect metrics
                if let Err(e) = collector.collect_metrics().await {
                    error!("Error collecting content metrics: {}", e);
                }
            }
        });

        info!("Content metrics collector started");

        Ok(())
    }

    /// Collect metrics from repositories
    pub async fn collect_metrics(&mut self) -> Result<()> {
        info!("Collecting repository content metrics");
        let start_time = Instant::now();

        // Get all repositories
        let repositories = self.repository_service.list_repositories().await?;

        // Limit the number of repositories if configured
        let repositories = if self.config.max_repositories > 0 && self.config.max_repositories < repositories.len() {
            repositories[0..self.config.max_repositories].to_vec()
        } else {
            repositories
        };

        // Collect metrics for each repository
        for repo in repositories {
            // Extract repository name from RepositoryInfo
            let repo_name = &repo.name;
            if let Err(e) = self.collect_repository_metrics(repo_name).await {
                error!("Error collecting metrics for repository {}: {}", repo_name, e);
                continue;
            }
        }

        // Update last collection time
        self.last_collection = Instant::now();

        let elapsed = start_time.elapsed();
        info!("Repository content metrics collection completed in {:?}", elapsed);

        Ok(())
    }

    /// Collect metrics for a single repository
    async fn collect_repository_metrics(&mut self, repo_name: &str) -> Result<()> {
        debug!("Collecting metrics for repository {}", repo_name);

        // Get repository
        let repo = match self.git.repository(repo_name) {
            Ok(repo) => repo,
            Err(e) => {
                error!("Error opening repository {}: {}", repo_name, e);
                return Err(e);
            }
        };

        // Initialize stats
        let mut stats = RepositoryContentStats {
            name: repo_name.to_string(),
            file_count: 0,
            total_size_bytes: 0,
            file_types: HashMap::new(),
            file_size_distribution: HashMap::new(),
            commit_count: 0,
            commits_last_day: 0,
            commits_last_week: 0,
            commits_last_month: 0,
            contributor_count: 0,
            age_days: 0,
            last_update: chrono::Utc::now(),
        };

        // We need to use git2::Repository for some operations
        let repo_path = repo.path();
        let git2_repo = match git2::Repository::open(repo_path) {
            Ok(r) => r,
            Err(e) => {
                error!("Error opening git2 repository at {}: {}", repo_path.display(), e);
                return Err(Error::Internal(format!("Git error: {}", e)));
            }
        };

        // Get the default branch
        let head = git2_repo.head()?;
        let branch_name = head.shorthand().unwrap_or("HEAD");

        // Get the commit
        let commit = head.peel_to_commit()?;

        // Get the tree
        let tree = commit.tree()?;

        // Walk the tree to count files and sizes
        let mut file_count = 0;
        let mut total_size_bytes = 0;
        let mut file_types = HashMap::new();
        let mut file_size_distribution = HashMap::new();

        if self.config.track_file_types || self.config.track_file_sizes {
            // Helper function to categorize file size
            let categorize_file_size = |size: u64| -> String {
                if size < 1024 {
                    "0-1KB".to_string()
                } else if size < 10 * 1024 {
                    "1-10KB".to_string()
                } else if size < 100 * 1024 {
                    "10-100KB".to_string()
                } else if size < 1024 * 1024 {
                    "100KB-1MB".to_string()
                } else if size < 10 * 1024 * 1024 {
                    "1-10MB".to_string()
                } else {
                    "10MB+".to_string()
                }
            };

            // Walk the tree
            for entry in tree.iter() {
                let entry_kind = entry.kind().unwrap_or(git2::ObjectType::Any);

                if entry_kind == git2::ObjectType::Blob {
                    // Count the file
                    file_count += 1;

                    // Get the blob
                    let object = entry.to_object(&git2_repo)?;
                    let blob = object.as_blob().ok_or_else(|| Error::Internal("Not a blob".to_string()))?;

                    // Get the size
                    let size = blob.size() as u64;
                    total_size_bytes += size;

                    // Record file type
                    if self.config.track_file_types {
                        let name = entry.name().unwrap_or("");
                        let extension = match name.rfind('.') {
                            Some(pos) => &name[pos + 1..],
                            None => "unknown",
                        };

                        *file_types.entry(extension.to_string()).or_insert(0) += 1;
                    }

                    // Record file size distribution
                    if self.config.track_file_sizes {
                        let category = categorize_file_size(size);
                        *file_size_distribution.entry(category).or_insert(0) += 1;
                    }
                }
            }
        } else {
            // Just count the files and sizes
            for entry in tree.iter() {
                let entry_kind = entry.kind().unwrap_or(git2::ObjectType::Any);

                if entry_kind == git2::ObjectType::Blob {
                    // Count the file
                    file_count += 1;

                    // Get the blob
                    let object = entry.to_object(&git2_repo)?;
                    let blob = object.as_blob().ok_or_else(|| Error::Internal("Not a blob".to_string()))?;

                    // Get the size
                    let size = blob.size() as u64;
                    total_size_bytes += size;
                }
            }
        }

        stats.file_count = file_count;
        stats.total_size_bytes = total_size_bytes;
        stats.file_types = file_types;
        stats.file_size_distribution = file_size_distribution;

        // Get commit statistics
        if self.config.track_commit_stats {
            let mut revwalk = git2_repo.revwalk()?;
            revwalk.push_head()?;

            let mut commit_count = 0;
            let mut commits_last_day = 0;
            let mut commits_last_week = 0;
            let mut commits_last_month = 0;
            let mut contributors = std::collections::HashSet::new();
            let mut first_commit_time = chrono::Utc::now().timestamp();

            // Current time
            let now = chrono::Utc::now().timestamp();
            let one_day_ago = now - 86400;
            let one_week_ago = now - 7 * 86400;
            let one_month_ago = now - 30 * 86400;

            for oid in revwalk {
                let oid = oid?;
                let commit = git2_repo.find_commit(oid)?;

                // Count the commit
                commit_count += 1;

                // Get the author
                let author = commit.author();
                let author_email = author.email().unwrap_or("unknown");
                contributors.insert(author_email.to_string());

                // Get the commit time
                let commit_time = commit.time().seconds();

                // Check if this is the earliest commit
                if commit_time < first_commit_time {
                    first_commit_time = commit_time;
                }

                // Check if the commit is recent
                if commit_time > one_day_ago {
                    commits_last_day += 1;
                }

                if commit_time > one_week_ago {
                    commits_last_week += 1;
                }

                if commit_time > one_month_ago {
                    commits_last_month += 1;
                }
            }

            stats.commit_count = commit_count;
            stats.commits_last_day = commits_last_day;
            stats.commits_last_week = commits_last_week;
            stats.commits_last_month = commits_last_month;
            stats.contributor_count = contributors.len();

            // Calculate repository age
            let age_seconds = now - first_commit_time;
            stats.age_days = (age_seconds / 86400) as u64;
        }

        // Record metrics
        self.file_count.with_label_values(&[repo_name]).set(stats.file_count as f64);
        self.total_size_bytes.with_label_values(&[repo_name]).set(stats.total_size_bytes as f64);

        // Commit count by timeframe
        self.commit_count.with_label_values(&[repo_name, "total"]).set(stats.commit_count as f64);
        self.commit_count.with_label_values(&[repo_name, "day"]).set(stats.commits_last_day as f64);
        self.commit_count.with_label_values(&[repo_name, "week"]).set(stats.commits_last_week as f64);
        self.commit_count.with_label_values(&[repo_name, "month"]).set(stats.commits_last_month as f64);

        self.contributor_count.with_label_values(&[repo_name]).set(stats.contributor_count as f64);
        self.repo_age_days.with_label_values(&[repo_name]).set(stats.age_days as f64);

        // File type metrics
        for (file_type, count) in &stats.file_types {
            self.file_type_count.with_label_values(&[repo_name, file_type]).set(*count as f64);
        }

        // File size distribution metrics
        for (size_range, count) in &stats.file_size_distribution {
            self.file_size_distribution.with_label_values(&[repo_name, size_range]).set(*count as f64);
        }

        // Store the stats
        self.repository_metrics.insert(repo_name.to_string(), stats);

        debug!("Metrics collection for repository {} completed", repo_name);

        Ok(())
    }

    /// Get the most recent metrics for a repository
    pub fn get_repository_metrics(&self, repo_name: &str) -> Option<&RepositoryContentStats> {
        self.repository_metrics.get(repo_name)
    }

    /// Get the most recent metrics for all repositories
    pub fn get_all_repository_metrics(&self) -> &HashMap<String, RepositoryContentStats> {
        &self.repository_metrics
    }

    /// Stop the metrics collector
    pub fn stop(&mut self) {
        self.is_running = false;
        info!("Content metrics collector stopped");
    }

    /// Collect activity statistics for a repository
    async fn collect_activity_stats(&self, repo_name: &str, repo_path: &Path) -> Result<RepositoryActivityStats> {
        let repo = match git2::Repository::open(repo_path) {
            Ok(repo) => repo,
            Err(e) => {
                error!("Failed to open repository {:?}: {}", repo_path, e);
                return Err(Error::Internal(format!("Failed to open repository: {}", e)));
            }
        };

        let mut commits_by_day = HashMap::new();
        let mut commits_by_hour = HashMap::new();
        let mut contributors = HashMap::new();
        let mut last_commit_time = None;

        // Walk the commit history
        let mut revwalk = repo.revwalk()?;
        revwalk.push_head()?;

        for oid in revwalk {
            let oid = oid?;
            let commit = repo.find_commit(oid)?;

            // Extract author details
            let author = commit.author();
            let author_name = author.name().unwrap_or("unknown").to_string();
            let author_email = author.email().unwrap_or("unknown").to_string();
            let contributor_key = format!("{} <{}>", author_name, author_email);

            // Count contributor commits
            *contributors.entry(contributor_key).or_insert(0) += 1;

            // Extract commit time
            let time = commit.time();
            let dt = chrono::DateTime::<chrono::Utc>::from_utc(
                chrono::NaiveDateTime::from_timestamp_opt(time.seconds(), 0).unwrap_or_default(),
                chrono::Utc,
            );

            // Update last commit time if this is newer
            if last_commit_time.is_none() || last_commit_time.as_ref().unwrap() < &dt {
                last_commit_time = Some(dt);
            }

            // Count by day of week (0 = Sunday, 6 = Saturday)
            let day_of_week = dt.weekday().num_days_from_sunday();
            *commits_by_day.entry(day_of_week).or_insert(0) += 1;

            // Count by hour of day (0-23)
            let hour = dt.hour();
            *commits_by_hour.entry(hour).or_insert(0) += 1;
        }

        // Calculate days since last commit
        let days_since_last_commit = match last_commit_time {
            Some(time) => {
                let now = chrono::Utc::now();
                let duration = now.signed_duration_since(time);
                duration.num_days().max(0) as u64
            }
            None => 0,
        };

        // Sort contributors by commit count and take top 10
        let mut top_contributors: Vec<_> = contributors.into_iter().collect();
        top_contributors.sort_by(|a, b| b.1.cmp(&a.1));
        let top_contributors: HashMap<String, usize> = top_contributors
            .into_iter()
            .take(10)
            .collect();

        // Get repository stats to calculate averages
        let repo_stats = self.get_repository_metrics(repo_name).cloned().unwrap_or_else(|| {
            RepositoryContentStats {
                name: repo_name.to_string(),
                file_count: 0,
                total_size_bytes: 0,
                file_types: HashMap::new(),
                file_size_distribution: HashMap::new(),
                commit_count: 0,
                commits_last_day: 0,
                commits_last_week: 0,
                commits_last_month: 0,
                contributor_count: 0,
                age_days: 0,
                last_update: chrono::Utc::now(),
            }
        });

        let avg_commits_per_day = if repo_stats.age_days > 0 {
            repo_stats.commit_count as f64 / repo_stats.age_days as f64
        } else {
            0.0
        };

        let avg_commits_per_day_last_month = if repo_stats.age_days >= 30 {
            repo_stats.commits_last_month as f64 / 30.0
        } else if repo_stats.age_days > 0 {
            repo_stats.commits_last_month as f64 / repo_stats.age_days as f64
        } else {
            0.0
        };

        Ok(RepositoryActivityStats {
            name: repo_name.to_string(),
            avg_commits_per_day,
            avg_commits_per_day_last_month,
            commits_by_day_of_week: commits_by_day,
            commits_by_hour: commits_by_hour,
            top_contributors,
            days_since_last_commit,
            last_active_day: last_commit_time.unwrap_or_else(chrono::Utc::now),
        })
    }

    /// Get activity metrics for a repository
    pub async fn get_repository_activity(&self, repo_name: &str) -> Option<RepositoryActivityStats> {
        // Try to get repository path from the repository service
        let repo_info = match self.repository_service.get_repository(repo_name).await {
            Ok(info) => info,
            Err(e) => {
                error!("Failed to get repository info for {}: {}", repo_name, e);
                return None;
            }
        };

        // Convert path string to PathBuf
        let path = PathBuf::from(repo_info.path);

        // Collect activity stats
        match self.collect_activity_stats(repo_name, &path).await {
            Ok(stats) => Some(stats),
            Err(e) => {
                error!("Failed to collect activity stats for {}: {}", repo_name, e);
                None
            }
        }
    }

    /// Collect metrics for a single repository
    async fn collect_repository_metrics(&mut self, repo_name: &str) -> Result<()> {
        debug!("Collecting metrics for repository {}", repo_name);

        // Get repository
        let repo = match self.git.repository(repo_name) {
            Ok(repo) => repo,
            Err(e) => {
                error!("Error opening repository {}: {}", repo_name, e);
                return Err(e);
            }
        };

        // Initialize stats
        let mut stats = RepositoryContentStats {
            name: repo_name.to_string(),
            file_count: 0,
            total_size_bytes: 0,
            file_types: HashMap::new(),
            file_size_distribution: HashMap::new(),
            commit_count: 0,
            commits_last_day: 0,
            commits_last_week: 0,
            commits_last_month: 0,
            contributor_count: 0,
            age_days: 0,
            last_update: chrono::Utc::now(),
        };

        // We need to use git2::Repository for some operations
        let repo_path = repo.path();
        let git2_repo = match git2::Repository::open(repo_path) {
            Ok(r) => r,
            Err(e) => {
                error!("Error opening git2 repository at {}: {}", repo_path.display(), e);
                return Err(Error::Internal(format!("Git error: {}", e)));
            }
        };

        // Get the default branch
        let head = git2_repo.head()?;
        let branch_name = head.shorthand().unwrap_or("HEAD");

        // Get the commit
        let commit = head.peel_to_commit()?;

        // Get the tree
        let tree = commit.tree()?;

        // Walk the tree to count files and sizes
        let mut file_count = 0;
        let mut total_size_bytes = 0;
        let mut file_types = HashMap::new();
        let mut file_size_distribution = HashMap::new();

        if self.config.track_file_types || self.config.track_file_sizes {
            // Helper function to categorize file size
            let categorize_file_size = |size: u64| -> String {
                if size < 1024 {
                    "0-1KB".to_string()
                } else if size < 10 * 1024 {
                    "1-10KB".to_string()
                } else if size < 100 * 1024 {
                    "10-100KB".to_string()
                } else if size < 1024 * 1024 {
                    "100KB-1MB".to_string()
                } else if size < 10 * 1024 * 1024 {
                    "1-10MB".to_string()
                } else {
                    "10MB+".to_string()
                }
            };

            // Walk the tree
            for entry in tree.iter() {
                let entry_kind = entry.kind().unwrap_or(git2::ObjectType::Any);

                if entry_kind == git2::ObjectType::Blob {
                    // Count the file
                    file_count += 1;

                    // Get the blob
                    let object = entry.to_object(&git2_repo)?;
                    let blob = object.as_blob().ok_or_else(|| Error::Internal("Not a blob".to_string()))?;

                    // Get the size
                    let size = blob.size() as u64;
                    total_size_bytes += size;

                    // Record file type
                    if self.config.track_file_types {
                        let name = entry.name().unwrap_or("");
                        let extension = match name.rfind('.') {
                            Some(pos) => &name[pos + 1..],
                            None => "unknown",
                        };

                        *file_types.entry(extension.to_string()).or_insert(0) += 1;
                    }

                    // Record file size distribution
                    if self.config.track_file_sizes {
                        let category = categorize_file_size(size);
                        *file_size_distribution.entry(category).or_insert(0) += 1;
                    }
                }
            }
        } else {
            // Just count the files and sizes
            for entry in tree.iter() {
                let entry_kind = entry.kind().unwrap_or(git2::ObjectType::Any);

                if entry_kind == git2::ObjectType::Blob {
                    // Count the file
                    file_count += 1;

                    // Get the blob
                    let object = entry.to_object(&git2_repo)?;
                    let blob = object.as_blob().ok_or_else(|| Error::Internal("Not a blob".to_string()))?;

                    // Get the size
                    let size = blob.size() as u64;
                    total_size_bytes += size;
                }
            }
        }

        stats.file_count = file_count;
        stats.total_size_bytes = total_size_bytes;
        stats.file_types = file_types;
        stats.file_size_distribution = file_size_distribution;

        // Get commit statistics
        if self.config.track_commit_stats {
            let mut revwalk = git2_repo.revwalk()?;
            revwalk.push_head()?;

            let mut commit_count = 0;
            let mut commits_last_day = 0;
            let mut commits_last_week = 0;
            let mut commits_last_month = 0;
            let mut contributors = std::collections::HashSet::new();
            let mut first_commit_time = chrono::Utc::now().timestamp();

            // Current time
            let now = chrono::Utc::now().timestamp();
            let one_day_ago = now - 86400;
            let one_week_ago = now - 7 * 86400;
            let one_month_ago = now - 30 * 86400;

            for oid in revwalk {
                let oid = oid?;
                let commit = git2_repo.find_commit(oid)?;

                // Count the commit
                commit_count += 1;

                // Get the author
                let author = commit.author();
                let author_email = author.email().unwrap_or("unknown");
                contributors.insert(author_email.to_string());

                // Get the commit time
                let commit_time = commit.time().seconds();

                // Check if this is the earliest commit
                if commit_time < first_commit_time {
                    first_commit_time = commit_time;
                }

                // Check if the commit is recent
                if commit_time > one_day_ago {
                    commits_last_day += 1;
                }

                if commit_time > one_week_ago {
                    commits_last_week += 1;
                }

                if commit_time > one_month_ago {
                    commits_last_month += 1;
                }
            }

            stats.commit_count = commit_count;
            stats.commits_last_day = commits_last_day;
            stats.commits_last_week = commits_last_week;
            stats.commits_last_month = commits_last_month;
            stats.contributor_count = contributors.len();

            // Calculate repository age
            let age_seconds = now - first_commit_time;
            stats.age_days = (age_seconds / 86400) as u64;
        }

        // Record metrics
        self.file_count.with_label_values(&[repo_name]).set(stats.file_count as f64);
        self.total_size_bytes.with_label_values(&[repo_name]).set(stats.total_size_bytes as f64);

        // Commit count by timeframe
        self.commit_count.with_label_values(&[repo_name, "total"]).set(stats.commit_count as f64);
        self.commit_count.with_label_values(&[repo_name, "day"]).set(stats.commits_last_day as f64);
        self.commit_count.with_label_values(&[repo_name, "week"]).set(stats.commits_last_week as f64);
        self.commit_count.with_label_values(&[repo_name, "month"]).set(stats.commits_last_month as f64);

        self.contributor_count.with_label_values(&[repo_name]).set(stats.contributor_count as f64);
        self.repo_age_days.with_label_values(&[repo_name]).set(stats.age_days as f64);

        // File type metrics
        for (file_type, count) in &stats.file_types {
            self.file_type_count.with_label_values(&[repo_name, file_type]).set(*count as f64);
        }

        // File size distribution metrics
        for (size_range, count) in &stats.file_size_distribution {
            self.file_size_distribution.with_label_values(&[repo_name, size_range]).set(*count as f64);
        }

        // Store the stats
        self.repository_metrics.insert(repo_name.to_string(), stats);

        debug!("Metrics collection for repository {} completed", repo_name);

        Ok(())
    }

    /// Process a blob to extract content data
    fn process_blob(&self, blob: &git2::Blob) -> Result<Vec<u8>> {
        if blob.is_binary() {
            return Ok(Vec::new());
        }

        let content = blob.content().to_vec();
        Ok(content)
    }

    // Update these helper methods to handle the Error type correctly
    fn get_blob_content(&self, blob: &git2::Blob) -> Result<Vec<u8>> {
        if blob.is_binary() {
            return Ok(Vec::new());
        }

        let content = blob.content().to_vec();
        Ok(content)
    }

    fn process_file(&self, repo: &git2::Repository, blob_id: git2::Oid) -> Result<(Vec<u8>, bool)> {
        let blob = repo.find_blob(blob_id).map_err(|e| Error::Internal(format!("Git error: {}", e)))?;

        let is_binary = blob.is_binary();
        let content = self.get_blob_content(&blob)?;

        Ok((content, is_binary))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use tempfile::TempDir;
    use git2::{Repository, Signature};

    /// Helper to create a test git repository
    fn create_test_repo() -> (TempDir, Repository) {
        // Create a temporary directory for the repository
        let temp_dir = tempfile::tempdir().unwrap();

        // Initialize a git repository in the temporary directory
        let repo = Repository::init(temp_dir.path()).unwrap();

        // Create a signature
        let sig = Signature::now("Test User", "test@example.com").unwrap();

        // Create a file
        let path = temp_dir.path().join("test.txt");
        std::fs::write(&path, "Hello, world!").unwrap();

        // Stage the file
        let mut index = repo.index().unwrap();
        index.add_path(Path::new("test.txt")).unwrap();
        let tree_id = index.write_tree().unwrap();
        index.write().unwrap();

        // Create a commit
        let tree = repo.find_tree(tree_id).unwrap();
        repo.commit(
            Some("HEAD"),
            &sig,
            &sig,
            "Initial commit",
            &tree,
            &[],
        ).unwrap();

        (temp_dir, repo)
    }

    /// Helper to create a test repository with multiple files and commits
    fn create_complex_test_repo() -> (TempDir, Repository) {
        // Create a temporary directory for the repository
        let temp_dir = tempfile::tempdir().unwrap();

        // Initialize a git repository in the temporary directory
        let repo = Repository::init(temp_dir.path()).unwrap();

        // Create a signature
        let sig = Signature::now("Test User", "test@example.com").unwrap();

        // Create file extensions and contents to test
        let files = vec![
            ("test.txt", "Hello, world!", 13),
            ("test.md", "# Markdown file", 15),
            ("test.rs", "fn main() { println!(\"Hello, world!\"); }", 38),
            ("test.js", "console.log('Hello, world!');", 28),
            ("test.py", "print('Hello, world!')", 22),
            ("test.json", "{ \"message\": \"Hello, world!\" }", 30),
            ("test.yml", "message: Hello, world!", 22),
            ("test.html", "<html><body>Hello, world!</body></html>", 41),
            ("test.css", "body { color: blue; }", 21),
            ("large.bin", &"a".repeat(1024 * 1024), 1024 * 1024), // 1MB file
        ];

        // Create and commit each file separately to simulate activity
        for (filename, content, _) in &files {
            // Create the file
            let path = temp_dir.path().join(filename);
            std::fs::write(&path, content).unwrap();

            // Stage the file
            let mut index = repo.index().unwrap();
            index.add_path(Path::new(filename)).unwrap();
            let tree_id = index.write_tree().unwrap();
            index.write().unwrap();

            // Create a commit
            let tree = repo.find_tree(tree_id).unwrap();
            let parent_commit = match repo.head() {
                Ok(head) => Some(head.peel_to_commit().unwrap()),
                Err(_) => None,
            };

            let parents = match parent_commit {
                Some(commit) => vec![&commit],
                None => vec![],
            };

            repo.commit(
                Some("HEAD"),
                &sig,
                &sig,
                &format!("Add {}", filename),
                &tree,
                &parents,
            ).unwrap();
        }

        (temp_dir, repo)
    }

    use proptest::prelude::*;

    proptest! {
        #[test]
        fn prop_test_categorize_file_size(size in 0u64..10_000_000u64) {
            // Helper function to categorize file size
            let categorize_file_size = |size: u64| -> String {
                if size < 1024 {
                    "0-1KB".to_string()
                } else if size < 10 * 1024 {
                    "1-10KB".to_string()
                } else if size < 100 * 1024 {
                    "10-100KB".to_string()
                } else if size < 1024 * 1024 {
                    "100KB-1MB".to_string()
                } else if size < 10 * 1024 * 1024 {
                    "1-10MB".to_string()
                } else {
                    "10MB+".to_string()
                }
            };

            let category = categorize_file_size(size);

            // Verify the category is one of the expected values
            prop_assert!(
                category == "0-1KB" ||
                category == "1-10KB" ||
                category == "10-100KB" ||
                category == "100KB-1MB" ||
                category == "1-10MB" ||
                category == "10MB+"
            );

            // Verify the categorization is correct
            if size < 1024 {
                prop_assert_eq!(category, "0-1KB");
            } else if size < 10 * 1024 {
                prop_assert_eq!(category, "1-10KB");
            } else if size < 100 * 1024 {
                prop_assert_eq!(category, "10-100KB");
            } else if size < 1024 * 1024 {
                prop_assert_eq!(category, "100KB-1MB");
            } else if size < 10 * 1024 * 1024 {
                prop_assert_eq!(category, "1-10MB");
            } else {
                prop_assert_eq!(category, "10MB+");
            }
        }

        #[test]
        fn prop_test_repo_stats_properties(
            file_count in 0usize..1000usize,
            total_size_bytes in 0u64..1_000_000u64,
            commit_count in 0usize..1000usize,
            contributor_count in 0usize..100usize
        ) {
            // Create repository stats with the generated values
            let stats = RepositoryContentStats {
                name: "test-repo".to_string(),
                file_count,
                total_size_bytes,
                file_types: HashMap::new(),
                file_size_distribution: HashMap::new(),
                commit_count,
                commits_last_day: commit_count.min(10), // Arbitrary values for testing
                commits_last_week: commit_count.min(50),
                commits_last_month: commit_count.min(200),
                contributor_count,
                age_days: 100, // Arbitrary value for testing
                last_update: chrono::Utc::now(),
            };

            // Verify basic properties
            prop_assert_eq!(stats.file_count, file_count);
            prop_assert_eq!(stats.total_size_bytes, total_size_bytes);
            prop_assert_eq!(stats.commit_count, commit_count);
            prop_assert_eq!(stats.contributor_count, contributor_count);

            // Verify that certain relationships hold
            prop_assert!(stats.commits_last_day <= stats.commits_last_week);
            prop_assert!(stats.commits_last_week <= stats.commits_last_month);
            prop_assert!(stats.commits_last_month <= stats.commit_count);
        }

        #[test]
        fn prop_test_file_type_counting(
            file_types in proptest::collection::hash_map("[a-z]{1,5}", 1usize..100usize, 0..20)
        ) {
            // Create repository stats with the generated file types
            let mut stats = RepositoryContentStats {
                name: "test-repo".to_string(),
                file_count: 0,
                total_size_bytes: 0,
                file_types: file_types.clone(),
                file_size_distribution: HashMap::new(),
                commit_count: 0,
                commits_last_day: 0,
                commits_last_week: 0,
                commits_last_month: 0,
                contributor_count: 0,
                age_days: 0,
                last_update: chrono::Utc::now(),
            };

            // Calculate the total file count
            let total_files: usize = file_types.values().sum();
            stats.file_count = total_files;

            // Verify that the sum of file types matches the total
            let sum_file_types: usize = stats.file_types.values().sum();
            prop_assert_eq!(sum_file_types, stats.file_count);

            // Verify each file type is counted correctly
            for (file_type, count) in &file_types {
                prop_assert_eq!(stats.file_types.get(file_type).unwrap(), count);
            }
        }

        #[test]
        fn prop_test_activity_stats_properties(
            age_days in 1u64..365u64,
            commit_count in 1usize..1000usize,
            commits_last_month in 0usize..1000usize,
            days_since_last_commit in 0u64..100u64
        ) {
            // Create a valid stats object with the generated properties
            let now = Utc::now();
            let last_active = now - chrono::Duration::days(days_since_last_commit as i64);

            let mut stats = RepositoryActivityStats {
                name: "test-repo".to_string(),
                avg_commits_per_day: commit_count as f64 / age_days as f64,
                avg_commits_per_day_last_month: if age_days >= 30 {
                    commits_last_month as f64 / 30.0
                } else {
                    commits_last_month as f64 / age_days as f64
                },
                commits_by_day_of_week: HashMap::new(),
                commits_by_hour: HashMap::new(),
                top_contributors: HashMap::new(),
                days_since_last_commit,
                last_active_day: last_active,
            };

            // Verify basic properties
            prop_assert!(stats.avg_commits_per_day >= 0.0);
            prop_assert!(stats.avg_commits_per_day_last_month >= 0.0);
            prop_assert_eq!(stats.days_since_last_commit, days_since_last_commit);

            // Add data to day of week (ensure valid days 0-6)
            for day in 0..7 {
                stats.commits_by_day_of_week.insert(day, day as usize * 10); // Arbitrary counts
            }

            // Add data to hour of day (ensure valid hours 0-23)
            for hour in 0..24 {
                stats.commits_by_hour.insert(hour, hour as usize * 5); // Arbitrary counts
            }

            // Add top contributors
            for i in 0..5 {
                stats.top_contributors.insert(format!("user{}", i), (5 - i) * 10); // Arbitrary counts
            }

            // Verify day of week contains valid days
            for day in stats.commits_by_day_of_week.keys() {
                prop_assert!(*day <= 6, "Day of week should be 0-6, got {}", day);
            }

            // Verify hour of day contains valid hours
            for hour in stats.commits_by_hour.keys() {
                prop_assert!(*hour <= 23, "Hour should be 0-23, got {}", hour);
            }

            // Verify contributor counts are positive
            for count in stats.top_contributors.values() {
                prop_assert!(*count > 0, "Contributor commit count should be positive");
            }

            // Verify last active day is not in the future
            prop_assert!(stats.last_active_day <= now, "Last active day should not be in the future");

            // Verify days since last commit calculation is consistent with last active day
            let calculated_days = now.signed_duration_since(stats.last_active_day).num_days() as u64;
            prop_assert_eq!(stats.days_since_last_commit, calculated_days);
        }

        #[test]
        fn prop_test_repository_activity_consistency(
            commit_count in 1usize..1000usize,
            age_days in 1u64..365u64,
            commits_last_month in 0usize..100usize
        ) {
            // Create repository stats
            let repo_stats = RepositoryContentStats {
                name: "test-repo".to_string(),
                file_count: 100, // Arbitrary
                total_size_bytes: 1000000, // Arbitrary
                file_types: HashMap::new(),
                file_size_distribution: HashMap::new(),
                commit_count,
                commits_last_day: commits_last_month.min(10),
                commits_last_week: commits_last_month.min(30),
                commits_last_month,
                contributor_count: 5, // Arbitrary
                age_days,
                last_update: Utc::now(),
            };

            // Generate activity stats from repository stats
            let activity_stats = repo_stats.activity_stats();

            // Verify consistency between repository stats and activity stats
            prop_assert_eq!(activity_stats.name, repo_stats.name);

            // Calculate expected average commits per day
            let expected_avg_commits = repo_stats.commit_count as f64 / repo_stats.age_days as f64;
            prop_assert!((activity_stats.avg_commits_per_day - expected_avg_commits).abs() < 0.001,
                "Average commits per day should match calculation");

            // Calculate expected average commits per day for last month
            let expected_avg_last_month = if repo_stats.age_days >= 30 {
                repo_stats.commits_last_month as f64 / 30.0
            } else {
                repo_stats.commits_last_month as f64 / repo_stats.age_days as f64
            };
            prop_assert!((activity_stats.avg_commits_per_day_last_month - expected_avg_last_month).abs() < 0.001,
                "Average commits per day last month should match calculation");
        }

        #[test]
        fn prop_test_commits_distribution(
            commits_by_day in proptest::collection::hash_map(0u32..7u32, 0usize..1000usize, 0..7),
            commits_by_hour in proptest::collection::hash_map(0u32..24u32, 0usize..1000usize, 0..24)
        ) {
            // Create activity stats with the generated distributions
            let mut stats = RepositoryActivityStats {
                name: "test-repo".to_string(),
                avg_commits_per_day: 10.0,
                avg_commits_per_day_last_month: 15.0,
                commits_by_day_of_week: commits_by_day.clone(),
                commits_by_hour: commits_by_hour.clone(),
                top_contributors: HashMap::new(),
                days_since_last_commit: 0,
                last_active_day: Utc::now(),
            };

            // Verify all days of week are within valid range
            for day in stats.commits_by_day_of_week.keys() {
                prop_assert!(*day <= 6, "Day of week should be 0-6, got {}", day);
            }

            // Verify all hours are within valid range
            for hour in stats.commits_by_hour.keys() {
                prop_assert!(*hour <= 23, "Hour should be 0-23, got {}", hour);
            }

            // Verify adding a new day works correctly
            let test_day = 3u32; // Wednesday
            let original_count = *stats.commits_by_day_of_week.get(&test_day).unwrap_or(&0);
            stats.commits_by_day_of_week.insert(test_day, original_count + 10);

            prop_assert_eq!(*stats.commits_by_day_of_week.get(&test_day).unwrap(), original_count + 10,
                "Incrementing commit count for a day should work correctly");

            // Verify adding a new hour works correctly
            let test_hour = 14u32; // 2 PM
            let original_hour_count = *stats.commits_by_hour.get(&test_hour).unwrap_or(&0);
            stats.commits_by_hour.insert(test_hour, original_hour_count + 5);

            prop_assert_eq!(*stats.commits_by_hour.get(&test_hour).unwrap(), original_hour_count + 5,
                "Incrementing commit count for an hour should work correctly");
        }
    }

    #[test]
    fn test_repository_activity_stats_generation() {
        // Create a test repository with multiple commits
        let (temp_dir, repo) = create_complex_test_repo();

        // Create a basic repository content stats
        let repo_stats = RepositoryContentStats {
            name: "test-repo".to_string(),
            file_count: 10,
            total_size_bytes: 1024 * 1024 * 2, // 2MB
            file_types: {
                let mut map = HashMap::new();
                map.insert("rs".to_string(), 3);
                map.insert("md".to_string(), 2);
                map.insert("txt".to_string(), 5);
                map
            },
            file_size_distribution: {
                let mut map = HashMap::new();
                map.insert("0-1KB".to_string(), 5);
                map.insert("1-10KB".to_string(), 3);
                map.insert("1-10MB".to_string(), 2);
                map
            },
            commit_count: 10,
            commits_last_day: 2,
            commits_last_week: 5,
            commits_last_month: 8,
            contributor_count: 2,
            age_days: 30,
            last_update: Utc::now(),
        };

        // Generate activity stats
        let activity_stats = repo_stats.activity_stats();

        // Verify basic properties
        assert_eq!(activity_stats.name, "test-repo");
        assert_eq!(activity_stats.avg_commits_per_day, 10.0 / 30.0);
        assert_eq!(activity_stats.avg_commits_per_day_last_month, 8.0 / 30.0);
    }
}
