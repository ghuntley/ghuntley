// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

use crate::service::search::*;
use crate::error::Result;
use crate::service::index::{SearchResult, FileMatch, LineMatch, RepositoryMatches, SearchOptions};
use crate::service::commit::{CommitInfo, CommitListResponse};
use crate::data::cache::{Cache, CacheKey};

use std::sync::Arc;
use mockall::predicate::*;
use mockall::mock;
use proptest::prelude::*;
use proptest::collection::vec;
use std::collections::BTreeMap;
use std::time::Duration;

// Mock implementations for testing
mock! {
    pub IndexService {}

    impl Clone for IndexService {
        fn clone(&self) -> Self;
    }

    #[async_trait::async_trait]
    impl IndexService {
        async fn search(&self, query: &str, options: &SearchOptions) -> Result<SearchResult>;
    }
}

mock! {
    pub RepositoryService {}

    impl Clone for RepositoryService {
        fn clone(&self) -> Self;
    }
}

mock! {
    pub FileService {}

    impl Clone for FileService {
        fn clone(&self) -> Self;
    }
}

mock! {
    pub CommitService {}

    impl Clone for CommitService {
        fn clone(&self) -> Self;
    }

    #[async_trait::async_trait]
    impl CommitService {
        async fn list_commits(&self, repo: &str, reference: &str, limit: usize, cursor: Option<&str>) -> Result<CommitListResponse>;
    }
}

mock! {
    pub Cache {}

    impl Clone for Cache {
        fn clone(&self) -> Self;
    }

    #[async_trait::async_trait]
    impl Cache {
        async fn get<T: serde::de::DeserializeOwned + Send + Sync>(&self, key: &CacheKey) -> Option<T>;
        async fn set<T: serde::Serialize + Send + Sync>(&self, key: CacheKey, value: &T, ttl: Option<Duration>) -> Result<()>;
        async fn delete(&self, key: &CacheKey) -> Result<()>;
    }
}

// Helper to create a test search service with mocks
async fn create_test_service() -> SearchService {
    let mut index_service = MockIndexService::new();
    index_service.expect_clone().returning(|| MockIndexService::new());
    index_service.expect_search().returning(|query, _| {
        let repos = vec![
            RepositoryMatches {
                repository: "test-repo".to_string(),
                matches: 2,
                files: vec![
                    FileMatch {
                        path: "src/main.rs".to_string(),
                        matches: 2,
                        lines: vec![
                            LineMatch {
                                line_number: 10,
                                content: format!("Line containing {}", query),
                                matches: vec![query.to_string()],
                            },
                            LineMatch {
                                line_number: 20,
                                content: format!("Another line with {}", query),
                                matches: vec![query.to_string()],
                            },
                        ],
                    },
                ],
            },
        ];

        Ok(SearchResult {
            query: query.to_string(),
            regex: false,
            case_sensitive: false,
            repositories: repos,
            total_matches: 2,
        })
    });

    let mut repository_service = MockRepositoryService::new();
    repository_service.expect_clone().returning(|| MockRepositoryService::new());

    let mut file_service = MockFileService::new();
    file_service.expect_clone().returning(|| MockFileService::new());

    let mut commit_service = MockCommitService::new();
    commit_service.expect_clone().returning(|| MockCommitService::new());
    commit_service.expect_list_commits().returning(|repo, _, limit, _| {
        let commits = vec![
            CommitInfo {
                id: "abcdef1234567890".to_string(),
                short_id: "abcdef1".to_string(),
                author: "Test User".to_string(),
                author_email: "test@example.com".to_string(),
                committer: "Test User".to_string(),
                committer_email: "test@example.com".to_string(),
                message: "Test commit".to_string(),
                summary: "Test commit".to_string(),
                timestamp: "2025-01-01T00:00:00Z".to_string(),
                parents: vec!["0123456789abcdef".to_string()],
                files_changed: 1,
                lines_added: 10,
                lines_removed: 5,
            },
        ];

        Ok(CommitListResponse {
            repository: repo.to_string(),
            reference: "HEAD".to_string(),
            total: 1,
            commits,
            next_cursor: None,
        })
    });

    let mut cache = MockCache::new();
    cache.expect_clone().returning(|| MockCache::new());
    cache.expect_get().returning(|_| None);
    cache.expect_set().returning(|_, _, _| Ok(()));
    cache.expect_delete().returning(|_| Ok(()));

    SearchService::new(
        Arc::new(index_service),
        Arc::new(repository_service),
        Arc::new(file_service),
        Arc::new(commit_service),
        Arc::new(cache),
    )
}

// Unit tests for SearchService
#[tokio::test]
async fn test_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.search("test", &options).await.unwrap();

    // Check basic properties
    assert_eq!(result.base_result.query, "test");
    assert_eq!(result.base_result.total_matches, 2);
    assert_eq!(result.repositories.len(), 1);

    // Check enhanced repository
    let repo = &result.repositories[0];
    assert_eq!(repo.base_matches.repository, "test-repo");
    assert_eq!(repo.files.len(), 1);

    // Check enhanced file
    let file = &repo.files[0];
    assert_eq!(file.base_match.path, "src/main.rs");
    assert_eq!(file.lines.len(), 2);

    // Check that language was detected
    assert_eq!(file.language, Some("Rust".to_string()));
}

#[tokio::test]
async fn test_symbol_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.symbol_search("function", &options).await.unwrap();

    // Verify search type was set correctly
    assert_eq!(result.base_result.query, "function");
    assert_eq!(result.base_result.total_matches, 2);
}

#[tokio::test]
async fn test_semantic_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.semantic_search("error handling", &options).await.unwrap();

    // Verify search type was set correctly
    assert_eq!(result.base_result.query, "error handling");
    assert_eq!(result.base_result.total_matches, 2);
}

#[tokio::test]
async fn test_regex_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.regex_search(r"test\w+", &options).await.unwrap();

    // Verify regex flag was set
    assert_eq!(result.base_result.query, r"test\w+");
    assert_eq!(result.base_result.total_matches, 2);
}

#[tokio::test]
async fn test_path_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.path_search("*.rs", &options).await.unwrap();

    // Verify path pattern was set
    assert_eq!(result.base_result.query, "");  // Empty for path search
    assert_eq!(result.base_result.total_matches, 2);
}

#[tokio::test]
async fn test_commit_search() {
    let service = create_test_service().await;

    let options = AdvancedSearchOptions::default();
    let result = service.commit_search("fix bug", &options).await.unwrap();

    // Verify commit search type was set
    assert_eq!(result.base_result.query, "fix bug");
    assert_eq!(result.base_result.total_matches, 2);
}

#[tokio::test]
async fn test_suggestions_generation() {
    let service = create_test_service().await;

    // Test with text search
    let text_options = AdvancedSearchOptions {
        search_type: SearchType::Text,
        ..AdvancedSearchOptions::default()
    };

    let text_suggestions = service.generate_suggestions("error", &text_options).await.unwrap();
    assert!(!text_suggestions.is_empty());

    // Test with symbol search
    let symbol_options = AdvancedSearchOptions {
        search_type: SearchType::Symbol,
        ..AdvancedSearchOptions::default()
    };

    let symbol_suggestions = service.generate_suggestions("fun", &symbol_options).await.unwrap();
    assert!(!symbol_suggestions.is_empty());
    assert!(symbol_suggestions.iter().any(|s| s == "function"));

    // Test with empty query
    let empty_suggestions = service.generate_suggestions("", &text_options).await.unwrap();
    assert!(empty_suggestions.is_empty());
}

#[tokio::test]
async fn test_language_detection() {
    let service = create_test_service().await;

    // Test with Rust file
    let rust_lang = service.detect_language("src/main.rs");
    assert_eq!(rust_lang, Some("Rust".to_string()));

    // Test with Python file
    let python_lang = service.detect_language("app/server.py");
    assert_eq!(python_lang, Some("Python".to_string()));

    // Test with unknown extension
    let unknown_lang = service.detect_language("data/config.xyz");
    assert_eq!(unknown_lang, None);

    // Test with no extension
    let no_ext_lang = service.detect_language("README");
    assert_eq!(no_ext_lang, None);
}

// Property-based tests for SearchService
proptest! {
    #[test]
    fn language_detection_works(
        path in "[a-zA-Z0-9_\\-/]{1,50}\\.[a-zA-Z0-9]{1,10}".prop_map(String::from)
    ) {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let service = rt.block_on(async { create_test_service().await });

        // Get file extension
        let extension = path.split('.').last().unwrap_or("");

        // Run the language detection
        let language = service.detect_language(&path);

        // Verify the language detection
        match extension {
            // These extensions should always result in a known language
            "rs" => prop_assert_eq!(language, Some("Rust".to_string())),
            "go" => prop_assert_eq!(language, Some("Go".to_string())),
            "py" => prop_assert_eq!(language, Some("Python".to_string())),
            "js" => prop_assert_eq!(language, Some("JavaScript".to_string())),
            "ts" => prop_assert_eq!(language, Some("TypeScript".to_string())),
            "java" => prop_assert_eq!(language, Some("Java".to_string())),
            "c" => prop_assert_eq!(language, Some("C".to_string())),
            "h" => prop_assert_eq!(language, Some("C".to_string())),
            "cpp" => prop_assert_eq!(language, Some("C++".to_string())),
            "hpp" => prop_assert_eq!(language, Some("C++".to_string())),
            "sh" => prop_assert_eq!(language, Some("Shell".to_string())),
            "md" => prop_assert_eq!(language, Some("Markdown".to_string())),
            "toml" => prop_assert_eq!(language, Some("TOML".to_string())),
            "json" => prop_assert_eq!(language, Some("JSON".to_string())),
            "yaml" => prop_assert_eq!(language, Some("YAML".to_string())),
            "yml" => prop_assert_eq!(language, Some("YAML".to_string())),
            // Other extensions should result in None
            _ => prop_assert_eq!(language, None),
        }
    }

    #[test]
    fn dummy_context_generation_works(
        count in 0..20usize
    ) {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let service = rt.block_on(async { create_test_service().await });

        // Generate dummy context
        let context = service.create_dummy_context(count);

        // Verify properties
        prop_assert_eq!(context.len(), count);

        // Each line should follow the expected format
        for (i, line) in context.iter().enumerate() {
            prop_assert_eq!(line, &format!("Context line {}", i + 1));
        }
    }

    #[test]
    fn search_suggestions_are_valid(
        query in "[a-zA-Z0-9_\\- ]{0,30}".prop_map(String::from),
        search_type in prop_oneof![
            Just(SearchType::Text),
            Just(SearchType::Symbol),
            Just(SearchType::Commit),
            Just(SearchType::Path),
            Just(SearchType::Regex),
            Just(SearchType::Semantic)
        ]
    ) {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let service = rt.block_on(async { create_test_service().await });

        let options = AdvancedSearchOptions {
            search_type,
            ..AdvancedSearchOptions::default()
        };

        let suggestions = rt.block_on(async {
            service.generate_suggestions(&query, &options).await.unwrap()
        });

        if query.is_empty() {
            // Empty query should return empty suggestions
            prop_assert!(suggestions.is_empty());
        } else {
            // Suggestions should be limited to MAX_SUGGESTIONS
            prop_assert!(suggestions.len() <= MAX_SUGGESTIONS);

            // Each suggestion should contain the original query
            for suggestion in &suggestions {
                // The suggestion should either start with the query
                // or contain the query followed by a space
                let contains_query = suggestion.starts_with(&query) ||
                    suggestion.contains(&format!("{} ", &query));
                prop_assert!(contains_query,
                    "Suggestion '{}' should contain query '{}'", suggestion, query);
            }
        }
    }
}
