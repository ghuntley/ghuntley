use axum::{
    Router,
    routing::{get, post, put, delete},
    extract::{Extension, Path, Query},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use crate::http::server::{ServerState, HasObservabilityService};
use crate::service::observability::{ObservabilityService, RepositoryContentStats, RepositoryActivityStats, LogLevel, LogQueryResponse};
use std::sync::Arc;
use serde_json::{json, Value};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use http::header;
use tracing::info;
use serde::{Deserialize, Serialize};

use crate::service::repository::RepositoryService;
use crate::service::index::IndexService;
use crate::service::search::SearchService;
use crate::service::status::StatusService;
use crate::service::health::HealthService;
use crate::service::commit::CommitService;
use crate::service::user::UserService;
use crate::service::maintenance::MaintenanceScheduler;

mod commit;
mod repository;
mod search;
mod user;
mod notifications;
mod email;
mod maintenance;

mod health {
    pub use super::health_handler;
}

mod metrics {
    pub use super::metrics_handler;
}

mod logs {
    pub use super::query_logs_handler;
}

use search::SearchApiHandler;
use commit::CommitApiHandler;
use repository::RepositoryApiHandler;
use user::UserApiHandler;
use crate::data::git::Git;

/// Log query parameters
#[derive(Debug, Deserialize)]
pub struct LogQueryParams {
    /// Log level filter (trace, debug, info, warn, error)
    pub level: Option<String>,

    /// Start time for the query (ISO-8601 format)
    pub start_time: Option<String>,

    /// End time for the query (ISO-8601 format)
    pub end_time: Option<String>,

    /// Maximum number of logs to return
    pub limit: Option<usize>,

    /// Filter by specific field values (key=value pairs)
    #[serde(flatten)]
    pub fields: HashMap<String, String>,
}

/// Log query parameters with pagination
#[derive(Debug, Deserialize)]
pub struct PaginatedLogQueryParams {
    /// Log level filter (trace, debug, info, warn, error)
    pub level: Option<String>,

    /// Start time for the query (ISO-8601 format)
    pub start_time: Option<String>,

    /// End time for the query (ISO-8601 format)
    pub end_time: Option<String>,

    /// Maximum number of logs to return per page
    pub page_size: Option<usize>,

    /// Cursor for pagination (timestamp of last log in previous page)
    pub cursor: Option<String>,

    /// Search term to filter logs
    pub search: Option<String>,

    /// Filter by specific field values (key=value pairs)
    #[serde(flatten)]
    pub fields: HashMap<String, String>,
}

/// Paginated logs response
#[derive(Debug, Serialize)]
pub struct PaginatedLogResponse {
    /// Total number of logs matching the query
    pub total: usize,

    /// Logs returned for this page
    pub logs: Vec<LogEntry>,

    /// Query parameters used
    pub query: HashMap<String, String>,

    /// Cursor for the next page (if available)
    pub next_cursor: Option<String>,

    /// Whether there are more logs available
    pub has_more: bool,
}

/// Metrics format query parameter
#[derive(Debug, Deserialize)]
pub struct MetricsFormatQuery {
    /// Format to export metrics in (prometheus, openmetrics, json, csv)
    pub format: Option<String>,
}

/// Create API router
pub fn create_router(
    repository_service: Arc<RepositoryService>,
    index_service: Option<Arc<IndexService>>,
    search_service: Option<Arc<SearchService>>,
    status_service: Arc<StatusService>,
    health_service: Arc<HealthService>,
    observability_service: Arc<ObservabilityService>,
    git: Arc<Git>,
    user_service: Option<Arc<UserService>>,
    maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
) -> Router {
    // Create the commit service
    let commit_service = Arc::new(CommitService::new(git, repository_service.clone()));

    // Create basic API router
    let mut router = Router::new()
        .route("/api/health", get(health_handler))
        .route("/api/metrics", get(metrics_handler))
        .route("/api/logs", get(query_logs_handler))
        // Repository API endpoints
        .route("/api/repos", get(RepositoryApiHandler::list_repositories))
        .route("/api/repos/stats", get(RepositoryApiHandler::get_all_repository_stats))
        .route("/api/repos/:repo", get(RepositoryApiHandler::get_repository))
        .route("/api/repos/:repo/stats", get(RepositoryApiHandler::get_repository_stats))
        // Repository metrics endpoints
        .route("/api/repo/:repo/metrics", get(repository_metrics_handler))
        .route("/api/repo/:repo/activity", get(repository_activity_handler))
        .route("/api/repos/metrics", get(all_repositories_metrics_handler))
        .route("/api/repos/metrics/refresh", post(refresh_repository_metrics_handler))
        // Commit API endpoints
        .route("/api/repos/:repo/commits/:id", get(CommitApiHandler::get_commit))
        .route("/api/repos/:repo/commits/:id/signature", get(CommitApiHandler::get_commit_signature))
        .route("/api/repos/:repo/commits", get(CommitApiHandler::list_commits));

    // Add repository service
    router = router.with_state(repository_service);

    // Add commit service
    router = router.with_state(commit_service);

    // Add health service
    router = router.with_state(health_service);

    // Add observability service
    router = router.with_state(observability_service);

    // Add optional services
    if let Some(index_service) = index_service {
        router = router
            .route("/api/repos/:repo/index", post(IndexService::index_repository))
            .route("/api/repos/:repo/index/status", get(IndexService::get_index_status))
            .with_state(index_service);
    }

    if let Some(search_service) = search_service {
        router = router
            .route("/api/search", get(SearchApiHandler::search))
            .route("/api/search/advanced", get(SearchApiHandler::advanced_search))
            .route("/api/search/symbols", get(SearchApiHandler::symbol_search))
            .route("/api/search/suggestions", get(SearchApiHandler::search_suggestions))
            .with_state(search_service);
    }

    // Add user API endpoints if user service is provided
    if let Some(user_service) = user_service {
        // Create user API handler and router
        let user_handler = UserApiHandler::new(user_service);
        let user_router = user_handler.create_router();

        // Nest the user router under /api/users path
        router = router.nest("/api/users", user_router);
    }

    // Add notifications API routes
    let notification_routes = Router::new()
        .route("/", get(notifications::get_notifications).post(notifications::create_notification))
        .route("/:id/read", post(notifications::mark_notification_as_read))
        .route("/:id/dismiss", post(notifications::dismiss_notification));

    router.nest("/api/notifications", notification_routes);

    // Add email API routes
    let email_routes = Router::new()
        .route("/notifications/:id/email", post(email::send_notification_as_email))
        .route("/notifications/digest/email", post(email::send_notifications_digest_email));

    router.nest("/api/email", email_routes);

    // Add maintenance routes if configured
    if let Some(scheduler) = maintenance_scheduler {
        let scheduler_clone = scheduler.clone();
        router = router.nest("/maintenance", maintenance::maintenance_routes(scheduler_clone));
    }

    info!("API router created");
    router
}

/// Create status routes (public health check endpoints)
pub fn status_routes() -> Router {
    Router::new()
        .route("/health", get(health_handler))
}

/// Health check handler
pub async fn health_handler() -> impl IntoResponse {
    (StatusCode::OK, Json(json!({"status": "ok"})))
}

/// Metrics handler that returns Prometheus metrics
pub async fn metrics_handler(
    state: Extension<ServerState>,
) -> impl IntoResponse {
    // Get observability service from state
    match state.observability_service() {
        Some(observability) => {
            // Get metrics as Prometheus text format
            match observability.metrics_as_string() {
                Ok(metrics) => {
                    Response::builder()
                        .status(StatusCode::OK)
                        .header("Content-Type", "text/plain")
                        .body(metrics.into())
                        .unwrap()
                }
                Err(_) => {
                    Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .header("Content-Type", "text/plain")
                        .body("Failed to get metrics".into())
                        .unwrap()
                }
            }
        }
        None => {
            // No observability service
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .header("Content-Type", "text/plain")
                .body("Metrics not enabled".into())
                .unwrap()
        }
    }
}

/// Get metrics for a specific repository
///
/// This endpoint returns content metrics for a specific repository.
/// It provides statistics about files, commits, contributors, and more.
///
/// GET /api/repo/:repo/metrics
pub async fn repository_metrics_handler(
    Path(repo_name): Path<String>,
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            match observability.get_repository_metrics(&repo_name).await {
                Some(metrics) => (StatusCode::OK, Json(metrics)),
                None => (
                    StatusCode::NOT_FOUND,
                    Json(json!({"error": format!("Repository {} not found or metrics not available", repo_name)}))
                ),
            }
        }
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "Metrics service is not available"}))
            )
        }
    }
}

/// Get metrics for all repositories
///
/// This endpoint returns content metrics for all repositories.
/// It provides a map of repository names to their metrics.
///
/// GET /api/repos/metrics
pub async fn all_repositories_metrics_handler(
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            let metrics = observability.get_all_repository_metrics().await;
            (StatusCode::OK, Json(metrics))
        }
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "Metrics service is not available"}))
            )
        }
    }
}

/// Force a refresh of repository metrics
///
/// This endpoint forces a refresh of all repository content metrics.
/// It triggers the content metrics collector to re-scan all repositories.
///
/// POST /api/repos/metrics/refresh
pub async fn refresh_repository_metrics_handler(
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            match observability.refresh_repository_metrics().await {
                Ok(_) => {
                    (
                        StatusCode::OK,
                        Json(json!({
                            "status": "success",
                            "message": "Repository metrics refresh initiated successfully"
                        }))
                    )
                },
                Err(e) => {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({
                            "status": "error",
                            "message": format!("Failed to refresh repository metrics: {}", e)
                        }))
                    )
                }
            }
        },
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({
                    "status": "error",
                    "message": "Metrics service is not available"
                }))
            )
        }
    }
}

/// Get activity metrics for a specific repository
pub async fn repository_activity_handler(
    Path(repo_name): Path<String>,
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            // Access the content metrics collector through observability service
            match observability.get_content_metrics_collector() {
                Some(collector) => {
                    // Get activity metrics
                    let collector = collector.lock().await;
                    match collector.get_repository_activity(&repo_name).await {
                        Some(activity) => (StatusCode::OK, Json(activity)),
                        None => (
                            StatusCode::NOT_FOUND,
                            Json(json!({"error": format!("Repository {} not found or activity metrics not available", repo_name)}))
                        ),
                    }
                }
                None => {
                    (
                        StatusCode::SERVICE_UNAVAILABLE,
                        Json(json!({"error": "Content metrics collector is not available"}))
                    )
                }
            }
        }
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "Metrics service is not available"}))
            )
        }
    }
}

/// Query logs with filtering
pub async fn query_logs_handler(
    Query(params): Query<LogQueryParams>,
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            // Parse log level
            let level = params.level.as_deref().map(LogLevel::from);

            // Parse time ranges
            let start_time = match params.start_time {
                Some(ref time_str) => match DateTime::parse_from_rfc3339(time_str) {
                    Ok(dt) => Some(dt.with_timezone(&Utc)),
                    Err(_) => {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error": "Invalid start_time format. Use ISO-8601/RFC3339 format (e.g., 2023-01-01T00:00:00Z)"}))
                        );
                    }
                },
                None => None,
            };

            let end_time = match params.end_time {
                Some(ref time_str) => match DateTime::parse_from_rfc3339(time_str) {
                    Ok(dt) => Some(dt.with_timezone(&Utc)),
                    Err(_) => {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error": "Invalid end_time format. Use ISO-8601/RFC3339 format (e.g., 2023-01-01T00:00:00Z)"}))
                        );
                    }
                },
                None => None,
            };

            // Set default and max limit
            let limit = params.limit.unwrap_or(100).min(1000);

            // Query logs
            match observability.query_logs(level, start_time, end_time, limit).await {
                Ok(logs) => {
                    // Apply additional field filtering if specified in the query
                    if !params.fields.is_empty() {
                        // Filter logs based on field values
                        let filtered_logs = LogQueryResponse {
                            total: logs.total,
                            logs: logs.logs
                                .into_iter()
                                .filter(|log| {
                                    // Check if all required fields match
                                    params.fields.iter().all(|(key, value)| {
                                        if let Some(field_value) = log.fields.get(key) {
                                            // If the field exists, check if its string representation contains the value
                                            let field_str = field_value.to_string();
                                            field_str.contains(value)
                                        } else {
                                            // If the field doesn't exist, this log doesn't match
                                            false
                                        }
                                    })
                                })
                                .collect(),
                            query: logs.query,
                        };

                        (StatusCode::OK, Json(filtered_logs))
                    } else {
                        // No additional filtering needed
                        (StatusCode::OK, Json(logs))
                    }
                }
                Err(e) => {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({"error": format!("Failed to query logs: {}", e)}))
                    )
                }
            }
        }
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "Observability service is not available"}))
            )
        }
    }
}

/// Query logs with pagination
pub async fn paginated_logs_handler(
    Query(params): Query<PaginatedLogQueryParams>,
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            // Parse log level
            let level = params.level.as_deref();

            // Parse time ranges
            let start_time = match params.start_time {
                Some(ref time_str) => match DateTime::parse_from_rfc3339(time_str) {
                    Ok(dt) => Some(dt.with_timezone(&Utc)),
                    Err(_) => {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error": "Invalid start_time format. Use ISO-8601/RFC3339 format (e.g., 2023-01-01T00:00:00Z)"}))
                        );
                    }
                },
                None => None,
            };

            let end_time = match params.end_time {
                Some(ref time_str) => match DateTime::parse_from_rfc3339(time_str) {
                    Ok(dt) => Some(dt.with_timezone(&Utc)),
                    Err(_) => {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error": "Invalid end_time format. Use ISO-8601/RFC3339 format (e.g., 2023-01-01T00:00:00Z)"}))
                        );
                    }
                },
                None => None,
            };

            // Parse cursor (timestamp of last log in previous page)
            let cursor_time = match params.cursor {
                Some(ref cursor) => match DateTime::parse_from_rfc3339(cursor) {
                    Ok(dt) => Some(dt.with_timezone(&Utc)),
                    Err(_) => {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error": "Invalid cursor format. Use ISO-8601/RFC3339 format (e.g., 2023-01-01T00:00:00Z)"}))
                        );
                    }
                },
                None => None,
            };

            // Set default and max page size
            let page_size = params.page_size.unwrap_or(100).min(1000);

            // Adjust start time based on cursor if provided
            let effective_start_time = if let Some(cursor) = cursor_time {
                // If both cursor and start_time are provided, use the later one
                if let Some(start) = start_time {
                    if cursor > start {
                        Some(cursor)
                    } else {
                        Some(start)
                    }
                } else {
                    Some(cursor)
                }
            } else {
                start_time
            };

            // Extract fields that aren't query parameters
            let fields = params.fields.iter()
                .filter(|(k, _)| !["level", "start_time", "end_time", "page_size", "cursor", "search"].contains(&k.as_str()))
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect::<HashMap<String, String>>();

            let fields_option = if fields.is_empty() { None } else { Some(fields) };

            // Query logs with all parameters
            match observability.query_logs_with_search(
                page_size + 1, // Request one more than needed to check if there are more logs
                level,
                params.search.as_deref(),
                effective_start_time,
                end_time,
                fields_option,
            ).await {
                Ok(log_response) => {
                    let mut logs = log_response.logs;

                    // Check if there are more logs
                    let has_more = logs.len() > page_size;

                    // Remove the extra log if we got more than requested
                    if has_more {
                        logs.truncate(page_size);
                    }

                    // Get the timestamp of the last log for the next cursor
                    let next_cursor = if has_more && !logs.is_empty() {
                        let last_log = logs.last().unwrap();
                        Some(last_log.timestamp.to_rfc3339())
                    } else {
                        None
                    };

                    // Create the paginated response
                    let paginated_response = PaginatedLogResponse {
                        total: log_response.total,
                        logs,
                        query: log_response.query,
                        next_cursor,
                        has_more,
                    };

                    (StatusCode::OK, Json(paginated_response))
                },
                Err(e) => {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({"error": format!("Failed to query logs: {}", e)}))
                    )
                }
            }
        },
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "Observability service is not available"}))
            )
        }
    }
}

/// Export metrics in different formats
pub async fn export_metrics_handler(
    Query(params): Query<MetricsFormatQuery>,
    Extension(state): Extension<ServerState>,
) -> impl IntoResponse {
    match state.observability_service() {
        Some(observability) => {
            // Determine the requested format (default to prometheus)
            let format = params.format.as_deref().unwrap_or("prometheus");

            match format.to_lowercase().as_str() {
                "json" => {
                    // Get metrics as JSON
                    match observability.metrics_as_json() {
                        Ok(metrics) => {
                            (
                                StatusCode::OK,
                                [(header::CONTENT_TYPE, "application/json")],
                                metrics
                            )
                        },
                        Err(e) => {
                            (
                                StatusCode::INTERNAL_SERVER_ERROR,
                                [(header::CONTENT_TYPE, "application/json")],
                                format!("{{\"error\": \"Failed to get metrics: {}\"}}", e)
                            )
                        }
                    }
                },
                "openmetrics" => {
                    // Get metrics in OpenMetrics format
                    match observability.metrics_as_openmetrics() {
                        Ok(metrics) => {
                            (
                                StatusCode::OK,
                                [(header::CONTENT_TYPE, "application/openmetrics-text; version=1.0.0; charset=utf-8")],
                                metrics
                            )
                        },
                        Err(e) => {
                            (
                                StatusCode::INTERNAL_SERVER_ERROR,
                                [(header::CONTENT_TYPE, "text/plain")],
                                format!("Failed to get metrics: {}", e)
                            )
                        }
                    }
                },
                "csv" => {
                    // Get metrics in CSV format
                    match observability.metrics_as_csv() {
                        Ok(metrics) => {
                            (
                                StatusCode::OK,
                                [(header::CONTENT_TYPE, "text/csv; charset=utf-8"),
                                 (header::CONTENT_DISPOSITION, "attachment; filename=\"art_metrics.csv\"")],
                                metrics
                            )
                        },
                        Err(e) => {
                            (
                                StatusCode::INTERNAL_SERVER_ERROR,
                                [(header::CONTENT_TYPE, "text/plain")],
                                format!("Failed to get metrics: {}", e)
                            )
                        }
                    }
                },
                _ => { // Default to prometheus format
                    // Get metrics in Prometheus format
                    match observability.metrics_as_string() {
                        Ok(metrics) => {
                            (
                                StatusCode::OK,
                                [(header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")],
                                metrics
                            )
                        },
                        Err(e) => {
                            (
                                StatusCode::INTERNAL_SERVER_ERROR,
                                [(header::CONTENT_TYPE, "text/plain")],
                                format!("Failed to get metrics: {}", e)
                            )
                        }
                    }
                }
            }
        },
        None => {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                [(header::CONTENT_TYPE, "text/plain")],
                "Metrics service not available".to_string()
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;
    use crate::service::observability::ObservabilityService;
    use crate::data::cache::Cache;
    use crate::config::ObservabilityConfig;
    use crate::config::Config;
    use crate::data::database::Sqlite;
    use crate::data::git::Git;
    use std::sync::Arc;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use prometheus::{Registry, IntCounter, Gauge, Histogram};

    // Mock implementations for testing

    impl Default for Config {
        fn default() -> Self {
            Self {
                server: Default::default(),
                database: Default::default(),
                repository: Default::default(),
                auth: Default::default(),
                ui: Default::default(),
                observability: ObservabilityConfig {
                    enable_metrics: true,
                    log_level: "info".to_string(),
                },
            }
        }
    }

    impl Default for Sqlite {
        fn default() -> Self {
            // Create an in-memory database for testing
            Self::new_in_memory().unwrap()
        }
    }

    impl Default for Git {
        fn default() -> Self {
            // Create a Git stub for testing
            Self::new_for_test()
        }
    }

    // Helper function for tests
    fn create_test_server_state(enable_metrics: bool) -> ServerState {
        // Create a test observability service
        let config = Arc::new(ObservabilityConfig {
            enable_metrics,
            log_level: "info".to_string(),
        });

        let cache = Arc::new(Cache::new_for_test());
        let observability = Arc::new(ObservabilityService::new(config, cache));

        // Create a mock server state for testing
        ServerState {
            observability_service: if enable_metrics { Some(observability) } else { None },
            // Initialize with Default trait where possible
            config: Arc::new(Default::default()),
            db: Arc::new(Default::default()),
            git: Arc::new(Default::default()),
            cache: Arc::new(Default::default()),
            repository_service: None,
            commit_service: None,
            file_service: None,
            format_service: None,
            index_service: None,
            search_service: None,
            status_service: None,
            auth_service: None,
        }
    }

    /// Strategy for generating metric format query parameters
    fn format_strategy() -> impl Strategy<Value = Option<String>> {
        prop_oneof![
            Just(None),
            Just(Some("prometheus".to_string())),
            Just(Some("json".to_string())),
            Just(Some("openmetrics".to_string())),
            Just(Some("csv".to_string())),
        ]
    }

    proptest! {
        /// Test that the metrics export endpoint handles different formats correctly
        #[test]
        fn test_metrics_export_endpoint(format in format_strategy()) {
            // Create a test registry
            let registry = Registry::new();

            // Create some test metrics
            let counter = IntCounter::new("test_counter", "Test counter").unwrap();
            registry.register(Box::new(counter.clone())).unwrap();
            counter.inc_by(42);

            let gauge = Gauge::new("test_gauge", "Test gauge").unwrap();
            registry.register(Box::new(gauge.clone())).unwrap();
            gauge.set(123.45);

            let histogram = Histogram::with_opts(
                prometheus::histogram_opts!("test_histogram", "Test histogram")
            ).unwrap();
            registry.register(Box::new(histogram.clone())).unwrap();
            histogram.observe(0.5);

            // Create a test observability service
            let service = Arc::new(ObservabilityService::new_with_registry(
                Arc::new(ObservabilityConfig::default()),
                registry
            ));

            // Create the query parameters
            let query = if let Some(format_value) = format.clone() {
                Query(MetricsFormatQuery { format: Some(format_value) })
            } else {
                Query(MetricsFormatQuery { format: None })
            };

            // Call the handler
            let result = tokio_test::block_on(export_metrics_handler(
                query,
                Extension(service.clone())
            ));

            // Check the response
            match format {
                Some(format_str) => match format_str.as_str() {
                    "json" => {
                        assert_eq!(result.status(), StatusCode::OK);
                        assert_eq!(result.headers().get("content-type").unwrap(), "application/json");
                        let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
                        let body_str = String::from_utf8(body.to_vec()).unwrap();
                        assert!(body_str.contains("test_counter"));
                        assert!(body_str.contains("test_gauge"));
                        // Verify it's valid JSON
                        assert!(serde_json::from_str::<serde_json::Value>(&body_str).is_ok());
                    },
                    "openmetrics" => {
                        assert_eq!(result.status(), StatusCode::OK);
                        assert_eq!(
                            result.headers().get("content-type").unwrap(),
                            "application/openmetrics-text; version=1.0.0; charset=utf-8"
                        );
                        let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
                        let body_str = String::from_utf8(body.to_vec()).unwrap();
                        assert!(body_str.contains("test_counter"));
                        assert!(body_str.contains("test_gauge"));
                        assert!(body_str.contains("# EOF"));
                    },
                    "csv" => {
                        assert_eq!(result.status(), StatusCode::OK);
                        assert_eq!(result.headers().get("content-type").unwrap(), "text/csv; charset=utf-8");
                        assert_eq!(
                            result.headers().get("content-disposition").unwrap(),
                            "attachment; filename=\"art_metrics.csv\""
                        );

                        let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
                        let body_str = String::from_utf8(body.to_vec()).unwrap();

                        // Verify basic CSV structure
                        assert!(body_str.starts_with("name,type,help,labels,value,sample_count,sample_sum,upper_bound,timestamp\n"));
                        assert!(body_str.contains("test_counter"));
                        assert!(body_str.contains("test_gauge"));
                        assert!(body_str.contains("test_histogram"));

                        // Verify CSV is parseable
                        let mut reader = csv::Reader::from_reader(body_str.as_bytes());
                        let headers = reader.headers().unwrap();
                        assert_eq!(headers.len(), 9); // 9 columns as defined in our schema

                        // Count records
                        let records: Vec<_> = reader.records().collect::<Result<_, _>>().unwrap();
                        assert!(!records.is_empty());
                    },
                    _ => { // Prometheus format
                        assert_eq!(result.status(), StatusCode::OK);
                        assert_eq!(
                            result.headers().get("content-type").unwrap(),
                            "text/plain; version=0.0.4; charset=utf-8"
                        );
                        let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
                        let body_str = String::from_utf8(body.to_vec()).unwrap();
                        assert!(body_str.contains("test_counter"));
                        assert!(body_str.contains("test_gauge"));
                    }
                },
                None => { // Default to prometheus format
                    assert_eq!(result.status(), StatusCode::OK);
                    assert_eq!(
                        result.headers().get("content-type").unwrap(),
                        "text/plain; version=0.0.4; charset=utf-8"
                    );
                    let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
                    let body_str = String::from_utf8(body.to_vec()).unwrap();
                    assert!(body_str.contains("test_counter"));
                    assert!(body_str.contains("test_gauge"));
                }
            }
        }
    }

    #[test]
    fn test_metrics_export_handler_error_handling() {
        // Create a mock service that returns errors
        let mock_service = Arc::new(MockObservabilityService::new());

        // Test with different formats
        for format in &[None, Some("json"), Some("prometheus"), Some("openmetrics")] {
            let query = Query(MetricsFormatQuery {
                format: format.as_ref().map(|s| s.to_string())
            });

            // Call the handler
            let result = tokio_test::block_on(export_metrics_handler(
                query,
                Extension(mock_service.clone() as Arc<dyn ObservabilityServiceTrait>)
            ));

            // Should return a 500 Internal Server Error
            assert_eq!(result.status(), StatusCode::INTERNAL_SERVER_ERROR);

            // Check that the response body contains an error message
            let body = tokio_test::block_on(hyper::body::to_bytes(result.into_body())).unwrap();
            let body_str = String::from_utf8(body.to_vec()).unwrap();

            assert!(body_str.contains("error"));
            assert!(body_str.contains("Failed to export metrics"));
        }
    }

    /// Test the user API integration
    #[tokio::test]
    async fn test_user_api_integration() {
        use crate::data::user::{User, UserRole};
        use crate::http::api::user::{UserApiHandler, CreateUserRequest, LoginRequest, UserResponse};
        use crate::service::user::UserService;
        use crate::data::user::repository::UserRepository;
        use crate::data::database::Sqlite;
        use r2d2_sqlite::SqliteConnectionManager;
        use r2d2::Pool;
        use tempfile::tempdir;
        use std::sync::Arc;
        use axum::extract::Json;
        use axum::http::{Request, StatusCode};
        use axum::routing::post;
        use axum::body::Body;
        use tower::ServiceExt;
        use std::time::Duration;
        use http_body_util::BodyExt;
        use tower_cookies::cookie::time::OffsetDateTime;
        use tower_cookies::{Cookie, CookieManagerLayer, Cookies};

        // Create an in-memory SQLite database for testing
        let manager = SqliteConnectionManager::memory();
        let pool = Pool::new(manager).unwrap();
        let pool = Arc::new(pool);

        // Create and initialize the user repository
        let user_repo = UserRepository::new(pool);
        pollster::block_on(user_repo.initialize()).unwrap();
        let user_repo = Arc::new(user_repo);

        // Create the user service
        let user_service = UserService::new(
            user_repo,
            3600, // 1 hour session timeout
            5,    // 5 max login attempts
            300,  // 5 minute lockout time
        );
        let user_service = Arc::new(user_service);

        // Create the user API handler
        let user_handler = UserApiHandler::new(user_service.clone());
        let app = user_handler.create_router()
            .layer(CookieManagerLayer::new());

        // Try to list users without authentication - should return 401
        let req = Request::builder()
            .uri("/")
            .method("GET")
            .body(Body::empty())
            .unwrap();

        let res = app.clone().oneshot(req).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

        // Create an admin user
        let admin_user = pollster::block_on(user_service.create_user(
            "admin".to_string(),
            "admin@example.com".to_string(),
            "Admin User".to_string(),
            "password123",
            UserRole::Admin,
        )).unwrap();

        // Login as admin
        let login_req = Request::builder()
            .uri("/login")
            .method("POST")
            .header("content-type", "application/json")
            .header("user-agent", "test-agent")
            .header("x-forwarded-for", "127.0.0.1")
            .body(Body::from(serde_json::to_string(&LoginRequest {
                username: "admin".to_string(),
                password: "password123".to_string(),
            }).unwrap()))
            .unwrap();

        let mut cookie_jar = Cookies::default();
        let res = app.clone().oneshot(login_req).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);

        // Extract session cookie
        let set_cookie = res.headers().get("set-cookie").unwrap();
        let cookie_str = set_cookie.to_str().unwrap();
        let session_cookie = Cookie::parse(cookie_str.to_string()).unwrap();
        cookie_jar.add(session_cookie.clone());

        // Now list users with authentication - should return 200 with the admin user
        let req = Request::builder()
            .uri("/")
            .method("GET")
            .header("cookie", format!("{}={}", session_cookie.name(), session_cookie.value()))
            .body(Body::empty())
            .unwrap();

        let res = app.clone().oneshot(req).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);

        // Create a new regular user
        let create_user_req = Request::builder()
            .uri("/")
            .method("POST")
            .header("content-type", "application/json")
            .header("cookie", format!("{}={}", session_cookie.name(), session_cookie.value()))
            .body(Body::from(serde_json::to_string(&CreateUserRequest {
                username: "testuser".to_string(),
                email: "test@example.com".to_string(),
                display_name: "Test User".to_string(),
                password: "testpassword".to_string(),
                role: Some(UserRole::User),
            }).unwrap()))
            .unwrap();

        let res = app.clone().oneshot(create_user_req).await.unwrap();
        assert_eq!(res.status(), StatusCode::CREATED);

        // Extract the user ID from the response
        let body = res.into_body().collect().await.unwrap().to_bytes();
        let user_response: UserResponse = serde_json::from_slice(&body).unwrap();
        let user_id = user_response.id;

        // Get the newly created user
        let get_user_req = Request::builder()
            .uri(&format!("/{}", user_id))
            .method("GET")
            .header("cookie", format!("{}={}", session_cookie.name(), session_cookie.value()))
            .body(Body::empty())
            .unwrap();

        let res = app.clone().oneshot(get_user_req).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);

        // Validate the user data
        let body = res.into_body().collect().await.unwrap().to_bytes();
        let user_response: UserResponse = serde_json::from_slice(&body).unwrap();
        assert_eq!(user_response.username, "testuser");
        assert_eq!(user_response.email, "test@example.com");
        assert_eq!(user_response.display_name, "Test User");

        // Test logout
        let logout_req = Request::builder()
            .uri("/logout")
            .method("POST")
            .header("cookie", format!("{}={}", session_cookie.name(), session_cookie.value()))
            .body(Body::empty())
            .unwrap();

        let res = app.clone().oneshot(logout_req).await.unwrap();
        assert_eq!(res.status(), StatusCode::NO_CONTENT);

        // Try to list users with an expired session - should return 401
        let req = Request::builder()
            .uri("/")
            .method("GET")
            .header("cookie", format!("{}={}", session_cookie.name(), session_cookie.value()))
            .body(Body::empty())
            .unwrap();

        let res = app.clone().oneshot(req).await.unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    struct MockObservabilityService;

    impl MockObservabilityService {
        fn new() -> Self {
            Self
        }
    }

    impl ObservabilityServiceTrait for MockObservabilityService {
        fn metrics_as_string(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
            Err("Mock error".into())
        }

        fn metrics_as_json(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
            Err("Mock error".into())
        }

        fn metrics_as_openmetrics(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
            Err("Mock error".into())
        }

        fn health(&self) -> HealthResponse {
            HealthResponse::default()
        }

        fn record_http_request(&self, _method: &str, _path: &str) {}

        fn record_http_response(&self, _method: &str, _path: &str, _status: u16, _duration: std::time::Duration) {}

        fn record_git_operation(&self, _operation: &str, _repository: &str, _duration: std::time::Duration) {}

        fn record_cache_hit(&self, _cache: &str) {}

        fn record_cache_miss(&self, _cache: &str) {}

        fn update_repository_stats(&self, _repository: &str, _stats: HashMap<String, f64>) {}

        fn update_memory_usage(&self, _bytes: i64) {}

        fn update_active_connections(&self, _count: i64) {}

        fn record_trace(&self, _trace_context: &TraceContext) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
            Ok(())
        }
    }
}
