// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Search API handlers
//!
//! This module provides handlers for search-related API endpoints.

use std::sync::Arc;
use std::collections::HashMap;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, warn};
use proptest::prelude::*;

use crate::error::{Error, Result};
use crate::service::search::{SearchService, AdvancedSearchOptions, SearchType, EnhancedSearchResult};
use crate::service::observability::metrics;

/// Search API handler
pub struct SearchApiHandler;

/// Basic search query parameters
#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    /// Search query
    pub q: String,

    /// Repositories to search (comma-separated list, empty means all)
    pub repos: Option<String>,

    /// Maximum number of results to return
    pub limit: Option<usize>,

    /// Page number (0-based)
    pub page: Option<usize>,

    /// Include code snippets in the results
    #[serde(default = "default_true")]
    pub snippets: bool,

    /// Get auto-complete suggestions
    #[serde(default = "default_false")]
    pub suggestions: bool,
}

/// Advanced search query parameters
#[derive(Debug, Deserialize)]
pub struct AdvancedSearchQuery {
    /// Search query
    pub q: String,

    /// Repositories to search (comma-separated list, empty means all)
    pub repos: Option<String>,

    /// Search type (text, symbol, commit, path, regex, semantic)
    pub type_: Option<String>,

    /// Authors to filter by (comma-separated list)
    pub authors: Option<String>,

    /// Languages to filter by (comma-separated list)
    pub languages: Option<String>,

    /// Start time for time range (ISO 8601 format)
    pub start_time: Option<String>,

    /// End time for time range (ISO 8601 format)
    pub end_time: Option<String>,

    /// Number of context lines to include
    pub context: Option<usize>,

    /// Sort results by (relevance, date, path)
    pub sort: Option<String>,

    /// Maximum number of results to return
    pub limit: Option<usize>,

    /// Page number (0-based)
    pub page: Option<usize>,

    /// Include code snippets in the results
    #[serde(default = "default_true")]
    pub snippets: bool,

    /// Get auto-complete suggestions
    #[serde(default = "default_false")]
    pub suggestions: bool,

    /// Case sensitive search
    #[serde(default = "default_false")]
    pub case_sensitive: bool,

    /// Whole word matching
    #[serde(default = "default_false")]
    pub whole_word: bool,
}

/// Symbol search query parameters
#[derive(Debug, Deserialize)]
pub struct SymbolSearchQuery {
    /// Symbol query
    pub q: String,

    /// Repositories to search (comma-separated list, empty means all)
    pub repos: Option<String>,

    /// Languages to filter by (comma-separated list)
    pub languages: Option<String>,

    /// Maximum number of results to return
    pub limit: Option<usize>,

    /// Page number (0-based)
    pub page: Option<usize>,
}

/// Search suggestions query parameters
#[derive(Debug, Deserialize)]
pub struct SuggestionsQuery {
    /// Partial query to get suggestions for
    pub q: String,

    /// Search type (text, symbol, commit, path, regex, semantic)
    pub type_: Option<String>,

    /// Maximum number of suggestions to return
    pub limit: Option<usize>,
}

/// Search suggestions response
#[derive(Debug, Serialize)]
pub struct SuggestionsResponse {
    /// Suggestions
    pub suggestions: Vec<String>,

    /// Query used
    pub query: String,
}

/// Search API response
#[derive(Debug, Serialize)]
pub struct SearchApiResponse {
    /// Query used
    pub query: String,

    /// Search options used
    pub options: HashMap<String, String>,

    /// Total number of matches
    pub total_matches: usize,

    /// Number of repositories with matches
    pub repository_count: usize,

    /// Search results
    pub results: EnhancedSearchResult,

    /// Time taken to execute the search (ms)
    pub time_ms: u64,

    /// Continuation token for pagination
    pub next_page: Option<String>,
}

/// Default true value
fn default_true() -> bool {
    true
}

/// Default false value
fn default_false() -> bool {
    false
}

impl SearchApiHandler {
    /// Basic search endpoint
    ///
    /// GET /api/search
    pub async fn search(
        State(search_service): State<Arc<SearchService>>,
        Query(params): Query<SearchQuery>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["search", "basic"]);
        debug!("Basic search query: {}", params.q);

        let start_time = std::time::Instant::now();

        // Convert to advanced search options
        let options = AdvancedSearchOptions {
            basic_options: crate::service::index::SearchOptions {
                repositories: params.repos.as_deref().map(|r| r.split(',').map(|s| s.trim().to_string()).collect()),
                page: params.page,
                limit: params.limit,
                case_sensitive: false,
                whole_word: false,
            },
            search_type: SearchType::Text,
            authors: None,
            languages: None,
            time_range: None,
            context_lines: Some(2),
            sort_by: Some("relevance".to_string()),
            max_results: params.limit,
            include_snippets: params.snippets,
            get_suggestions: params.suggestions,
        };

        // Execute search
        let results = search_service.search(&params.q, &options).await?;
        let elapsed = start_time.elapsed();

        // Construct response
        let response = SearchApiResponse {
            query: params.q,
            options: HashMap::from([
                ("type".to_string(), "text".to_string()),
                ("snippets".to_string(), params.snippets.to_string()),
                ("suggestions".to_string(), params.suggestions.to_string()),
            ]),
            total_matches: results.base_result.total_matches,
            repository_count: results.repositories.len(),
            results,
            time_ms: elapsed.as_millis() as u64,
            next_page: params.page.map(|p| (p + 1).to_string()),
        };

        Ok(Json(response))
    }

    /// Advanced search endpoint
    ///
    /// GET /api/search/advanced
    pub async fn advanced_search(
        State(search_service): State<Arc<SearchService>>,
        Query(params): Query<AdvancedSearchQuery>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["search", "advanced"]);
        debug!("Advanced search query: {}", params.q);

        let start_time = std::time::Instant::now();

        // Parse search type
        let search_type = match params.type_.as_deref() {
            Some("symbol") => SearchType::Symbol,
            Some("commit") => SearchType::Commit,
            Some("path") => SearchType::Path,
            Some("regex") => SearchType::Regex,
            Some("semantic") => SearchType::Semantic,
            _ => SearchType::Text,
        };

        // Parse repositories
        let repositories = params.repos.as_deref()
            .map(|r| r.split(',').map(|s| s.trim().to_string()).collect());

        // Parse authors
        let authors = params.authors.as_deref()
            .map(|a| a.split(',').map(|s| s.trim().to_string()).collect());

        // Parse languages
        let languages = params.languages.as_deref()
            .map(|l| l.split(',').map(|s| s.trim().to_string()).collect());

        // Parse time range
        let time_range = match (params.start_time.as_deref(), params.end_time.as_deref()) {
            (Some(start), Some(end)) => Some((start.to_string(), end.to_string())),
            _ => None,
        };

        // Create advanced search options
        let options = AdvancedSearchOptions {
            basic_options: crate::service::index::SearchOptions {
                repositories,
                page: params.page,
                limit: params.limit,
                case_sensitive: params.case_sensitive,
                whole_word: params.whole_word,
            },
            search_type,
            authors,
            languages,
            time_range,
            context_lines: params.context,
            sort_by: params.sort,
            max_results: params.limit,
            include_snippets: params.snippets,
            get_suggestions: params.suggestions,
        };

        // Execute search based on search type
        let results = match search_type {
            SearchType::Symbol => search_service.symbol_search(&params.q, &options).await?,
            SearchType::Commit => search_service.commit_search(&params.q, &options).await?,
            SearchType::Path => search_service.path_search(&params.q, &options).await?,
            SearchType::Regex => search_service.regex_search(&params.q, &options).await?,
            SearchType::Semantic => search_service.semantic_search(&params.q, &options).await?,
            SearchType::Text => search_service.search(&params.q, &options).await?,
        };

        let elapsed = start_time.elapsed();

        // Build options map for response
        let mut options_map = HashMap::new();
        options_map.insert("type".to_string(), format!("{:?}", search_type).to_lowercase());
        options_map.insert("snippets".to_string(), params.snippets.to_string());
        options_map.insert("suggestions".to_string(), params.suggestions.to_string());
        options_map.insert("case_sensitive".to_string(), params.case_sensitive.to_string());
        options_map.insert("whole_word".to_string(), params.whole_word.to_string());

        if let Some(context) = params.context {
            options_map.insert("context".to_string(), context.to_string());
        }

        if let Some(sort) = params.sort {
            options_map.insert("sort".to_string(), sort);
        }

        // Construct response
        let response = SearchApiResponse {
            query: params.q,
            options: options_map,
            total_matches: results.base_result.total_matches,
            repository_count: results.repositories.len(),
            results,
            time_ms: elapsed.as_millis() as u64,
            next_page: params.page.map(|p| (p + 1).to_string()),
        };

        Ok(Json(response))
    }

    /// Symbol search endpoint
    ///
    /// GET /api/search/symbols
    pub async fn symbol_search(
        State(search_service): State<Arc<SearchService>>,
        Query(params): Query<SymbolSearchQuery>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["search", "symbol"]);
        debug!("Symbol search query: {}", params.q);

        let start_time = std::time::Instant::now();

        // Create advanced search options
        let options = AdvancedSearchOptions {
            basic_options: crate::service::index::SearchOptions {
                repositories: params.repos.as_deref()
                    .map(|r| r.split(',').map(|s| s.trim().to_string()).collect()),
                page: params.page,
                limit: params.limit,
                case_sensitive: false,
                whole_word: true,
            },
            search_type: SearchType::Symbol,
            authors: None,
            languages: params.languages.as_deref()
                .map(|l| l.split(',').map(|s| s.trim().to_string()).collect()),
            time_range: None,
            context_lines: Some(1),
            sort_by: Some("relevance".to_string()),
            max_results: params.limit,
            include_snippets: true,
            get_suggestions: false,
        };

        // Execute search
        let results = search_service.symbol_search(&params.q, &options).await?;
        let elapsed = start_time.elapsed();

        // Construct response
        let response = SearchApiResponse {
            query: params.q,
            options: HashMap::from([
                ("type".to_string(), "symbol".to_string()),
            ]),
            total_matches: results.base_result.total_matches,
            repository_count: results.repositories.len(),
            results,
            time_ms: elapsed.as_millis() as u64,
            next_page: params.page.map(|p| (p + 1).to_string()),
        };

        Ok(Json(response))
    }

    /// Search suggestions endpoint
    ///
    /// GET /api/search/suggestions
    pub async fn search_suggestions(
        State(search_service): State<Arc<SearchService>>,
        Query(params): Query<SuggestionsQuery>,
    ) -> Result<impl IntoResponse> {
        metrics::increment_counter("api_requests_total", &["search", "suggestions"]);
        debug!("Search suggestions query: {}", params.q);

        // Parse search type
        let search_type = match params.type_.as_deref() {
            Some("symbol") => SearchType::Symbol,
            Some("commit") => SearchType::Commit,
            Some("path") => SearchType::Path,
            Some("regex") => SearchType::Regex,
            Some("semantic") => SearchType::Semantic,
            _ => SearchType::Text,
        };

        // Set up search options
        let limit = params.limit.unwrap_or(10);
        let options = AdvancedSearchOptions {
            basic_options: crate::service::index::SearchOptions {
                repositories: None,
                page: Some(0),
                limit: Some(1), // We only need 1 result
                case_sensitive: false,
                whole_word: false,
            },
            search_type,
            authors: None,
            languages: None,
            time_range: None,
            context_lines: None,
            sort_by: None,
            max_results: Some(1), // We only need 1 result
            include_snippets: false,
            get_suggestions: true,
        };

        // Execute search
        let results = search_service.search(&params.q, &options).await?;

        // Extract suggestions
        let suggestions = results.suggestions
            .unwrap_or_default()
            .into_iter()
            .take(limit)
            .collect();

        // Construct response
        let response = SuggestionsResponse {
            suggestions,
            query: params.q,
        };

        Ok(Json(response))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::index::{IndexService, SearchResult, RepositoryMatches, FileMatch, LineMatch};
    use crate::service::repository::RepositoryService;
    use crate::service::file::FileService;
    use crate::service::commit::CommitService;
    use crate::data::cache::Cache;
    use crate::service::search::EnhancedSearchResult;
    use crate::error::Result;
    use std::time::Duration;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
        routing::get,
        Router,
    };
    use tower::ServiceExt;
    use http_body_util::BodyExt;
    use proptest::prelude::*;

    // Mock SearchService for testing
    struct MockSearchService;

    impl MockSearchService {
        fn new() -> Arc<Self> {
            Arc::new(Self)
        }

        async fn search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }

        async fn symbol_search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }

        async fn commit_search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }

        async fn path_search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }

        async fn regex_search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }

        async fn semantic_search(&self, _query: &str, _options: &AdvancedSearchOptions) -> Result<EnhancedSearchResult> {
            // Return a simple mock result
            Ok(create_mock_search_result())
        }
    }

    // Helper to create a mock search result
    fn create_mock_search_result() -> EnhancedSearchResult {
        let base_result = SearchResult {
            query: "test".to_string(),
            total_matches: 1,
            repositories: vec![
                RepositoryMatches {
                    name: "test-repo".to_string(),
                    matches: vec![
                        FileMatch {
                            path: "src/main.rs".to_string(),
                            matches: vec![
                                LineMatch {
                                    line_number: 10,
                                    line: "fn test() {".to_string(),
                                    start: 3,
                                    end: 7,
                                }
                            ],
                        }
                    ],
                }
            ],
        };

        EnhancedSearchResult {
            base_result,
            suggestions: Some(vec!["test function".to_string(), "testing".to_string()]),
            repositories: Vec::new(),
            languages: Default::default(),
            authors: Default::default(),
            time_periods: Default::default(),
            related_searches: vec!["rust test".to_string()],
        }
    }

    // Create a test app with mock service
    fn create_test_app() -> Router {
        let mock_service = MockSearchService::new();

        Router::new()
            .route("/api/search", get(SearchApiHandler::search))
            .route("/api/search/advanced", get(SearchApiHandler::advanced_search))
            .route("/api/search/symbols", get(SearchApiHandler::symbol_search))
            .route("/api/search/suggestions", get(SearchApiHandler::search_suggestions))
            .with_state(mock_service)
    }

    // Property-based tests for query parameters

    // Generate valid search queries
    fn valid_search_query() -> impl Strategy<Value = String> {
        "\\PC{1,50}".prop_map(|s| s)
    }

    // Generate repository lists
    fn repository_list() -> impl Strategy<Value = Option<String>> {
        option::of("[a-zA-Z0-9_-]{1,20}(,[a-zA-Z0-9_-]{1,20}){0,5}")
    }

    // Generate limit values
    fn limit_value() -> impl Strategy<Value = Option<usize>> {
        option::of(1usize..100)
    }

    // Generate page values
    fn page_value() -> impl Strategy<Value = Option<usize>> {
        option::of(0usize..10)
    }

    // Generate boolean values
    fn bool_value() -> impl Strategy<Value = bool> {
        prop_oneof![Just(true), Just(false)]
    }

    // Generate search type values
    fn search_type() -> impl Strategy<Value = Option<String>> {
        option::of(prop_oneof![
            Just("text".to_string()),
            Just("symbol".to_string()),
            Just("commit".to_string()),
            Just("path".to_string()),
            Just("regex".to_string()),
            Just("semantic".to_string())
        ])
    }

    proptest! {
        // Test basic search endpoint with various inputs
        #[test]
        fn test_basic_search_endpoint(
            query in valid_search_query(),
            repos in repository_list(),
            limit in limit_value(),
            page in page_value(),
            snippets in bool_value(),
            suggestions in bool_value()
        ) {
            // Set up test environment
            let runtime = tokio::runtime::Runtime::new().unwrap();
            let app = create_test_app();

            // Build the URL
            let mut url = format!("/api/search?q={}", urlencoding::encode(&query));
            if let Some(repos) = repos {
                url.push_str(&format!("&repos={}", urlencoding::encode(&repos)));
            }
            if let Some(limit) = limit {
                url.push_str(&format!("&limit={}", limit));
            }
            if let Some(page) = page {
                url.push_str(&format!("&page={}", page));
            }
            url.push_str(&format!("&snippets={}", snippets));
            url.push_str(&format!("&suggestions={}", suggestions));

            // Create request
            let request = Request::builder()
                .uri(&url)
                .method("GET")
                .body(Body::empty())
                .unwrap();

            // Send request
            let response = runtime.block_on(app.oneshot(request)).unwrap();

            // Verify response
            prop_assert_eq!(response.status(), StatusCode::OK);

            // Extract and parse the response body
            let body_bytes = runtime.block_on(response.into_body().collect()).unwrap().to_bytes();
            let body_str = std::str::from_utf8(&body_bytes).unwrap();
            let json: serde_json::Value = serde_json::from_str(body_str).unwrap();

            // Verify response structure
            prop_assert!(json.is_object());
            prop_assert!(json.get("query").is_some());
            prop_assert!(json.get("options").is_some());
            prop_assert!(json.get("total_matches").is_some());
            prop_assert!(json.get("repository_count").is_some());
            prop_assert!(json.get("results").is_some());
            prop_assert!(json.get("time_ms").is_some());

            // Verify query matches
            prop_assert_eq!(json["query"].as_str().unwrap(), query);
        }

        // Test advanced search endpoint with various inputs
        #[test]
        fn test_advanced_search_endpoint(
            query in valid_search_query(),
            repos in repository_list(),
            search_type in search_type(),
            limit in limit_value(),
            page in page_value()
        ) {
            // Set up test environment
            let runtime = tokio::runtime::Runtime::new().unwrap();
            let app = create_test_app();

            // Build the URL
            let mut url = format!("/api/search/advanced?q={}", urlencoding::encode(&query));
            if let Some(repos) = repos {
                url.push_str(&format!("&repos={}", urlencoding::encode(&repos)));
            }
            if let Some(type_) = search_type {
                url.push_str(&format!("&type_={}", type_));
            }
            if let Some(limit) = limit {
                url.push_str(&format!("&limit={}", limit));
            }
            if let Some(page) = page {
                url.push_str(&format!("&page={}", page));
            }

            // Create request
            let request = Request::builder()
                .uri(&url)
                .method("GET")
                .body(Body::empty())
                .unwrap();

            // Send request
            let response = runtime.block_on(app.oneshot(request)).unwrap();

            // Verify response
            prop_assert_eq!(response.status(), StatusCode::OK);

            // Extract and parse the response body
            let body_bytes = runtime.block_on(response.into_body().collect()).unwrap().to_bytes();
            let body_str = std::str::from_utf8(&body_bytes).unwrap();
            let json: serde_json::Value = serde_json::from_str(body_str).unwrap();

            // Verify response structure
            prop_assert!(json.is_object());
            prop_assert!(json.get("query").is_some());
            prop_assert!(json.get("options").is_some());
            prop_assert!(json.get("total_matches").is_some());
            prop_assert!(json.get("repository_count").is_some());
            prop_assert!(json.get("results").is_some());
            prop_assert!(json.get("time_ms").is_some());

            // Verify query matches
            prop_assert_eq!(json["query"].as_str().unwrap(), query);
        }

        // Test suggestions endpoint
        #[test]
        fn test_suggestions_endpoint(
            query in valid_search_query(),
            search_type in search_type(),
            limit in limit_value()
        ) {
            // Set up test environment
            let runtime = tokio::runtime::Runtime::new().unwrap();
            let app = create_test_app();

            // Build the URL
            let mut url = format!("/api/search/suggestions?q={}", urlencoding::encode(&query));
            if let Some(type_) = search_type {
                url.push_str(&format!("&type_={}", type_));
            }
            if let Some(limit) = limit {
                url.push_str(&format!("&limit={}", limit));
            }

            // Create request
            let request = Request::builder()
                .uri(&url)
                .method("GET")
                .body(Body::empty())
                .unwrap();

            // Send request
            let response = runtime.block_on(app.oneshot(request)).unwrap();

            // Verify response
            prop_assert_eq!(response.status(), StatusCode::OK);

            // Extract and parse the response body
            let body_bytes = runtime.block_on(response.into_body().collect()).unwrap().to_bytes();
            let body_str = std::str::from_utf8(&body_bytes).unwrap();
            let json: serde_json::Value = serde_json::from_str(body_str).unwrap();

            // Verify response structure
            prop_assert!(json.is_object());
            prop_assert!(json.get("suggestions").is_some());
            prop_assert!(json.get("query").is_some());

            // Verify suggestions is an array
            prop_assert!(json["suggestions"].is_array());

            // Verify query matches
            prop_assert_eq!(json["query"].as_str().unwrap(), query);
        }
    }
}
