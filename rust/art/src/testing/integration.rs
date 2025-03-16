// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Integration testing utilities for Art
//!
//! This module provides utilities for integration testing, allowing for testing
//! the entire system with various components working together.

use crate::prelude::*;
use crate::state::AppState;
use crate::testing::fixtures::TestFixture;
use crate::testing::harness::TestServer;
use reqwest::StatusCode;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

/// A test environment for running full integration tests
pub struct IntegrationTestEnv {
    /// The test server running the application
    pub server: TestServer,

    /// Test fixture with temporary resources
    pub fixture: TestFixture,

    /// The base URL for API requests
    pub api_url: String,

    /// The application state
    pub app_state: Arc<AppState>,

    /// HTTP client for making requests
    pub client: reqwest::Client,
}

impl IntegrationTestEnv {
    /// Create a new integration test environment
    pub async fn new() -> Result<Self> {
        // Create test fixture
        let fixture = TestFixture::new().await?;

        // Create test server
        let server = TestServer::new().await?;

        // Create HTTP client
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;

        // Get the app state from the server
        let app_state = server.app_state.clone();

        // Construct API URL
        let api_url = format!("{}/api", server.base_url);

        Ok(Self {
            server,
            fixture,
            api_url,
            app_state,
            client,
        })
    }

    /// Create a repository for testing
    pub async fn create_repository(&self, name: &str) -> Result<String> {
        let repo_path = self.server.create_repository(name).await?;
        Ok(repo_path)
    }

    /// Make a GET request to the API
    pub async fn get(&self, path: &str) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.api_url, path);
        let resp = self.client.get(&url).send().await?;
        Ok(resp)
    }

    /// Make a POST request to the API
    pub async fn post(&self, path: &str, body: impl serde::Serialize) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.api_url, path);
        let resp = self.client.post(&url).json(&body).send().await?;
        Ok(resp)
    }

    /// Make a PUT request to the API
    pub async fn put(&self, path: &str, body: impl serde::Serialize) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.api_url, path);
        let resp = self.client.put(&url).json(&body).send().await?;
        Ok(resp)
    }

    /// Make a DELETE request to the API
    pub async fn delete(&self, path: &str) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.api_url, path);
        let resp = self.client.delete(&url).send().await?;
        Ok(resp)
    }

    /// Verify repository creation and access via API
    pub async fn verify_repository_api(&self, name: &str) -> Result<()> {
        // Create a repository
        let repo_path = self.create_repository(name).await?;

        // Verify we can get it via the API
        let resp = self.get(&format!("/repositories/{}", name)).await?;
        ensure!(resp.status() == StatusCode::OK, "Failed to get repository via API");

        // Verify the repository data
        let repo_data: serde_json::Value = resp.json().await?;
        ensure!(repo_data["name"] == name, "Repository name mismatch");
        ensure!(repo_data["path"].as_str().unwrap().contains(&repo_path), "Repository path mismatch");

        // Verify we can list it via the API
        let resp = self.get("/repositories").await?;
        ensure!(resp.status() == StatusCode::OK, "Failed to list repositories via API");

        let repos: Vec<serde_json::Value> = resp.json().await?;
        ensure!(!repos.is_empty(), "Repository list should not be empty");
        ensure!(repos.iter().any(|r| r["name"] == name), "Repository should be in the list");

        Ok(())
    }
}

/// Run a function with a fresh integration test environment
pub async fn with_integration_env<F, Fut, T>(f: F) -> Result<T>
where
    F: FnOnce(IntegrationTestEnv) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let env = IntegrationTestEnv::new().await?;
    f(env).await
}

/// A builder for creating scenarios for integration tests
pub struct ScenarioBuilder {
    /// The integration test environment
    env: Option<IntegrationTestEnv>,

    /// Repository names to create
    repositories: Vec<String>,

    /// Files to create in repositories (repo_name, path, content)
    files: Vec<(String, String, String)>,

    /// Commands to run in repositories (repo_name, command)
    commands: Vec<(String, String)>,

    /// Environment variables to set
    env_vars: Vec<(String, String)>,
}

impl ScenarioBuilder {
    /// Create a new scenario builder
    pub fn new() -> Self {
        Self {
            env: None,
            repositories: Vec::new(),
            files: Vec::new(),
            commands: Vec::new(),
            env_vars: Vec::new(),
        }
    }

    /// Add a repository to create
    pub fn with_repository(mut self, name: impl Into<String>) -> Self {
        self.repositories.push(name.into());
        self
    }

    /// Add a file to create in a repository
    pub fn with_file(
        mut self,
        repo_name: impl Into<String>,
        path: impl Into<String>,
        content: impl Into<String>,
    ) -> Self {
        self.files.push((repo_name.into(), path.into(), content.into()));
        self
    }

    /// Add a command to run in a repository
    pub fn with_command(
        mut self,
        repo_name: impl Into<String>,
        command: impl Into<String>,
    ) -> Self {
        self.commands.push((repo_name.into(), command.into()));
        self
    }

    /// Add an environment variable to set
    pub fn with_env_var(
        mut self,
        key: impl Into<String>,
        value: impl Into<String>,
    ) -> Self {
        self.env_vars.push((key.into(), value.into()));
        self
    }

    /// Build the scenario and return the integration test environment
    pub async fn build(mut self) -> Result<IntegrationTestEnv> {
        // Create a new integration test environment if one doesn't exist
        if self.env.is_none() {
            self.env = Some(IntegrationTestEnv::new().await?);
        }

        let env = self.env.as_ref().unwrap();

        // Set environment variables
        for (key, value) in self.env_vars {
            std::env::set_var(key, value);
        }

        // Create repositories
        for repo_name in &self.repositories {
            env.create_repository(repo_name).await?;
        }

        // Create files
        for (repo_name, file_path, content) in &self.files {
            // Find the repository path
            let resp = env.get(&format!("/repositories/{}", repo_name)).await?;
            ensure!(resp.status() == StatusCode::OK, "Failed to get repository via API");

            let repo_data: serde_json::Value = resp.json().await?;
            let repo_path = repo_data["path"].as_str().unwrap();

            // Create the file
            let full_path = Path::new(repo_path).join(file_path);
            if let Some(parent) = full_path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::write(full_path, content)?;
        }

        // Run commands
        for (repo_name, command) in &self.commands {
            // Find the repository path
            let resp = env.get(&format!("/repositories/{}", repo_name)).await?;
            ensure!(resp.status() == StatusCode::OK, "Failed to get repository via API");

            let repo_data: serde_json::Value = resp.json().await?;
            let repo_path = repo_data["path"].as_str().unwrap();

            // Run the command
            let output = tokio::process::Command::new("sh")
                .arg("-c")
                .arg(command)
                .current_dir(repo_path)
                .output()
                .await?;

            ensure!(output.status.success(), "Command failed: {}", command);
        }

        // Return the environment
        Ok(self.env.unwrap())
    }
}

impl Default for ScenarioBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_integration_env() {
        let env = IntegrationTestEnv::new().await.unwrap();

        // Create a repository
        let repo_name = "test-integration-env";
        env.create_repository(repo_name).await.unwrap();

        // Verify we can get it via the API
        let resp = env.get(&format!("/repositories/{}", repo_name)).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        // Verify the repository data
        let repo_data: serde_json::Value = resp.json().await.unwrap();
        assert_eq!(repo_data["name"], repo_name);
    }

    #[tokio::test]
    async fn test_with_integration_env() {
        let result = with_integration_env(|env| async move {
            // Create a repository
            let repo_name = "test-with-integration-env";
            env.create_repository(repo_name).await?;

            // Verify we can get it via the API
            let resp = env.get(&format!("/repositories/{}", repo_name)).await?;
            ensure!(resp.status() == StatusCode::OK, "Failed to get repository via API");

            Ok(repo_name.to_string())
        }).await.unwrap();

        assert_eq!(result, "test-with-integration-env");
    }

    #[tokio::test]
    async fn test_scenario_builder() {
        let env = ScenarioBuilder::new()
            .with_repository("test-scenario-builder")
            .with_file("test-scenario-builder", "README.md", "# Test Repository")
            .with_command("test-scenario-builder", "git init && git add README.md && git commit -m 'Initial commit'")
            .build()
            .await
            .unwrap();

        // Verify we can get the repository via the API
        let resp = env.get("/repositories/test-scenario-builder").await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        // Verify it has a commit
        let resp = env.get("/repositories/test-scenario-builder/commits").await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let commits: Vec<serde_json::Value> = resp.json().await.unwrap();
        assert!(!commits.is_empty(), "Repository should have commits");
        assert_eq!(commits[0]["message"], "Initial commit");
    }
}
