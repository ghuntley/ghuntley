// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Example property-based tests for Art
//!
//! This file contains example tests to demonstrate the testing framework.

use crate::testing::prelude::*;
use crate::testing::fixtures::TestFixture;
use crate::testing::properties::check_idempotent;
use std::path::PathBuf;

/// Example property test for repository path sanitization
#[cfg(test)]
mod tests {
    use super::*;

    /// Test that repository path sanitization prevents path traversal
    #[test]
    fn test_repo_path_sanitization() {
        // Define a sanitize function similar to what would be in the codebase
        let sanitize = |path: &str| -> String {
            let path = path.trim();
            let path = path.replace("..", "");
            let path = path.trim_start_matches('/');
            let path = path.trim_end_matches('/');

            if path.is_empty() {
                ".".to_string()
            } else {
                path.to_string()
            }
        };

        // Use proptest to check many possible inputs
        proptest!(|(path in "[a-zA-Z0-9_./-]{1,100}")| {
            // Check that path sanitization prevents traversal
            prop_assert!(!sanitize(&path).contains(".."));
            prop_assert!(!sanitize(&path).starts_with('/'));
        });
    }

    /// Integration test using the test fixture and property testing
    #[tokio::test]
    async fn test_repository_operations() {
        // Initialize the test fixture
        let fixture = TestFixture::new().await.unwrap();

        // Create a test repository
        let repo_path = fixture.create_test_repository("test-repo").await.unwrap();

        // Verify the repository exists
        assert!(repo_path.exists());
        assert!(repo_path.join(".git").exists());

        // Test repository service operations
        let repos = fixture.repository_service.list_repositories().await.unwrap();
        assert!(repos.iter().any(|r| r.name == "test-repo"));

        // Test property: Repository lookup by name is idempotent
        let lookup = |name: String| -> String {
            let repo = fixture.repository_service.get_repository_by_name(&name).unwrap();
            repo.name.clone()
        };

        // Check that lookup is idempotent (a core property)
        let result = check_idempotent(lookup, "test-repo".to_string());
        assert!(result.is_ok());
    }

    /// Property test using the test server
    #[tokio::test]
    async fn test_server_response_codes() {
        use crate::testing::harness::TestServer;

        // Create a test server
        let server = TestServer::new().await.unwrap();

        // Create a test repository
        server.create_repository("test-repo").await.unwrap();

        // Define a generator for repository API paths
        let repo_api_paths = proptest::collection::vec(
            "[a-zA-Z0-9_.-]+",
            1..5
        ).prop_map(|segments| {
            format!("/repo/test-repo/{}", segments.join("/"))
        });

        // Use proptest to test various paths
        proptest!(
            async move |(path in repo_api_paths)| {
                // Make a request to the path
                let response = server.get(&path).await;

                // Assert the response is either 200 OK or 404 Not Found
                // but never 500 Internal Server Error
                let status = response.status().as_u16();
                prop_assert!(
                    status == 200 || status == 404,
                    "Expected 200 or 404, got {} for path {}",
                    status,
                    path
                );

                Ok(())
            }
        );
    }

    /// Test for observability metrics
    #[tokio::test]
    async fn test_observability_metrics() {
        // Initialize the test fixture
        let fixture = TestFixture::new().await.unwrap();

        // Record some metrics
        fixture.observability_service.record_http_request("GET", "/test");
        fixture.observability_service.record_http_response("GET", "/test", 200);

        // Get metrics as string
        let metrics = fixture.observability_service.metrics_as_string().unwrap();

        // Check that metrics contain expected values
        assert!(metrics.contains("http_requests_total"));
        assert!(metrics.contains("http_response_status"));
    }
}
