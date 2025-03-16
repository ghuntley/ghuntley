//! API routes for the Art application

use crate::http::ServerState;
use crate::http::error::{ApiError, not_found, bad_request, internal_error};
use crate::error::Result;

use axum::{
    extract::{Path, Query, State, Extension},
    routing::{get, post},
    Json, Router,
};
use axum::response::IntoResponse;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use hyper::Body;
use hyper::Response;
use hyper::StatusCode;
use chrono::{DateTime, Utc};
use serde_json;

/// Create all API routes
pub fn api_routes(state: ServerState) -> Router {
    Router::new()
        // Repository API
        .route("/repos", get(list_repos))
        .route("/repos/:name", get(get_repo))
        .route("/repos/:name/branches", get(list_branches))
        .route("/repos/:name/tags", get(list_tags))

        // Commit API
        .route("/repos/:name/commits", get(list_commits))
        .route("/repos/:name/commits/:id", get(get_commit))

        // File API
        .route("/repos/:name/tree/:ref/*path", get(get_file_or_dir))
        .route("/repos/:name/blob/:ref/*path", get(get_file))
        .route("/repos/:name/raw/:ref/*path", get(get_raw_file))

        // Search API
        .route("/search", get(search))
        .route("/search/suggestions", get(search_suggestions))
        .route("/search/symbol", get(symbol_search))
        .route("/search/semantic", get(semantic_search))
        .route("/search/regex", get(regex_search))
        .route("/search/path", get(path_search))
        .route("/search/commit", get(commit_search))

        // System API
        .route("/health", get(health_check))
        .route("/metrics", get(metrics))
        .route("/logs", get(query_logs))
        .route("/repo/:repo/metrics", get(repository_metrics))
        .route("/repos/metrics", get(all_repository_metrics))
        .route("/repos/metrics/refresh", post(refresh_repository_metrics))
        .route("/repo/:repo/activity", get(repository_activity))
        .with_state(state)
}

/// Repository list response
#[derive(Debug, Serialize)]
struct RepoListResponse {
    repositories: Vec<RepoInfo>,
}

/// Repository info response
#[derive(Debug, Serialize)]
struct RepoInfo {
    name: String,
    description: Option<String>,
    branches: usize,
    tags: usize,
    last_updated: Option<String>,
}

/// List all repositories
async fn list_repos(
    State(state): State<ServerState>,
) -> Result<Json<RepoListResponse>, ApiError> {
    // Get repositories from Git
    let repos = state.git.list_repositories()
        .map_err(|e| internal_error(format!("Failed to list repositories: {}", e)))?;

    // Convert to response format
    let repos_info = repos.into_iter()
        .map(|repo| {
            RepoInfo {
                name: repo.name,
                description: repo.description,
                branches: repo.branch_count,
                tags: repo.tag_count,
                last_updated: repo.last_commit.map(|dt| dt.to_rfc3339()),
            }
        })
        .collect();

    Ok(Json(RepoListResponse { repositories: repos_info }))
}

/// Get details of a specific repository
async fn get_repo(
    State(state): State<ServerState>,
    Path(name): Path<String>,
) -> Result<Json<RepoInfo>, ApiError> {
    // Get repository info
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get repository info
    let info = repo.info()
        .map_err(|e| internal_error(format!("Failed to get repository info: {}", e)))?;

    // Convert to response format
    let repo_info = RepoInfo {
        name: info.name,
        description: info.description,
        branches: info.branch_count,
        tags: info.tag_count,
        last_updated: info.last_commit.map(|dt| dt.to_rfc3339()),
    };

    Ok(Json(repo_info))
}

/// Branch list response
#[derive(Debug, Serialize)]
struct BranchListResponse {
    branches: Vec<String>,
}

/// List branches for a repository
async fn list_branches(
    State(state): State<ServerState>,
    Path(name): Path<String>,
) -> Result<Json<BranchListResponse>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get branches
    let branches = repo.branches()
        .map_err(|e| internal_error(format!("Failed to get branches: {}", e)))?;

    // Extract branch names
    let branch_names = branches.keys().cloned().collect();

    Ok(Json(BranchListResponse { branches: branch_names }))
}

/// Tag list response
#[derive(Debug, Serialize)]
struct TagListResponse {
    tags: Vec<String>,
}

/// List tags for a repository
async fn list_tags(
    State(state): State<ServerState>,
    Path(name): Path<String>,
) -> Result<Json<TagListResponse>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get tags
    let tags = repo.tags()
        .map_err(|e| internal_error(format!("Failed to get tags: {}", e)))?;

    // Extract tag names
    let tag_names = tags.keys().cloned().collect();

    Ok(Json(TagListResponse { tags: tag_names }))
}

/// Commit list query parameters
#[derive(Debug, Deserialize)]
struct CommitListQuery {
    limit: Option<usize>,
}

/// Commit list response
#[derive(Debug, Serialize)]
struct CommitListResponse {
    commits: Vec<CommitInfo>,
}

/// Commit info response
#[derive(Debug, Serialize)]
struct CommitInfo {
    id: String,
    author_name: String,
    author_email: String,
    message: String,
    time: String,
    parents: Vec<String>,
}

/// List commits for a repository
async fn list_commits(
    State(state): State<ServerState>,
    Path(name): Path<String>,
    Query(params): Query<CommitListQuery>,
) -> Result<Json<CommitListResponse>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get the HEAD commit
    let head_commit = repo.last_commit()
        .map_err(|e| internal_error(format!("Failed to get HEAD commit: {}", e)))?
        .ok_or_else(|| not_found("No commits found".to_string()))?;

    // Start with the HEAD commit
    let mut commits = Vec::new();
    let mut current = Some(head_commit);
    let limit = params.limit.unwrap_or(10);

    // Walk the commit history up to the limit
    while let Some(commit) = current {
        if commits.len() >= limit {
            break;
        }

        let info = commit.info();
        commits.push(CommitInfo {
            id: info.id.clone(),
            author_name: info.author.name.clone(),
            author_email: info.author.email.clone(),
            message: info.message.clone(),
            time: info.time.to_rfc3339(),
            parents: info.parents.clone(),
        });

        // Move to the first parent
        if let Some(parent_id) = info.parents.first() {
            current = repo.commit(parent_id)
                .map_err(|e| internal_error(format!("Failed to get parent commit: {}", e)))?
                .ok_or_else(|| internal_error("Parent commit not found".to_string()))?
                .into();
        } else {
            current = None;
        }
    }

    Ok(Json(CommitListResponse { commits }))
}

/// Get details of a specific commit
async fn get_commit(
    State(state): State<ServerState>,
    Path((name, id)): Path<(String, String)>,
) -> Result<Json<CommitInfo>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get the commit
    let commit = repo.commit(&id)
        .map_err(|e| internal_error(format!("Failed to get commit: {}", e)))?
        .ok_or_else(|| not_found(format!("Commit '{}' not found", id)))?;

    // Create response
    let info = commit.info();
    let commit_info = CommitInfo {
        id: info.id.clone(),
        author_name: info.author.name.clone(),
        author_email: info.author.email.clone(),
        message: info.message.clone(),
        time: info.time.to_rfc3339(),
        parents: info.parents.clone(),
    };

    Ok(Json(commit_info))
}

/// File or directory response
#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum FileOrDirResponse {
    #[serde(rename = "file")]
    File {
        name: String,
        path: String,
        size: usize,
        is_binary: bool,
        content: Option<String>,
    },
    #[serde(rename = "directory")]
    Directory {
        path: String,
        entries: Vec<FileEntry>,
    },
}

/// File entry in directory listing
#[derive(Debug, Serialize)]
struct FileEntry {
    name: String,
    path: String,
    size: usize,
    is_dir: bool,
    last_modified: Option<String>,
}

/// Get file or directory content
async fn get_file_or_dir(
    State(state): State<ServerState>,
    Path((name, git_ref, path)): Path<(String, String, String)>,
) -> Result<Json<FileOrDirResponse>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // List files at the path
    let files = repo.list_files(&path, &git_ref)
        .map_err(|e| internal_error(format!("Failed to list files: {}", e)))?;

    if files.is_empty() {
        // Try to get file content
        match repo.file(&path, &git_ref) {
            Ok(file) => {
                // This is a file
                let is_binary = file.is_binary;
                let content = if !is_binary {
                    // Only include content for text files
                    let text = String::from_utf8_lossy(&file.content).to_string();
                    Some(text)
                } else {
                    None
                };

                Ok(Json(FileOrDirResponse::File {
                    name: path.split('/').last().unwrap_or(&path).to_string(),
                    path,
                    size: file.size,
                    is_binary,
                    content,
                }))
            },
            Err(_) => {
                // Neither a file nor a directory
                Err(not_found(format!("Path '{}' not found", path)))
            }
        }
    } else {
        // This is a directory
        let entries = files.into_iter()
            .map(|file| FileEntry {
                name: file.name.to_string(),
                path: file.path.to_string_lossy().to_string(),
                size: file.size,
                is_dir: file.is_dir,
                last_modified: file.last_modified.map(|dt| dt.to_rfc3339()),
            })
            .collect();

        Ok(Json(FileOrDirResponse::Directory { path, entries }))
    }
}

/// Get file content
async fn get_file(
    State(state): State<ServerState>,
    Path((name, git_ref, path)): Path<(String, String, String)>,
) -> Result<Json<FileOrDirResponse>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get file content
    let file = repo.file(&path, &git_ref)
        .map_err(|e| internal_error(format!("Failed to get file: {}", e)))?;

    // Determine if the file is binary
    let is_binary = file.is_binary;

    // Create the response
    let content = if !is_binary {
        // Only include content for text files
        let text = String::from_utf8_lossy(&file.content).to_string();
        Some(text)
    } else {
        None
    };

    Ok(Json(FileOrDirResponse::File {
        name: path.split('/').last().unwrap_or(&path).to_string(),
        path,
        size: file.size,
        is_binary,
        content,
    }))
}

/// Get raw file content
async fn get_raw_file(
    State(state): State<ServerState>,
    Path((name, git_ref, path)): Path<(String, String, String)>,
) -> Result<Vec<u8>, ApiError> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&name);

    if !repo_path.exists() {
        return Err(not_found(format!("Repository '{}' not found", name)));
    }

    // Open the repository
    let repo = state.git.open(&name, &repo_path)
        .map_err(|e| internal_error(format!("Failed to open repository: {}", e)))?;

    // Get file content
    let file = repo.file(&path, &git_ref)
        .map_err(|e| internal_error(format!("Failed to get file: {}", e)))?;

    Ok(file.content)
}

/// Health check response
#[derive(Debug, Serialize)]
struct HealthCheckResponse {
    status: String,
    version: String,
    uptime: u64,
    components: HashMap<String, ComponentStatus>,
}

/// Component status
#[derive(Debug, Serialize)]
struct ComponentStatus {
    status: String,
    message: Option<String>,
}

/// Perform a health check
async fn health_check(
    State(state): State<ServerState>,
) -> Result<Json<HealthCheckResponse>, ApiError> {
    // Get observability service
    let observability_service = state.observability_service
        .as_ref()
        .ok_or_else(|| internal_error("Observability service not configured".to_string()))?;

    // Perform health check
    let health = observability_service.health_check().await
        .map_err(|e| internal_error(format!("Health check failed: {}", e)))?;

    // Convert to response format
    let response = HealthCheckResponse {
        status: health.status,
        version: health.version,
        uptime: health.uptime,
        components: health.components,
    };

    Ok(Json(response))
}

/// Get Prometheus metrics
async fn metrics(
    State(state): State<ServerState>,
    Query(params): Query<HashMap<String, String>>,
) -> Response<Body> {
    // Get observability service
    if let Some(observability_service) = state.observability_service.as_ref() {
        // Check if metrics should be reset
        if params.get("reset").map(|v| v == "true").unwrap_or(false) {
            observability_service.reset_metrics();
        }

        // Get metrics
        match observability_service.metrics_as_string() {
            Ok(metrics) => Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "text/plain")
                .body(Body::from(metrics))
                .unwrap(),
            Err(e) => Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::from(format!("Error generating metrics: {}", e)))
                .unwrap(),
        }
    } else {
        Response::builder()
            .status(StatusCode::SERVICE_UNAVAILABLE)
            .body(Body::from("Metrics service not available"))
            .unwrap()
    }
}

/// Query parameters for logs endpoint
#[derive(Debug, Deserialize)]
struct LogsQuery {
    level: Option<String>,
    start: Option<String>,
    end: Option<String>,
    limit: Option<usize>,
}

/// Query logs
async fn query_logs(
    State(state): State<ServerState>,
    Query(params): Query<LogsQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    // Get observability service
    let observability_service = state.observability_service
        .as_ref()
        .ok_or_else(|| internal_error("Observability service not configured".to_string()))?;

    // Parse query parameters
    let level = params.level.as_deref().map(LogLevel::from);

    let start_time = params.start
        .as_deref()
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&Utc));

    let end_time = params.end
        .as_deref()
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&Utc));

    let limit = params.limit.unwrap_or(100);

    // Query logs
    let logs = observability_service.query_logs(level, start_time, end_time, limit).await
        .map_err(|e| internal_error(format!("Failed to query logs: {}", e)))?;

    // Convert to JSON response
    let json = serde_json::to_value(logs)
        .map_err(|e| internal_error(format!("Failed to serialize logs: {}", e)))?;

    Ok(Json(json))
}

/// Get telemetry data
async fn telemetry(
    State(state): State<ServerState>,
) -> Result<Json<SystemMetrics>, ApiError> {
    // Get observability service
    let observability_service = state.observability_service
        .as_ref()
        .ok_or_else(|| internal_error("Observability service not configured".to_string()))?;

    // Get system metrics
    let metrics = observability_service.system_metrics();

    Ok(Json(metrics))
}

/// Search query parameters
#[derive(Debug, Deserialize)]
struct SearchQuery {
    /// Search query string
    q: String,

    /// Optional repository filter
    repo: Option<String>,

    /// Optional file path filter
    path: Option<String>,

    /// Optional language filter
    language: Option<String>,

    /// Optional author filter
    author: Option<String>,

    /// Optional time range filter (ISO 8601 format "start,end")
    time_range: Option<String>,

    /// Optional context lines
    context: Option<usize>,

    /// Optional maximum results
    limit: Option<usize>,

    /// Whether to include snippets in results
    #[serde(default = "default_true")]
    snippets: bool,

    /// Whether to get suggestions
    #[serde(default)]
    suggestions: bool,

    /// Optional sort order ("relevance", "date", "path")
    sort: Option<String>,

    /// Whether to use regex
    #[serde(default)]
    regex: bool,

    /// Whether search is case sensitive
    #[serde(default)]
    case_sensitive: bool,
}

/// Default value for snippets (true)
fn default_true() -> bool {
    true
}

/// Enhanced search result for the API
#[derive(Debug, Serialize)]
struct ApiSearchResponse {
    /// The original query
    query: String,

    /// Total number of matches
    total_matches: usize,

    /// Repositories with matches
    repositories: Vec<ApiRepositoryMatches>,

    /// Suggested search terms
    suggestions: Option<Vec<String>>,

    /// Breakdowns by language
    languages: HashMap<String, usize>,

    /// Breakdowns by author
    authors: HashMap<String, usize>,

    /// Breakdowns by time period
    time_periods: HashMap<String, usize>,

    /// Related searches
    related_searches: Vec<String>,

    /// Search type used
    search_type: String,

    /// Time taken to perform search (ms)
    elapsed_ms: u64,
}

/// Repository matches for the API
#[derive(Debug, Serialize)]
struct ApiRepositoryMatches {
    /// Repository name
    name: String,

    /// Total matches in this repository
    matches: usize,

    /// Files with matches
    files: Vec<ApiFileMatch>,

    /// Recent commits affecting matching files (if requested)
    recent_commits: Option<Vec<ApiCommitSummary>>,
}

/// File match for the API
#[derive(Debug, Serialize)]
struct ApiFileMatch {
    /// File path
    path: String,

    /// Total matches in this file
    matches: usize,

    /// Language detected for the file
    language: Option<String>,

    /// Contributors to this file (if requested)
    contributors: Option<Vec<String>>,

    /// Lines with matches
    lines: Vec<ApiLineMatch>,
}

/// Line match for the API
#[derive(Debug, Serialize)]
struct ApiLineMatch {
    /// Line number (1-based)
    line_number: usize,

    /// Line content
    content: String,

    /// Matched terms in this line
    matches: Vec<String>,

    /// Context lines before (if requested)
    context_before: Option<Vec<String>>,

    /// Context lines after (if requested)
    context_after: Option<Vec<String>>,

    /// Last changed by (if requested)
    last_changed_by: Option<String>,

    /// Last changed at (if requested)
    last_changed_at: Option<String>,
}

/// Commit summary for the API
#[derive(Debug, Serialize)]
struct ApiCommitSummary {
    /// Commit ID
    id: String,

    /// Short commit ID
    short_id: String,

    /// Author name
    author: String,

    /// Commit date
    date: String,

    /// Commit message summary
    summary: String,
}

/// Perform a search across repositories
async fn search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service (at this point, we need to modify the ServerState to include these services)
    // This is just placeholder code until we update the ServerState
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.search(query, &options).await
        .map_err(|err| internal_error(format!("Search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "text", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Get search suggestions
async fn search_suggestions(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<Vec<String>>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Ok(Json(Vec::new()));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options with suggestions enabled
    let mut options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;
    options.get_suggestions = true;

    // Generate suggestions
    let suggestions = search_service.generate_suggestions(query, &options).await
        .map_err(|err| internal_error(format!("Failed to generate suggestions: {}", err)))?;

    Ok(Json(suggestions))
}

/// Perform a symbol search
async fn symbol_search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.symbol_search(query, &options).await
        .map_err(|err| internal_error(format!("Symbol search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "symbol", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Perform a semantic search
async fn semantic_search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.semantic_search(query, &options).await
        .map_err(|err| internal_error(format!("Semantic search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "semantic", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Perform a regex search
async fn regex_search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.regex_search(query, &options).await
        .map_err(|err| internal_error(format!("Regex search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "regex", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Perform a path search
async fn path_search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.path_search(query, &options).await
        .map_err(|err| internal_error(format!("Path search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "path", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Perform a commit search
async fn commit_search(
    State(state): State<ServerState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<ApiSearchResponse>, ApiError> {
    let query = params.q.trim();
    if query.is_empty() {
        return Err(bad_request("Search query cannot be empty"));
    }

    // Create search service
    let search_service = get_search_service(&state).await
        .map_err(|err| internal_error(format!("Failed to create search service: {}", err)))?;

    // Convert query params to search options
    let options = build_search_options(&params)
        .map_err(|err| bad_request(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.commit_search(query, &options).await
        .map_err(|err| internal_error(format!("Commit search failed: {}", err)))?;

    // Convert to API response
    let api_response = convert_search_result(search_result, "commit", start_time.elapsed().as_millis() as u64);

    Ok(Json(api_response))
}

/// Helper function to get search service from server state
async fn get_search_service(state: &ServerState) -> Result<crate::service::search::SearchService> {
    if let Some(service) = &state.search_service {
        // Return a cloned instance of the service
        Ok(service.as_ref().clone())
    } else {
        Err(Error::Internal("Search service not initialized".to_string()))
    }
}

/// Helper function to build search options from query parameters
fn build_search_options(params: &SearchQuery) -> Result<crate::service::search::AdvancedSearchOptions> {
    use crate::service::search::{AdvancedSearchOptions, SearchType};
    use crate::service::index::SearchOptions;

    // Create basic search options
    let mut basic_options = SearchOptions {
        regex: params.regex,
        case_sensitive: params.case_sensitive,
        path_pattern: params.path.clone(),
        repository: params.repo.clone(),
        max_results: params.limit,
    };

    // Parse time range if provided
    let time_range = if let Some(range_str) = &params.time_range {
        let parts: Vec<&str> = range_str.split(',').collect();
        if parts.len() == 2 {
            Some((parts[0].to_string(), parts[1].to_string()))
        } else {
            return Err(Error::InvalidInput("Time range must be in format 'start,end'".to_string()));
        }
    } else {
        None
    };

    // Create advanced search options
    let options = AdvancedSearchOptions {
        basic_options,
        search_type: SearchType::Text, // Default, may be overridden by specific endpoints
        authors: params.author.as_ref().map(|a| vec![a.clone()]),
        languages: params.language.as_ref().map(|l| vec![l.clone()]),
        time_range,
        context_lines: params.context,
        sort_by: params.sort.clone(),
        max_results: params.limit,
        include_snippets: params.snippets,
        get_suggestions: params.suggestions,
    };

    Ok(options)
}

/// Helper function to convert search result to API response
fn convert_search_result(
    result: crate::service::search::EnhancedSearchResult,
    search_type: &str,
    elapsed_ms: u64,
) -> ApiSearchResponse {
    // Convert repositories
    let repositories = result.repositories.into_iter().map(|repo| {
        // Convert files
        let files = repo.files.into_iter().map(|file| {
            // Convert lines
            let lines = file.lines.into_iter().map(|line| {
                ApiLineMatch {
                    line_number: line.base_match.line_number,
                    content: line.base_match.content,
                    matches: line.base_match.matches,
                    context_before: line.context_before,
                    context_after: line.context_after,
                    last_changed_by: line.last_changed_by,
                    last_changed_at: line.last_changed_at,
                }
            }).collect();

            ApiFileMatch {
                path: file.base_match.path,
                matches: file.base_match.matches,
                language: file.language,
                contributors: file.contributors,
                lines,
            }
        }).collect();

        // Convert commits if available
        let recent_commits = repo.recent_commits.map(|commits| {
            commits.into_iter().map(|commit| {
                ApiCommitSummary {
                    id: commit.id,
                    short_id: commit.short_id,
                    author: commit.author,
                    date: commit.date,
                    summary: commit.summary,
                }
            }).collect()
        });

        ApiRepositoryMatches {
            name: repo.base_matches.repository,
            matches: repo.base_matches.matches,
            files,
            recent_commits,
        }
    }).collect();

    // Convert breakdowns to HashMaps for the API
    let languages: HashMap<String, usize> = result.languages.into_iter().collect();
    let authors: HashMap<String, usize> = result.authors.into_iter().collect();
    let time_periods: HashMap<String, usize> = result.time_periods.into_iter().collect();

    ApiSearchResponse {
        query: result.base_result.query,
        total_matches: result.base_result.total_matches,
        repositories,
        suggestions: result.suggestions,
        languages,
        authors,
        time_periods,
        related_searches: result.related_searches,
        search_type: search_type.to_string(),
        elapsed_ms,
    }
}

/// Get repository content metrics
pub async fn repository_metrics(
    Extension(observability): Extension<Arc<ObservabilityService>>,
    Path(repo_name): Path<String>,
) -> Response {
    match observability.get_repository_metrics(&repo_name).await {
        Some(metrics) => (StatusCode::OK, axum::Json(metrics)).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            format!("No metrics found for repository: {}", repo_name),
        )
            .into_response(),
    }
}

/// Get repository activity metrics
pub async fn repository_activity(
    Extension(observability): Extension<Arc<ObservabilityService>>,
    Path(repo_name): Path<String>,
) -> Response {
    match observability.get_repository_activity(&repo_name).await {
        Some(activity) => (StatusCode::OK, axum::Json(activity)).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            format!("No activity metrics found for repository: {}", repo_name),
        )
            .into_response(),
    }
}

/// Get all repository content metrics
pub async fn all_repository_metrics(
    Extension(observability): Extension<Arc<ObservabilityService>>,
) -> impl IntoResponse {
    let metrics = observability.get_all_repository_metrics().await;
    (StatusCode::OK, axum::Json(metrics))
}

/// Refresh repository metrics
pub async fn refresh_repository_metrics(
    Extension(observability): Extension<Arc<ObservabilityService>>,
) -> Response {
    match observability.refresh_repository_metrics().await {
        Ok(_) => (
            StatusCode::OK,
            axum::Json(json!({
                "status": "success",
                "message": "Repository metrics refresh initiated successfully"
            }))
        ).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            axum::Json(json!({
                "status": "error",
                "message": format!("Failed to refresh repository metrics: {}", e)
            }))
        ).into_response(),
    }
}

/// Set up routes for observability endpoints
pub fn observability_routes<S>(
    router: &mut Router<S>,
    observability_service: Option<Arc<ObservabilityService>>,
) where
    S: Clone + Send + Sync + 'static,
{
    // If observability service is not configured, do nothing
    let Some(service) = observability_service else {
        return;
    };

    // Metrics endpoint
    router.route(
        "/metrics",
        get(move |query: Option<Query<HashMap<String, String>>>| {
            let service = service.clone();
            async move {
                let reset = query
                    .as_ref()
                    .and_then(|q| q.0.get("reset"))
                    .map(|v| v == "true")
                    .unwrap_or(false);

                if reset {
                    service.reset_metrics();
                }

                match service.metrics_as_string() {
                    Ok(metrics) => Response::builder()
                        .status(StatusCode::OK)
                        .header("Content-Type", "text/plain")
                        .body(Body::from(metrics))
                        .unwrap(),
                    Err(e) => Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .body(Body::from(format!("Error generating metrics: {}", e)))
                        .unwrap(),
                }
            }
        }),
    );

    // Health check endpoint
    router.route(
        "/health",
        get(move || {
            let service = service.clone();
            async move {
                match service.health_check().await {
                    Ok(health) => Response::builder()
                        .status(StatusCode::OK)
                        .header("Content-Type", "application/json")
                        .body(Body::from(
                            serde_json::to_string(&health).unwrap_or_default(),
                        ))
                        .unwrap(),
                    Err(e) => Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .body(Body::from(format!("Error checking health: {}", e)))
                        .unwrap(),
                }
            }
        }),
    );

    // Logs query endpoint
    router.route(
        "/logs",
        get(move |query: Option<Query<HashMap<String, String>>>| {
            let service = service.clone();
            async move {
                let query = query.unwrap_or_default().0;

                // Parse query parameters
                let level = query.get("level").map(|l| LogLevel::from(l.as_str()));

                let start_time = query.get("start")
                    .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.with_timezone(&Utc));

                let end_time = query.get("end")
                    .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.with_timezone(&Utc));

                let limit = query.get("limit")
                    .and_then(|l| l.parse::<usize>().ok())
                    .unwrap_or(100);

                match service.query_logs(level, start_time, end_time, limit).await {
                    Ok(logs) => Response::builder()
                        .status(StatusCode::OK)
                        .header("Content-Type", "application/json")
                        .body(Body::from(
                            serde_json::to_string(&logs).unwrap_or_default(),
                        ))
                        .unwrap(),
                    Err(e) => Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .body(Body::from(format!("Error querying logs: {}", e)))
                        .unwrap(),
                }
            }
        }),
    );
}

/// Set up API routes
pub fn api_routes<S>(router: &mut Router<S>, state: &S) -> Result<()>
where
    S: HasRepositoryService
        + HasHealthService
        + HasAuthService
        + HasGitService
        + HasIndexService
        + HasSearchService
        + HasStatusService
        + HasObservabilityService
        + Clone
        + Send
        + Sync
        + 'static,
{
    let repo_service = state.repository_service()?.clone();
    let health_service = state.health_service()?.clone();
    let git_service = state.git_service()?.clone();
    let auth_service = state.auth_service()?.clone();
    let index_service = state.index_service()?.clone();
    let search_service = state.search_service()?.clone();
    let status_service = state.status_service()?.clone();
    let observability_service = state.observability_service();

    // Set up routes
    let mut api_router = Router::new();

    // Repository routes
    repository_routes(&mut api_router, repo_service, auth_service);

    // Git routes
    git_routes(&mut api_router, git_service.clone());

    // Health routes
    health_routes(&mut api_router, health_service);

    // Index routes
    index_routes(&mut api_router, index_service);

    // Search routes
    search_routes(&mut api_router, search_service);

    // Status routes
    status_routes(&mut api_router, status_service);

    // Observability routes
    observability_routes(&mut api_router, observability_service);

    // Add API router under /api
    router.nest("/api", api_router);

    Ok(())
}

/// Add repository routes to the router
pub fn repository_routes<S>(
    router: &mut Router<S>,
    repository_service: Arc<crate::service::repository::RepositoryService>,
    auth_service: Arc<crate::service::auth::AuthService>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Add repository routes
    router
        .route("/repos", get(list_repos))
        .route("/repos/:name", get(get_repo))
        .route("/repos/:name/branches", get(list_branches))
        .route("/repos/:name/tags", get(list_tags))
        .route("/repos/:name/tree/:ref/*path", get(get_file_or_dir));
}

/// Add health routes to the router
pub fn health_routes<S>(
    router: &mut Router<S>,
    health_service: Arc<crate::service::health::HealthService>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Add health routes
    router
        .route("/health", get(health_check));
}

/// Add index routes to the router
pub fn index_routes<S>(
    router: &mut Router<S>,
    index_service: Option<Arc<crate::service::index::IndexService>>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Only add index routes if we have an index service
    if let Some(index_service) = index_service {
        // Add routes for indexing operations here
    }
}

/// Add search routes to the router
pub fn search_routes<S>(
    router: &mut Router<S>,
    search_service: Option<Arc<crate::service::search::SearchService>>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Only add search routes if we have a search service
    if let Some(search_service) = search_service {
        router
            .route("/search", get(search))
            .route("/search/suggestions", get(search_suggestions))
            .route("/search/symbol", get(symbol_search))
            .route("/search/semantic", get(semantic_search))
            .route("/search/regex", get(regex_search))
            .route("/search/path", get(path_search))
            .route("/search/commit", get(commit_search));
    }
}

/// Add git routes to the router
pub fn git_routes<S>(
    router: &mut Router<S>,
    git_service: Arc<crate::data::git::Git>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Add git-specific routes
    router
        .route("/repos/:name/commits", get(list_commits))
        .route("/repos/:name/commits/:id", get(get_commit))
        .route("/repos/:name/raw/:ref/*path", get(get_raw_file));
}

/// Add status routes to the router
pub fn status_routes<S>(
    router: &mut Router<S>,
    status_service: Arc<crate::service::status::StatusService>,
) where
    S: Clone + Send + Sync + 'static,
{
    // Add status routes
    router
        .route("/status", get(status_handler));
}

// Helper function for status route
async fn status_handler(
    State(status_service): State<Arc<crate::service::status::StatusService>>,
) -> impl IntoResponse {
    let status = status_service.get_system_status().await;
    Json(status)
}
