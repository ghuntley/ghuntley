#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{Config, DatabaseConfig, RepositoryConfig, ServerConfig, UiConfig};
    use crate::data::database::Database;
    use crate::data::git::Git;
    use crate::error::Result;
    use axum::http::Request;
    use hyper::{Client, Body};
    use std::net::SocketAddr;
    use std::time::Duration;
    use tempfile::TempDir;
    use tokio::time::sleep;
    use crate::service::{
        auth::AuthService,
        repository::RepositoryService,
        commit::CommitService,
        file::FileService,
        format::FormatService,
        index::IndexService,
        search::SearchService,
        status::StatusService,
        observability::ObservabilityService,
    };
    use std::collections::HashMap;
    use serde_json;
    use tracing_subscriber::EnvFilter;
    use crate::service::observability::{LogLevel, TraceContext};
}

// Add required imports for the main module
use std::collections::HashMap;
use serde_json;
use tracing_subscriber::EnvFilter;
use crate::service::observability::{LogLevel, TraceContext};
use crate::error::{Error, Result};
use crate::service::status::{HasStatusService, StatusService};
use crate::data::cache::Cache;
use crate::data::git::Git;
use crate::data::database::Sqlite;
use crate::config::Config;
use std::sync::{Arc, Mutex};
use axum::Router;
use tracing::Level;
use chrono::Utc;
use crate::http::middleware::MetricsMiddleware;
use crate::service::user::{UserService, UserListOptions};
use crate::data::user::repository::UserRepository;
use crate::data::user::{User, UserRole};
use crate::service::repository::maintenance::MaintenanceScheduler;

/// State for the HTTP server and all routes
#[derive(Clone)]
pub struct ServerState {
    /// Application configuration
    pub config: Arc<Config>,

    /// Database connection
    pub db: Arc<Sqlite>,

    /// Git service
    pub git: Arc<Git>,

    /// Cache service
    pub cache: Arc<Cache>,

    /// Repository service
    pub repository_service: Option<Arc<RepositoryService>>,

    /// Commit service
    pub commit_service: Option<Arc<CommitService>>,

    /// File service
    pub file_service: Option<Arc<FileService>>,

    /// Format service
    pub format_service: Option<Arc<Mutex<FormatService>>>,

    /// Index service
    pub index_service: Option<Arc<IndexService>>,

    /// Search service
    pub search_service: Option<Arc<SearchService>>,

    /// Status service
    pub status_service: Option<Arc<StatusService>>,

    /// Observability service
    pub observability_service: Option<Arc<ObservabilityService>>,

    /// JWT authentication service
    pub auth_service: Option<Arc<AuthService>>,

    /// User service for authentication and user management
    pub user_service: Option<Arc<UserService>>,

    /// Maintenance scheduler service
    pub maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
}

/// Trait for accessing the observability service
pub trait HasObservabilityService {
    /// Get the observability service
    fn observability_service(&self) -> Option<Arc<ObservabilityService>>;
}

/// HasUserService trait for accessing the user service
pub trait HasUserService {
    /// Get the user service
    fn user_service(&self) -> Option<Arc<UserService>>;
}

pub trait HasMaintenanceScheduler {
    /// Get the maintenance scheduler service
    fn maintenance_scheduler(&self) -> Option<Arc<MaintenanceScheduler>>;
}

impl HasStatusService for ServerState {
    fn status_service(&self) -> Result<&Arc<StatusService>> {
        self.status_service
            .as_ref()
            .ok_or_else(|| Error::Internal("Status service not configured".to_string()))
    }
}

impl HasObservabilityService for ServerState {
    fn observability_service(&self) -> Option<Arc<ObservabilityService>> {
        self.observability_service.clone()
    }
}

impl HasUserService for ServerState {
    fn user_service(&self) -> Option<Arc<UserService>> {
        self.user_service.clone()
    }
}

impl HasMaintenanceScheduler for ServerState {
    fn maintenance_scheduler(&self) -> Option<Arc<MaintenanceScheduler>> {
        self.maintenance_scheduler.clone()
    }
}

/// Initialize all the application services
pub async fn initialize_services(mut state: ServerState) -> Result<ServerState> {
    // ... existing code ...

    // Initialize search service (if enabled)
    if state.config.features.search {
        let index_service = state.index_service.clone().expect("Index service not initialized");
        let search_service = Arc::new(SearchService::new(index_service));
        state.search_service = Some(search_service);
        info!("Search service initialized");
    }

    // Initialize status service
    let repository_service = state.repository_service.clone().expect("Repository service not initialized");
    let index_service = state.index_service.clone().expect("Index service not initialized");
    let format_service = state.format_service.clone().expect("Format service not initialized");
    let version = env!("CARGO_PKG_VERSION").to_string();

    let status_service = Arc::new(StatusService::new(
        state.git.clone(),
        state.db.clone(),
        state.cache.clone(),
        repository_service,
        index_service,
        format_service,
        version,
    ));
    state.status_service = Some(status_service);
    info!("Status service initialized");

    // Initialize user repository and service if database is available
    if let Some(db) = state.db.clone() {
        // Create user repository
        let user_repo = Arc::new(UserRepository::new(db));

        // Initialize user repository (create tables if needed)
        user_repo.initialize().await?;

        // Create user service
        let user_service = Arc::new(UserService::new(
            user_repo,
            3600,              // 1 hour session timeout
            5,                 // 5 max login attempts
            300,               // 5 minute lockout time
        ));

        // Initialize user service
        user_service.initialize().await?;

        // Store user service in state
        state.user_service = Some(user_service);
    }

    // ... existing code ...

    Ok(state)
}

/// Initialize the HTTP server
pub async fn init(config: &Config) -> Result<Server<AddrIncoming>> {
    // ... existing code ...

    // Create tracing subscriber for structured logging
    let fmt_layer = tracing_subscriber::fmt::layer()
        .with_target(true)
        .with_level(true)
        .with_ansi(true);

    let filter_layer = EnvFilter::try_from_default_env()
        .or_else(|_| EnvFilter::try_new("info"))
        .unwrap();

    tracing_subscriber::registry()
        .with(filter_layer)
        .with(fmt_layer)
        .init();

    // Create observability service
    let cache = Arc::new(Cache::new(
        config.cache.max_size as usize,
        Some(config.cache.ttl),
    ));

    let observability_service = Arc::new(ObservabilityService::new(
        Arc::new(config.observability.clone()),
        cache.clone(),
    ));

    // Create a new trace context for the server startup
    let trace_ctx = observability_service.create_trace_context();

    // Log server startup with trace context
    let mut fields = HashMap::new();
    fields.insert("address".to_string(), serde_json::to_value(addr.to_string()).unwrap());
    fields.insert("version".to_string(), serde_json::to_value(env!("CARGO_PKG_VERSION")).unwrap());

    observability_service.log(LogLevel::Info, "Server starting", fields, Some(trace_ctx));

    // Create server state
    let state = ServerState {
        config: Arc::new(config.clone()),
        db: Arc::new(db),
        git: Arc::new(git),
        cache,
        repository_service: None,
        commit_service: None,
        file_service: None,
        format_service: None,
        index_service: None,
        search_service: None,
        status_service: None,
        observability_service: Some(observability_service.clone()),
        auth_service: None,
        user_service: None,
        maintenance_scheduler: None,
    };

    // Initialize services
    let state = initialize_services(state).await?;

    // Build router
    let mut router = Router::new();

    // Add routes for API
    crate::http::routes::api::api_routes(&mut router, &state)?;

    // Add routes for web interface
    crate::http::routes::web::web_routes(&mut router, &state)?;

    // Add middleware for metrics collection
    let metrics_middleware = MetricsMiddleware::new(observability_service);
    let router = router.layer(metrics_middleware);

    // Create the Axum service
    let app = router.into_make_service();

    // Create the HTTP server
    let server = Server::bind(&addr).serve(app);

    Ok(server)
}
