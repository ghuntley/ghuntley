use axum::{Router, middleware};
use axum::handler::HandlerWithoutStateExt;
use tower_http::services::ServeDir;
use crate::http::{api, web, auth, logging};
use crate::http::server::ServerState;
use crate::http::middleware::{RateLimitLayer, MetricsMiddleware, RateLimiterMiddleware, OpenTelemetryMiddleware, AuthLayer, extract_client_info, require_admin_role};
use crate::service::observability::ObservabilityService;
use axum::routing::{get, post};
use axum::{
    extract::{Path, State, Query},
    Json,
    response::{IntoResponse, Response},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use serde_json::json;

/// Create the main application router with all routes
pub fn router(state: ServerState) -> Router {
    // Extract services from state
    let observability_service = state.services.observability_service.clone();

    let api_routes = api_router(observability_service.clone())
        .with_state(state.clone());

    let web_routes = web::router()
        .with_state(state.clone());

    Router::new()
        .merge(web_routes)
        .nest("/api", api_routes)
        .fallback(api::fallback)
}

/// Build the API router
pub fn api_router(observability_service: ObservabilityService) -> Router {
    // Create middleware layers
    let metrics_layer = MetricsMiddleware::new(observability_service.clone());
    let rate_limiter_layer = RateLimiterMiddleware::new(observability_service.clone());

    // Create OpenTelemetry middleware if a tracer is configured
    let router = if let Some(tracer) = observability_service.opentelemetry_tracer() {
        let opentelemetry_layer = OpenTelemetryMiddleware::new(tracer);
        Router::new()
            .route("/logs", get(logs_handler))
            .route("/metrics", get(metrics_handler))
            .route("/traces", get(traces_handler))
            .route("/health", get(health_handler))
            // Repository metrics endpoints
            .route("/repo/:repo/metrics", get(get_repo_metrics_handler))
            .route("/repo/:repo/activity", get(get_repo_activity_handler))
            .route("/repos/metrics", get(get_all_repo_metrics_handler))
            .route("/repos/metrics/refresh", post(refresh_metrics_handler))
            .route_layer(rate_limiter_layer)
            .layer(metrics_layer)
            .layer(opentelemetry_layer)
    } else {
        Router::new()
            .route("/logs", get(logs_handler))
            .route("/metrics", get(metrics_handler))
            .route("/traces", get(traces_handler))
            .route("/health", get(health_handler))
            // Repository metrics endpoints
            .route("/repo/:repo/metrics", get(get_repo_metrics_handler))
            .route("/repo/:repo/activity", get(get_repo_activity_handler))
            .route("/repos/metrics", get(get_all_repo_metrics_handler))
            .route("/repos/metrics/refresh", post(refresh_metrics_handler))
            .route_layer(rate_limiter_layer)
            .layer(metrics_layer)
    };

    router
}

// Handler functions for API endpoints
async fn logs_handler(
    State(state): State<ServerState>,
    query: Option<Query<LogsQuery>>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Extract query parameters with defaults
    let query = query.unwrap_or_default();
    let limit = query.limit.unwrap_or(100);
    let level = query.level.as_deref();
    let search = query.search.as_deref();

    // Query logs from the observability service
    match observability_service.query_logs_with_search(limit, level, search).await {
        Ok(logs) => Json(logs).into_response(),
        Err(err) => {
            (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into_response()
        }
    }
}

async fn metrics_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Get metrics from the observability service
    match observability_service.get_metrics() {
        Ok(metrics) => Json(metrics).into_response(),
        Err(err) => {
            (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into_response()
        }
    }
}

async fn traces_handler(
    State(state): State<ServerState>,
    query: Option<Query<TracesQuery>>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Extract query parameters with defaults
    let query = query.unwrap_or_default();
    let limit = query.limit.unwrap_or(100);
    let service = query.service.as_deref();

    // Query traces from the observability service
    match observability_service.query_traces(limit, service).await {
        Ok(traces) => Json(traces).into_response(),
        Err(err) => {
            (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into_response()
        }
    }
}

// Handler functions for repository metrics endpoints
async fn get_repo_metrics_handler(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Get repository metrics from the observability service
    match observability_service.get_repository_metrics(&repo_name).await {
        Some(metrics) => Json(metrics).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": format!("Repository {} not found or metrics not available", repo_name)
            }))
        ).into_response(),
    }
}

async fn get_repo_activity_handler(
    State(state): State<ServerState>,
    Path(repo_name): Path<String>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Get repository activity metrics from the observability service
    match observability_service.get_repository_activity(&repo_name).await {
        Some(activity) => Json(activity).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": format!("Repository {} not found or activity metrics not available", repo_name)
            }))
        ).into_response(),
    }
}

async fn get_all_repo_metrics_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Get metrics for all repositories
    let metrics = observability_service.get_all_repository_metrics().await;
    Json(metrics).into_response()
}

async fn refresh_metrics_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Refresh repository metrics
    match observability_service.refresh_repository_metrics().await {
        Ok(_) => Json(json!({
            "status": "success",
            "message": "Repository metrics refresh initiated successfully"
        })).into_response(),
        Err(err) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({
                "status": "error",
                "message": format!("Failed to refresh repository metrics: {}", err)
            }))
        ).into_response(),
    }
}

async fn health_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    let observability_service = &state.services.observability_service;

    // Get detailed health information from the observability service
    match observability_service.health_check().await {
        Ok(health) => {
            // Determine HTTP status based on health status
            let status_code = match health.status.as_str() {
                "ok" => StatusCode::OK,
                "degraded" => StatusCode::OK, // Still return 200 for degraded, but with warning in payload
                _ => StatusCode::SERVICE_UNAVAILABLE,
            };

            (status_code, Json(health)).into_response()
        },
        Err(err) => {
            // If health check fails, return 500
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "status": "error",
                    "message": format!("Health check failed: {}", err)
                }))
            ).into_response()
        }
    }
}

// Query parameter structs
#[derive(Debug, Deserialize, Default)]
struct LogsQuery {
    limit: Option<usize>,
    level: Option<String>,
    search: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct TracesQuery {
    limit: Option<usize>,
    service: Option<String>,
}

// API fallback handler
pub async fn fallback() -> (StatusCode, &'static str) {
    (StatusCode::NOT_FOUND, "API endpoint not found")
}

/// Create the application router
pub fn create_router(app_state: Arc<AppState>) -> Router {
    // Extract services from app state
    let user_service = app_state.user_service.clone();

    // Define public routes (accessible without authentication)
    let public_routes = vec![
        "/".to_string(),
        "/api/health".to_string(),
        "/api/metrics".to_string(),
        "/assets/".to_string(),
        "/repo/".to_string(),        // Allow repository browsing without authentication
        "/repos".to_string(),        // Allow repository listing without authentication
        "/api/repo/".to_string(),    // Allow repository API access without authentication
        "/api/repos".to_string(),    // Allow repositories API access without authentication
    ];

    // Create the main router
    let mut router = Router::new();

    // Add routes

    // Public routes
    router = router
        .route("/", get(routes::index))
        .route("/repos", get(routes::repos))
        .route("/repo/:repo", get(routes::repo))
        .route("/repo/:repo/*path", get(routes::repo_path))
        .route("/api/health", get(routes::api::health))
        .route("/api/metrics", get(routes::api::metrics))
        .route("/api/repo/:repo/metrics", get(routes::api::repository_metrics))
        .route("/api/repo/:repo/activity", get(routes::api::repository_activity))
        .route("/api/repos/metrics", get(routes::api::all_repository_metrics));

    // Protected API routes (require authentication)
    let protected_api_routes = Router::new()
        .route("/api/repos/metrics/refresh", post(routes::api::refresh_repository_metrics))
        .route_layer(middleware::from_fn(require_admin_role));

    // Authentication routes
    let auth_routes = Router::new()
        .route("/api/auth/login", post(routes::auth::login))
        .route("/api/auth/logout", post(routes::auth::logout))
        .route("/api/auth/session", get(routes::auth::session));

    // Admin routes (require admin role)
    let admin_routes = Router::new()
        .route("/admin", get(routes::admin::dashboard))
        .route("/admin/users", get(routes::admin::users))
        .route("/admin/users/new", get(routes::admin::new_user_form).post(routes::admin::create_user))
        .route("/admin/users/:id", get(routes::admin::edit_user_form).post(routes::admin::update_user))
        .route("/admin/users/:id/delete", post(routes::admin::delete_user))
        .route_layer(middleware::from_fn(require_admin_role));

    // Combine all routers
    router = router
        .merge(protected_api_routes)
        .merge(auth_routes)
        .merge(admin_routes);

    // Add global middleware
    router = router
        .layer(middleware::from_fn(extract_client_info))
        .layer(TraceLayer::new_for_http());

    // Add authentication middleware if user service is available
    if let Some(user_service) = user_service {
        router = router.layer(
            AuthLayer::new(user_service)
                .with_public_routes(public_routes)
        );
    }

    // Add state to the router
    router.with_state(app_state)
}
