//! Search templates for the Art application

use crate::error::Result;
use askama::Template;
use std::collections::HashMap;

use super::base::BaseTemplate;

/// SearchTemplate represents the template for search results
#[derive(Template)]
#[template(path = "search/search.html")]
pub struct SearchTemplate {
    /// Base template fields
    pub base: BaseTemplate,

    /// Query string
    pub query: String,

    /// Type of search ("text", "symbol", "semantic", "regex", "path", "commit")
    pub search_type: String,

    /// Search results (if any)
    pub results: Option<SearchResults>,

    /// Search statistics
    pub search_stats: Option<SearchStats>,

    /// Suggested search terms
    pub suggestions: Vec<String>,

    /// Breakdown of results by programming language
    pub languages: HashMap<String, usize>,

    /// Breakdown of results by author
    pub authors: HashMap<String, usize>,

    /// Breakdown of results by time period
    pub time_periods: HashMap<String, usize>,

    /// Related searches
    pub related_searches: Vec<String>,

    /// Pagination data (if more than one page of results)
    pub pagination: Option<Pagination>,

    /// Sort options for the search results
    pub sort_options: Vec<(String, String)>,

    /// Current sort option
    pub current_sort: String,

    /// Applied filters
    pub filters: SearchFilters,
}

/// SearchResults represents the search results
pub struct SearchResults {
    /// List of repositories with matches
    pub repositories: Vec<RepositoryMatch>,

    /// Total number of repositories with matches
    pub total_repositories: usize,

    /// Number of matches shown on the current page
    pub shown_matches: usize,
}

/// RepositoryMatch represents a repository with search matches
pub struct RepositoryMatch {
    /// Repository name
    pub name: String,

    /// Number of matches in the repository
    pub matches: usize,

    /// Files with matches
    pub files: Vec<FileMatch>,
}

/// FileMatch represents a file with search matches
pub struct FileMatch {
    /// File path
    pub path: String,

    /// Matches in the file
    pub matches: Vec<LineMatch>,
}

/// LineMatch represents a line with a search match
pub struct LineMatch {
    /// Line number
    pub line_number: usize,

    /// Line content
    pub content: String,
}

/// SearchStats represents statistics about the search
pub struct SearchStats {
    /// Total number of matches
    pub total_matches: usize,

    /// Time taken to perform the search in milliseconds
    pub elapsed_ms: u64,
}

/// Pagination data for search results
pub struct Pagination {
    /// Current page number
    pub current_page: usize,

    /// Total number of pages
    pub total_pages: usize,

    /// Whether there is a previous page
    pub has_previous: bool,

    /// Whether there is a next page
    pub has_next: bool,

    /// Previous page number (if any)
    pub previous_page: Option<usize>,

    /// Next page number (if any)
    pub next_page: Option<usize>,

    /// List of page numbers to display
    pub pages: Vec<usize>,
}

/// SearchFilters represents the filters applied to a search
pub struct SearchFilters {
    /// Repository filter
    pub repo: Option<String>,

    /// Path filter
    pub path: Option<String>,

    /// Language filter
    pub language: Option<String>,

    /// Author filter
    pub author: Option<String>,

    /// Time range filter
    pub time_range: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_search_template() {
        // Create a simple search template
        let template = SearchTemplate {
            base: BaseTemplate {
                title: "Search Results".to_string(),
                current_year: "2023".to_string(),
                current_page: "search".to_string(),
                base_url: "/".to_string(),
                search_url: Some("/search".to_string()),
            },
            query: "test".to_string(),
            search_type: "text".to_string(),
            results: None,
            search_stats: None,
            suggestions: Vec::new(),
            languages: HashMap::new(),
            authors: HashMap::new(),
            time_periods: HashMap::new(),
            related_searches: Vec::new(),
            pagination: None,
            sort_options: vec![
                ("relevance".to_string(), "Relevance".to_string()),
                ("date".to_string(), "Date".to_string()),
            ],
            current_sort: "relevance".to_string(),
            filters: SearchFilters {
                repo: None,
                path: None,
                language: None,
                author: None,
                time_range: None,
            },
        };

        // Test that the template can be created
        assert_eq!(template.query, "test");
        assert_eq!(template.search_type, "text");
        assert_eq!(template.base.title, "Search Results");
    }
}
