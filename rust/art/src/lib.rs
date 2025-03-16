// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Art: A modern Git repository browser inspired by cgit
//!
//! Art is a command-line application that provides a web server for browsing
//! Git repositories with a clean and responsive interface.

pub mod app;
pub mod cli;
pub mod config;
pub mod data;
pub mod error;
pub mod http;
pub mod service;
pub mod template;
pub mod testing;
pub mod util;

/// Re-export of common types and traits
pub mod prelude {
    pub use crate::error::{Error, Result};
    pub use anyhow;
    pub use tracing::{debug, error, info, trace, warn};
}

use crate::service::format::FormatService;
use crate::config::Config;
use crate::service::repository::RepositoryService;
use crate::service::git::GitService;
use crate::service::cache::CacheService;
use crate::service::database::DatabaseService;
use crate::service::auth::AuthService;
use crate::service::content::ContentService;
use crate::service::observability::ObservabilityService;

use std::sync::Arc;
use std::sync::RwLock;

/// Application state shared across components
pub struct AppState {
    /// Configuration
    pub config: Config,

    /// Repository service
    pub repository_service: Arc<RepositoryService>,

    /// Git service
    pub git_service: Arc<GitService>,

    /// Cache service
    pub cache_service: Arc<CacheService>,

    /// Database service
    pub db_service: Arc<DatabaseService>,

    /// Authentication service
    pub auth_service: Arc<AuthService>,

    /// Repository content service
    pub content_service: Arc<ContentService>,

    /// Observability service
    pub observability_service: Arc<ObservabilityService>,

    /// Format service with accessibility features
    pub format_service: Arc<RwLock<FormatService>>,
}
