//! Configuration handling for the Art application

use crate::error::{Error, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::fs;
use std::net::SocketAddr;

/// Main configuration structure for the Art application
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Server configuration
    pub server: ServerConfig,

    /// Repository configuration
    pub repository: RepositoryConfig,

    /// Database configuration
    pub database: DatabaseConfig,

    /// Authentication and authorization configuration
    pub auth: AuthConfig,

    /// UI configuration
    pub ui: UiConfig,

    /// Cache configuration
    pub cache: CacheConfig,

    /// Observability configuration
    pub observability: ObservabilityConfig,

    /// Git HTTP protocol configuration
    pub git_http: Option<GitHttpConfig>,

    /// Feature flags
    #[serde(default)]
    pub features: FeaturesConfig,
}

/// Server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// HTTP server port
    pub port: u16,

    /// Server bind address
    #[serde(default = "default_bind_address")]
    pub bind_address: String,

    /// Base URL for the application
    #[serde(default = "default_base_url")]
    pub base_url: String,

    /// Number of worker threads (0 = default to number of CPU cores)
    pub threads: usize,
}

/// Git HTTP protocol configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GitHttpConfig {
    /// Whether Git HTTP protocol is enabled
    #[serde(default = "default_false")]
    pub is_enabled: bool,

    /// Whether to allow push operations (write)
    #[serde(default = "default_true")]
    pub enable_push: bool,

    /// Whether to allow fetch operations (read)
    #[serde(default = "default_true")]
    pub enable_fetch: bool,

    /// Whether to enable Git LFS support
    #[serde(default = "default_false")]
    pub enable_lfs: bool,

    /// Maximum push size in bytes (None for unlimited)
    pub max_push_size: Option<usize>,

    /// Whether to verify commit signatures
    #[serde(default = "default_false")]
    pub verify_commit_signatures: bool,

    /// Path prefix for Git HTTP endpoints
    pub path_prefix: Option<String>,

    /// Whether to automatically run git gc after push
    #[serde(default = "default_true")]
    pub auto_gc: bool,

    /// Timeout for Git operations in seconds
    #[serde(default = "default_git_timeout")]
    pub operation_timeout: u64,
}

/// Repository configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryConfig {
    /// Directory containing Git repositories
    pub repo_dir: PathBuf,

    /// Maximum size of repository cache (in bytes)
    pub max_cache_size: usize,

    /// Enable repository maintenance tasks
    pub enable_maintenance: bool,

    /// Interval for maintenance tasks (in seconds)
    pub maintenance_interval: u64,

    /// Verify commit signatures
    #[serde(default = "default_false")]
    pub verify_commit_signatures: bool,

    /// Custom GPG home directory (None for default)
    pub gpg_homedir: Option<PathBuf>,

    /// List of trusted GPG key IDs
    #[serde(default)]
    pub trusted_gpg_keys: Vec<String>,

    /// List of trusted SSH key IDs
    #[serde(default)]
    pub trusted_ssh_keys: Vec<String>,
}

/// Database configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    /// Path to the SQLite database file
    pub path: PathBuf,

    /// Maximum number of connections in the pool
    pub max_connections: u32,

    /// Connection timeout in seconds
    pub connection_timeout: u64,
}

/// Cache configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// Maximum size of the memory cache (in bytes)
    pub max_size: usize,

    /// Time-to-live for cache entries (in seconds, 0 = no expiry)
    pub ttl: u64,

    /// Name of the cache (used for metrics)
    pub name: Option<String>,

    /// Enable detailed cache analytics
    pub enable_analytics: bool,

    /// Analytics sampling interval in seconds (default = 60)
    pub analytics_sampling_interval_secs: Option<u64>,

    /// Maximum number of historical samples to keep (default = 60)
    pub analytics_max_history_samples: Option<usize>,

    /// Whether to track per-key metrics (more detailed but higher overhead)
    pub analytics_track_per_key_metrics: Option<bool>,
}

/// Observability configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObservabilityConfig {
    /// Enable Prometheus metrics
    pub enable_metrics: bool,

    /// Log level (trace, debug, info, warn, error)
    pub log_level: String,
}

/// Feature flags for enabling/disabling functionality
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeaturesConfig {
    /// Enable user management features
    #[serde(default = "default_true")]
    pub user_management: bool,

    /// Enable repository maintenance features
    #[serde(default = "default_true")]
    pub repository_maintenance: bool,

    /// Enable Git HTTP protocol features
    #[serde(default = "default_true")]
    pub git_http: bool,
}

/// Authentication and authorization configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthConfig {
    /// Authentication providers (e.g., local, ldap, oauth)
    #[serde(default)]
    pub providers: Vec<String>,

    /// Session timeout in minutes
    #[serde(default = "default_session_timeout")]
    pub session_timeout: u64,

    /// Default admin user to create if no users exist
    pub default_admin: Option<DefaultAdminConfig>,

    /// Authentication rate limiting settings
    #[serde(default)]
    pub rate_limit: RateLimitConfig,
}

/// Default admin user configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DefaultAdminConfig {
    /// Admin username
    pub username: String,

    /// Admin email
    pub email: String,

    /// Admin password
    pub password: String,
}

/// Authentication rate limiting configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    /// Max login attempts per IP address
    #[serde(default = "default_max_login_attempts")]
    pub max_login_attempts: u32,

    /// Lockout time in minutes after reaching max attempts
    #[serde(default = "default_lockout_time")]
    pub lockout_time: u64,
}

/// Default value for Git operation timeout (300 seconds)
fn default_git_timeout() -> u64 {
    300
}

/// Default true value
fn default_true() -> bool {
    true
}

/// Default false value
fn default_false() -> bool {
    false
}

/// Default bind address
fn default_bind_address() -> String {
    "127.0.0.1".to_string()
}

/// Default base URL
fn default_base_url() -> String {
    "http://localhost:3000".to_string()
}

/// Default session timeout in minutes (24 hours)
fn default_session_timeout() -> u64 {
    24 * 60
}

/// Default max login attempts
fn default_max_login_attempts() -> u32 {
    5
}

/// Default lockout time in minutes
fn default_lockout_time() -> u64 {
    15
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig {
                bind_address: "127.0.0.1".to_string(),
                port: 3000,
                threads: 0,
                base_url: "http://localhost:3000".to_string(),
            },
            repository: RepositoryConfig {
                repo_dir: PathBuf::from("./repositories"),
                max_cache_size: 100 * 1024 * 1024, // 100MB
                enable_maintenance: true,
                maintenance_interval: 3600, // 1 hour
                verify_commit_signatures: false,
                gpg_homedir: None,
                trusted_gpg_keys: Vec::new(),
                trusted_ssh_keys: Vec::new(),
            },
            database: DatabaseConfig {
                path: PathBuf::from("./art.db"),
                max_connections: 10,
                connection_timeout: 30,
            },
            cache: CacheConfig {
                max_size: 50 * 1024 * 1024, // 50MB
                ttl: 300, // 5 minutes
                name: None,
                enable_analytics: false,
                analytics_sampling_interval_secs: None,
                analytics_max_history_samples: None,
                analytics_track_per_key_metrics: None,
            },
            observability: ObservabilityConfig {
                enable_metrics: true,
                log_level: "info".to_string(),
            },
            git_http: None,
            auth: AuthConfig {
                providers: vec!["local".to_string()],
                session_timeout: default_session_timeout(),
                default_admin: None,
                rate_limit: Default::default(),
            },
            features: FeaturesConfig {
                user_management: true,
                repository_maintenance: true,
                git_http: true,
            },
        }
    }
}

impl Config {
    /// Load configuration from a file
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let contents = fs::read_to_string(path)
            .map_err(|e| Error::Config(format!("Failed to read config file: {}", e)))?;

        let config: Config = serde_json::from_str(&contents)
            .map_err(|e| Error::Config(format!("Failed to parse config file: {}", e)))?;

        Ok(config)
    }

    /// Save configuration to a file
    pub fn to_file<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let contents = serde_json::to_string_pretty(self)
            .map_err(|e| Error::Config(format!("Failed to serialize config: {}", e)))?;

        fs::write(path, contents)
            .map_err(|e| Error::Config(format!("Failed to write config file: {}", e)))?;

        Ok(())
    }

    /// Get the socket address for the server
    pub fn socket_addr(&self) -> Result<SocketAddr> {
        let addr = format!("{}:{}", self.server.bind_address, self.server.port);
        addr.parse()
            .map_err(|e| Error::Config(format!("Invalid socket address: {}", e)))
    }
}
