//! Integration tests for the Art application

use art::config::{Config, RepositoryConfig, DatabaseConfig};
use art::data::git::Git;
use art::data::database::Database;
use art::http::{ServerState, start_server};
use art::error::Result;

use axum::body::Body;
use hyper::{Client, Request};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::net::SocketAddr;
use std::str::FromStr;
use tempfile::TempDir;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

/// Creates a test repository with some commits
async fn setup_test_repository(dir: &TempDir, name: &str) -> Result<PathBuf> {
    let repo_path = dir.path().join(name);

    // Create a directory for the repository
    fs::create_dir_all(&repo_path)?;

    // Initialize the repository
    let output = Command::new("git")
        .args(&["init"])
        .current_dir(&repo_path)
        .output()?;

    if !output.status.success() {
        panic!("Failed to initialize git repository: {}", String::from_utf8_lossy(&output.stderr));
    }

    // Configure user information
    Command::new("git")
        .args(&["config", "user.name", "Test User"])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["config", "user.email", "test@example.com"])
        .current_dir(&repo_path)
        .output()?;

    // Create some files
    fs::write(repo_path.join("README.md"), "# Test Repository\n\nThis is a test repository.")?;

    // Add files and make first commit
    Command::new("git")
        .args(&["add", "."])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Initial commit"])
        .current_dir(&repo_path)
        .output()?;

    // Add another file and commit
    fs::write(repo_path.join("example.rs"), "fn main() {\n    println!(\"Hello, world!\");\n}")?;

    Command::new("git")
        .args(&["add", "."])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Add example Rust file"])
        .current_dir(&repo_path)
        .output()?;

    // Create a branch
    Command::new("git")
        .args(&["checkout", "-b", "feature"])
        .current_dir(&repo_path)
        .output()?;

    // Modify a file and commit on the branch
    fs::write(repo_path.join("example.rs"), "fn main() {\n    println!(\"Hello from feature branch!\");\n}")?;

    Command::new("git")
        .args(&["add", "."])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Update example in feature branch"])
        .current_dir(&repo_path)
        .output()?;

    // Return to main branch
    Command::new("git")
        .args(&["checkout", "master"])
        .current_dir(&repo_path)
        .output()?;

    // Create a tag
    Command::new("git")
        .args(&["tag", "-a", "v1.0", "-m", "Version 1.0"])
        .current_dir(&repo_path)
        .output()?;

    Ok(repo_path)
}

/// Starts a test server for integration testing
async fn start_test_server(temp_dir: &TempDir) -> Result<(SocketAddr, JoinHandle<()>, oneshot::Sender<()>)> {
    let repo_dir = temp_dir.path().join("repositories");
    let db_path = temp_dir.path().join("test.db");

    fs::create_dir_all(&repo_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: repo_dir.clone(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let db_config = DatabaseConfig {
        path: db_path,
        use_cache: true,
        cache_max_entries: 100,
        cache_ttl_seconds: 60,
    };

    let mut config = Config::default();
    config.repository = repo_config;
    config.database = db_config;

    // Choose a random available port
    let addr = SocketAddr::from_str("127.0.0.1:0")?;

    // Channel to shut down the server
    let (shutdown_tx, shutdown_rx) = oneshot::channel();

    // Start the server in a separate task
    let server_handle = tokio::spawn(async move {
        let _ = start_server(&config, &addr.to_string(), shutdown_rx).await;
    });

    // Give the server a moment to start
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    Ok((addr, server_handle, shutdown_tx))
}

/// Makes an HTTP request to the test server
async fn make_request(addr: &SocketAddr, path: &str) -> hyper::Result<hyper::Response<Body>> {
    let client = Client::new();
    let url = format!("http://{}{}", addr, path);

    let req = Request::builder()
        .uri(url)
        .method("GET")
        .body(Body::empty())?;

    client.request(req).await
}

/// Tests the complete repository workflow
#[tokio::test]
async fn test_repository_workflow() -> Result<()> {
    // Create a temporary directory for testing
    let temp_dir = TempDir::new()?;

    // Setup test repositories
    let repo_path = setup_test_repository(&temp_dir, "test-repo").await?;

    // Copy the repository to the repositories directory
    let repo_dir = temp_dir.path().join("repositories");
    fs::create_dir_all(&repo_dir)?;

    let target_path = repo_dir.join("test-repo.git");

    // Create a bare clone in the repositories directory
    Command::new("git")
        .args(&["clone", "--bare", repo_path.to_str().unwrap(), target_path.to_str().unwrap()])
        .output()?;

    // Start the test server
    let (addr, server_handle, shutdown_tx) = start_test_server(&temp_dir).await?;

    // Test the repository list endpoint
    let response = make_request(&addr, "/api/repos").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    let body_bytes = hyper::body::to_bytes(response.into_body()).await?;
    let body: serde_json::Value = serde_json::from_slice(&body_bytes)?;

    let repos = body["repositories"].as_array().unwrap();
    assert!(!repos.is_empty(), "Repository list should not be empty");

    // Find our test repository
    let repo = repos.iter().find(|r| r["name"].as_str().unwrap().contains("test-repo"));
    assert!(repo.is_some(), "Test repository should be in the list");

    // Test the repository detail endpoint
    let response = make_request(&addr, "/api/repos/test-repo").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    // Test the branches endpoint
    let response = make_request(&addr, "/api/repos/test-repo/branches").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    let body_bytes = hyper::body::to_bytes(response.into_body()).await?;
    let body: serde_json::Value = serde_json::from_slice(&body_bytes)?;

    let branches = body["branches"].as_array().unwrap();
    assert!(branches.len() >= 2, "Repository should have at least master and feature branches");

    // Test the commits endpoint
    let response = make_request(&addr, "/api/repos/test-repo/commits").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    let body_bytes = hyper::body::to_bytes(response.into_body()).await?;
    let body: serde_json::Value = serde_json::from_slice(&body_bytes)?;

    let commits = body["commits"].as_array().unwrap();
    assert!(commits.len() >= 2, "Repository should have at least two commits");

    // Test the file content endpoint
    let response = make_request(&addr, "/api/repos/test-repo/blob/master/README.md").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    let body_bytes = hyper::body::to_bytes(response.into_body()).await?;
    let body: serde_json::Value = serde_json::from_slice(&body_bytes)?;

    assert!(body["content"].as_str().unwrap().contains("# Test Repository"),
           "README.md content should contain the expected text");

    // Test a specific commit
    if let Some(commit) = commits.first() {
        let commit_id = commit["id"].as_str().unwrap();

        let response = make_request(&addr, &format!("/api/repos/test-repo/commits/{}", commit_id)).await?;
        assert_eq!(response.status(), hyper::StatusCode::OK);
    }

    // Test the web UI endpoints
    let response = make_request(&addr, "/").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    let response = make_request(&addr, "/test-repo").await?;
    assert_eq!(response.status(), hyper::StatusCode::OK);

    // Shutdown the server
    let _ = shutdown_tx.send(());
    let _ = server_handle.await;

    Ok(())
}

/// Tests concurrent access to repositories
#[tokio::test]
async fn test_concurrent_repository_access() -> Result<()> {
    // Create a temporary directory for testing
    let temp_dir = TempDir::new()?;

    // Setup test repositories
    let repo_path = setup_test_repository(&temp_dir, "test-repo").await?;

    // Copy the repository to the repositories directory
    let repo_dir = temp_dir.path().join("repositories");
    fs::create_dir_all(&repo_dir)?;

    let target_path = repo_dir.join("test-repo.git");

    // Create a bare clone in the repositories directory
    Command::new("git")
        .args(&["clone", "--bare", repo_path.to_str().unwrap(), target_path.to_str().unwrap()])
        .output()?;

    // Start the test server
    let (addr, server_handle, shutdown_tx) = start_test_server(&temp_dir).await?;

    // Make multiple concurrent requests
    let mut handles = Vec::new();

    for i in 0..10 {
        let addr_clone = addr.clone();

        let handle = tokio::spawn(async move {
            if i % 3 == 0 {
                // Request repository list
                let response = make_request(&addr_clone, "/api/repos").await.unwrap();
                assert_eq!(response.status(), hyper::StatusCode::OK);
            } else if i % 3 == 1 {
                // Request commits
                let response = make_request(&addr_clone, "/api/repos/test-repo/commits").await.unwrap();
                assert_eq!(response.status(), hyper::StatusCode::OK);
            } else {
                // Request file content
                let response = make_request(&addr_clone, "/api/repos/test-repo/blob/master/README.md").await.unwrap();
                assert_eq!(response.status(), hyper::StatusCode::OK);
            }
        });

        handles.push(handle);
    }

    // Wait for all requests to complete
    for handle in handles {
        let _ = handle.await;
    }

    // Shutdown the server
    let _ = shutdown_tx.send(());
    let _ = server_handle.await;

    Ok(())
}

/// Tests error handling with invalid inputs
#[tokio::test]
async fn test_error_handling() -> Result<()> {
    // Create a temporary directory for testing
    let temp_dir = TempDir::new()?;

    // Setup a minimal repository environment
    let repo_dir = temp_dir.path().join("repositories");
    fs::create_dir_all(&repo_dir)?;

    // Start the test server
    let (addr, server_handle, shutdown_tx) = start_test_server(&temp_dir).await?;

    // Test non-existent repository
    let response = make_request(&addr, "/api/repos/non-existent-repo").await?;
    assert_eq!(response.status(), hyper::StatusCode::NOT_FOUND);

    // Test non-existent commit
    let response = make_request(&addr, "/api/repos/test-repo/commits/non-existent-commit").await?;
    assert_eq!(response.status(), hyper::StatusCode::NOT_FOUND);

    // Test invalid branch
    let response = make_request(&addr, "/api/repos/test-repo/tree/non-existent-branch").await?;
    assert_eq!(response.status(), hyper::StatusCode::NOT_FOUND);

    // Test malformed request (invalid path traversal)
    let response = make_request(&addr, "/api/repos/test-repo/blob/master/../../../etc/passwd").await?;
    assert_eq!(response.status(), hyper::StatusCode::BAD_REQUEST);

    // Shutdown the server
    let _ = shutdown_tx.send(());
    let _ = server_handle.await;

    Ok(())
}

/// Tests repository indexing performance
#[tokio::test]
async fn test_indexing_performance() -> Result<()> {
    // Create a temporary directory for testing
    let temp_dir = TempDir::new()?;

    // Setup a repository with many commits for performance testing
    let repo_path = temp_dir.path().join("perf-repo");

    // Initialize the repository
    fs::create_dir_all(&repo_path)?;

    let _ = Command::new("git")
        .args(&["init"])
        .current_dir(&repo_path)
        .output()?;

    // Configure user information
    Command::new("git")
        .args(&["config", "user.name", "Test User"])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["config", "user.email", "test@example.com"])
        .current_dir(&repo_path)
        .output()?;

    // Create base files
    fs::write(repo_path.join("README.md"), "# Performance Test Repository")?;

    // Add files and make first commit
    Command::new("git")
        .args(&["add", "."])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Initial commit"])
        .current_dir(&repo_path)
        .output()?;

    // Create multiple commits (about 20) for performance testing
    for i in 1..21 {
        let filename = format!("file{}.txt", i);
        let content = format!("Content for file {}\n", i);

        fs::write(repo_path.join(&filename), content)?;

        Command::new("git")
            .args(&["add", &filename])
            .current_dir(&repo_path)
            .output()?;

        Command::new("git")
            .args(&["commit", "-m", &format!("Add file {}", i)])
            .current_dir(&repo_path)
            .output()?;
    }

    // Copy the repository to the repositories directory
    let repo_dir = temp_dir.path().join("repositories");
    fs::create_dir_all(&repo_dir)?;

    let target_path = repo_dir.join("perf-repo.git");

    // Create a bare clone in the repositories directory
    Command::new("git")
        .args(&["clone", "--bare", repo_path.to_str().unwrap(), target_path.to_str().unwrap()])
        .output()?;

    // Create database configuration
    let db_config = DatabaseConfig {
        path: temp_dir.path().join("perf-test.db"),
        use_cache: true,
        cache_max_entries: 1000,
        cache_ttl_seconds: 60,
    };

    // Create repository configuration
    let repo_config = RepositoryConfig {
        repo_dir: repo_dir.clone(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    // Create the database
    let db = Database::new(&db_config)?;

    // Create the Git manager
    let git = Git::new(&repo_config)?;

    // Measure performance of repository indexing
    let start_time = std::time::Instant::now();

    // Index repository
    let repos = git.list_repositories()?;

    for repo_info in repos {
        if repo_info.name == "perf-repo.git" {
            // Index repository in database
            db.index_repository(
                &repo_info.name,
                &repo_info.name,
                &repo_info.description.unwrap_or_default(),
            )?;

            // Open repository
            let repo = git.open(&repo_info.name, &repo_info.path)?;

            // Get repository info
            let info = repo.info()?;

            // Update repository stats
            db.update_repository_stats(
                &repo_info.name,
                info.branch_count,
                info.tag_count,
                info.commit_count,
            )?;

            // Index repository commits (limited to 10 for the test)
            let branches = repo.branches()?;
            if let Some((_, commit_id)) = branches.iter().next() {
                // Get commit history
                let mut commit = repo.commit(commit_id)?;

                // Index at most 10 commits
                let mut count = 0;
                while count < 10 {
                    // Index the commit
                    db.index_commit(
                        &repo_info.name,
                        commit.id(),
                        commit.message(),
                        &commit.author().name,
                        &commit.author().email,
                        commit.time().timestamp(),
                    )?;

                    count += 1;

                    // If this commit has parents, move to the first parent
                    if let Some(parent_id) = commit.parents().first() {
                        commit = repo.commit(parent_id)?;
                    } else {
                        break;
                    }
                }
            }
        }
    }

    let duration = start_time.elapsed();
    println!("Repository indexing took: {:?}", duration);

    // The test passes if indexing completes in a reasonable time
    // This is subjective, but we'll say under 5 seconds is acceptable
    assert!(duration.as_secs() < 5, "Repository indexing took too long: {:?}", duration);

    Ok(())
}
