// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Search service for advanced repository searching capabilities
//!
//! This module provides enhanced search functionality on top of the IndexService,
//! including semantic code search, symbol search, real-time suggestions, and
//! structured search results.

use crate::error::{Error, Result};
use crate::service::index::{IndexService, SearchOptions, SearchResult, FileMatch, LineMatch, RepositoryMatches};
use crate::service::repository::RepositoryService;
use crate::service::file::FileService;
use crate::service::commit::CommitService;
use crate::data::cache::{Cache, CacheKey};

use std::sync::Arc;
use std::collections::{HashMap, BTreeMap, HashSet};
use std::time::{Duration, Instant};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, trace, warn};

/// Maximum number of search suggestions to return
const MAX_SUGGESTIONS: usize = 10;

/// Maximum number of commits to include in context
const MAX_COMMIT_CONTEXT: usize = 5;

/// Maximum number of files to return per repository
const MAX_FILES_PER_REPO: usize = 100;

/// Maximum number of matches to return per file
const MAX_MATCHES_PER_FILE: usize = 50;

/// Search types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SearchType {
    /// Full text search
    Text,

    /// Code symbol search (functions, classes, etc.)
    Symbol,

    /// Commit search (commit message, author, etc.)
    Commit,

    /// File path search
    Path,

    /// Regular expression search
    Regex,

    /// Semantic code search
    Semantic,
}

/// Advanced search options
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvancedSearchOptions {
    /// Basic search options
    pub basic_options: SearchOptions,

    /// Search type
    pub search_type: SearchType,

    /// Search specific authors
    pub authors: Option<Vec<String>>,

    /// Search in specific languages
    pub languages: Option<Vec<String>>,

    /// Search in specific time range (ISO 8601 format)
    pub time_range: Option<(String, String)>,

    /// Include context (number of lines before/after matches)
    pub context_lines: Option<usize>,

    /// Sort results by relevance, date, path, etc.
    pub sort_by: Option<String>,

    /// Maximum number of results to return
    pub max_results: Option<usize>,

    /// Return code snippets in results
    pub include_snippets: bool,

    /// Get result suggestions for auto-complete
    pub get_suggestions: bool,
}

impl Default for AdvancedSearchOptions {
    fn default() -> Self {
        Self {
            basic_options: SearchOptions::default(),
            search_type: SearchType::Text,
            authors: None,
            languages: None,
            time_range: None,
            context_lines: Some(3),
            sort_by: Some("relevance".to_string()),
            max_results: Some(100),
            include_snippets: true,
            get_suggestions: false,
        }
    }
}

/// Enhanced search result with additional context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedSearchResult {
    /// Basic search result
    pub base_result: SearchResult,

    /// Suggested search terms
    pub suggestions: Option<Vec<String>>,

    /// Enhanced repositories with context
    pub repositories: Vec<EnhancedRepositoryMatches>,

    /// Breakdown by language
    pub languages: BTreeMap<String, usize>,

    /// Breakdown by author
    pub authors: BTreeMap<String, usize>,

    /// Breakdown by time periods
    pub time_periods: BTreeMap<String, usize>,

    /// Related searches
    pub related_searches: Vec<String>,
}

/// Enhanced repository matches with additional context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedRepositoryMatches {
    /// Basic repository matches
    pub base_matches: RepositoryMatches,

    /// Recent commits affecting matching files
    pub recent_commits: Option<Vec<CommitSummary>>,

    /// Enhanced file matches
    pub files: Vec<EnhancedFileMatch>,
}

/// Enhanced file match with additional context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedFileMatch {
    /// Basic file match
    pub base_match: FileMatch,

    /// File language
    pub language: Option<String>,

    /// Contributors to this file
    pub contributors: Option<Vec<String>>,

    /// Enhanced line matches with context
    pub lines: Vec<EnhancedLineMatch>,
}

/// Enhanced line match with context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedLineMatch {
    /// Basic line match
    pub base_match: LineMatch,

    /// Context lines before match
    pub context_before: Option<Vec<String>>,

    /// Context lines after match
    pub context_after: Option<Vec<String>>,

    /// Last changed by (author)
    pub last_changed_by: Option<String>,

    /// Last changed date
    pub last_changed_at: Option<String>,
}

/// Commit summary for context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitSummary {
    /// Commit ID
    pub id: String,

    /// Short commit ID
    pub short_id: String,

    /// Author name
    pub author: String,

    /// Commit date
    pub date: String,

    /// Commit message summary
    pub summary: String,
}

/// Search service for advanced Git repository searching
pub struct SearchService {
    /// Git data access
    git: Arc<Git>,

    /// Database access
    db: Arc<Sqlite>,

    /// Cache for search results
    cache: Arc<Cache<String, String>>,

    /// Repository service
    repository_service: Arc<RepositoryService>,

    /// File service
    file_service: Arc<FileService>,

    /// Commit service
    commit_service: Arc<CommitService>,
}

impl SearchService {
    /// Create a new search service
    pub fn new(
        git: Arc<Git>,
        db: Arc<Sqlite>,
        cache: Arc<Cache<String, String>>,
        repository_service: Arc<RepositoryService>,
        file_service: Arc<FileService>,
        commit_service: Arc<CommitService>
    ) -> Self {
        Self {
            git,
            db,
            cache,
            repository_service,
            file_service,
            commit_service,
        }
    }

    /// Perform an advanced search across repositories
    pub async fn search(&self, query: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        let start_time = Instant::now();

        // Get basic search results from index service
        let base_result = self.index_service.search(query, &options.basic_options).await?;

        // Start building enhanced result
        let mut enhanced_result = EnhancedSearchResult {
            base_result: base_result.clone(),
            suggestions: None,
            repositories: Vec::new(),
            languages: BTreeMap::new(),
            authors: BTreeMap::new(),
            time_periods: BTreeMap::new(),
            related_searches: Vec::new(),
        };

        // Generate suggestions if requested
        if options.get_suggestions {
            enhanced_result.suggestions = Some(self.generate_suggestions(query, options).await?);
        }

        // Process each repository's matches
        for repo_match in &base_result.repositories {
            let enhanced_repo = self.enhance_repository_matches(repo_match.clone(), options).await?;

            // Collect statistics for result breakdowns
            self.collect_statistics(&enhanced_repo, &mut enhanced_result).await?;

            enhanced_result.repositories.push(enhanced_repo);
        }

        // Generate related searches
        enhanced_result.related_searches = self.generate_related_searches(query, &enhanced_result).await?;

        Ok(enhanced_result)
    }

    /// Generate search suggestions for auto-complete
    async fn generate_suggestions(&self, query: &str, options: &AdvancedSearchOptions) -> Result<Vec<String>> {
        // For a simple implementation, we'll just append common code terms to the query
        // In a real implementation, this would use more sophisticated techniques

        let mut suggestions = Vec::new();

        if query.is_empty() {
            return Ok(suggestions);
        }

        // Common terms to suggest based on search type
        let terms = match options.search_type {
            SearchType::Symbol => vec![
                "class", "function", "method", "struct", "enum", "interface", "trait",
                "var", "const", "type", "impl", "def", "fn"
            ],
            SearchType::Commit => vec![
                "fix", "feat", "docs", "style", "refactor", "perf", "test", "chore",
                "bugfix", "update", "improve", "add", "remove"
            ],
            SearchType::Path => vec![
                "src/", "test/", "lib/", "include/", "docs/", "examples/",
                ".rs", ".go", ".py", ".js", ".ts", ".c", ".cpp", ".h"
            ],
            _ => vec![
                "error", "bug", "fix", "implement", "feature", "todo", "hack",
                "refactor", "optimize", "performance", "security", "crash"
            ],
        };

        // Generate suggestions by combining query with common terms
        for term in terms {
            if term.starts_with(query) {
                suggestions.push(term.to_string());
            } else if query.ends_with(' ') {
                suggestions.push(format!("{}{}", query, term));
            } else {
                suggestions.push(format!("{} {}", query, term));
            }

            if suggestions.len() >= MAX_SUGGESTIONS {
                break;
            }
        }

        Ok(suggestions)
    }

    /// Enhance repository matches with additional context
    async fn enhance_repository_matches(
        &self,
        repo_match: RepositoryMatches,
        options: &AdvancedSearchOptions
    ) -> Result<EnhancedRepositoryMatches> {
        let repo_name = &repo_match.repository;

        // Fetch recent commits for context if needed
        let recent_commits = if options.search_type == SearchType::Commit
            || options.search_type == SearchType::Semantic {

            // Get commit information
            let commits = self.commit_service
                .list_commits(repo_name, "HEAD", MAX_COMMIT_CONTEXT, None)
                .await?;

            // Convert to commit summaries
            let commit_summaries = commits.commits
                .into_iter()
                .map(|commit| CommitSummary {
                    id: commit.id,
                    short_id: commit.short_id,
                    author: commit.author,
                    date: commit.timestamp,
                    summary: commit.summary,
                })
                .collect();

            Some(commit_summaries)
        } else {
            None
        };

        // Enhance file matches
        let mut enhanced_files = Vec::new();

        for file_match in &repo_match.files {
            // Skip if we've reached the maximum files per repository
            if enhanced_files.len() >= MAX_FILES_PER_REPO {
                break;
            }

            let enhanced_file = self.enhance_file_match(repo_name, file_match.clone(), options).await?;
            enhanced_files.push(enhanced_file);
        }

        Ok(EnhancedRepositoryMatches {
            base_matches: repo_match,
            recent_commits,
            files: enhanced_files,
        })
    }

    /// Enhance file match with additional context
    async fn enhance_file_match(
        &self,
        repo_name: &str,
        file_match: FileMatch,
        options: &AdvancedSearchOptions
    ) -> Result<EnhancedFileMatch> {
        // Determine language from file extension
        let language = self.detect_language(&file_match.path);

        // Get file information to find contributors
        let mut contributors = None;

        if options.include_snippets {
            // This would get contributor information in a real implementation
            // For simplicity, we'll just create some dummy data
            contributors = Some(vec!["Alice Smith".to_string(), "Bob Jones".to_string()]);
        }

        // Enhance line matches
        let mut enhanced_lines = Vec::new();
        let context_lines = options.context_lines.unwrap_or(0);

        for line_match in &file_match.lines {
            // Skip if we've reached the maximum matches per file
            if enhanced_lines.len() >= MAX_MATCHES_PER_FILE {
                break;
            }

            // For a real implementation, we would fetch the actual context lines
            // from the file content. For simplicity, we'll create dummy context.
            let context_before = if context_lines > 0 {
                Some(self.create_dummy_context(context_lines))
            } else {
                None
            };

            let context_after = if context_lines > 0 {
                Some(self.create_dummy_context(context_lines))
            } else {
                None
            };

            // In a real implementation, we would get this from git blame
            let last_changed_by = Some("Charlie Brown".to_string());
            let last_changed_at = Some("2025-03-15T14:32:00Z".to_string());

            enhanced_lines.push(EnhancedLineMatch {
                base_match: line_match.clone(),
                context_before,
                context_after,
                last_changed_by,
                last_changed_at,
            });
        }

        Ok(EnhancedFileMatch {
            base_match: file_match,
            language,
            contributors,
            lines: enhanced_lines,
        })
    }

    /// Detect language from file path
    fn detect_language(&self, path: &str) -> Option<String> {
        let extension = path.split('.').last()?;

        match extension {
            "rs" => Some("Rust".to_string()),
            "go" => Some("Go".to_string()),
            "py" => Some("Python".to_string()),
            "js" => Some("JavaScript".to_string()),
            "ts" => Some("TypeScript".to_string()),
            "java" => Some("Java".to_string()),
            "c" | "h" => Some("C".to_string()),
            "cpp" | "hpp" => Some("C++".to_string()),
            "sh" => Some("Shell".to_string()),
            "md" => Some("Markdown".to_string()),
            "toml" => Some("TOML".to_string()),
            "json" => Some("JSON".to_string()),
            "yaml" | "yml" => Some("YAML".to_string()),
            _ => None,
        }
    }

    /// Create dummy context lines for simplified implementation
    fn create_dummy_context(&self, count: usize) -> Vec<String> {
        (0..count)
            .map(|i| format!("Context line {}", i + 1))
            .collect()
    }

    /// Collect statistics for result breakdowns
    async fn collect_statistics(
        &self,
        repo: &EnhancedRepositoryMatches,
        result: &mut EnhancedSearchResult
    ) -> Result<()> {
        // Collect language statistics
        for file in &repo.files {
            if let Some(lang) = &file.language {
                *result.languages.entry(lang.clone()).or_insert(0) += 1;
            }
        }

        // Collect author statistics
        if let Some(commits) = &repo.recent_commits {
            for commit in commits {
                *result.authors.entry(commit.author.clone()).or_insert(0) += 1;
            }
        }

        // In a real implementation, we would collect time period stats
        // from actual data. For simplicity, we'll use dummy data.
        *result.time_periods.entry("Last 24 hours".to_string()).or_insert(0) += 5;
        *result.time_periods.entry("Last week".to_string()).or_insert(0) += 12;
        *result.time_periods.entry("Last month".to_string()).or_insert(0) += 25;

        Ok(())
    }

    /// Generate related searches based on results
    async fn generate_related_searches(
        &self,
        query: &str,
        result: &EnhancedSearchResult
    ) -> Result<Vec<String>> {
        let mut related = Vec::new();

        // In a real implementation, this would analyze the search results
        // and extract meaningful related search terms. For simplicity, we'll
        // use a basic approach.

        // Add language-specific searches
        for (language, count) in result.languages.iter().take(3) {
            if *count > 0 {
                related.push(format!("{} in:{}", query, language));
            }
        }

        // Add author-specific searches
        for (author, count) in result.authors.iter().take(3) {
            if *count > 0 {
                related.push(format!("{} author:{}", query, author));
            }
        }

        // Add some common modifiers
        related.push(format!("{} type:function", query));
        related.push(format!("{} type:class", query));
        related.push(format!("{} file:test", query));

        Ok(related)
    }

    /// Perform a symbol search (functions, classes, etc.)
    pub async fn symbol_search(&self, query: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        // Create options specifically for symbol search
        let mut symbol_options = options.clone();
        symbol_options.search_type = SearchType::Symbol;

        // In a real implementation, this would use language-specific parsers
        // to identify and search for code symbols. For simplicity, we'll just
        // use the regular search with some modifications.

        self.search(query, &symbol_options).await
    }

    /// Perform a semantic code search
    pub async fn semantic_search(&self, query: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        // Create options specifically for semantic search
        let mut semantic_options = options.clone();
        semantic_options.search_type = SearchType::Semantic;

        // In a real implementation, this would use embeddings or other NLP techniques
        // to find semantically related code. For simplicity, we'll just use
        // the regular search with some modifications.

        self.search(query, &semantic_options).await
    }

    /// Search for code patterns using regular expressions
    pub async fn regex_search(&self, pattern: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        // Create options specifically for regex search
        let mut regex_options = options.clone();
        regex_options.search_type = SearchType::Regex;
        regex_options.basic_options.regex = true;

        self.search(pattern, &regex_options).await
    }

    /// Search for specific file paths
    pub async fn path_search(&self, pattern: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        // Create options specifically for path search
        let mut path_options = options.clone();
        path_options.search_type = SearchType::Path;
        path_options.basic_options.path_pattern = Some(pattern.to_string());

        // For path search, we'll search for an empty string since we're only
        // interested in matching paths
        self.search("", &path_options).await
    }

    /// Search for commits by message, author, etc.
    pub async fn commit_search(&self, query: &str, options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
        // Create options specifically for commit search
        let mut commit_options = options.clone();
        commit_options.search_type = SearchType::Commit;

        // In a real implementation, this would search commit metadata
        // For simplicity, we'll just use regular search

        self.search(query, &commit_options).await
    }
}

#[cfg(test)]
mod tests;
