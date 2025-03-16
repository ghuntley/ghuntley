// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Repository API handlers
//!
//! This module provides API handlers for repository-related operations.

use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, warn};

use crate::error::{Error, Result};
use crate::service::repository::{RepositoryService, RepositoryStats, ContributorStats};
use crate::service::observability::metrics;

/// Repository API handler
pub struct RepositoryApiHandler;

/// Query parameters for repository list endpoint
#[derive(Debug, Deserialize)]
pub struct RepositoryListParams {
    /// Sort order (name, updated, size)
    pub sort: Option<String>,

    /// Sort direction (asc, desc)
    pub direction: Option<String>,

    /// Filter by name
    pub filter: Option<String>,

    /// Maximum number of repositories to return
    pub limit: Option<usize>,

    /// Page number (0-based)
    pub page: Option<usize>,
}

/// Query parameters for repository statistics endpoint
#[derive(Debug, Deserialize)]
pub struct RepositoryStatsParams {
    /// Whether to force a refresh of statistics
    pub refresh: Option<bool>,

    /// Whether to include contributor statistics
    pub include_contributors: Option<bool>,

    /// Whether to include file statistics
    pub include_files: Option<bool>,
}

/// Repository statistics response
#[derive(Debug, Serialize)]
pub struct RepositoryStatsResponse {
    /// Repository name
    pub name: String,

    /// Repository description
    pub description: Option<String>,

    /// File statistics
    pub files: FileStats,

    /// Commit statistics
    pub commits: CommitStats,

    /// Contributor statistics
    pub contributors: Option<ContributorStatsResponse>,

    /// Last updated timestamp
    pub last_updated: String,
}

/// File statistics
#[derive(Debug, Serialize)]
pub struct FileStats {
    /// Total number of files
    pub count: usize,

    /// Total size of all files in bytes
    pub total_size_bytes: u64,

    /// Formatted total size
    pub total_size_formatted: String,

    /// Breakdown of files by type
    pub by_type: Option<Vec<FileTypeCount>>,

    /// Breakdown of files by size range
    pub by_size: Option<Vec<FileSizeRange>>,
}

/// File type count
#[derive(Debug, Serialize)]
pub struct FileTypeCount {
    /// File extension
    pub extension: String,

    /// Number of files with this extension
    pub count: usize,

    /// Percentage of total files
    pub percentage: f64,
}

/// File size range
#[derive(Debug, Serialize)]
pub struct FileSizeRange {
    /// Size range description
    pub range: String,

    /// Number of files in this size range
    pub count: usize,

    /// Percentage of total files
    pub percentage: f64,
}

/// Commit statistics
#[derive(Debug, Serialize)]
pub struct CommitStats {
    /// Total number of commits
    pub count: usize,

    /// Number of commits in the last day
    pub last_day: usize,

    /// Number of commits in the last week
    pub last_week: usize,

    /// Number of commits in the last month
    pub last_month: usize,

    /// Average commits per day
    pub avg_per_day: f64,

    /// Commits by day of week
    pub by_day_of_week: Option<Vec<DayOfWeekCount>>,

    /// Commits by hour of day
    pub by_hour: Option<Vec<HourCount>>,

    /// Commits by month for the past year
    pub by_month: Option<Vec<MonthCount>>,
}

/// Day of week count
#[derive(Debug, Serialize)]
pub struct DayOfWeekCount {
    /// Day of week (0 = Sunday, 6 = Saturday)
    pub day: u32,

    /// Day name
    pub name: String,

    /// Number of commits on this day
    pub count: usize,

    /// Percentage of total commits
    pub percentage: f64,
}

/// Hour count
#[derive(Debug, Serialize)]
pub struct HourCount {
    /// Hour of day (0-23)
    pub hour: u32,

    /// Number of commits in this hour
    pub count: usize,

    /// Percentage of total commits
    pub percentage: f64,
}

/// Month count
#[derive(Debug, Serialize)]
pub struct MonthCount {
    /// Month name
    pub month: String,

    /// Number of commits in this month
    pub count: usize,

    /// Percentage of total commits
    pub percentage: f64,
}

/// Contributor statistics response
#[derive(Debug, Serialize)]
pub struct ContributorStatsResponse {
    /// Total number of contributors
    pub count: usize,

    /// Top contributors
    pub top: Vec<ContributorInfo>,
}

/// Contributor information
#[derive(Debug, Serialize)]
pub struct ContributorInfo {
    /// Contributor name
    pub name: String,

    /// Contributor email
    pub email: String,

    /// Number of commits
    pub commit_count: usize,

    /// Percentage of total commits
    pub percentage: f64,

    /// First commit timestamp
    pub first_commit: String,

    /// Last commit timestamp
    pub last_commit: String,

    /// Days active
    pub days_active: u64,
}

impl RepositoryApiHandler {
    /// List all repositories
    ///
    /// GET /api/repos
    pub async fn list_repositories(
        State(repository_service): State<Arc<RepositoryService>>,
        Query(params): Query<RepositoryListParams>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["repository", "list"]);

        debug!("Listing repositories");
        let repos = repository_service.list_repositories().await?;

        // Apply filtering if specified
        let mut filtered_repos = if let Some(filter) = &params.filter {
            repos.into_iter()
                .filter(|repo| repo.name.contains(filter))
                .collect::<Vec<_>>()
        } else {
            repos
        };

        // Apply sorting if specified
        if let Some(sort) = &params.sort {
            let direction = params.direction.as_deref().unwrap_or("asc");

            match sort.as_str() {
                "name" => {
                    if direction == "desc" {
                        filtered_repos.sort_by(|a, b| b.name.cmp(&a.name));
                    } else {
                        filtered_repos.sort_by(|a, b| a.name.cmp(&b.name));
                    }
                },
                "updated" => {
                    if direction == "desc" {
                        filtered_repos.sort_by(|a, b| b.last_updated.cmp(&a.last_updated));
                    } else {
                        filtered_repos.sort_by(|a, b| a.last_updated.cmp(&b.last_updated));
                    }
                },
                "commits" => {
                    if direction == "desc" {
                        filtered_repos.sort_by(|a, b| b.commit_count.cmp(&a.commit_count));
                    } else {
                        filtered_repos.sort_by(|a, b| a.commit_count.cmp(&b.commit_count));
                    }
                },
                _ => {}
            }
        }

        // Apply pagination if specified
        let limit = params.limit.unwrap_or(100);
        let page = params.page.unwrap_or(0);
        let start = page * limit;

        let paginated_repos = if start < filtered_repos.len() {
            let end = (start + limit).min(filtered_repos.len());
            filtered_repos[start..end].to_vec()
        } else {
            Vec::new()
        };

        Ok(Json(paginated_repos))
    }

    /// Get repository information
    ///
    /// GET /api/repos/:repo
    pub async fn get_repository(
        State(repository_service): State<Arc<RepositoryService>>,
        Path(repo_name): Path<String>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["repository", "get"]);

        debug!("Getting repository {repo_name}");
        let repo = repository_service.get_repository(&repo_name).await?;

        Ok(Json(repo))
    }

    /// Get repository statistics
    ///
    /// GET /api/repos/:repo/stats
    pub async fn get_repository_stats(
        State(repository_service): State<Arc<RepositoryService>>,
        Path(repo_name): Path<String>,
        Query(params): Query<RepositoryStatsParams>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["repository", "stats"]);

        debug!("Getting statistics for repository {repo_name}");

        // Get repository stats (refreshing if requested)
        let stats = if params.refresh.unwrap_or(false) {
            repository_service.refresh_repository_stats(&repo_name).await?
        } else {
            repository_service.get_repository_stats(&repo_name).await?
        };

        // Convert to response format
        let response = format_repository_stats(
            stats,
            params.include_contributors.unwrap_or(true),
            params.include_files.unwrap_or(true),
        );

        Ok(Json(response))
    }

    /// Get statistics for all repositories
    ///
    /// GET /api/repos/stats
    pub async fn get_all_repository_stats(
        State(repository_service): State<Arc<RepositoryService>>,
        Query(params): Query<RepositoryStatsParams>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["repository", "all_stats"]);

        debug!("Getting statistics for all repositories");

        // Get all repository stats (refreshing if requested)
        let all_stats = if params.refresh.unwrap_or(false) {
            repository_service.refresh_all_stats().await?;
            repository_service.get_all_stats().await?
        } else {
            repository_service.get_all_stats().await?
        };

        // Convert each to response format
        let response: Vec<_> = all_stats.into_iter()
            .map(|stats| format_repository_stats(
                stats,
                params.include_contributors.unwrap_or(true),
                params.include_files.unwrap_or(true),
            ))
            .collect();

        Ok(Json(response))
    }
}

/// Format repository statistics for API response
fn format_repository_stats(
    stats: RepositoryStats,
    include_contributors: bool,
    include_files: bool,
) -> RepositoryStatsResponse {
    // Format file statistics
    let files = FileStats {
        count: stats.file_count,
        total_size_bytes: stats.total_size_bytes,
        total_size_formatted: format_size(stats.total_size_bytes),
        by_type: if include_files {
            let mut by_type: Vec<FileTypeCount> = stats.file_types.iter()
                .map(|(ext, count)| FileTypeCount {
                    extension: ext.clone(),
                    count: *count,
                    percentage: if stats.file_count > 0 {
                        (*count as f64 / stats.file_count as f64) * 100.0
                    } else {
                        0.0
                    },
                })
                .collect();

            // Sort by count (descending)
            by_type.sort_by(|a, b| b.count.cmp(&a.count));

            Some(by_type)
        } else {
            None
        },
        by_size: if include_files {
            let mut by_size: Vec<FileSizeRange> = stats.file_size_distribution.iter()
                .map(|(range, count)| FileSizeRange {
                    range: range.clone(),
                    count: *count,
                    percentage: if stats.file_count > 0 {
                        (*count as f64 / stats.file_count as f64) * 100.0
                    } else {
                        0.0
                    },
                })
                .collect();

            // Sort by range (ascending size)
            by_size.sort_by(|a, b| {
                // Custom sort for size ranges
                let size_order = |s: &str| match s {
                    "0-1KB" => 0,
                    "1KB-10KB" => 1,
                    "10KB-100KB" => 2,
                    "100KB-1MB" => 3,
                    "1MB-10MB" => 4,
                    ">10MB" => 5,
                    _ => 6,
                };

                size_order(&a.range).cmp(&size_order(&b.range))
            });

            Some(by_size)
        } else {
            None
        },
    };

    // Format commit statistics
    let commits = CommitStats {
        count: stats.commit_count,
        last_day: stats.commits_last_day,
        last_week: stats.commits_last_week,
        last_month: stats.commits_last_month,
        avg_per_day: stats.avg_commits_per_day,
        by_day_of_week: Some(format_day_of_week_stats(
            &stats.commits_by_day_of_week,
            stats.commit_count,
        )),
        by_hour: Some(format_hour_stats(
            &stats.commits_by_hour,
            stats.commit_count,
        )),
        by_month: Some(format_month_stats(
            &stats.commit_activity_by_month,
            stats.commit_count,
        )),
    };

    // Format contributor statistics
    let contributors = if include_contributors {
        let mut top_contributors: Vec<ContributorInfo> = stats.top_contributors.iter()
            .map(|contributor| ContributorInfo {
                name: contributor.name.clone(),
                email: contributor.email.clone(),
                commit_count: contributor.commit_count,
                percentage: if stats.commit_count > 0 {
                    (contributor.commit_count as f64 / stats.commit_count as f64) * 100.0
                } else {
                    0.0
                },
                first_commit: contributor.first_commit.to_rfc3339(),
                last_commit: contributor.last_commit.to_rfc3339(),
                days_active: contributor.days_active,
            })
            .collect();

        Some(ContributorStatsResponse {
            count: stats.contributor_count,
            top: top_contributors,
        })
    } else {
        None
    };

    RepositoryStatsResponse {
        name: stats.name,
        description: stats.description,
        files,
        commits,
        contributors,
        last_updated: stats.last_updated.to_rfc3339(),
    }
}

/// Format day of week statistics
fn format_day_of_week_stats(
    day_counts: &std::collections::HashMap<u32, usize>,
    total_commits: usize,
) -> Vec<DayOfWeekCount> {
    let day_names = [
        "Sunday", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday",
    ];

    // Create entries for all days of the week
    let mut result = (0..7).map(|day| {
        let count = *day_counts.get(&day).unwrap_or(&0);

        DayOfWeekCount {
            day,
            name: day_names[day as usize].to_string(),
            count,
            percentage: if total_commits > 0 {
                (count as f64 / total_commits as f64) * 100.0
            } else {
                0.0
            },
        }
    }).collect::<Vec<_>>();

    // Sort by day of week
    result.sort_by_key(|d| d.day);

    result
}

/// Format hour statistics
fn format_hour_stats(
    hour_counts: &std::collections::HashMap<u32, usize>,
    total_commits: usize,
) -> Vec<HourCount> {
    // Create entries for all hours
    let mut result = (0..24).map(|hour| {
        let count = *hour_counts.get(&hour).unwrap_or(&0);

        HourCount {
            hour,
            count,
            percentage: if total_commits > 0 {
                (count as f64 / total_commits as f64) * 100.0
            } else {
                0.0
            },
        }
    }).collect::<Vec<_>>();

    // Sort by hour
    result.sort_by_key(|h| h.hour);

    result
}

/// Format month statistics
fn format_month_stats(
    month_counts: &std::collections::HashMap<String, usize>,
    total_commits: usize,
) -> Vec<MonthCount> {
    let mut result: Vec<MonthCount> = month_counts.iter()
        .map(|(month, count)| MonthCount {
            month: month.clone(),
            count: *count,
            percentage: if total_commits > 0 {
                (*count as f64 / total_commits as f64) * 100.0
            } else {
                0.0
            },
        })
        .collect();

    // Sort by month (chronologically)
    result.sort_by(|a, b| a.month.cmp(&b.month));

    result
}

/// Format size in human-readable form
fn format_size(size_bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if size_bytes < KB {
        format!("{} B", size_bytes)
    } else if size_bytes < MB {
        format!("{:.2} KB", size_bytes as f64 / KB as f64)
    } else if size_bytes < GB {
        format!("{:.2} MB", size_bytes as f64 / MB as f64)
    } else {
        format!("{:.2} GB", size_bytes as f64 / GB as f64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use chrono::TimeZone;

    // Property test for the format_size function
    proptest! {
        #[test]
        fn test_format_size(size in 0u64..10 * 1024 * 1024 * 1024) {
            let formatted = format_size(size);

            if size < 1024 {
                prop_assert!(formatted.ends_with(" B"));
            } else if size < 1024 * 1024 {
                prop_assert!(formatted.ends_with(" KB"));
            } else if size < 1024 * 1024 * 1024 {
                prop_assert!(formatted.ends_with(" MB"));
            } else {
                prop_assert!(formatted.ends_with(" GB"));
            }

            prop_assert!(formatted.split(' ').next().unwrap().parse::<f64>().is_ok());
        }
    }

    // Property test for day of week statistics formatting
    proptest! {
        #[test]
        fn test_format_day_of_week_stats(
            day0 in 0usize..100,
            day1 in 0usize..100,
            day2 in 0usize..100,
            day3 in 0usize..100,
            day4 in 0usize..100,
            day5 in 0usize..100,
            day6 in 0usize..100,
        ) {
            // Create a map of day counts
            let mut day_counts = std::collections::HashMap::new();
            day_counts.insert(0, day0);
            day_counts.insert(1, day1);
            day_counts.insert(2, day2);
            day_counts.insert(3, day3);
            day_counts.insert(4, day4);
            day_counts.insert(5, day5);
            day_counts.insert(6, day6);

            let total_commits = day0 + day1 + day2 + day3 + day4 + day5 + day6;

            let result = format_day_of_week_stats(&day_counts, total_commits);

            // Verify the result
            prop_assert_eq!(result.len(), 7, "Should contain all 7 days");

            // Check that days are in order
            for i in 0..7 {
                prop_assert_eq!(result[i].day, i as u32);
            }

            // Check counts and percentages
            for day in &result {
                let expected_count = *day_counts.get(&day.day).unwrap_or(&0);
                prop_assert_eq!(day.count, expected_count);

                let expected_percentage = if total_commits > 0 {
                    (expected_count as f64 / total_commits as f64) * 100.0
                } else {
                    0.0
                };

                // Allow a small floating point error
                prop_assert!((day.percentage - expected_percentage).abs() < 0.001);
            }

            // Check day names
            prop_assert_eq!(result[0].name, "Sunday");
            prop_assert_eq!(result[1].name, "Monday");
            prop_assert_eq!(result[2].name, "Tuesday");
            prop_assert_eq!(result[3].name, "Wednesday");
            prop_assert_eq!(result[4].name, "Thursday");
            prop_assert_eq!(result[5].name, "Friday");
            prop_assert_eq!(result[6].name, "Saturday");
        }
    }

    // Test format_repository_stats
    #[test]
    fn test_format_repository_stats() {
        // Create a sample repository stats object
        let now = chrono::Utc::now();
        let one_day_ago = now - chrono::Duration::days(1);

        let mut file_types = std::collections::HashMap::new();
        file_types.insert("rs".to_string(), 10);
        file_types.insert("md".to_string(), 5);

        let mut file_size_distribution = std::collections::HashMap::new();
        file_size_distribution.insert("0-1KB".to_string(), 5);
        file_size_distribution.insert("1KB-10KB".to_string(), 10);

        let mut commits_by_day_of_week = std::collections::HashMap::new();
        commits_by_day_of_week.insert(0, 10); // Sunday
        commits_by_day_of_week.insert(1, 20); // Monday

        let mut commits_by_hour = std::collections::HashMap::new();
        commits_by_hour.insert(9, 10); // 9 AM
        commits_by_hour.insert(14, 20); // 2 PM

        let mut commit_activity_by_month = std::collections::HashMap::new();
        commit_activity_by_month.insert("2023-01".to_string(), 10);
        commit_activity_by_month.insert("2023-02".to_string(), 20);

        let contributor = ContributorStats {
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            commit_count: 30,
            first_commit: one_day_ago,
            last_commit: now,
            days_active: 1,
        };

        let stats = RepositoryStats {
            name: "test-repo".to_string(),
            path: "/path/to/repo".to_string(),
            description: Some("Test repository".to_string()),
            file_count: 15,
            total_size_bytes: 15 * 1024,
            file_types,
            file_size_distribution,
            commit_count: 30,
            commits_last_day: 5,
            commits_last_week: 10,
            commits_last_month: 20,
            contributor_count: 1,
            top_contributors: vec![contributor],
            age_days: 10,
            created_at: now - chrono::Duration::days(10),
            last_updated: now,
            avg_commits_per_day: 3.0,
            commits_by_day_of_week,
            commits_by_hour,
            commit_activity_by_month,
            branch_count: 2,
            tag_count: 1,
        };

        // Format stats with everything included
        let response = format_repository_stats(stats.clone(), true, true);

        // Verify basic fields
        assert_eq!(response.name, "test-repo");
        assert_eq!(response.description, Some("Test repository".to_string()));
        assert_eq!(response.files.count, 15);
        assert_eq!(response.files.total_size_bytes, 15 * 1024);
        assert_eq!(response.files.by_type.as_ref().unwrap().len(), 2);
        assert_eq!(response.files.by_size.as_ref().unwrap().len(), 2);
        assert_eq!(response.commits.count, 30);
        assert_eq!(response.commits.last_day, 5);
        assert_eq!(response.commits.last_week, 10);
        assert_eq!(response.commits.last_month, 20);
        assert_eq!(response.commits.avg_per_day, 3.0);
        assert_eq!(response.commits.by_day_of_week.as_ref().unwrap().len(), 7);
        assert_eq!(response.commits.by_hour.as_ref().unwrap().len(), 24);
        assert_eq!(response.commits.by_month.as_ref().unwrap().len(), 2);
        assert_eq!(response.contributors.as_ref().unwrap().count, 1);
        assert_eq!(response.contributors.as_ref().unwrap().top.len(), 1);
        assert_eq!(response.contributors.as_ref().unwrap().top[0].name, "Test User");
        assert_eq!(response.last_updated, now.to_rfc3339());

        // Format stats without contributors
        let response_no_contributors = format_repository_stats(stats.clone(), false, true);
        assert!(response_no_contributors.contributors.is_none());

        // Format stats without file details
        let response_no_files = format_repository_stats(stats.clone(), true, false);
        assert!(response_no_files.files.by_type.is_none());
        assert!(response_no_files.files.by_size.is_none());
    }
}
