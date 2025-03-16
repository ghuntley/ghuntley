//! Implementation of CLI commands

use crate::cli::{Commands, RepoCommands, UserCommands};
use crate::config::Config;
use crate::error::{Error, Result};
use crate::prelude::*;
use std::path::PathBuf;
use tracing::{debug, error, info, warn};
use std::sync::Arc;
use std::io::{self, Write};
use crate::data::user::{User, UserRole};
use rpassword::read_password;

/// Execute the command specified in the CLI arguments
pub async fn execute_command(
    command: &Commands,
    config: &mut Config,
    verbose: bool,
) -> Result<()> {
    // Set log level based on verbose flag
    if verbose {
        config.observability.log_level = "debug".to_string();
    }

    match command {
        Commands::Serve {
            port,
            bind,
            repo_dir,
            db_path,
            cache_size,
            threads,
        } => {
            // Override config with CLI arguments
            if let Some(port_val) = port {
                config.server.port = *port_val;
            }

            if let Some(bind_val) = bind {
                config.server.bind_address = bind_val.clone();
            }

            if let Some(repo_dir_val) = repo_dir {
                config.repository.repo_dir = repo_dir_val.clone();
            }

            if let Some(db_path_val) = db_path {
                config.database.path = db_path_val.clone();
            }

            if let Some(cache_size_val) = cache_size {
                // Convert MB to bytes
                config.cache.max_size = *cache_size_val * 1024 * 1024;
            }

            if let Some(threads_val) = threads {
                config.server.threads = *threads_val;
            }

            serve_command(config).await
        }

        Commands::Repo { command } => match command {
            RepoCommands::List { repo_dir } => {
                if let Some(dir) = repo_dir {
                    config.repository.repo_dir = dir.clone();
                }

                list_repos_command(config)
            }

            RepoCommands::Add { path } => add_repo_command(config, path),

            RepoCommands::Reindex { repo_dir, db_path } => {
                if let Some(dir) = repo_dir {
                    config.repository.repo_dir = dir.clone();
                }

                if let Some(db) = db_path {
                    config.database.path = db.clone();
                }

                reindex_repos_command(config)
            }
        },

        Commands::Maintenance { repo_dir } => {
            if let Some(dir) = repo_dir {
                config.repository.repo_dir = dir.clone();
            }

            maintenance_command(config)
        }

        Commands::Status { repo_dir, db_path } => {
            if let Some(dir) = repo_dir {
                config.repository.repo_dir = dir.clone();
            }

            if let Some(db) = db_path {
                config.database.path = db.clone();
            }

            status_command(config)
        }

        Commands::User { command } => match command {
            UserCommands::List { db_path, limit, offset, role, active_only } => {
                if let Some(db) = db_path {
                    config.database.path = db.clone();
                }

                list_users_command(config, *limit, *offset, role.clone(), *active_only).await
            }

            UserCommands::Add { db_path, username, email, display_name, password, role } => {
                if let Some(db) = db_path {
                    config.database.path = db.clone();
                }

                let password = match password {
                    Some(p) => p.clone(),
                    None => prompt_password("Enter password: ")?
                };

                add_user_command(config, username, email, display_name, &password, role).await
            }

            UserCommands::Update { db_path, user, email, display_name, password, role, active, inactive } => {
                if let Some(db) = db_path {
                    config.database.path = db.clone();
                }

                let password = match password {
                    Some(p) => Some(p.as_str()),
                    None => None
                };

                let active_status = if *active {
                    Some(true)
                } else if *inactive {
                    Some(false)
                } else {
                    None
                };

                update_user_command(
                    config,
                    user,
                    email.clone(),
                    display_name.clone(),
                    password,
                    role.clone(),
                    active_status
                ).await
            }

            UserCommands::Delete { db_path, user, force } => {
                if let Some(db) = db_path {
                    config.database.path = db.clone();
                }

                delete_user_command(config, user, *force).await
            }

            UserCommands::CreateAdmin { db_path, username, email, display_name, password } => {
                // Get the password if not provided
                let pwd = match password {
                    Some(p) => p,
                    None => prompt_password()?,
                };

                // Initialize user service
                let db_path = db_path.unwrap_or_else(|| config.database.path.clone());
                let user_service = initialize_user_service(&db_path).await?;

                // First check if there are any users
                let users = user_service.list_users(100, 0, None, false).await?;

                if users.is_empty() {
                    // Create the admin user
                    let result = user_service.create_user(&username, &email, &display_name, &pwd, UserRole::Admin, true).await;

                    match result {
                        Ok(_) => {
                            println!("Admin user '{}' created successfully", username);
                            Ok(())
                        },
                        Err(e) => {
                            error!("Failed to create admin user: {}", e);
                            Err(anyhow!("Failed to create admin user: {}", e))
                        }
                    }
                } else {
                    println!("Admin user not created as users already exist in the database");
                    Ok(())
                }
            },

            UserCommands::Validate { db_path, username, password } => {
                // Get the password if not provided
                let pwd = match password {
                    Some(p) => p,
                    None => prompt_password()?,
                };

                // Initialize user service
                let db_path = db_path.unwrap_or_else(|| config.database.path.clone());
                let user_service = initialize_user_service(&db_path).await?;

                // Validate the credentials
                match user_service.validate_credentials(&username, &pwd).await {
                    Ok(true) => {
                        println!("Authentication successful for user '{}'", username);
                        Ok(())
                    },
                    Ok(false) => {
                        println!("Authentication failed: Invalid username or password");
                        Err(anyhow!("Authentication failed: Invalid username or password"))
                    },
                    Err(e) => {
                        error!("Authentication error: {}", e);
                        Err(anyhow!("Authentication error: {}", e))
                    }
                }
            },
        },

        Commands::Db(db_command) => {
            match db_command {
                DbCommands::Backup { db_path, backup_dir, compression } => {
                    if let Some(db) = db_path {
                        config.database.path = db.clone();
                    }

                    if let Some(dir) = backup_dir {
                        config.database.backup_dir = dir.clone();
                    }

                    config.database.backup_compression_level = *compression;
                    config.database.enable_backups = true;

                    db_backup_command(config).await
                },

                DbCommands::List { db_path, backup_dir, detailed } => {
                    if let Some(db) = db_path {
                        config.database.path = db.clone();
                    }

                    if let Some(dir) = backup_dir {
                        config.database.backup_dir = dir.clone();
                    }

                    db_list_backups_command(config, *detailed).await
                },

                DbCommands::Restore { db_path, backup_file, force } => {
                    if let Some(db) = db_path {
                        config.database.path = db.clone();
                    }

                    db_restore_command(config, backup_file, *force).await
                },

                DbCommands::Verify { backup_file } => {
                    db_verify_backup_command(config, backup_file).await
                },
            }
        },
    }
}

/// Start the web server
async fn serve_command(config: &Config) -> Result<()> {
    info!("Starting Art web server...");
    info!("Listening on {}:{}", config.server.bind_address, config.server.port);
    info!("Repository directory: {:?}", config.repository.repo_dir);
    info!("Database path: {:?}", config.database.path);

    // Create a root trace context for the entire server startup process
    let root_trace_ctx = crate::service::observability::TraceContext::new();
    let mut otel_tracer: Option<Arc<crate::service::observability::opentelemetry::OpenTelemetryTracer>> = None;

    // Initialize database
    let db = match crate::data::sqlite::Sqlite::new(&config.database) {
        Ok(db) => {
            info!("Database initialized successfully");
            Arc::new(db)
        },
        Err(e) => {
            error!("Failed to initialize database: {}", e);
            // Record the error in the trace if OpenTelemetry is configured later
            return Err(Error::Database(format!("Database initialization failed: {}", e)));
        }
    };

    // Initialize Git service
    let git = match crate::data::git::Git::new(&config.repository.repo_dir) {
        Ok(git) => {
            info!("Git service initialized successfully");
            Arc::new(git)
        },
        Err(e) => {
            error!("Failed to initialize Git service: {}", e);
            return Err(Error::Git(format!("Git service initialization failed: {}", e)));
        }
    };

    // Initialize cache
    let cache = Arc::new(crate::data::cache::Cache::new(
        config.database.cache_max_entries,
        Some(config.database.cache_ttl_seconds)
    ));
    info!("Cache initialized with max {} entries and {} seconds TTL",
          config.database.cache_max_entries,
          config.database.cache_ttl_seconds);

    // Initialize repository service
    let repository_service = Arc::new(crate::service::repository::RepositoryService::new(
        git.clone(),
        db.clone(),
        cache.clone(),
        config.clone()
    ));
    info!("Repository service initialized");

    // Initialize OpenTelemetry if configured
    if let Some(otel_config) = &config.observability.opentelemetry {
        if otel_config.enabled {
            // Log configuration details for debugging
            info!("Initializing OpenTelemetry with endpoint: {}", otel_config.endpoint);
            info!("OpenTelemetry service name: {}", otel_config.service_name);
            info!("OpenTelemetry sampling ratio: {}", otel_config.sampling_ratio);

            // Log export destinations
            if otel_config.export_otlp {
                info!("OpenTelemetry OTLP export enabled");
            }
            if otel_config.export_stdout {
                info!("OpenTelemetry stdout export enabled (for debugging)");
            }

            // Log custom attributes if configured
            if !otel_config.default_attributes.is_empty() {
                info!("OpenTelemetry configured with {} custom attributes",
                     otel_config.default_attributes.len());
                for (key, value) in &otel_config.default_attributes {
                    debug!("OpenTelemetry attribute: {}={}", key, value);
                }
            }

            // Initialize the OpenTelemetry tracer with better error handling
            match crate::service::observability::opentelemetry::OpenTelemetryTracer::new(otel_config.clone()) {
                Ok(tracer) => {
                    info!("OpenTelemetry tracer initialized successfully");

                    // Save the tracer for later use
                    let tracer_arc = Arc::new(tracer);
                    otel_tracer = Some(tracer_arc.clone());

                    // Create a root span for server startup with detailed attributes
                    match tracer_arc.create_and_record_span(
                        "art_server_startup",
                        &root_trace_ctx,
                        &[
                            ("component", "server"),
                            ("event", "startup"),
                            ("port", &config.server.port.to_string()),
                            ("address", &config.server.bind_address),
                            ("repo_dir", &config.repository.repo_dir.to_string_lossy()),
                            ("db_path", &config.database.path.to_string_lossy()),
                            ("cache_size", &config.database.cache_max_entries.to_string()),
                            ("cache_ttl", &config.database.cache_ttl_seconds.to_string()),
                        ],
                        &[
                            ("server_init", {
                                let mut map = std::collections::HashMap::new();
                                map.insert("timestamp".to_string(),
                                           chrono::Utc::now().to_rfc3339().to_string());
                                map.insert("version".to_string(),
                                           env!("CARGO_PKG_VERSION").to_string());
                                map
                            }),
                        ],
                        crate::service::observability::opentelemetry::SpanKind::Server,
                    ) {
                        Ok(_) => info!("Server startup span recorded successfully"),
                        Err(e) => warn!("Failed to record server startup span: {}", e),
                    }

                    // Create child spans for major components
                    let db_trace_ctx = root_trace_ctx.create_child();
                    match tracer_arc.create_and_record_span(
                        "database_initialization",
                        &db_trace_ctx,
                        &[
                            ("component", "database"),
                            ("path", &config.database.path.to_string_lossy()),
                            ("max_connections", &config.database.max_connections.to_string()),
                            ("connection_timeout", &config.database.connection_timeout.to_string()),
                        ],
                        &[("database_init", std::collections::HashMap::new())],
                        crate::service::observability::opentelemetry::SpanKind::Internal,
                    ) {
                        Ok(_) => debug!("Database initialization span recorded"),
                        Err(e) => warn!("Failed to record database span: {}", e),
                    }

                    let git_trace_ctx = root_trace_ctx.create_child();
                    match tracer_arc.create_and_record_span(
                        "git_service_initialization",
                        &git_trace_ctx,
                        &[
                            ("component", "git"),
                            ("repo_dir", &config.repository.repo_dir.to_string_lossy()),
                        ],
                        &[("git_init", std::collections::HashMap::new())],
                        crate::service::observability::opentelemetry::SpanKind::Internal,
                    ) {
                        Ok(_) => debug!("Git service initialization span recorded"),
                        Err(e) => warn!("Failed to record git service span: {}", e),
                    }

                    let cache_trace_ctx = root_trace_ctx.create_child();
                    match tracer_arc.create_and_record_span(
                        "cache_initialization",
                        &cache_trace_ctx,
                        &[
                            ("component", "cache"),
                            ("max_entries", &config.database.cache_max_entries.to_string()),
                            ("ttl_seconds", &config.database.cache_ttl_seconds.to_string()),
                        ],
                        &[("cache_init", std::collections::HashMap::new())],
                        crate::service::observability::opentelemetry::SpanKind::Internal,
                    ) {
                        Ok(_) => debug!("Cache initialization span recorded"),
                        Err(e) => warn!("Failed to record cache span: {}", e),
                    }
                },
                Err(e) => {
                    warn!("Failed to initialize OpenTelemetry tracer: {}", e);
                    warn!("Distributed tracing will be disabled");
                    warn!("Error details: {:?}", e);

                    // Try to determine the root cause of the initialization failure
                    let error_message = match e.to_string().to_lowercase() {
                        msg if msg.contains("connection") => {
                            "Failed to connect to the OpenTelemetry endpoint. Please check network connectivity and endpoint configuration."
                        },
                        msg if msg.contains("timeout") => {
                            "Connection to OpenTelemetry endpoint timed out. Consider increasing the timeout in configuration."
                        },
                        msg if msg.contains("authentication") || msg.contains("auth") => {
                            "Authentication to the OpenTelemetry endpoint failed. Please check credentials."
                        },
                        _ => "Unknown error occurred during OpenTelemetry initialization."
                    };
                    warn!("OpenTelemetry initialization error: {}", error_message);
                }
            }
        } else {
            info!("OpenTelemetry tracing is disabled in configuration");
        }
    } else {
        info!("OpenTelemetry is not configured, distributed tracing will be disabled");
    }

    // Initialize observability service with more detailed error handling
    let observability_service = Arc::new(
        match crate::service::observability::ObservabilityService::new(
            config.observability.clone(),
            Some(git.clone()),
            Some(repository_service.clone())
        ).await {
            Ok(service) => {
                info!("Observability service initialized successfully");

                // If we have a tracer, store it in the service
                if let Some(tracer) = otel_tracer.clone() {
                    debug!("Storing OpenTelemetry tracer in observability service");
                    // This would require a method to set the tracer, which doesn't exist yet
                    // We'll use what the service itself creates
                }

                service
            },
            Err(e) => {
                warn!("Failed to initialize observability service with advanced features: {}", e);
                warn!("Falling back to basic observability service");

                match crate::service::observability::ObservabilityService::new(
                    config.observability.clone(),
                    None,
                    None
                ).await {
                    Ok(service) => {
                        info!("Basic observability service initialized successfully");
                        service
                    },
                    Err(e) => {
                        error!("Failed to initialize basic observability service: {}", e);
                        return Err(Error::Internal(format!("Observability service initialization failed: {}", e)));
                    }
                }
            }
        }
    );

    // Record the server start event in metrics with more details
    observability_service.increment_connections();
    observability_service.record_request("SERVER", "startup");

    // Track business metrics for server startup
    let _ = observability_service.track_business_metric(
        "server_startup",
        1.0,
        &[
            ("port", &config.server.port.to_string()),
            ("address", &config.server.bind_address),
            ("timestamp", &chrono::Utc::now().timestamp().to_string()),
        ]
    );

    // Collect initial system metrics with better error handling
    match observability_service.collect_system_metrics() {
        Ok(_) => debug!("Initial system metrics collected successfully"),
        Err(e) => {
            warn!("Failed to collect initial system metrics: {}", e);
            // Try to determine the reason for failure
            if e.to_string().contains("permission") {
                warn!("System metrics collection may require elevated permissions");
            }
        }
    };

    // Start repository indexing in the background with enhanced tracing
    let index_service = Arc::new(crate::service::index::IndexService::new(
        git.clone(),
        db.clone(),
        cache.clone(),
        repository_service.clone()
    ));

    // Spawn background task to index all repositories with improved tracing
    tokio::spawn({
        let index_service = index_service.clone();
        let repo_service = repository_service.clone();
        let obs_service = observability_service.clone();
        let index_root_trace = root_trace_ctx.create_child(); // Create child span from root

        async move {
            // Create a specific trace context for the indexing task
            info!("Creating indexing task trace context");

            // Get all repositories with better error handling
            match repo_service.list_repositories().await {
                Ok(repos) => {
                    let repos_count = repos.len();
                    info!("Starting indexing of {} repositories in the background", repos_count);

                    // Record indexing task in metrics and tracing with more details
                    obs_service.track_business_metric("indexing_task", 1.0, &[
                        ("operation", "start"),
                        ("repository_count", &repos_count.to_string()),
                        ("timestamp", &chrono::Utc::now().timestamp().to_string()),
                    ]).ok();

                    // Record the indexing operation in OpenTelemetry
                    obs_service.record_trace(&index_root_trace);

                    // Create a trace span specifically for the indexing process
                    if let Some(tracer) = obs_service.opentelemetry_tracer() {
                        let _ = tracer.create_and_record_span(
                            "repository_indexing",
                            &index_root_trace,
                            &[
                                ("component", "indexer"),
                                ("repository_count", &repos_count.to_string()),
                                ("operation", "bulk_index"),
                            ],
                            &[("indexing_start", std::collections::HashMap::new())],
                            crate::service::observability::opentelemetry::SpanKind::Internal,
                        );
                    }

                    let mut success_count = 0;
                    let mut error_count = 0;

                    // Process each repository with more detailed logging and tracing
                    for repo in repos {
                        // Create a child trace specific to this repository
                        let repo_trace = index_root_trace.create_child();

                        // Add specific repository information to the trace baggage
                        let mut repo_trace_with_info = repo_trace.clone();
                        repo_trace_with_info.add_baggage("repository.name", &repo.name);
                        repo_trace_with_info.add_baggage("repository.path", &repo.path);

                        // Record the start of this repository's indexing process
                        obs_service.record_trace(&repo_trace_with_info);

                        // Use the observability service to record the git operation and timing
                        obs_service.record_git_operation("index", &repo.name);
                        let timer = obs_service.start_git_operation_timer("index", &repo.name);

                        // Create a span for this specific repository's indexing operation
                        if let Some(tracer) = obs_service.opentelemetry_tracer() {
                            let _ = tracer.create_and_record_span(
                                &format!("index_repository_{}", repo.name),
                                &repo_trace_with_info,
                                &[
                                    ("component", "indexer"),
                                    ("repository", &repo.name),
                                    ("repository_path", &repo.path),
                                    ("operation", "index"),
                                ],
                                &[("repository_indexing", std::collections::HashMap::new())],
                                crate::service::observability::opentelemetry::SpanKind::Internal,
                            );
                        }

                        // Execute the actual indexing operation with detailed error handling
                        match index_service.index_repository(&repo.name).await {
                            Ok(_) => {
                                info!("Successfully indexed repository: {}", repo.name);
                                success_count += 1;

                                // Record successful indexing in business metrics
                                obs_service.track_business_metric("repository_indexed", 1.0, &[
                                    ("repository", &repo.name),
                                    ("status", "success"),
                                ]).ok();

                                // Create a span to mark successful completion
                                if let Some(tracer) = obs_service.opentelemetry_tracer() {
                                    let _ = tracer.create_and_record_span(
                                        &format!("index_repository_{}_complete", repo.name),
                                        &repo_trace_with_info,
                                        &[
                                            ("component", "indexer"),
                                            ("repository", &repo.name),
                                            ("status", "success"),
                                        ],
                                        &[],
                                        crate::service::observability::opentelemetry::SpanKind::Internal,
                                    );
                                }
                            },
                            Err(e) => {
                                warn!("Failed to index repository {}: {}", repo.name, e);
                                error_count += 1;

                                // Track the error with more details
                                obs_service.track_business_metric("indexing_error", 1.0, &[
                                    ("repository", &repo.name),
                                    ("error_type", "index_failure"),
                                    ("error_message", &e.to_string()),
                                ]).ok();

                                // Create a span to record the error
                                if let Some(tracer) = obs_service.opentelemetry_tracer() {
                                    let mut error_details = std::collections::HashMap::new();
                                    error_details.insert("error_message".to_string(), e.to_string());

                                    let _ = tracer.create_and_record_span(
                                        &format!("index_repository_{}_error", repo.name),
                                        &repo_trace_with_info,
                                        &[
                                            ("component", "indexer"),
                                            ("repository", &repo.name),
                                            ("status", "error"),
                                            ("error_type", "index_failure"),
                                        ],
                                        &[("indexing_error", error_details)],
                                        crate::service::observability::opentelemetry::SpanKind::Internal,
                                    );
                                }
                            }
                        }

                        // Stop the timer for this repository
                        timer.observe_duration();
                    }

                    // Record detailed indexing completion metrics
                    obs_service.track_business_metric("indexing_task", 0.0, &[
                        ("operation", "complete"),
                        ("repositories_total", &repos_count.to_string()),
                        ("repositories_success", &success_count.to_string()),
                        ("repositories_error", &error_count.to_string()),
                        ("duration_seconds", &chrono::Utc::now().timestamp().to_string()),
                    ]).ok();

                    // Create a final span to mark the completion of all indexing
                    if let Some(tracer) = obs_service.opentelemetry_tracer() {
                        let mut completion_details = std::collections::HashMap::new();
                        completion_details.insert("repositories_total".to_string(), repos_count.to_string());
                        completion_details.insert("repositories_success".to_string(), success_count.to_string());
                        completion_details.insert("repositories_error".to_string(), error_count.to_string());

                        let _ = tracer.create_and_record_span(
                            "repository_indexing_complete",
                            &index_root_trace,
                            &[
                                ("component", "indexer"),
                                ("operation", "bulk_index_complete"),
                                ("repositories_total", &repos_count.to_string()),
                                ("repositories_success", &success_count.to_string()),
                                ("repositories_error", &error_count.to_string()),
                            ],
                            &[("indexing_complete", completion_details)],
                            crate::service::observability::opentelemetry::SpanKind::Internal,
                        );
                    }

                    info!("Repository indexing complete: {} successful, {} failed",
                         success_count, error_count);
                },
                Err(e) => {
                    warn!("Failed to list repositories for indexing: {}", e);

                    // Record the error with more details
                    obs_service.track_business_metric("indexing_error", 1.0, &[
                        ("error_type", "list_repositories_failure"),
                        ("error_message", &e.to_string()),
                    ]).ok();

                    // Create a span to record the error
                    if let Some(tracer) = obs_service.opentelemetry_tracer() {
                        let mut error_details = std::collections::HashMap::new();
                        error_details.insert("error_message".to_string(), e.to_string());

                        let _ = tracer.create_and_record_span(
                            "repository_listing_error",
                            &index_root_trace,
                            &[
                                ("component", "indexer"),
                                ("operation", "list_repositories"),
                                ("status", "error"),
                                ("error_type", "list_failure"),
                            ],
                            &[("listing_error", error_details)],
                            crate::service::observability::opentelemetry::SpanKind::Internal,
                        );
                    }
                }
            }
        }
    });

    // Create HTTP server address
    let addr = format!("{}:{}", config.server.bind_address, config.server.port)
        .parse()
        .map_err(|e| Error::InvalidConfig(format!("Invalid server address: {}", e)))?;

    // Initialize web server
    let app = match crate::http::serve(
        Arc::new(config.clone()),
        repository_service,
        observability_service.clone(),
        git,
        None // No user service for now
    ).await {
        Ok(app) => app,
        Err(e) => {
            error!("Failed to initialize web server: {}", e);
            return Err(Error::Server(format!("Server initialization failed: {}", e)));
        }
    };

    // Start HTTP server
    info!("Starting HTTP server on {}", addr);
    match axum::Server::bind(&addr.parse::<std::net::SocketAddr>().unwrap())
        .serve(app.into_make_service())
        .await
    {
        Ok(_) => Ok(()),
        Err(e) => {
            error!("HTTP server error: {}", e);
            Err(Error::Server(format!("HTTP server error: {}", e)))
        }
    }
}

/// List repositories
fn list_repos_command(config: &Config) -> Result<()> {
    info!("Listing repositories in {:?}", config.repository.repo_dir);

    // Get list of repositories
    let repo_dir = &config.repository.repo_dir;
    let entries = std::fs::read_dir(repo_dir)
        .map_err(|e| Error::IoError(format!("Failed to read repository directory: {}", e)))?;

    // Collect repositories info
    let mut repos = Vec::new();
    let mut max_name_len = 0;
    let mut max_desc_len = 0;

    for entry in entries {
        let entry = entry.map_err(|e| Error::IoError(format!("Failed to read directory entry: {}", e)))?;
        let path = entry.path();

        // Skip non-directories
        if !path.is_dir() {
            continue;
        }

        // Check if this is a Git repository (has .git directory or is a bare repo)
        let is_git_repo = path.join(".git").exists() || path.join("HEAD").exists();
        if !is_git_repo {
            debug!("Skipping non-Git directory: {:?}", path);
            continue;
        }

        // Get repository name (directory name)
        let name = path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        // Get repository description if available
        let description = get_repo_description(path);

        // Get last update time
        let last_update = get_repo_last_update(path);

        // Get branch count
        let branch_count = get_repo_branch_count(path);

        // Track max lengths for formatting
        max_name_len = max_name_len.max(name.len());
        max_desc_len = max_desc_len.max(description.as_ref().map_or(0, |d| d.len()));

        // Add repo info to the list
        repos.push((name, description, last_update, branch_count));
    }

    // Sort repositories by name
    repos.sort_by(|a, b| a.0.cmp(&b.0));

    // Print header if we found any repositories
    if !repos.is_empty() {
        println!("{} repositories found in {}", repos.len(), repo_dir.display());
        println!();

        // Calculate width for nice formatting (pad with 2 spaces)
        let name_width = max_name_len + 2;
        let desc_width = max_desc_len.min(50) + 2; // Limit description width

        // Print header
        println!("{:<name_width$}{:<desc_width$}{:<20}Branches",
            "Repository", "Description", "Last Update",
            name_width = name_width, desc_width = desc_width);

        // Print separator
        println!("{}", "-".repeat(name_width + desc_width + 30));

        // Print each repository
        for (name, description, last_update, branch_count) in repos {
            let desc_display = description.as_deref().unwrap_or("-");
            let last_update_display = last_update.unwrap_or_else(|| "unknown".to_string());

            println!("{:<name_width$}{:<desc_width$}{:<20}{}",
                name, desc_display, last_update_display, branch_count,
                name_width = name_width, desc_width = desc_width);
        }
    } else {
        println!("No Git repositories found in {}", repo_dir.display());
    }

    Ok(())
}

/// Get repository description from description file
fn get_repo_description(repo_path: &std::path::Path) -> Option<String> {
    // Check for description file (common in Git repositories)
    let desc_path = if repo_path.join(".git").exists() {
        // Non-bare repository
        repo_path.join(".git").join("description")
    } else {
        // Bare repository
        repo_path.join("description")
    };

    if desc_path.exists() {
        match std::fs::read_to_string(&desc_path) {
            Ok(content) => {
                let content = content.trim();
                // Skip default description
                if content == "Unnamed repository; edit this file 'description' to name the repository." {
                    None
                } else if !content.is_empty() {
                    Some(content.to_string())
                } else {
                    None
                }
            }
            Err(_) => None,
        }
    } else {
        None
    }
}

/// Get repository last update time
fn get_repo_last_update(repo_path: &std::path::Path) -> Option<String> {
    use std::process::Command;

    // Use git log to get the last commit date
    let is_bare = !repo_path.join(".git").exists();
    let git_dir_arg = if is_bare {
        format!("--git-dir={}", repo_path.display())
    } else {
        format!("--git-dir={}/.git", repo_path.display())
    };

    let output = Command::new("git")
        .arg(&git_dir_arg)
        .args(["log", "-1", "--format=%cr"])
        .output();

    match output {
        Ok(output) if output.status.success() => {
            let date_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !date_str.is_empty() {
                Some(date_str)
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Get repository branch count
fn get_repo_branch_count(repo_path: &std::path::Path) -> usize {
    use std::process::Command;

    // Use git branch to count branches
    let is_bare = !repo_path.join(".git").exists();
    let git_dir_arg = if is_bare {
        format!("--git-dir={}", repo_path.display())
    } else {
        format!("--git-dir={}/.git", repo_path.display())
    };

    let output = Command::new("git")
        .arg(&git_dir_arg)
        .args(["branch", "--list"])
        .output();

    match output {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout)
                .lines()
                .count()
        }
        _ => 0,
    }
}

/// Add a repository
fn add_repo_command(config: &Config, path: &PathBuf) -> Result<()> {
    info!("Adding repository from {:?}", path);

    // Validate that the path exists
    if !path.exists() {
        return Err(Error::InvalidRequest(format!("Path {:?} does not exist", path)));
    }

    // Check if this is a Git repository
    let is_git_repo = path.join(".git").exists() || path.join("HEAD").exists();
    if !is_git_repo {
        return Err(Error::InvalidRequest(format!("Path {:?} is not a Git repository", path)));
    }

    // Determine repository type (bare or non-bare)
    let is_bare = !path.join(".git").exists();
    let repo_type = if is_bare { "bare" } else { "non-bare" };

    // Get repository name
    let repo_name = path.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();

    // Get repository description
    let description = get_repo_description(path);
    let desc_display = description.as_deref().unwrap_or("<No description>");

    // Determine target location in the configured repository directory
    let target_path = config.repository.repo_dir.join(&repo_name);

    // Check if the repository already exists in the target directory
    if target_path.exists() {
        return Err(Error::InvalidRequest(
            format!("Repository '{}' already exists in {:?}", repo_name, config.repository.repo_dir)
        ));
    }

    // Create the target repository directory if it doesn't exist
    if !config.repository.repo_dir.exists() {
        std::fs::create_dir_all(&config.repository.repo_dir)
            .map_err(|e| Error::IoError(format!("Failed to create repository directory: {}", e)))?;
    }

    // Now we have two options:
    // 1. Create a symlink to the repository (this is simpler but less portable)
    // 2. Clone the repository to the target location (more portable but requires more disk space)

    // For this implementation, we'll use a symlink approach for simplicity
    // On Windows, this requires admin privileges, so this might need to be revisited

    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;
        // Create a symlink
        symlink(path, &target_path)
            .map_err(|e| Error::IoError(format!("Failed to create symlink: {}", e)))?;

        println!("Added {} repository '{}' ({}) as a symlink", repo_type, repo_name, desc_display);
        println!("Source: {:?}", path);
        println!("Target: {:?}", target_path);
    }

    #[cfg(windows)]
    {
        use std::os::windows::fs::symlink_dir;
        // Create a directory symlink
        symlink_dir(path, &target_path)
            .map_err(|e| Error::IoError(format!("Failed to create symlink: {}", e)))?;

        println!("Added {} repository '{}' ({}) as a symlink", repo_type, repo_name, desc_display);
        println!("Source: {:?}", path);
        println!("Target: {:?}", target_path);
        println!("Note: Creating symlinks on Windows may require administrator privileges");
    }

    println!("\nRepository added successfully. You can now browse it using the Art web interface.");

    Ok(())
}

/// Reindex repositories
fn reindex_repos_command(config: &Config) -> Result<()> {
    info!("Reindexing repositories in {:?}", config.repository.repo_dir);

    // Ensure repository directory exists
    if !config.repository.repo_dir.exists() {
        return Err(Error::InvalidRequest(
            format!("Repository directory {:?} does not exist", config.repository.repo_dir)
        ));
    }

    // Get list of repositories
    let entries = std::fs::read_dir(&config.repository.repo_dir)
        .map_err(|e| Error::IoError(format!("Failed to read repository directory: {}", e)))?;

    // Collect repository information
    let mut repos = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|e| Error::IoError(format!("Failed to read directory entry: {}", e)))?;
        let path = entry.path();

        // Skip non-directories
        if !path.is_dir() {
            continue;
        }

        // Check if this is a Git repository
        let is_git_repo = path.join(".git").exists() || path.join("HEAD").exists();
        if !is_git_repo {
            debug!("Skipping non-Git directory: {:?}", path);
            continue;
        }

        // Get repository information
        let repo_name = path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        let is_bare = !path.join(".git").exists();
        let description = get_repo_description(&path);

        // Get repository stats
        let stats = collect_repository_stats(&path, is_bare);

        // Add repository to the list
        repos.push((repo_name, path.clone(), is_bare, description, stats));
    }

    // Sort repositories by name
    repos.sort_by(|a, b| a.0.cmp(&b.0));

    // Print results
    if repos.is_empty() {
        println!("No repositories found in {:?}", config.repository.repo_dir);
        return Ok(());
    }

    println!("Found {} repositories:", repos.len());

    // Database connection would be established here
    // For this implementation, we'll just print the repositories that would be indexed
    println!("\nRepositories to be indexed:");
    println!("{:<30} {:<10} {:<10} {:<10} {}", "Name", "Branches", "Tags", "Commits", "Description");
    println!("{}", "-".repeat(80));

    for (name, _, _, description, stats) in &repos {
        let desc_display = description.as_deref().unwrap_or("-");
        println!("{:<30} {:<10} {:<10} {:<10} {}",
                 name,
                 stats.branch_count,
                 stats.tag_count,
                 stats.commit_count,
                 desc_display);
    }

    // In a real implementation, we would update the database with repository information here
    println!("\nRepository indexing simulation completed.");
    println!("Note: This is a simulation - actual database updates would happen here.");
    println!("To enable full database reindexing, further implementation is required.");

    Ok(())
}

/// Collect repository statistics
fn collect_repository_stats(repo_path: &std::path::Path, is_bare: bool) -> RepositoryStats {
    use std::process::Command;

    // Initialize stats
    let mut stats = RepositoryStats {
        branch_count: 0,
        tag_count: 0,
        commit_count: 0,
    };

    // Git directory argument
    let git_dir_arg = if is_bare {
        format!("--git-dir={}", repo_path.display())
    } else {
        format!("--git-dir={}/.git", repo_path.display())
    };

    // Count branches
    if let Ok(output) = Command::new("git")
        .arg(&git_dir_arg)
        .args(["branch", "--list"])
        .output()
    {
        if output.status.success() {
            stats.branch_count = String::from_utf8_lossy(&output.stdout)
                .lines()
                .count();
        }
    }

    // Count tags
    if let Ok(output) = Command::new("git")
        .arg(&git_dir_arg)
        .args(["tag", "--list"])
        .output()
    {
        if output.status.success() {
            stats.tag_count = String::from_utf8_lossy(&output.stdout)
                .lines()
                .count();
        }
    }

    // Count commits on the default branch
    if let Ok(output) = Command::new("git")
        .arg(&git_dir_arg)
        .args(["rev-list", "--count", "HEAD"])
        .output()
    {
        if output.status.success() {
            if let Ok(count) = String::from_utf8_lossy(&output.stdout).trim().parse::<usize>() {
                stats.commit_count = count;
            }
        }
    }

    stats
}

/// Simple repository statistics
struct RepositoryStats {
    branch_count: usize,
    tag_count: usize,
    commit_count: usize,
}

/// Run maintenance tasks
fn maintenance_command(config: &Config) -> Result<()> {
    info!("Running maintenance on repositories in {:?}", config.repository.repo_dir);

    // Get list of repositories
    let repo_dir = &config.repository.repo_dir;
    let entries = std::fs::read_dir(repo_dir)
        .map_err(|e| Error::IoError(format!("Failed to read repository directory: {}", e)))?;

    let mut success_count = 0;
    let mut error_count = 0;

    // Process each repository
    for entry in entries {
        let entry = entry.map_err(|e| Error::IoError(format!("Failed to read directory entry: {}", e)))?;
        let path = entry.path();

        // Skip non-directories
        if !path.is_dir() {
            continue;
        }

        // Check if this is a Git repository (has .git directory or is a bare repo)
        let is_git_repo = path.join(".git").exists() || path.join("HEAD").exists();
        if !is_git_repo {
            debug!("Skipping non-Git directory: {:?}", path);
            continue;
        }

        info!("Maintaining repository at {:?}", path);

        // Determine if this is a bare repository
        let is_bare = !path.join(".git").exists();

        // Perform maintenance tasks
        if let Err(e) = perform_git_maintenance(&path, is_bare, config.repository.maintenance_level) {
            error!("Maintenance failed for repository {:?}: {}", path, e);
            error_count += 1;
        } else {
            success_count += 1;
        }
    }

    info!("Maintenance completed. Successful: {}, Failed: {}", success_count, error_count);
    Ok(())
}

/// Perform Git maintenance tasks on a repository
fn perform_git_maintenance(repo_path: &std::path::Path, is_bare: bool, level: u8) -> Result<()> {
    use std::process::Command;

    // For bare repositories, use the path directly; for non-bare, use .git directory
    let git_dir_arg = if is_bare {
        format!("--git-dir={}", repo_path.display())
    } else {
        format!("--git-dir={}/.git", repo_path.display())
    };

    // 1. Basic maintenance - always run
    debug!("Running basic maintenance for {:?}", repo_path);

    // Run git gc with auto option
    let output = Command::new("git")
        .arg(&git_dir_arg)
        .args(["gc", "--auto", "--quiet"])
        .output()
        .map_err(|e| Error::GitError(format!("Failed to execute git gc: {}", e)))?;

    if !output.status.success() {
        warn!("Git gc failed for {:?}: {}", repo_path,
              String::from_utf8_lossy(&output.stderr));
    }

    // 2. Reference update - clean up stale references
    debug!("Updating references for {:?}", repo_path);
    let output = Command::new("git")
        .arg(&git_dir_arg)
        .args(["reflog", "expire", "--all", "--expire=now"])
        .output()
        .map_err(|e| Error::GitError(format!("Failed to execute git reflog expire: {}", e)))?;

    if !output.status.success() {
        warn!("Git reflog expire failed for {:?}: {}", repo_path,
              String::from_utf8_lossy(&output.stderr));
    }

    // If maintenance level is standard (1) or higher, perform additional tasks
    if level >= 1 {
        // 3. Repack objects
        debug!("Repacking objects for {:?}", repo_path);
        let output = Command::new("git")
            .arg(&git_dir_arg)
            .args(["repack", "-d", "-l"])
            .output()
            .map_err(|e| Error::GitError(format!("Failed to execute git repack: {}", e)))?;

        if !output.status.success() {
            warn!("Git repack failed for {:?}: {}", repo_path,
                  String::from_utf8_lossy(&output.stderr));
        }

        // 4. Prune old objects
        debug!("Pruning old objects for {:?}", repo_path);
        let output = Command::new("git")
            .arg(&git_dir_arg)
            .args(["prune", "--expire=now"])
            .output()
            .map_err(|e| Error::GitError(format!("Failed to execute git prune: {}", e)))?;

        if !output.status.success() {
            warn!("Git prune failed for {:?}: {}", repo_path,
                  String::from_utf8_lossy(&output.stderr));
        }
    }

    // If maintenance level is full (2), perform intensive optimization
    if level >= 2 {
        // 5. Full repack with window-memory option
        debug!("Performing full repack for {:?}", repo_path);
        let output = Command::new("git")
            .arg(&git_dir_arg)
            .args(["repack", "-a", "-d", "-f", "--window-memory=1g", "--depth=50"])
            .output()
            .map_err(|e| Error::GitError(format!("Failed to execute full git repack: {}", e)))?;

        if !output.status.success() {
            warn!("Full git repack failed for {:?}: {}", repo_path,
                  String::from_utf8_lossy(&output.stderr));
        }

        // 6. Optimize references
        debug!("Optimizing references for {:?}", repo_path);
        let output = Command::new("git")
            .arg(&git_dir_arg)
            .args(["pack-refs", "--all"])
            .output()
            .map_err(|e| Error::GitError(format!("Failed to execute git pack-refs: {}", e)))?;

        if !output.status.success() {
            warn!("Git pack-refs failed for {:?}: {}", repo_path,
                  String::from_utf8_lossy(&output.stderr));
        }
    }

    info!("Maintenance completed successfully for {:?}", repo_path);
    Ok(())
}

/// Check system status
fn status_command(config: &Config) -> Result<()> {
    info!("Checking system status");

    // Print header
    println!("Art Git Repository Browser - System Status");
    println!("{}", "=".repeat(50));
    println!();

    // Check repository directory
    check_repository_directory(config);

    // Check database
    check_database_status(config);

    // Check Git installation
    check_git_installation();

    // Print summary
    println!();
    println!("Status check completed.");

    Ok(())
}

/// Check repository directory status
fn check_repository_directory(config: &Config) -> bool {
    println!("Repository Directory:");
    println!("  Path: {}", config.repository.repo_dir.display());

    // Check if directory exists
    if !config.repository.repo_dir.exists() {
        println!("  Status: {} Directory does not exist", format_status(false));
        return false;
    }

    // Check if it's a directory
    if !config.repository.repo_dir.is_dir() {
        println!("  Status: {} Not a directory", format_status(false));
        return false;
    }

    // Check if it's readable
    match std::fs::read_dir(&config.repository.repo_dir) {
        Ok(entries) => {
            // Count repositories
            let mut repo_count = 0;
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if path.is_dir() && (path.join(".git").exists() || path.join("HEAD").exists()) {
                        repo_count += 1;
                    }
                }
            }
            println!("  Status: {} Directory exists and is readable", format_status(true));
            println!("  Repositories: {}", repo_count);
            true
        }
        Err(e) => {
            println!("  Status: {} Directory exists but is not readable: {}", format_status(false), e);
            false
        }
    }
}

/// Check database status
fn check_database_status(config: &Config) -> bool {
    println!("\nDatabase:");
    println!("  Path: {}", config.database.path.display());

    // Check if database file exists
    let db_exists = config.database.path.exists();
    println!("  File exists: {}", format_status(db_exists));

    // If the database file doesn't exist, parent directory must be writable
    if !db_exists {
        if let Some(parent) = config.database.path.parent() {
            let parent_exists = parent.exists();
            let parent_writable = if parent_exists {
                match std::fs::metadata(parent) {
                    Ok(metadata) => metadata.permissions().readonly() == false,
                    Err(_) => false,
                }
            } else {
                false
            };

            println!("  Parent directory: {}", format_status(parent_exists));
            println!("  Parent writable: {}", format_status(parent_writable));

            return parent_exists && parent_writable;
        } else {
            println!("  Parent directory: {} No parent directory", format_status(false));
            return false;
        }
    }

    // Check if database file is writable
    let db_writable = match std::fs::metadata(&config.database.path) {
        Ok(metadata) => metadata.permissions().readonly() == false,
        Err(_) => false,
    };
    println!("  File writable: {}", format_status(db_writable));

    // Check database schema (this would require connecting to the database)
    println!("  Schema status: {} Not checked", format_status_neutral());

    db_exists && db_writable
}

/// Check Git installation
fn check_git_installation() -> bool {
    println!("\nGit Installation:");

    // Check git command
    use std::process::Command;
    match Command::new("git").arg("--version").output() {
        Ok(output) if output.status.success() => {
            let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
            println!("  Git command: {} {}", format_status(true), version);
            true
        }
        Ok(_) => {
            println!("  Git command: {} Installed but command failed", format_status(false));
            false
        }
        Err(_) => {
            println!("  Git command: {} Not found in PATH", format_status(false));
            false
        }
    }
}

/// Format status for display (OK/FAIL)
fn format_status(ok: bool) -> String {
    if ok {
        "[OK]".to_string()
    } else {
        "[FAIL]".to_string()
    }
}

/// Format neutral status for display
fn format_status_neutral() -> String {
    "[--]".to_string()
}

/// Prompt for a password without displaying input
fn prompt_password(prompt: &str) -> Result<String> {
    print!("{}", prompt);
    io::stdout().flush().map_err(|e| Error::IoError(format!("Failed to flush stdout: {}", e)))?;

    read_password().map_err(|e| Error::IoError(format!("Failed to read password: {}", e)))
}

/// Initialize the user service
async fn init_user_service(config: &Config) -> Result<Arc<crate::service::user::UserService>> {
    // Initialize SQLite database
    let db = match crate::data::sqlite::Sqlite::new(&config.database) {
        Ok(db) => Arc::new(db),
        Err(e) => {
            return Err(Error::Database(format!("Failed to initialize database: {}", e)));
        }
    };

    // Create user repository
    let user_repo = Arc::new(crate::data::user::repository::UserRepository::new(db));

    // Initialize repository
    user_repo.initialize().await?;

    // Create user service
    let user_service = Arc::new(crate::service::user::UserService::new(
        user_repo,
        config.auth.session_timeout,
        config.auth.max_login_attempts,
        config.auth.lockout_time,
    ));

    Ok(user_service)
}

/// Convert a string to a user role
fn string_to_role(role: &str) -> Result<UserRole> {
    match UserRole::from_str(role) {
        Some(r) => Ok(r),
        None => Err(Error::InvalidRequest(format!("Invalid role: {}", role)))
    }
}

/// List users command
async fn list_users_command(
    config: &Config,
    limit: usize,
    offset: usize,
    role: Option<String>,
    active_only: bool,
) -> Result<()> {
    info!("Listing users from database at {:?}", config.database.path);

    // Initialize user service
    let user_service = init_user_service(config).await?;

    // Create options for filtering
    let mut list_options = crate::data::user::UserListOptions {
        limit,
        offset,
        role: None,
        is_active: if active_only { Some(true) } else { None },
        is_locked: None,
    };

    // Set role filter if provided
    if let Some(role_str) = role {
        if let Some(role) = UserRole::from_str(&role_str) {
            list_options.role = Some(role);
        } else {
            return Err(Error::InvalidRequest(format!("Invalid role: {}", role_str)));
        }
    }

    // Get users from database
    let users = user_service.list_users(Some(list_options.limit), Some(list_options.offset)).await?;

    // Format and print user information
    println!("{} users found", users.len());
    println!();

    if users.is_empty() {
        println!("No users found in the database");
        return Ok(());
    }

    // Print header
    println!("{:<5} {:<20} {:<30} {:<20} {:<10} {:<10}",
             "ID", "Username", "Email", "Display Name", "Role", "Active");
    println!("{}", "-".repeat(100));

    // Print each user
    for user in users {
        println!("{:<5} {:<20} {:<30} {:<20} {:<10} {:<10}",
                 user.id,
                 user.username,
                 user.email,
                 user.display_name,
                 user.role,
                 if user.active { "Yes" } else { "No" });
    }

    Ok(())
}

/// Add user command
async fn add_user_command(
    config: &Config,
    username: &str,
    email: &str,
    display_name: &str,
    password: &str,
    role: &str,
) -> Result<()> {
    info!("Adding user {} to database at {:?}", username, config.database.path);

    // Initialize user service
    let user_service = init_user_service(config).await?;

    // Parse role
    let role = string_to_role(role)?;

    // Create user
    let user = user_service.create_user(
        username.to_string(),
        email.to_string(),
        display_name.to_string(),
        password,
        role,
    ).await?;

    println!("User created successfully:");
    println!("  ID:           {}", user.id);
    println!("  Username:     {}", user.username);
    println!("  Email:        {}", user.email);
    println!("  Display Name: {}", user.display_name);
    println!("  Role:         {}", user.role);

    Ok(())
}

/// Update user command
async fn update_user_command(
    config: &Config,
    user_identifier: &str,
    email: Option<String>,
    display_name: Option<String>,
    password: Option<&str>,
    role: Option<String>,
    active: Option<bool>,
) -> Result<()> {
    info!("Updating user {} in database at {:?}", user_identifier, config.database.path);

    // Initialize user service
    let user_service = init_user_service(config).await?;

    // Parse role if provided
    let role = match role {
        Some(r) => Some(string_to_role(&r)?),
        None => None,
    };

    // Find user by ID or username
    let user = if let Ok(id) = user_identifier.parse::<i64>() {
        // Try to find by ID
        user_service.get_user(id).await?
    } else {
        // Try to find by username
        user_service.get_user_by_username(user_identifier).await?
    };

    // Update user
    let updated_user = user_service.update_user(
        user.id,
        email.clone(),
        display_name.clone(),
        password,
        role,
        active,
    ).await?;

    println!("User updated successfully:");
    println!("  ID:           {}", updated_user.id);
    println!("  Username:     {}", updated_user.username);
    println!("  Email:        {}", updated_user.email);
    println!("  Display Name: {}", updated_user.display_name);
    println!("  Role:         {}", updated_user.role);
    println!("  Active:       {}", if updated_user.active { "Yes" } else { "No" });

    Ok(())
}

/// Delete user command
async fn delete_user_command(
    config: &Config,
    user_identifier: &str,
    force: bool,
) -> Result<()> {
    info!("Deleting user {} from database at {:?}", user_identifier, config.database.path);

    // Initialize user service
    let user_service = init_user_service(config).await?;

    // Find user by ID or username
    let user = if let Ok(id) = user_identifier.parse::<i64>() {
        // Try to find by ID
        user_service.get_user(id).await?
    } else {
        // Try to find by username
        user_service.get_user_by_username(user_identifier).await?
    };

    // Confirm deletion if not forced
    if !force {
        println!("Warning: You are about to delete the following user:");
        println!("  ID:           {}", user.id);
        println!("  Username:     {}", user.username);
        println!("  Email:        {}", user.email);
        println!("  Display Name: {}", user.display_name);
        println!("  Role:         {}", user.role);
        println!();

        print!("Are you sure you want to proceed? (y/N) ");
        io::stdout().flush().map_err(|e| Error::IoError(format!("Failed to flush stdout: {}", e)))?;

        let mut input = String::new();
        io::stdin().read_line(&mut input).map_err(|e| Error::IoError(format!("Failed to read input: {}", e)))?;

        if !["y", "yes"].contains(&input.trim().to_lowercase().as_str()) {
            println!("Deletion canceled.");
            return Ok(());
        }
    }

    // Delete user
    user_service.delete_user(user.id).await?;

    println!("User deleted successfully.");

    Ok(())
}

/// Create admin user command
async fn create_admin_command(
    config: &Config,
    username: &str,
    email: &str,
    display_name: &str,
    password: &str,
) -> Result<()> {
    info!("Creating admin user {} in database at {:?}", username, config.database.path);

    // Initialize user service
    let user_service = init_user_service(config).await?;

    // Create admin user
    match user_service.create_default_admin(
        username.to_string(),
        email.to_string(),
        display_name.to_string(),
        password,
    ).await? {
        Some(user) => {
            println!("Admin user created successfully:");
            println!("  ID:           {}", user.id);
            println!("  Username:     {}", user.username);
            println!("  Email:        {}", user.email);
            println!("  Display Name: {}", user.display_name);
            println!("  Role:         {}", user.role);
        },
        None => {
            println!("Admin user not created as users already exist in the database.");
        }
    }

    Ok(())
}

// Initialize a SQLite database with backup support
async fn init_db(config: &Config) -> Result<Sqlite> {
    Sqlite::new(&config.database).map_err(|e| anyhow!("Failed to initialize database: {}", e))
}

/// Create a database backup
async fn db_backup_command(config: &Config) -> Result<()> {
    println!("Creating database backup...");

    // Initialize database
    let db = init_db(config).await?;

    // Create backup
    match db.create_backup() {
        Ok(()) => {
            println!("Database backup created successfully.");
            Ok(())
        },
        Err(e) => {
            error!("Failed to create database backup: {}", e);
            Err(anyhow!("Failed to create database backup: {}", e))
        }
    }
}

/// List available database backups
async fn db_list_backups_command(config: &Config, detailed: bool) -> Result<()> {
    // Initialize database
    let db = init_db(config).await?;

    // Get list of backups
    let backups = db.list_backups()?;

    if backups.is_empty() {
        println!("No database backups found.");
        return Ok(());
    }

    println!("Available database backups ({})", backups.len());
    println!("----------------------------");

    for (i, (path, metadata)) in backups.iter().enumerate() {
        if detailed {
            println!("{}. {} ({})", i + 1, path.display(), format_size(metadata.size_bytes));
            println!("   Created: {}", metadata.created_at);
            println!("   Database version: {}", metadata.database_version);
            println!("   Source: {}", metadata.source_path.display());
            println!("   Compressed: {}", if metadata.compressed { "Yes" } else { "No" });
            println!("   Checksum: {}", metadata.checksum);
            println!();
        } else {
            println!(
                "{}. {} (Created: {}, Size: {})",
                i + 1,
                path.display(),
                metadata.created_at.format("%Y-%m-%d %H:%M:%S"),
                format_size(metadata.size_bytes)
            );
        }
    }

    Ok(())
}

/// Restore database from backup
async fn db_restore_command(config: &Config, backup_path: &Path, force: bool) -> Result<()> {
    // Check if backup exists
    if !backup_path.exists() {
        return Err(anyhow!("Backup file not found: {}", backup_path.display()));
    }

    // Ask for confirmation if not forced
    if !force {
        println!("WARNING: This will replace the current database with the backup.");
        println!("Database path: {}", config.database.path.display());
        println!("Backup path: {}", backup_path.display());
        print!("Are you sure you want to proceed? [y/N] ");
        std::io::stdout().flush()?;

        let mut response = String::new();
        std::io::stdin().read_line(&mut response)?;

        if !response.trim().eq_ignore_ascii_case("y") {
            println!("Restore cancelled.");
            return Ok(());
        }
    }

    println!("Restoring database from backup...");

    // Initialize database
    let db = init_db(config).await?;

    // Restore backup
    match db.restore_backup(backup_path) {
        Ok(()) => {
            println!("Database restored successfully.");
            Ok(())
        },
        Err(e) => {
            error!("Failed to restore database: {}", e);
            Err(anyhow!("Failed to restore database: {}", e))
        }
    }
}

/// Verify backup integrity
async fn db_verify_backup_command(config: &Config, backup_path: &Path) -> Result<()> {
    // Check if backup exists
    if !backup_path.exists() {
        return Err(anyhow!("Backup file not found: {}", backup_path.display()));
    }

    println!("Verifying backup integrity...");

    // Initialize database
    let db = init_db(config).await?;

    // Verify backup
    match db.verify_backup(backup_path) {
        Ok(true) => {
            println!("Backup integrity verified: OK");
            Ok(())
        },
        Ok(false) => {
            println!("Backup verification failed: Backup is corrupted.");
            Err(anyhow!("Backup is corrupted"))
        },
        Err(e) => {
            error!("Failed to verify backup: {}", e);
            Err(anyhow!("Failed to verify backup: {}", e))
        }
    }
}

/// Format file size in human-readable form
fn format_size(size: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];

    if size == 0 {
        return "0 B".to_string();
    }

    let base = 1024.0;
    let i = (size as f64).log(base).floor() as usize;
    let i = i.min(UNITS.len() - 1);

    let value = size as f64 / base.powi(i as i32);

    format!("{:.2} {}", value, UNITS[i])
}
