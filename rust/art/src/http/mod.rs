//! HTTP server implementation for the Art application

pub mod routes;
pub mod error;
pub mod errors;
pub mod git;
pub mod api;
pub mod server;

use axum::{
    Router,
    routing::{get, post},
};
use tower_http::{
    compression::CompressionLayer,
    trace::TraceLayer,
    cors::CorsLayer,
    services::ServeDir,
};
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::{info, warn};

use crate::config::Config;
use crate::data::{Git, Sqlite, Cache};
use crate::error::{Error, Result};
use crate::service::repository::RepositoryService;
use crate::service::observability::ObservabilityService;
use crate::service::user::UserService;
use crate::service::repository::maintenance::MaintenanceScheduler;
use crate::prelude::*;
use self::git::{GitHttp, GitHttpConfig};
use self::git::auth::{GitAuthService, UserAuthService, GitAuthConfig};

/// HTTP server state
#[derive(Clone)]
pub struct State {
    pub config: Arc<Config>,
    pub db: Arc<Sqlite>,
    pub cache: Arc<Cache>,
    pub git: Arc<Git>,
    pub repository_service: Arc<RepositoryService>,
    pub observability_service: Arc<ObservabilityService>,
    pub user_service: Option<Arc<UserService>>,
    pub maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
}

/// Create a new HTTP router
pub fn create_router(
    config: Arc<Config>,
    repository_service: Arc<RepositoryService>,
    observability_service: Arc<ObservabilityService>,
    git: Arc<Git>,
    user_service: Option<Arc<UserService>>,
    maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
) -> Router {
    // Create API router
    let api_router = api::create_router(
        repository_service.clone(),
        None, // index_service
        None, // search_service
        repository_service.clone(), // status_service
        observability_service.clone(), // health_service
        observability_service.clone(),
        git.clone(),
        user_service.clone(),
    );

    // Create static file server
    let static_routes = ServeDir::new("static");

    // Create base router
    let mut router = Router::new()
        .nest("/api", api_router)
        .nest_service("/static", static_routes)
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .layer(CorsLayer::permissive());

    // Add Git HTTP router if enabled and the feature is enabled
    if config.features.git_http {
        if let Some(git_http_config) = &config.git_http {
            if git_http_config.is_enabled {
                // Create Git HTTP service with configuration
                let http_config = GitHttpConfig {
                    enable_push: git_http_config.enable_push,
                    enable_fetch: git_http_config.enable_fetch,
                    enable_lfs: git_http_config.enable_lfs,
                    max_push_size: git_http_config.max_push_size,
                    verify_commit_signatures: git_http_config.verify_commit_signatures,
                    path_prefix: git_http_config.path_prefix.clone(),
                    auto_gc: git_http_config.auto_gc,
                    operation_timeout: git_http_config.operation_timeout,
                };

                let mut git_http = Arc::new(GitHttp::new(git.clone(), http_config));

                // Set up authentication if user service is available
                if let Some(user_service) = &user_service {
                    // Create auth config
                    let auth_config = GitAuthConfig {
                        require_auth_for_read: git_http_config.enable_fetch && config.auth.providers.contains(&"git".to_string()),
                        require_auth_for_write: git_http_config.enable_push,
                        realm: "Art Git".to_string(),
                        auth_header: None,
                        use_bearer_auth: false,
                    };

                    // Create user auth service
                    let auth_service = UserAuthService::new(auth_config, user_service.clone())
                        .with_default_permissions();

                    // Set auth service for Git HTTP
                    git_http = Arc::new(
                        GitHttp::new(git.clone(), http_config)
                            .with_auth(Arc::new(auth_service))
                    );

                    info!("Git HTTP authentication enabled using user service");
                }

                // Create Git HTTP router
                let git_router = git::router::GitRouter::new(git_http, git.clone());

                // Merge with main router
                router = router.merge(git_router);

                info!("Git HTTP protocol enabled");
            }
        }
    }

    router
}

/// Start the HTTP server
pub async fn serve(
    config: Arc<Config>,
    repository_service: Arc<RepositoryService>,
    observability_service: Arc<ObservabilityService>,
    git: Arc<Git>,
    user_service: Option<Arc<UserService>>,
    maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
) -> Result<Router> {
    // Create router
    let app = create_router(
        config.clone(),
        repository_service.clone(),
        observability_service.clone(),
        git.clone(),
        user_service,
        maintenance_scheduler,
    );

    Ok(app)
}
