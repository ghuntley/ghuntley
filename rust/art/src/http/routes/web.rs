//! Web routes for the Art application

use crate::http::ServerState;
use crate::template::{
    BaseTemplate, RepoListTemplate, RepoDetailTemplate,
    CommitListTemplate, CommitDetailTemplate,
    FileContentTemplate, DirectoryTemplate,
    TemplateRender, Pagination,
};
use crate::template::search::{
    SearchTemplate, SearchResults, RepositoryMatch,
    FileMatch, LineMatch, SearchStats, SearchFilters,
};
use crate::data::git::{FileInfo, Commit, CommitInfo};
use crate::error::{Error, Result};
use crate::util::{path, highlight};
use crate::http::routes::api::SearchQuery;
use super::current_year;
use super::user;

use axum::{
    extract::{Path, Query, State},
    response::{Html, Redirect},
    routing::get,
    Router,
};
use std::path::PathBuf;
use std::sync::Arc;
use serde::Deserialize;
use std::collections::HashMap;
use super::ApiError;

/// Create all web routes
pub fn web_routes(state: ServerState) -> Router {
    // Create the main router
    let main_router = Router::new()
        .route("/", get(index))
        .route("/about", get(about))
        .route("/accessibility/guide", get(accessibility_guide))

        // Repository routes
        .route("/:repo", get(repo_overview))
        .route("/:repo/", get(repo_overview))

        // Commit routes
        .route("/:repo/commits/:ref", get(commit_list))
        .route("/:repo/commits/:ref/", get(commit_list))
        .route("/:repo/commits/:ref/*path", get(commit_list_path))
        .route("/:repo/commit/:id", get(commit_detail))

        // File routes
        .route("/:repo/tree/:ref", get(repo_files))
        .route("/:repo/tree/:ref/", get(repo_files))
        .route("/:repo/tree/:ref/*path", get(repo_files_path))
        .route("/:repo/tree/:ref/*path/", get(repo_files_path))
        .route("/:repo/raw/:ref/*path", get(file_raw))
        .route("/:repo/blame/:ref/*path", get(file_blame))

        // Search routes
        .route("/search", get(search))

        // Merge with maintenance routes
        .merge(super::maintenance::maintenance_routes());

    // Add user routes
    let router_with_user = main_router.nest("/user", user::user_routes(state.clone()));

    // Return the router with state
    router_with_user.with_state(state)
}

/// Index page - repository list
async fn index(
    State(state): State<ServerState>,
) -> Result<Html<String>> {
    // Get repositories from Git
    let repos = state.git.list_repositories()?;

    // Render the repository list template
    let template = RepoListTemplate {
        repositories: repos,
    };

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// About page
async fn about(
    State(state): State<ServerState>,
) -> Result<Html<String>> {
    // Create about page template
    let base = BaseTemplate {
        title: "About Art",
        content: "<h1>About Art</h1><p>Art is a Git repository browser inspired by cgit.</p>".into(),
        body_classes: Some("about-page"),
        head: None,
    };

    Ok(Html(base.render_to_string()?))
}

/// Accessibility guide page handler
pub async fn accessibility_guide() -> Html<String> {
    // Create a simple response to avoid HTML parsing issues in the code
    let content = "Accessibility Guide for Art";

    // Create a base template
    let base = BaseTemplate {
        title: "Accessibility Guide",
        content: format!("<h1>{}</h1><p>Art is designed to be accessible to all users.</p>", content),
        body_classes: Some("accessibility-page"),
        head: None,
    };

    Ok(Html(base.render_to_string().unwrap_or_else(|_| String::from("Error rendering template"))))
}

/// Repository overview page
async fn repo_overview(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // Get branches and tags
    let branches = repo.branches()?;
    let tags = repo.tags()?;

    // Get default branch (or first branch if none is marked as default)
    let default_branch = branches.keys()
        .find(|&name| name == "main" || name == "master")
        .or_else(|| branches.keys().next())
        .cloned()
        .unwrap_or_else(|| "HEAD".to_string());

    // Create branch and tag lists
    let branch_list = branches.iter()
        .map(|(name, target)| (name.as_str(), target.as_str()))
        .collect();

    let tag_list = tags.iter()
        .map(|(name, target)| (name.as_str(), target.as_str()))
        .collect();

    // Render the repository detail template
    let template = RepoDetailTemplate::new(
        &info,
        &default_branch,
        branch_list,
        tag_list,
    );

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// Commit list query parameters
#[derive(Debug, Deserialize)]
struct CommitListQuery {
    page: Option<usize>,
    limit: Option<usize>,
}

/// Commit list for a repository
async fn commit_list(
    State(state): State<ServerState>,
    Path((repo_name, git_ref)): Path<(String, String)>,
    Query(params): Query<CommitListQuery>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // Get the HEAD commit
    let head_commit = repo.last_commit()?
        .ok_or_else(|| Error::NotFound("No commits found".to_string()))?;

    // Start with the HEAD commit
    let mut commits = Vec::new();
    let mut current = Some(head_commit);
    let limit = params.limit.unwrap_or(20);
    let page = params.page.unwrap_or(1);
    let offset = (page - 1) * limit;

    // Track current position
    let mut position = 0;

    // Walk the commit history up to the limit + offset
    while let Some(commit) = current {
        if position >= offset && commits.len() < limit {
            commits.push(commit.info().clone());
        }

        position += 1;

        if position >= offset + limit {
            break;
        }

        // Move to the first parent
        if let Some(parent_id) = commit.info().parents.first() {
            current = repo.commit(parent_id)?.map(|c| c);
        } else {
            current = None;
        }
    }

    // Render the commit list template
    let template = CommitListTemplate {
        repo: &info,
        current_ref: &git_ref,
        commits,
    };

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// Commit list for a specific path in a repository
async fn commit_list_path(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, path)): Path<(String, String, String)>,
    Query(params): Query<CommitListQuery>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // TODO: Implement commit history for a specific path
    // This would require file history tracking which is complex
    // For now, redirect to commit list for the entire repository

    Ok(Html(format!("<script>window.location.href='/{}/commits/{}';</script>", repo_name, git_ref)))
}

/// Commit detail page
async fn commit_detail(
    State(state): State<ServerState>,
    Path((repo_name, commit_id)): Path<(String, String)>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // Get the commit
    let commit = repo.commit(&commit_id)?
        .ok_or_else(|| Error::NotFound(format!("Commit {} not found", commit_id)))?;

    // TODO: Find child commits by scanning repository
    // This requires walking all commits which is expensive
    // For now, use an empty list
    let children = Vec::new();

    // TODO: Generate diff HTML
    // This requires comparing with parent commit
    // For now, use None
    let diff_html = None;

    // Render the commit detail template
    let template = CommitDetailTemplate::new(
        &info,
        commit.info(),
        children,
        diff_html,
    );

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// Repository files page (root directory)
async fn repo_files(
    State(state): State<ServerState>,
    Path((repo_name, git_ref)): Path<(String, String)>,
) -> Result<Html<String>> {
    // Forward to repo_files_path with empty path
    repo_files_path(state, Path((repo_name, git_ref, String::new()))).await
}

/// Repository files page for a specific path
async fn repo_files_path(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, file_path)): Path<(String, String, String)>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // Normalize the path
    let normalized_path = path::normalize_path(&file_path);

    // List files at the path
    let files = repo.list_files(&normalized_path, &git_ref)?;

    if files.is_empty() {
        // Try to get file content
        match repo.file(&normalized_path, &git_ref) {
            Ok(_) => {
                // This is a file - redirect to file content view
                return Ok(Html(format!(
                    "<script>window.location.href='/{}/blob/{}/{}';</script>",
                    repo_name, git_ref, normalized_path
                )));
            },
            Err(_) => {
                // Neither a file nor a directory
                return Err(Error::NotFound(format!("Path {} not found", normalized_path)));
            }
        }
    }

    // Get the last commit for this directory
    let last_commit = repo.last_commit()?
        .ok_or_else(|| Error::NotFound("No commits found".to_string()))?;

    // Render the directory template
    let template = DirectoryTemplate::new(
        &info,
        &git_ref,
        &normalized_path,
        files,
        &last_commit.id(),
        &last_commit.message(),
        &last_commit.author().name,
        last_commit.time(),
    );

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// File content page
async fn file_content(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, file_path)): Path<(String, String, String)>,
) -> Result<Html<String>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Get repository info
    let info = repo.info()?;

    // Normalize the path
    let normalized_path = path::normalize_path(&file_path);

    // Get file content
    let file_content = repo.file(&normalized_path, &git_ref)?;

    // Check if file is binary
    let is_binary = file_content.is_binary;
    let path_obj = PathBuf::from(&normalized_path);

    // Get file content as text
    let content = if !is_binary {
        String::from_utf8_lossy(&file_content.content).to_string()
    } else {
        String::new()
    };

    // Get syntax highlighting if text file
    let content_html = if !is_binary {
        highlight::highlight_syntax(&path_obj, &content).ok()
    } else {
        None
    };

    // Create a placeholder FileInfo
    let file_info = FileInfo {
        path: path_obj,
        name: normalized_path.split('/').last().unwrap_or(&normalized_path).to_string(),
        size: file_content.size,
        is_dir: false,
        last_modified: None,
        last_commit_id: None,
    };

    // Get the last commit for this file
    let last_commit = repo.last_commit()?
        .ok_or_else(|| Error::NotFound("No commits found".to_string()))?;

    // Render the file content template
    let template = FileContentTemplate::new(
        &info,
        &git_ref,
        &normalized_path,
        &file_info,
        &content,
        content_html,
        &last_commit.id(),
        &last_commit.message(),
        &last_commit.author().name,
        last_commit.time(),
    );

    let base = template.as_base_template();

    Ok(Html(base.render_to_string()?))
}

/// Raw file content
async fn raw_file(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, file_path)): Path<(String, String, String)>,
) -> Result<Vec<u8>> {
    // Get repository path
    let repo_path = state.config.repository.repo_dir.join(&repo_name);

    if !repo_path.exists() {
        return Err(Error::NotFound(format!("Repository {} not found", repo_name)));
    }

    // Open the repository
    let repo = state.git.open(&repo_name, &repo_path)?;

    // Normalize the path
    let normalized_path = path::normalize_path(&file_path);

    // Get file content
    let file_content = repo.file(&normalized_path, &git_ref)?;

    Ok(file_content.content)
}

/// File blame view
async fn file_blame(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, file_path)): Path<(String, String, String)>,
) -> Result<Html<String>> {
    // Blame is not yet implemented - redirect to file content
    let normalized_path = path::normalize_path(&file_path);
    Ok(Html(format!(
        "<script>window.location.href='/{}/blob/{}/{}';</script>",
        repo_name, git_ref, normalized_path
    )))
}

/// File history view
async fn file_history(
    State(state): State<ServerState>,
    Path((repo_name, git_ref, file_path)): Path<(String, String, String)>,
) -> Result<Html<String>> {
    // File history is not yet implemented - redirect to commits list
    Ok(Html(format!(
        "<script>window.location.href='/{}/commits/{}';</script>",
        repo_name, git_ref
    )))
}

/// Search query parameters
#[derive(Debug, Deserialize)]
struct SearchWebQuery {
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

    /// Optional page number
    page: Option<usize>,

    /// Optional results per page
    per_page: Option<usize>,

    /// Optional sort order ("relevance", "date", "path")
    sort: Option<String>,

    /// Whether to use regex
    #[serde(default)]
    regex: bool,

    /// Whether search is case sensitive
    #[serde(default)]
    case_sensitive: bool,
}

/// Perform a search
async fn search(
    State(state): State<ServerState>,
    Query(params): Query<SearchWebQuery>,
) -> Result<Html<String>> {
    let query = params.q.trim();
    if query.is_empty() {
        // If no query, just render the search page template
        let template = crate::template::SearchTemplate {
            base: BaseTemplate {
                title: "Search".to_string(),
                current_year: current_year(),
                current_page: "search".to_string(),
                base_url: state.base_url.clone(),
            },
            query: "".to_string(),
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
                ("path".to_string(), "Path".to_string()),
            ],
            current_sort: params.sort.unwrap_or_else(|| "relevance".to_string()),
            filters: build_search_filters(&params),
        };

        return Ok(Html(template.render()?));
    }

    // Get the search service (placeholder until we update ServerState)
    let search_service = get_search_service(&state).await
        .map_err(|err| Error::Internal(format!("Failed to create search service: {}", err)))?;

    // Build search options
    let options = build_web_search_options(&params)
        .map_err(|err| Error::InvalidInput(format!("Invalid search parameters: {}", err)))?;

    // Perform the search
    let start_time = std::time::Instant::now();
    let search_result = search_service.search(query, &options).await
        .map_err(|err| Error::Internal(format!("Search failed: {}", err)))?;

    // Calculate pagination
    let page = params.page.unwrap_or(1);
    let per_page = params.per_page.unwrap_or(20);
    let total_matches = search_result.base_result.total_matches;
    let total_pages = (total_matches as f64 / per_page as f64).ceil() as usize;

    let pagination = if total_pages > 1 {
        Some(crate::template::Pagination {
            current_page: page,
            total_pages,
            has_previous: page > 1,
            has_next: page < total_pages,
            previous_page: if page > 1 { Some(page - 1) } else { None },
            next_page: if page < total_pages { Some(page + 1) } else { None },
            pages: (1..=total_pages).collect(),
        })
    } else {
        None
    };

    // Convert the search result to template data
    let search_stats = crate::template::SearchStats {
        total_matches,
        elapsed_ms: start_time.elapsed().as_millis() as u64,
    };

    let results = convert_to_template_results(&search_result, page, per_page);

    // Render the template
    let template = crate::template::SearchTemplate {
        base: BaseTemplate {
            title: format!("Search: {}", query),
            current_year: current_year(),
            current_page: "search".to_string(),
            base_url: state.base_url.clone(),
        },
        query: query.to_string(),
        search_type: "text".to_string(),
        results: Some(results),
        search_stats: Some(search_stats),
        suggestions: search_result.suggestions.unwrap_or_default(),
        languages: search_result.languages.into_iter().collect(),
        authors: search_result.authors.into_iter().collect(),
        time_periods: search_result.time_periods.into_iter().collect(),
        related_searches: search_result.related_searches,
        pagination,
        sort_options: vec![
            ("relevance".to_string(), "Relevance".to_string()),
            ("date".to_string(), "Date".to_string()),
            ("path".to_string(), "Path".to_string()),
        ],
        current_sort: params.sort.unwrap_or_else(|| "relevance".to_string()),
        filters: build_search_filters(&params),
    };

    Ok(Html(template.render()?))
}

/// Helper function to get search service from server state
async fn get_search_service(state: &ServerState) -> Result<crate::service::search::SearchService> {
    // This is a placeholder implementation until we update the ServerState
    // to include the necessary services for the SearchService

    Err(Error::Internal("SearchService not yet implemented in ServerState".to_string()))
}

/// Helper function to build search options from web query parameters
fn build_web_search_options(params: &SearchWebQuery) -> Result<crate::service::search::AdvancedSearchOptions> {
    use crate::service::search::{AdvancedSearchOptions, SearchType};
    use crate::service::index::SearchOptions;

    // Create basic search options
    let basic_options = SearchOptions {
        regex: params.regex,
        case_sensitive: params.case_sensitive,
        path_pattern: params.path.clone(),
        repository: params.repo.clone(),
        max_results: params.per_page,
    };

    // Parse time range if provided
    let time_range = if let Some(range_str) = &params.time_range {
        let parts: Vec<&str> = range_str.split(',').collect();
        if parts.len() == 2 {
            Some((parts[0].to_string(), parts[1].to_string()))
        } else {
            return Err(Error::InvalidInput("Time range must be in format 'start,end".to_string()));
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
        max_results: params.per_page,
        include_snippets: true, // Always include snippets for web UI
        get_suggestions: true,  // Always get suggestions for web UI
    };

    Ok(options)
}

/// Helper function to convert search result to template data
fn convert_to_template_results(
    result: &crate::service::search::EnhancedSearchResult,
    page: usize,
    per_page: usize,
) -> crate::template::SearchResults {
    // Calculate offset for pagination
    let offset = (page - 1) * per_page;

    // Convert repositories
    let mut repositories = Vec::new();
    let mut total_matches_shown = 0;
    let total_matches_in_repos = result.repositories.len();

    for repo in &result.repositories {
        if total_matches_shown >= per_page {
            break;
        }

        // Convert files
        let mut files = Vec::new();
        for file in &repo.files {
            if total_matches_shown >= per_page {
                break;
            }

            // Convert lines
            let mut lines = Vec::new();
            for line in &file.lines {
                if total_matches_shown >= per_page {
                    break;
                }

                if total_matches_shown >= offset {
                    lines.push(crate::template::LineMatch {
                        line_number: line.base_match.line_number,
                        content: line.base_match.content.clone(),
                        matches: line.base_match.matches.clone(),
                        context_before: line.context_before.clone(),
                        context_after: line.context_after.clone(),
                        last_changed_by: line.last_changed_by.clone(),
                        last_changed_at: line.last_changed_at.clone(),
                    });
                }

                total_matches_shown += 1;
            }

            if !lines.is_empty() {
                files.push(crate::template::FileMatch {
                    path: file.base_match.path.clone(),
                    matches: file.base_match.matches,
                    language: file.language.clone(),
                    lines,
                });
            }
        }

        if !files.is_empty() {
            repositories.push(crate::template::RepositoryMatch {
                name: repo.base_matches.repository.clone(),
                matches: repo.base_matches.matches,
                files,
            });
        }
    }

    crate::template::SearchResults {
        repositories,
        total_repositories: total_matches_in_repos,
        shown_matches: total_matches_shown - offset,
    }
}

/// Helper function to build search filters from query parameters
fn build_search_filters(params: &SearchWebQuery) -> crate::template::SearchFilters {
    crate::template::SearchFilters {
        repository: params.repo.clone(),
        path: params.path.clone(),
        language: params.language.clone(),
        author: params.author.clone(),
        time_range: params.time_range.clone(),
        regex: params.regex,
        case_sensitive: params.case_sensitive,
    }
}

/// Render the search page
async fn search_page(
    State(state): State<ServerState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Html<String>, ApiError> {
    // Helper functions
    fn current_year() -> String {
        chrono::Utc::now().format("%Y").to_string()
    }

    fn internal_error<E: std::fmt::Display>(err: E) -> ApiError {
        ApiError::InternalError(format!("Internal server error: {}", err))
    }

    // Extract search query parameters
    let query = params.get("q").map(|s| s.to_string()).unwrap_or_default();
    let trimmed_query = query.trim();
    let repo = params.get("repo").map(|s| s.to_string());
    let path = params.get("path").map(|s| s.to_string());
    let language = params.get("language").map(|s| s.to_string());
    let author = params.get("author").map(|s| s.to_string());
    let search_type = params.get("type").map(|s| s.to_string()).unwrap_or_else(|| "text".to_string());
    let page = params.get("page").and_then(|p| p.parse::<usize>().ok()).unwrap_or(1);
    let per_page = 20;

    // Prepare template data
    let mut search_results = None;
    let mut search_stats = None;
    let mut suggestions = Vec::new();
    let mut languages = HashMap::new();
    let mut authors = HashMap::new();
    let mut time_periods = HashMap::new();
    let mut related_searches = Vec::new();
    let mut pagination = None;

    // Perform search if query is not empty
    if !trimmed_query.is_empty() {
        let start_time = std::time::Instant::now();

        // Convert to search query for API
        let search_query = SearchQuery {
            q: trimmed_query.to_string(),
            repo: repo.clone(),
            path: path.clone(),
            language: language.clone(),
            author: author.clone(),
            time_range: None,
            context: Some(3),
            limit: Some(per_page),
            page: Some(page),
            snippets: true,
            suggestions: true,
            sort: Some("relevance".to_string()),
            regex: search_type == "regex",
            case_sensitive: false,
        };

        // Get search service
        let search_service = match state.search_service {
            Some(ref service) => service.clone(),
            None => return Err(internal_error("Search service not initialized")),
        };

        // Build search options
        let search_options = match build_search_options(&search_query, &search_type) {
            Ok(options) => options,
            Err(err) => return Err(internal_error(err)),
        };

        // Perform search
        let search_result = match search_service.search(trimmed_query, search_options).await {
            Ok(result) => result,
            Err(err) => return Err(internal_error(err)),
        };

        // Calculate pagination
        let total_matches = search_result.total_matches;
        let total_pages = (total_matches as f64 / per_page as f64).ceil() as usize;

        if total_pages > 1 {
            pagination = Some(crate::template::Pagination {
                current_page: page,
                total_pages,
                has_previous: page > 1,
                has_next: page < total_pages,
                previous_page: if page > 1 { Some(page - 1) } else { None },
                next_page: if page < total_pages { Some(page + 1) } else { None },
                pages: (1..=total_pages).collect(),
            });
        }

        // Convert search results to template format
        search_stats = Some(SearchStats {
            total_matches,
            elapsed_ms: start_time.elapsed().as_millis() as u64,
        });

        // Convert repositories and matches
        let mut repositories = Vec::new();

        for repo_match in search_result.repositories {
            let mut files = Vec::new();

            for file_match in repo_match.files {
                let mut matches = Vec::new();

                for line_match in file_match.lines {
                    matches.push(LineMatch {
                        line_number: line_match.line_number,
                        content: line_match.content,
                    });
                }

                files.push(FileMatch {
                    path: file_match.path,
                    matches,
                });
            }

            repositories.push(RepositoryMatch {
                name: repo_match.name,
                matches: repo_match.total_matches,
                files,
            });
        }

        search_results = Some(SearchResults {
            repositories,
            total_repositories: search_result.total_repositories,
            shown_matches: search_result.shown_matches,
        });

        // Get suggestions, languages, authors, time periods, and related searches
        suggestions = search_result.suggestions.unwrap_or_default();
        languages = search_result.languages.into_iter().collect();
        authors = search_result.authors.into_iter().collect();
        time_periods = search_result.time_periods.into_iter().collect();
        related_searches = search_result.related_searches;
    }

    // Build filters
    let filters = SearchFilters {
        repo: repo.clone(),
        path: path.clone(),
        language: language.clone(),
        author: author.clone(),
        time_range: None,
    };

    // Sort options
    let sort_options = vec![
        ("relevance".to_string(), "Relevance".to_string()),
        ("date".to_string(), "Date".to_string()),
        ("path".to_string(), "Path".to_string()),
    ];

    // Render template
    let template = SearchTemplate {
        base: BaseTemplate {
            title: if !trimmed_query.is_empty() {
                format!("Search: {}", trimmed_query)
            } else {
                "Search Code".to_string()
            },
            current_year: current_year(),
            current_page: "search".to_string(),
            base_url: state.base_url.clone(),
            search_url: Some("/search".to_string()),
        },
        query: query.to_string(),
        search_type,
        results: search_results,
        search_stats,
        suggestions,
        languages,
        authors,
        time_periods,
        related_searches,
        pagination,
        sort_options,
        current_sort: "relevance".to_string(),
        filters,
    };

    match template.render() {
        Ok(html) => Ok(Html(html)),
        Err(err) => Err(internal_error(format!("Template rendering error: {}", err))),
    }
}

/// Helper function to build search options from search query and type
fn build_search_options(
    query: &SearchQuery,
    search_type: &str,
) -> Result<crate::service::search::AdvancedSearchOptions, String> {
    use crate::service::search::{AdvancedSearchOptions, SearchType};

    let search_type = match search_type {
        "text" => SearchType::Text,
        "symbol" => SearchType::Symbol,
        "semantic" => SearchType::Semantic,
        "regex" => SearchType::Regex,
        "path" => SearchType::Path,
        "commit" => SearchType::Commit,
        _ => return Err(format!("Invalid search type: {}", search_type)),
    };

    let mut options = AdvancedSearchOptions {
        search_type,
        repo: query.repo.clone(),
        path: query.path.clone(),
        language: query.language.clone(),
        author: query.author.clone(),
        time_range: query.time_range.clone(),
        context: query.context.unwrap_or(3),
        limit: query.limit.unwrap_or(20),
        page: query.page.unwrap_or(1),
        snippets: query.snippets,
        suggestions: query.suggestions,
        sort: query.sort.clone(),
        regex: query.regex,
        case_sensitive: query.case_sensitive,
    };

    Ok(options)
}
