//! Art - A Git Repository Browser
//!
//! Art is a lightweight web-based Git repository browser inspired by cgit,
//! providing a clean interface to browse repositories, view commit history,
//! and display files with syntax highlighting.

mod config;
mod data;
mod error;
mod http;
mod service;
mod template;
mod util;

use crate::config::Config;
use crate::error::{Error, Result};
use crate::http::serve;
use crate::data::user::UserRepository;
use crate::service::user::UserService;
use crate::service::repository::maintenance::{MaintenanceScheduler, MaintenanceSchedulerConfig};
use crate::data::{Sqlite, Git};
use crate::service::{RepositoryService, ObservabilityService};
use crate::service::format::FormatService;
use crate::data::cache::Cache;
use crate::template::TemplateManager;
use crate::service::observability::ContentMetricsCollector;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::{info, error};
use tracing_subscriber::EnvFilter;
use std::net::SocketAddr;
use std::sync::Arc;
use std::env;
use std::sync::RwLock;

/// Application state
struct AppState {
    /// Configuration
    pub config: Arc<Config>,

    /// Database connection pool
    pub db_pool: Arc<Sqlite>,

    /// Git repository store
    pub git_store: Arc<Git>,

    /// Cache service
    pub cache: Arc<Cache>,

    /// Template manager
    pub template_manager: Arc<TemplateManager>,

    /// Repository service
    pub repository_service: Arc<RepositoryService>,

    /// Observability service
    pub observability_service: Arc<ObservabilityService>,

    /// Format service
    pub format_service: Arc<RwLock<FormatService>>,

    /// Maintenance scheduler
    pub maintenance_scheduler: Option<Arc<MaintenanceScheduler>>,
}

/// Command line arguments for the application
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    /// Path to the configuration file
    #[clap(short, long, value_parser, default_value = "config.toml")]
    config: PathBuf,

    /// Command to run
    #[clap(subcommand)]
    command: Option<Command>,
}

/// Subcommands for the application
#[derive(Subcommand, Debug)]
enum Command {
    /// Start the HTTP server
    Serve {
        /// Address to bind to
        #[clap(short, long, value_parser, default_value = "127.0.0.1:3000")]
        address: String,
    },
}

/// Main function
#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing for logging
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .json()
        .init();

    info!("Starting Art application");

    // Load configuration
    let config_path = env::var("ART_CONFIG_PATH").unwrap_or_else(|_| "config.toml".to_string());
    let config = Config::from_file(&config_path)?;
    info!("Configuration loaded from {}", config_path);

    // Set up database connection
    let db_pool = Arc::new(Sqlite::new(&config.database)?);
    info!("Database connection pool created");

    // Set up Git repository store
    let git_store = Arc::new(Git::new(&config.git)?);
    info!("Git repository store initialized at {}", config.git.base_path);

    // Set up caching
    let cache = Arc::new(Cache::new(config.cache.clone()));
    info!("Cache initialized with {} max items", config.cache.max_items);

    // Set up template manager
    let template_manager = Arc::new(TemplateManager::new(&config.ui)?);
    info!("Template manager initialized");

    // Initialize services
    let repository_service = Arc::new(RepositoryService::new(
        git_store.clone(),
        cache.clone(),
    ));
    info!("Repository service initialized");

    // Initialize maintenance scheduler if enabled
    let maintenance_scheduler = if config.repository.maintenance_level > 0 {
        info!("Initializing maintenance scheduler");
        // Create maintenance config from repository config
        let scheduler_config = MaintenanceSchedulerConfig {
            enabled: true,
            check_interval_seconds: 3600, // Check every hour
            max_concurrent_tasks: 2,
            default_schedule: "0 2 * * *".to_string(), // 2 AM daily
            loose_objects_threshold: 10000,
            packfiles_threshold: 50,
            size_threshold: 1024 * 1024 * 1024, // 1 GB
            days_since_maintenance_threshold: 7, // 1 week
        };

        let scheduler = Arc::new(MaintenanceScheduler::new(
            scheduler_config,
            git_store.clone(),
            db_pool.clone(),
            repository_service.clone(),
        ));

        // Start the scheduler
        match scheduler.start().await {
            Ok(_) => {
                info!("Maintenance scheduler started successfully");
                Some(scheduler)
            }
            Err(e) => {
                error!("Failed to start maintenance scheduler: {}", e);
                None
            }
        }
    } else {
        info!("Maintenance scheduler disabled (maintenance_level=0)");
        None
    };

    // Initialize observability service with basic components
    let mut observability_service = ObservabilityService::new(
        config.observability.clone(),
        None, // No custom Prometheus registry
        None, // No content metrics config yet
    )
    .await?;

    // Now initialize the ContentMetricsCollector by modifying the structure directly
    if let Some(content_config) = &config.observability.content_metrics {
        // Create the ContentMetricsCollector
        let collector = ContentMetricsCollector::new(
            git_store.clone(),
            repository_service.clone(),
            Arc::new(observability_service.clone()),  // Pass a clone
            content_config.clone(),
        )?;

        let collector = Arc::new(tokio::sync::Mutex::new(collector));

        // Start the collector in a background task
        let collector_clone = collector.clone();
        tokio::spawn(async move {
            let mut collector = collector_clone.lock().await;
            if let Err(e) = collector.start().await {
                error!("Failed to start content metrics collector: {}", e);
            }
        });

        // Store the collector
        observability_service.content_metrics_collector = Some(collector);
        info!("Content metrics collection configured");
    }

    let observability_service = Arc::new(observability_service);
    info!("Observability service initialized");

    // Initialize FormatService with accessibility support
    let format_service = Arc::new(RwLock::new(FormatService::new()));
    info!("Format service initialized");

    // Create application state
    let app_state = Arc::new(AppState {
        config: Arc::new(config.clone()),
        db_pool: db_pool.clone(),
        git_store,
        cache,
        template_manager,
        repository_service,
        observability_service,
        format_service,
        maintenance_scheduler,
    });
    info!("Application state created");

    // Initialize user service if enabled
    let user_service = if config.features.user_management {
        info!("Initializing user service");
        let service = match UserService::new(db_pool.clone()) {
            Ok(service) => {
                // Initialize tables
                if let Err(err) = service.init().await {
                    error!("Failed to initialize user service: {}", err);
                    None
                } else {
                    // Create default admin user if configured
                    if let Some(admin) = &config.auth.default_admin {
                        if let Err(err) = service.create_default_admin(
                            &admin.username,
                            &admin.email,
                            &admin.password
                        ).await {
                            error!("Failed to create default admin user: {}", err);
                        } else {
                            info!("Default admin user created: {}", admin.username);
                        }
                    }
                    Some(Arc::new(service))
                }
            }
            Err(err) => {
                error!("Failed to create user service: {}", err);
                None
            }
        };
        service
    } else {
        info!("User management disabled");
        None
    };

    // Set up HTTP routes
    let app = serve(
        app_state.config.clone(),
        app_state.repository_service.clone(),
        app_state.observability_service.clone(),
        app_state.git_store.clone(),
        user_service,
        app_state.maintenance_scheduler.clone(),
    )?;
    info!("Routes configured");

    // Run the HTTP server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server.port));
    info!("Starting HTTP server on {}", addr);
    axum::Server::bind(&addr)
        .serve(app.into_make_service_with_connect_info::<SocketAddr>())
        .await
        .map_err(|e| Error::Server(format!("Server error: {}", e)))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;
    use std::path::PathBuf;
    use tempfile::TempDir;

    #[test]
    fn test_cli_args_default() {
        // Test default arguments
        let args = Args::parse_from(["art"]);

        assert_eq!(args.config, PathBuf::from("config.toml"));
        assert!(args.command.is_none());
    }

    #[test]
    fn test_cli_args_custom() {
        // Test custom arguments
        let args = Args::parse_from([
            "art",
            "--config", "custom.toml",
            "serve",
            "--address", "127.0.0.1:8080"
        ]);

        assert_eq!(args.config, PathBuf::from("custom.toml"));
        match args.command {
            Some(Command::Serve { address }) => {
                assert_eq!(address, "127.0.0.1:8080");
            },
            _ => panic!("Expected Serve command")
        }
    }
}
