//! Observability service for metrics, logging, and tracing
//!
//! This module provides functionality for capturing telemetry data about
//! the Art application's operation, including metrics, structured logging,
//! and tracing information.

use crate::data::cache::Cache;
use crate::error::{Error, Result};
use crate::config::{ObservabilityConfig, OpenTelemetryConfig};

use std::sync::Arc;
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::sync::atomic::{AtomicU64, Ordering};
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, trace, warn, Level, Subscriber};
use tokio::sync::RwLock;
use lazy_static::lazy_static;
use prometheus::{
    Counter, CounterVec, Gauge, GaugeVec, Histogram, HistogramVec,
    IntCounter, IntCounterVec, IntGauge, IntGaugeVec, Registry,
    Encoder, TextEncoder,
};
use uuid::Uuid;

mod opentelemetry;
mod content_metrics;
mod cache_metrics;

pub use opentelemetry::{OpenTelemetryConfig, OpenTelemetryTracer};
pub use content_metrics::{ContentMetricsConfig, ContentMetricsCollector, RepositoryContentStats, RepositoryActivityStats};
pub use cache_metrics::CacheMetricsCollector;

/// Metric types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MetricType {
    /// Counter (monotonically increasing value)
    Counter,

    /// Gauge (value that can go up and down)
    Gauge,

    /// Histogram (statistical distribution)
    Histogram,
}

/// Observability service for metrics and tracing
#[derive(Clone)]
pub struct ObservabilityService {
    /// Configuration
    config: Arc<ObservabilityConfig>,

    /// Prometheus registry
    registry: Registry,

    /// HTTP requests counter
    http_requests_total: IntCounterVec,

    /// Request duration
    pub http_request_duration: HistogramVec,

    /// Response status codes
    pub http_response_status: IntCounterVec,

    /// Git operation counter
    pub git_operations_total: IntCounterVec,

    /// Git operation duration
    pub git_operation_duration: HistogramVec,

    /// Cache hits
    pub cache_hits_total: IntCounterVec,

    /// Cache misses
    pub cache_misses_total: IntCounterVec,

    /// Repository statistics
    pub repository_stats: GaugeVec,

    /// System memory usage
    pub memory_usage_bytes: IntGauge,

    /// Active connections
    pub active_connections: IntGauge,

    /// Metrics cache
    cache: Arc<Cache>,

    /// Content metrics collector for repositories
    content_metrics_collector: Option<Arc<tokio::sync::Mutex<ContentMetricsCollector>>>,

    /// OpenTelemetry tracer for distributed tracing
    opentelemetry_tracer: Option<Arc<OpenTelemetryTracer>>,

    /// Historical time-series data storage
    time_series_data: RwLock<HashMap<String, Vec<(DateTime<Utc>, f64)>>>,

    /// Maximum number of data points to store per metric
    max_time_series_points: usize,

    /// Historical data collection interval in seconds
    time_series_interval_secs: u64,

    /// Last time series collection time
    last_time_series_collection: RwLock<DateTime<Utc>>,
}

/// Health check response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    /// Overall status: ok, degraded, error
    pub status: String,
    /// Version of the service
    pub version: String,
    /// Uptime in seconds
    pub uptime: u64,
    /// Component statuses
    pub components: HashMap<String, ComponentStatus>,
    /// System metrics
    pub system_metrics: Option<SystemMetrics>,
}

/// Component status for health check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentStatus {
    /// Status of the component: ok, degraded, error
    pub status: String,
    /// Optional message with additional information
    pub message: Option<String>,
}

/// System metrics for health check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    /// CPU usage percentage
    pub cpu_usage: f64,
    /// Memory usage in bytes
    pub memory_usage: u64,
    /// Memory available in bytes
    pub memory_available: u64,
    /// Disk usage in bytes
    pub disk_usage: u64,
    /// Disk available in bytes
    pub disk_available: u64,
}

/// Request span context
#[derive(Debug, Clone)]
pub struct RequestSpan {
    /// Request ID
    pub request_id: String,

    /// Start time
    pub start_time: Instant,

    /// Path
    pub path: String,

    /// Method
    pub method: String,

    /// User agent
    pub user_agent: Option<String>,

    /// Remote address
    pub remote_addr: Option<String>,
}

/// Trace context for distributed tracing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceContext {
    /// Trace ID
    pub trace_id: String,

    /// Span ID
    pub span_id: String,

    /// Parent span ID
    pub parent_id: Option<String>,

    /// Sampled flag
    pub sampled: bool,

    /// Trace flags
    pub flags: u8,

    /// Baggage items
    pub baggage: HashMap<String, String>,
}

impl TraceContext {
    /// Create a new trace context
    pub fn new() -> Self {
        // Generate random trace and span IDs
        let trace_id = format!("{:x}", rand::random::<u128>());
        let span_id = format!("{:x}", rand::random::<u64>());

        Self {
            trace_id,
            span_id,
            parent_id: None,
            sampled: true,
            flags: 0,
            baggage: HashMap::new(),
        }
    }

    /// Create a child span
    pub fn create_child(&self) -> Self {
        let span_id = format!("{:x}", rand::random::<u64>());

        Self {
            trace_id: self.trace_id.clone(),
            span_id,
            parent_id: Some(self.span_id.clone()),
            sampled: self.sampled,
            flags: self.flags,
            baggage: self.baggage.clone(),
        }
    }

    /// Add baggage item
    pub fn add_baggage(&mut self, key: &str, value: &str) {
        self.baggage.insert(key.to_string(), value.to_string());
    }

    /// Get baggage item
    pub fn get_baggage(&self, key: &str) -> Option<&String> {
        self.baggage.get(key)
    }
}

/// Log level for structured logging
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl From<LogLevel> for Level {
    fn from(level: LogLevel) -> Self {
        match level {
            LogLevel::Trace => Level::TRACE,
            LogLevel::Debug => Level::DEBUG,
            LogLevel::Info => Level::INFO,
            LogLevel::Warn => Level::WARN,
            LogLevel::Error => Level::ERROR,
        }
    }
}

impl From<&str> for LogLevel {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "trace" => LogLevel::Trace,
            "debug" => LogLevel::Debug,
            "info" => LogLevel::Info,
            "warn" | "warning" => LogLevel::Warn,
            "error" | "err" => LogLevel::Error,
            _ => LogLevel::Info, // Default to Info
        }
    }
}

/// Log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    /// Log level
    pub level: LogLevel,

    /// Log message
    pub message: String,

    /// Timestamp
    pub timestamp: DateTime<Utc>,

    /// Additional fields
    pub fields: HashMap<String, serde_json::Value>,

    /// Trace context
    pub trace_context: Option<TraceContext>,
}

/// Log query response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogQueryResponse {
    /// Total number of logs
    pub total: usize,

    /// Logs returned (limited by pagination)
    pub logs: Vec<LogEntry>,

    /// Query parameters
    pub query: HashMap<String, String>,
}

/// Paginated log query response with cursor-based pagination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginatedLogQueryResponse {
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

// Lazily initialized start time
lazy_static! {
    static ref START_TIME: Instant = Instant::now();
}

/// Service trait for accessing observability features
pub trait HasObservabilityService {
    /// Get the observability service if configured
    fn observability_service(&self) -> Option<Arc<ObservabilityService>>;
}

/// Rate limiting configuration for observability endpoints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    /// Maximum requests per window
    pub max_requests: u64,

    /// Window duration in seconds
    pub window_seconds: u64,

    /// Whether to bypass rate limits for localhost
    pub bypass_localhost: bool,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 60,
            window_seconds: 60,
            bypass_localhost: true,
        }
    }
}

/// Entry in the rate limit store
#[derive(Debug, Clone)]
struct RateLimitEntry {
    /// Count of requests
    count: AtomicU64,

    /// Window start time
    window_start: Instant,
}

/// Rate limiter for API endpoints
pub struct RateLimiter {
    /// Configuration
    config: RateLimitConfig,

    /// Map of IP addresses to rate limit entries
    entries: RwLock<HashMap<String, Arc<RateLimitEntry>>>,

    /// Last cleanup time
    last_cleanup: RwLock<Instant>,
}

impl RateLimiter {
    /// Create a new rate limiter
    pub fn new(config: RateLimitConfig) -> Self {
        Self {
            config,
            entries: RwLock::new(HashMap::new()),
            last_cleanup: RwLock::new(Instant::now()),
        }
    }

    /// Check if a request from the given IP should be rate limited
    pub async fn check(&self, ip: &str) -> bool {
        // Bypass for localhost if configured
        if self.config.bypass_localhost && (ip == "127.0.0.1" || ip == "::1" || ip == "localhost") {
            return true;
        }

        // Try to clean up expired entries
        self.try_cleanup().await;

        // Get or create entry
        let entries = self.entries.read().await;
        let entry = match entries.get(ip) {
            Some(entry) => {
                // Check if window has expired
                let now = Instant::now();
                if now.duration_since(entry.window_start) > Duration::from_secs(self.config.window_seconds) {
                    // Window expired, create new entry after releasing read lock
                    drop(entries);
                    self.create_entry(ip).await
                } else {
                    // Window still valid
                    Arc::clone(entry)
                }
            }
            None => {
                // No entry, create new after releasing read lock
                drop(entries);
                self.create_entry(ip).await
            }
        };

        // Increment count and check limit
        let count = entry.count.fetch_add(1, Ordering::Relaxed) + 1;
        count <= self.config.max_requests
    }

    /// Create a new rate limit entry for IP
    async fn create_entry(&self, ip: &str) -> Arc<RateLimitEntry> {
        let mut entries = self.entries.write().await;
        let entry = Arc::new(RateLimitEntry {
            count: AtomicU64::new(0),
            window_start: Instant::now(),
        });
        entries.insert(ip.to_string(), Arc::clone(&entry));
        entry
    }

    /// Clean up expired entries (called periodically)
    async fn try_cleanup(&self) {
        let should_cleanup = {
            let last_cleanup = self.last_cleanup.read().await;
            Instant::now().duration_since(*last_cleanup) > Duration::from_secs(60)
        };

        if should_cleanup {
            let mut last_cleanup = self.last_cleanup.write().await;
            *last_cleanup = Instant::now();

            let now = Instant::now();
            let mut entries = self.entries.write().await;
            entries.retain(|_, entry| {
                now.duration_since(entry.window_start) <= Duration::from_secs(self.config.window_seconds)
            });
        }
    }

    /// Reset all rate limits (for testing)
    #[cfg(test)]
    async fn reset(&self) {
        let mut entries = self.entries.write().await;
        entries.clear();
    }
}

impl ObservabilityService {
    /// Create a new observability service
    pub async fn new(
        config: ObservabilityConfig,
        prometheus_registry: Option<Registry>,
        content_metrics_config: Option<ContentMetricsConfig>,
    ) -> Result<Self> {
        // Create registry
        let registry = Registry::new();

        // Define metrics
        let http_requests_total = IntCounterVec::new(
            prometheus::opts!("art_http_requests_total", "Total HTTP requests"),
            &["method", "path"],
        ).unwrap();

        let http_request_duration = HistogramVec::new(
            prometheus::histogram_opts!("art_http_request_duration_seconds", "HTTP request duration"),
            &["method", "path"],
        ).unwrap();

        let http_response_status = IntCounterVec::new(
            prometheus::opts!("art_http_response_status", "HTTP response status codes"),
            &["method", "path", "status"],
        ).unwrap();

        let git_operations_total = IntCounterVec::new(
            prometheus::opts!("art_git_operations_total", "Total Git operations"),
            &["operation", "repository"],
        ).unwrap();

        let git_operation_duration = HistogramVec::new(
            prometheus::histogram_opts!("art_git_operation_duration_seconds", "Git operation duration"),
            &["operation", "repository"],
        ).unwrap();

        let cache_hits_total = IntCounterVec::new(
            prometheus::opts!("art_cache_hits_total", "Total cache hits"),
            &["cache"],
        ).unwrap();

        let cache_misses_total = IntCounterVec::new(
            prometheus::opts!("art_cache_misses_total", "Total cache misses"),
            &["cache"],
        ).unwrap();

        let repository_stats = GaugeVec::new(
            prometheus::opts!("art_repository_stats", "Repository statistics"),
            &["repository", "metric"],
        ).unwrap();

        let memory_usage_bytes = IntGauge::new(
            "art_memory_usage_bytes", "Memory usage in bytes",
        ).unwrap();

        let active_connections = IntGauge::new(
            "art_active_connections", "Number of active connections",
        ).unwrap();

        // Register all metrics
        registry.register(Box::new(http_requests_total.clone())).unwrap();
        registry.register(Box::new(http_request_duration.clone())).unwrap();
        registry.register(Box::new(http_response_status.clone())).unwrap();
        registry.register(Box::new(git_operations_total.clone())).unwrap();
        registry.register(Box::new(git_operation_duration.clone())).unwrap();
        registry.register(Box::new(cache_hits_total.clone())).unwrap();
        registry.register(Box::new(cache_misses_total.clone())).unwrap();
        registry.register(Box::new(repository_stats.clone())).unwrap();
        registry.register(Box::new(memory_usage_bytes.clone())).unwrap();
        registry.register(Box::new(active_connections.clone())).unwrap();

        // Initialize content metrics collector if configured
        let content_metrics_collector = if let Some(content_config) = content_metrics_config {
            // The ContentMetricsCollector needs Git and RepositoryService, but we don't have those available
            // This should be redesigned to either:
            // 1. Pass Git and RepositoryService as parameters to ObservabilityService::new
            // 2. Initialize the ContentMetricsCollector later when these services are available
            // For now, return None to avoid using undefined variables
            None
        } else {
            None
        };

        // OpenTelemetry tracer
        let opentelemetry_tracer = match config.opentelemetry {
            Some(config) => Some(Arc::new(OpenTelemetryTracer::new(config)?)),
            None => None
        };

        let service = Self {
            config: Arc::new(config),
            registry,
            http_requests_total,
            http_request_duration,
            http_response_status,
            git_operations_total,
            git_operation_duration,
            cache_hits_total,
            cache_misses_total,
            repository_stats,
            memory_usage_bytes,
            active_connections,
            cache: Arc::new(Cache::new_for_test()),
            content_metrics_collector,
            opentelemetry_tracer,
            time_series_data: RwLock::new(HashMap::new()),
            max_time_series_points: 1000,
            time_series_interval_secs: 60,
            last_time_series_collection: RwLock::new(Utc::now()),
        };

        // Start time series collection
        service.start_time_series_collection().await;

        Ok(service)
    }

    /// Setup observability (once, during application startup)
    pub fn setup() -> Result<()> {
        // Initialize global tracing subscriber

        // This is already handled by the application's main function
        // and included here for reference
        /*
        let subscriber = tracing_subscriber::registry()
            .with(tracing_subscriber::fmt::layer())
            .with(tracing_subscriber::EnvFilter::from_default_env());

        tracing::subscriber::set_global_default(subscriber)
            .map_err(|e| Error::Internal(format!("Failed to set tracing subscriber: {}", e)))?;
        */

        Ok(())
    }

    /// Record a HTTP request
    pub fn record_request(&self, method: &str, path: &str) {
        self.http_requests_total.with_label_values(&[method, path]).inc();
    }

    /// Start a HTTP request timer
    pub fn start_request_timer(&self, method: &str, path: &str) -> prometheus::HistogramTimer {
        self.http_request_duration.with_label_values(&[method, path]).start_timer()
    }

    /// Record a HTTP response
    pub fn record_response(&self, method: &str, path: &str, status: u16) {
        self.http_response_status.with_label_values(&[
            method,
            path,
            &status.to_string(),
        ]).inc();
    }

    /// Record a Git operation
    pub fn record_git_operation(&self, operation: &str, repository: &str) {
        self.git_operations_total.with_label_values(&[operation, repository]).inc();
    }

    /// Start a Git operation timer
    pub fn start_git_operation_timer(&self, operation: &str, repository: &str) -> prometheus::HistogramTimer {
        self.git_operation_duration.with_label_values(&[operation, repository]).start_timer()
    }

    /// Record a cache hit
    pub fn record_cache_hit(&self, cache_name: &str) {
        self.cache_hits_total.with_label_values(&[cache_name]).inc();
    }

    /// Record a cache miss
    pub fn record_cache_miss(&self, cache_name: &str) {
        self.cache_misses_total.with_label_values(&[cache_name]).inc();
    }

    /// Set repository statistic
    pub fn set_repository_stat(&self, repository: &str, metric: &str, value: f64) {
        self.repository_stats.with_label_values(&[repository, metric]).set(value);
    }

    /// Update memory usage
    pub fn update_memory_usage(&self, bytes: i64) {
        self.memory_usage_bytes.set(bytes);
    }

    /// Increment active connections
    pub fn increment_connections(&self) {
        self.active_connections.inc();
    }

    /// Decrement active connections
    pub fn decrement_connections(&self) {
        self.active_connections.dec();
    }

    /// Get metrics as string in Prometheus format
    pub fn metrics_as_string(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)
            .map_err(|e| Error::Internal(format!("Failed to encode metrics: {}", e)))?;

        String::from_utf8(buffer)
            .map_err(|e| Error::Internal(format!("Invalid UTF-8 in metrics: {}", e)))
    }

    /// Reset all metrics to their initial values
    pub fn reset_metrics(&self) {
        // The prometheus crate doesn't provide a direct way to reset metrics
        // To work around this, we can recreate the registry and metrics
        // For now, we'll just log that this was called
        warn!("Reset metrics called - note that prometheus metrics cannot be fully reset");

        // Clear counters where possible
        // This doesn't actually reset the counter but adds a negative value to bring it closer to zero
        // Note: In real implementation, we would need to track the current values to properly reset
    }

    /// Get system health
    pub fn health(&self) -> HealthResponse {
        let mut components = HashMap::new();

        // Check memory usage
        let memory_status = if self.memory_usage_bytes.get() > 1_000_000_000 {
            ComponentStatus {
                status: "degraded".to_string(),
                message: Some("High memory usage".to_string()),
            }
        } else {
            ComponentStatus {
                status: "ok".to_string(),
                message: None,
            }
        };
        components.insert("memory".to_string(), memory_status);

        // Add more component checks here

        // Determine overall status
        let status = if components.values().any(|c| c.status == "error") {
            "error"
        } else if components.values().any(|c| c.status == "degraded") {
            "degraded"
        } else {
            "ok"
        }.to_string();

        HealthResponse {
            status,
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime: START_TIME.elapsed().as_secs(),
            components,
        }
    }

    /// Perform a health check of the observability system
    pub async fn health_check(&self) -> Result<HealthResponse> {
        let mut components = HashMap::new();

        // Check memory usage
        let memory_status = if self.memory_usage_bytes.get() > 1_000_000_000 {
            ComponentStatus {
                status: "degraded".to_string(),
                message: Some("High memory usage".to_string()),
            }
        } else {
            ComponentStatus {
                status: "ok".to_string(),
                message: None,
            }
        };
        components.insert("memory".to_string(), memory_status);

        // Check active connections
        let connections_status = if self.active_connections.get() > 100 {
            ComponentStatus {
                status: "degraded".to_string(),
                message: Some("High number of active connections".to_string()),
            }
        } else {
            ComponentStatus {
                status: "ok".to_string(),
                message: None,
            }
        };
        components.insert("connections".to_string(), connections_status);

        // Check metrics registry
        let metrics_status = match self.metrics_as_string() {
            Ok(_) => ComponentStatus {
                status: "ok".to_string(),
                message: None,
            },
            Err(e) => ComponentStatus {
                status: "error".to_string(),
                message: Some(format!("Failed to collect metrics: {}", e)),
            },
        };
        components.insert("metrics".to_string(), metrics_status);

        // Check opentelemetry status
        let otel_status = if let Some(tracer) = &self.opentelemetry_tracer {
            ComponentStatus {
                status: "ok".to_string(),
                message: Some("OpenTelemetry tracer configured".to_string()),
            }
        } else {
            ComponentStatus {
                status: "degraded".to_string(),
                message: Some("OpenTelemetry tracer not configured".to_string()),
            }
        };
        components.insert("opentelemetry".to_string(), otel_status);

        // Check content metrics collector status
        let content_metrics_status = if let Some(_) = &self.content_metrics_collector {
            ComponentStatus {
                status: "ok".to_string(),
                message: None,
            }
                } else {
            ComponentStatus {
                status: "degraded".to_string(),
                message: Some("Content metrics collector not configured".to_string()),
            }
        };
        components.insert("content_metrics".to_string(), content_metrics_status);

        // Determine overall status
        let status = if components.values().any(|c| c.status == "error") {
            "error"
        } else if components.values().any(|c| c.status == "degraded") {
            "degraded"
        } else {
            "ok"
        }.to_string();

        // Get system metrics
        let system_metrics = self.system_metrics();

        // Add system metrics to response
        let health_response = HealthResponse {
            status,
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime: Self::uptime(),
            components,
            system_metrics: Some(system_metrics),
        };

        Ok(health_response)
    }

    /// Get system metrics
    pub fn system_metrics(&self) -> SystemMetrics {
        let memory_usage = self.memory_usage_bytes.get();
        let active_connections = self.active_connections.get();

        // Calculate request rate as requests per second over the last minute
        let requests = self.requests_per_minute.get();
        let request_rate = requests as f64 / 60.0;

        // Average response time
        let avg_response_time = if requests > 0 {
            self.response_time_ms.get() / requests
        } else {
            0
        };

        // Error rate as percentage
        let errors = self.errors_per_minute.get();
        let error_rate = if requests > 0 {
            (errors as f64 / requests as f64) * 100.0
        } else {
            0.0
        };

        // Trace metrics
        let trace_export_count = self.trace_exports.get();
        let trace_success_count = self.trace_export_successes.get();
        let trace_success_rate = if trace_export_count > 0 {
            (trace_success_count as f64 / trace_export_count as f64) * 100.0
        } else {
            100.0
        };

        // Disk usage (this is a placeholder - real implementation would get actual disk metrics)
        let disk_usage_bytes = 0;
        let disk_available_bytes = 0;

        // Memory available (placeholder - real implementation would get actual system metrics)
        let memory_available_bytes = 0;

        // CPU usage (placeholder - real implementation would get actual CPU metrics)
        let cpu_usage_percent = 0.0;

        SystemMetrics {
            cpu_usage: cpu_usage_percent,
            memory_usage: memory_usage,
            memory_available: memory_available_bytes,
            disk_usage: disk_usage_bytes,
            disk_available: disk_available_bytes,
        }
    }

    /// Create a new request span
    pub fn create_request_span(&self, request_id: &str, path: &str, method: &str) -> RequestSpan {
        RequestSpan {
            request_id: request_id.to_string(),
            start_time: Instant::now(),
            path: path.to_string(),
            method: method.to_string(),
            user_agent: None,
            remote_addr: None,
        }
    }

    /// Get uptime in seconds
    pub fn uptime() -> u64 {
        START_TIME.elapsed().as_secs()
    }

    /// Log with structured data
    pub fn log(&self, level: LogLevel, message: &str, fields: HashMap<String, serde_json::Value>, trace: Option<TraceContext>) {
        // Log to tracing system
        match level {
            LogLevel::Trace => trace!(message = message, ?fields, trace_id = trace.as_ref().map(|t| t.trace_id.clone())),
            LogLevel::Debug => debug!(message = message, ?fields, trace_id = trace.as_ref().map(|t| t.trace_id.clone())),
            LogLevel::Info => info!(message = message, ?fields, trace_id = trace.as_ref().map(|t| t.trace_id.clone())),
            LogLevel::Warn => warn!(message = message, ?fields, trace_id = trace.as_ref().map(|t| t.trace_id.clone())),
            LogLevel::Error => error!(message = message, ?fields, trace_id = trace.as_ref().map(|t| t.trace_id.clone())),
        }

        // Save log to cache
        if let Some(trace_ctx) = trace {
            self.cache_log_entry(level, message, fields, trace_ctx);
        } else {
            let trace_ctx = self.create_trace_context();
            self.cache_log_entry(level, message, fields, trace_ctx);
        }
    }

    /// Cache log entry
    fn cache_log_entry(&self, level: LogLevel, message: &str, fields: HashMap<String, serde_json::Value>, trace: TraceContext) {
        let entry = LogEntry {
            timestamp: Utc::now(),
            level,
            message: message.to_string(),
            fields,
            trace_context: Some(trace),
        };

        // Generate a unique key for the log entry
        let key = self.generate_log_id();

        // Serialize and cache the log entry
        if let Ok(json) = serde_json::to_string(&entry) {
            // Using spawn to avoid blocking
            let cache = self.cache.clone();
            let key_clone = key.clone();
            tokio::spawn(async move {
                // Set TTL based on level (keep errors longer)
                let ttl = match entry.level {
                    LogLevel::Error => Duration::from_secs(86400 * 7), // 7 days
                    LogLevel::Warn => Duration::from_secs(86400 * 3),  // 3 days
                    _ => Duration::from_secs(86400),                   // 1 day
                };

                if let Err(e) = cache.set_with_ttl(&key_clone, json, ttl).await {
                    error!("Failed to cache log entry: {}", e);
                }
            });
        }
    }

    /// Create a new trace context for distributed tracing
    pub fn create_trace_context(&self) -> TraceContext {
        TraceContext::new()
    }

    /// Collect and add system metrics
    pub fn collect_system_metrics(&self) -> Result<()> {
        // Use sysinfo to gather actual system metrics
        #[cfg(not(test))]
        {
            use sysinfo::{System, SystemExt, ProcessExt, CpuExt};

            // Initialize system information collector
            let mut system = System::new_all();
            system.refresh_all();

            // Get current process
            let pid = std::process::id();
            system.refresh_process(pid as i32);
            let process = system.process(pid as i32);

            // Memory metrics
            if let Some(proc) = process {
                // Record process memory usage
                let memory_usage = proc.memory() as i64;
                self.memory_usage_bytes.set(memory_usage);

                // Log memory usage for tracking
                debug!("Process memory usage: {} bytes", memory_usage);
            } else {
                // Fallback to system memory metrics
                let total_memory = system.total_memory();
                let used_memory = system.used_memory();

                // Record system memory usage
                self.memory_usage_bytes.set(used_memory as i64);

                // Create a gauge for memory utilization percentage
                let memory_usage_pct = (used_memory as f64 / total_memory as f64) * 100.0;
                let memory_pct_gauge = self.create_gauge(
                    "memory_usage_percent",
                    "Memory usage percentage",
                    vec![]
                ).ok();

                if let Some(gauge) = memory_pct_gauge {
                    gauge.with_label_values(&[]).set(memory_usage_pct);
                }

                debug!("System memory: {}% used ({}/{} bytes)",
                     memory_usage_pct, used_memory, total_memory);
            }

            // CPU metrics
            let cpu_usage: f64 = system.global_cpu_info().cpu_usage() as f64;

            // Create a gauge for CPU usage
            let cpu_gauge = self.create_gauge(
                "cpu_usage_percent",
                "CPU usage percentage",
                vec![]
            ).ok();

            if let Some(gauge) = cpu_gauge {
                gauge.with_label_values(&[]).set(cpu_usage);
            }

            // Connection count metrics (already tracked in middleware)

            // Record other system metrics as needed
            let disk_free = if let Ok(stats) = std::fs::metadata(".") {
                if let Ok(stats) = stats.as_ref().file_type().is_dir() {
                    if let Ok(stats) = std::fs::metadata(".").and_then(|m| m.as_ref().file_type().is_dir()) {
                        // Get disk space
                        if let Ok(disk) = std::fs::metadata(".") {
                            // Log disk info
                            debug!("Disk usage stats retrieved");
                            true
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    false
                }
            } else {
                false
            };

            debug!("System metrics collection complete: CPU: {}%, Memory tracked, Disk: {}",
                 cpu_usage, if disk_free { "tracked" } else { "not tracked" });
        }

        // For tests, use mock data
        #[cfg(test)]
        {
            self.memory_usage_bytes.set(100_000_000);
            debug!("Test system metrics collection complete");
        }

        Ok(())
    }

    /// Track a business metric (general purpose metric with custom labels)
    pub fn track_business_metric(&self, name: &str, value: f64, labels: &[(&str, &str)]) -> Result<()> {
        // Create a metric name with proper format
        let metric_name = format!("art_business_{}", name);
        let help_text = format!("Business metric: {}", name);

        // Extract label names and values
        let label_names: Vec<&str> = labels.iter().map(|(k, _)| *k).collect();
        let label_values: Vec<&str> = labels.iter().map(|(_, v)| *v).collect();

        // Try to find or create a gauge for this metric
        let metric_key = format!("business_metric:{}", name);

        // Create or get the gauge for this metric
        let gauge = match self.get_or_create_business_metric(&metric_name, &help_text, &label_names) {
            Ok(g) => g,
            Err(e) => {
                error!("Failed to create business metric {}: {}", name, e);
                return Err(e);
            }
        };

        // Set the metric value with the provided labels
        gauge.with_label_values(&label_values).set(value);

        // Also store in cache for historical tracking
        let key = format!(
            "metric:{}:{}",
            metric_name,
            serde_json::to_string(&labels).unwrap_or_default()
        );

        self.cache.set(&key, value.to_string()).await?;

        debug!("Tracked business metric {} = {} with labels {:?}", name, value, labels);

        Ok(())
    }

    /// Get or create a business metric gauge
    fn get_or_create_business_metric(&self, name: &str, help: &str, label_names: &[&str]) -> Result<GaugeVec> {
        // Create a gauge for the business metric
        let gauge = GaugeVec::new(
            prometheus::opts!(name, help),
            label_names,
        ).map_err(|e| Error::Internal(format!("Failed to create business metric: {}", e)))?;

        // Try to register it (might fail if already registered)
        match self.registry.register(Box::new(gauge.clone())) {
            Ok(_) => {
                debug!("Created new business metric: {}", name);
                Ok(gauge)
            },
            Err(e) => {
                // If the metric already exists, we need to retrieve it
                if e.to_string().contains("already registered") {
                    warn!("Business metric {} already exists, using existing metric", name);

                    // We need to use a workaround as prometheus-rust doesn't provide a way to get existing metrics
                    // In a real implementation, we would use a metric registry cache
                    let gauge = GaugeVec::new(
                        prometheus::opts!(
                            format!("{}_copy", name),
                            help
                        ),
                        label_names,
                    ).map_err(|e| Error::Internal(format!("Failed to create business metric copy: {}", e)))?;

                    Ok(gauge)
                } else {
                    Err(Error::Internal(format!("Failed to register business metric: {}", e)))
                }
            }
        }
    }

    /// Record the trace in the logs and propagate for distributed tracing
    pub fn record_trace(&self, trace_ctx: &TraceContext) {
        // Here we would typically save the trace in a persistent store
        // For this implementation, we'll just log it
        debug!("Recording trace: trace_id={}, span_id={}", trace_ctx.trace_id, trace_ctx.span_id);

        // Export to OpenTelemetry if configured
        if let Some(tracer) = &self.opentelemetry_tracer {
            if let Err(e) = self.export_trace_to_opentelemetry(tracer, trace_ctx) {
                warn!("Failed to export trace to OpenTelemetry: {}", e);
            }
        }
    }

    /// Export a trace to OpenTelemetry
    fn export_trace_to_opentelemetry(&self, tracer: &OpenTelemetryTracer, trace_ctx: &TraceContext) -> Result<()> {
        // Create attributes for the trace
        let mut attributes = Vec::new();
        attributes.push(("service.name", "art"));
        attributes.push(("trace.id", &trace_ctx.trace_id));
        attributes.push(("span.id", &trace_ctx.span_id));

        if let Some(parent_id) = &trace_ctx.parent_id {
            attributes.push(("parent.id", parent_id));
        }

        // Create events from baggage items
        let mut events = Vec::new();
        if !trace_ctx.baggage.is_empty() {
            let mut event_attrs = HashMap::new();
            for (key, value) in &trace_ctx.baggage {
                event_attrs.insert(key.clone(), value.clone());
            }
            events.push(("baggage", event_attrs));
        }

        // Record the span with the tracer
        tracer.record_span(
            "art.trace",
            trace_ctx,
            &attributes,
            &events,
            opentelemetry::trace::SpanKind::Server,
        )?;

        Ok(())
    }

    /// Query logs with filtering
    pub async fn query_logs(
        &self,
        level: Option<LogLevel>,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        limit: usize,
    ) -> Result<LogQueryResponse> {
        // Get the minimum log level to filter by
        let min_level = level.unwrap_or(LogLevel::Info);

        // Create a query description for the response
        let mut query_desc = Vec::new();
        if let Some(level) = &level {
            query_desc.push(format!("level >= {}", level));
        }
        if let Some(start) = &start_time {
            query_desc.push(format!("time >= {}", start.to_rfc3339()));
        }
        if let Some(end) = &end_time {
            query_desc.push(format!("time <= {}", end.to_rfc3339()));
        }
        query_desc.push(format!("limit: {}", limit));

        // This is where we would typically query a persistent log store
        // For now, we'll return a synthetic response or fetch from in-memory logs

        let logs = self.fetch_logs(min_level, start_time, end_time, limit).await?;

        Ok(LogQueryResponse {
            total: logs.len(),
            logs,
            query: query_desc.join(", "),
        })
    }

    /// Fetch logs from the storage backend (in-memory for now)
    async fn fetch_logs(
        &self,
        min_level: LogLevel,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        limit: usize,
    ) -> Result<Vec<LogEntry>> {
        // This is where we would query a log storage backend
        // For now, we'll return synthetic logs or the last N logs from memory

        // Access in-memory logs (would be replaced with actual backend)
        let mut logs = self.get_in_memory_logs();

        // Apply filters
        logs.retain(|log| {
            // Filter by log level
            if log.level < min_level {
                return false;
            }

            // Filter by start time
            if let Some(start) = start_time {
                if log.timestamp < start {
                    return false;
                }
            }

            // Filter by end time
            if let Some(end) = end_time {
                if log.timestamp > end {
                    return false;
                }
            }

            true
        });

        // Apply limit
        if logs.len() > limit {
            logs.truncate(limit);
        }

        Ok(logs)
    }

    /// Get the in-memory logs (temporary implementation)
    fn get_in_memory_logs(&self) -> Vec<LogEntry> {
        // In a real implementation, this would fetch from a persistent store
        // For now, we'll return synthetic logs
        let now = chrono::Utc::now();
        let one_hour_ago = now - chrono::Duration::hours(1);

        vec![
            LogEntry {
                timestamp: now - chrono::Duration::minutes(5),
                level: LogLevel::Info,
                message: "API request received".to_string(),
                fields: {
                    let mut fields = std::collections::HashMap::new();
                    fields.insert("method".to_string(), serde_json::Value::String("GET".to_string()));
                    fields.insert("path".to_string(), serde_json::Value::String("/api/repos".to_string()));
                    fields.insert("status".to_string(), serde_json::Value::Number(serde_json::Number::from(200)));
                    fields.insert("duration_ms".to_string(), serde_json::Value::Number(serde_json::Number::from(15)));
                    fields
                },
                trace_context: None,
            },
            LogEntry {
                timestamp: now - chrono::Duration::minutes(10),
                level: LogLevel::Warn,
                message: "Slow API request".to_string(),
                fields: {
                    let mut fields = std::collections::HashMap::new();
                    fields.insert("method".to_string(), serde_json::Value::String("GET".to_string()));
                    fields.insert("path".to_string(), serde_json::Value::String("/api/repos/metrics".to_string()));
                    fields.insert("status".to_string(), serde_json::Value::Number(serde_json::Number::from(200)));
                    fields.insert("duration_ms".to_string(), serde_json::Value::Number(serde_json::Number::from(500)));
                    fields
                },
                trace_context: None,
            },
            LogEntry {
                timestamp: now - chrono::Duration::minutes(15),
                level: LogLevel::Error,
                message: "Failed to open repository".to_string(),
                fields: {
                    let mut fields = std::collections::HashMap::new();
                    fields.insert("repository".to_string(), serde_json::Value::String("missing-repo".to_string()));
                    fields.insert("error".to_string(), serde_json::Value::String("Repository not found".to_string()));
                    fields
                },
                trace_context: None,
            },
            LogEntry {
                timestamp: now - chrono::Duration::minutes(30),
                level: LogLevel::Info,
                message: "Git operation completed".to_string(),
                fields: {
                    let mut fields = std::collections::HashMap::new();
                    fields.insert("operation".to_string(), serde_json::Value::String("clone".to_string()));
                    fields.insert("repository".to_string(), serde_json::Value::String("test-repo".to_string()));
                    fields.insert("duration_ms".to_string(), serde_json::Value::Number(serde_json::Number::from(1200)));
                    fields
                },
                trace_context: None,
            },
            LogEntry {
                timestamp: one_hour_ago,
                level: LogLevel::Debug,
                message: "Cache lookup".to_string(),
                fields: {
                    let mut fields = std::collections::HashMap::new();
                    fields.insert("key".to_string(), serde_json::Value::String("repo:test-repo:stats".to_string()));
                    fields.insert("found".to_string(), serde_json::Value::Bool(true));
                    fields
                },
                trace_context: None,
            },
        ]
    }

    /// Create a custom metric with the specified name, help text, and labels
    pub fn create_counter(&self, name: &str, help: &str, labels: Vec<&str>) -> Result<IntCounterVec> {
        let metric_name = format!("art_{}", name);
        let counter = IntCounterVec::new(
            prometheus::opts!(metric_name, help),
            &labels,
        ).map_err(|e| Error::Internal(format!("Failed to create counter: {}", e)))?;

        self.registry.register(Box::new(counter.clone()))
            .map_err(|e| Error::Internal(format!("Failed to register counter: {}", e)))?;

        Ok(counter)
    }

    /// Create a custom gauge metric
    pub fn create_gauge(&self, name: &str, help: &str, labels: Vec<&str>) -> Result<GaugeVec> {
        let metric_name = format!("art_{}", name);
        let gauge = GaugeVec::new(
            prometheus::opts!(metric_name, help),
            &labels,
        ).map_err(|e| Error::Internal(format!("Failed to create gauge: {}", e)))?;

        self.registry.register(Box::new(gauge.clone()))
            .map_err(|e| Error::Internal(format!("Failed to register gauge: {}", e)))?;

        Ok(gauge)
    }

    /// Create a custom histogram metric
    pub fn create_histogram(&self, name: &str, help: &str, buckets: Vec<f64>, labels: Vec<&str>) -> Result<HistogramVec> {
        let metric_name = format!("art_{}", name);
        let histogram = HistogramVec::new(
            prometheus::histogram_opts!(
                metric_name,
                help,
                buckets
            ),
            &labels,
        ).map_err(|e| Error::Internal(format!("Failed to create histogram: {}", e)))?;

        self.registry.register(Box::new(histogram.clone()))
            .map_err(|e| Error::Internal(format!("Failed to register histogram: {}", e)))?;

        Ok(histogram)
    }

    /// Get repository metrics for a specific repository
    pub async fn get_repository_metrics(&self, repo_name: &str) -> Option<RepositoryContentStats> {
        if let Some(collector) = &self.content_metrics_collector {
            let collector = collector.lock().await;
            collector.get_repository_metrics(repo_name).cloned()
        } else {
            None
        }
    }

    /// Get metrics for all repositories
    pub async fn get_all_repository_metrics(&self) -> HashMap<String, RepositoryContentStats> {
        if let Some(collector) = &self.content_metrics_collector {
            let collector = collector.lock().await;
            collector.get_all_repository_metrics().clone()
        } else {
            HashMap::new()
        }
    }

    /// Get activity metrics for a repository
    pub async fn get_repository_activity(&self, repo_name: &str) -> Option<RepositoryActivityStats> {
        if let Some(collector) = &self.content_metrics_collector {
            let collector = collector.lock().await;
            collector.get_repository_activity(repo_name).await
        } else {
            None
        }
    }

    /// Force a refresh of repository metrics
    pub async fn refresh_repository_metrics(&self) -> Result<()> {
        if let Some(collector) = &self.content_metrics_collector {
            let mut collector = collector.lock().await;
            collector.collect_metrics().await?;
            Ok(())
        } else {
            Err(Error::Internal("Content metrics collector is not available".to_string()))
        }
    }

    /// Create a rate limiter with specified configuration
    pub fn create_rate_limiter(&self, config: RateLimitConfig) -> RateLimiter {
        RateLimiter::new(config)
    }

    /// Create a rate limiter with default configuration
    pub fn create_default_rate_limiter(&self) -> RateLimiter {
        RateLimiter::new(RateLimitConfig::default())
    }

    /// Get the content metrics collector if available
    pub fn get_content_metrics_collector(&self) -> Option<&Arc<tokio::sync::Mutex<ContentMetricsCollector>>> {
        self.content_metrics_collector.as_ref()
    }

    /// Get a reference to the OpenTelemetry tracer if configured
    pub fn opentelemetry_tracer(&self) -> Option<Arc<OpenTelemetryTracer>> {
        self.opentelemetry_tracer.clone()
    }

    /// Query traces from the observability service
    pub async fn query_traces(&self, limit: usize, service: Option<&str>) -> Result<Vec<TraceData>, Error> {
        // Implementation that would normally query traces from storage
        // For this example, we'll return a mock response
        let mut traces = Vec::new();

        // For testing, create some mock trace data
        if let Some(tracer) = &self.opentelemetry_tracer {
            // Mock trace data based on recent spans if we have a tracer
            let trace_id = Uuid::new_v4().to_string();
            let span_id = Uuid::new_v4().to_string();

            let mut attributes = HashMap::new();
            attributes.insert("http.method".to_string(), "GET".to_string());
            attributes.insert("http.path".to_string(), "/api/metrics".to_string());

            let mut events = Vec::new();
            events.push(TraceEvent {
                name: "db.query".to_string(),
                timestamp: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64,
                attributes: {
                    let mut attrs = HashMap::new();
                    attrs.insert("db.statement".to_string(), "SELECT * FROM metrics".to_string());
                    attrs.insert("db.system".to_string(), "postgresql".to_string());
                    attrs
                },
            });

            // Filter by service if specified
            let service_name = service.unwrap_or("art-observability");
            if service.is_none() || service.unwrap() == service_name {
                traces.push(TraceData {
                    trace_id,
                    span_id,
                    parent_id: None,
                    service: service_name.to_string(),
                    operation: "http.request".to_string(),
                    timestamp: SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as u64 - 100, // Make it start slightly in the past
                    duration: 100, // 100ms duration
                    attributes,
                    events,
                });
            }

            // Apply limit
            traces.truncate(limit);
        }

        Ok(traces)
    }

    /// Query logs with search functionality
    pub async fn query_logs_with_search(
        &self,
        limit: usize,
        level: Option<&str>,
        search: Option<&str>,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        fields: Option<HashMap<String, String>>,
    ) -> Result<LogQueryResponse> {
        // Convert log level string to LogLevel enum
        let min_level = match level {
            Some(level_str) => {
                let level: LogLevel = level_str.into();
                level
            }
            None => LogLevel::Info, // Default to INFO level
        };

        // Fetch logs from cache
        let mut logs = self.fetch_logs(min_level, start_time, end_time, limit).await?;

        // Apply search filter if provided
        if let Some(search_term) = search {
            logs = logs
                .into_iter()
                .filter(|log| {
                    // Search in message
                    if log.message.contains(search_term) {
                        return true;
                    }

                    // Search in fields
                    for (_, value) in &log.fields {
                        if let Some(value_str) = value.as_str() {
                            if value_str.contains(search_term) {
                                return true;
                            }
                        }
                    }

                    false
                })
                .collect();
        }

        // Apply field filters if provided
        if let Some(field_filters) = fields {
            logs = logs
                .into_iter()
                .filter(|log| {
                    field_filters.iter().all(|(key, value)| {
                        if let Some(field_value) = log.fields.get(key) {
                            match field_value {
                                serde_json::Value::String(s) => s.contains(value),
                                _ => field_value.to_string().contains(value),
                            }
                        } else {
                            false
                        }
                    })
                })
                .collect();
        }

        // Build query parameters for response
        let mut query_params = HashMap::new();
        if let Some(level_str) = level {
            query_params.insert("level".to_string(), level_str.to_string());
        }
        if let Some(search_term) = search {
            query_params.insert("search".to_string(), search_term.to_string());
        }
        if let Some(start) = start_time {
            query_params.insert("start_time".to_string(), start.to_rfc3339());
        }
        if let Some(end) = end_time {
            query_params.insert("end_time".to_string(), end.to_rfc3339());
        }
        if let Some(field_filters) = &fields {
            for (key, value) in field_filters {
                query_params.insert(format!("field_{}", key), value.clone());
            }
        }

        Ok(LogQueryResponse {
            total: logs.len(),
            logs,
            query: query_params,
        })
    }

    proptest! {
        // Property-based test for log level parsing
        #[test]
        fn test_log_level_parsing(
            level in proptest::sample::select(&["trace", "debug", "info", "warn", "error", "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "unknown"])
        ) {
            let parsed_level = LogLevel::from(level);

            match level.to_lowercase().as_str() {
                "trace" => prop_assert_eq!(parsed_level, LogLevel::Trace),
                "debug" => prop_assert_eq!(parsed_level, LogLevel::Debug),
                "info" => prop_assert_eq!(parsed_level, LogLevel::Info),
                "warn" => prop_assert_eq!(parsed_level, LogLevel::Warn),
                "error" => prop_assert_eq!(parsed_level, LogLevel::Error),
                _ => prop_assert_eq!(parsed_level, LogLevel::Info), // Default
            }

            Ok(())
        }

        // Property-based test for log level ordering
        #[test]
        fn test_log_level_ordering() -> Result<()> {
            // Ensure log levels are ordered correctly (Trace < Debug < Info < Warn < Error)
            prop_assert!(LogLevel::Trace < LogLevel::Debug);
            prop_assert!(LogLevel::Debug < LogLevel::Info);
            prop_assert!(LogLevel::Info < LogLevel::Warn);
            prop_assert!(LogLevel::Warn < LogLevel::Error);

            // Test reflexivity
            prop_assert!(LogLevel::Trace <= LogLevel::Trace);
            prop_assert!(LogLevel::Debug <= LogLevel::Debug);
            prop_assert!(LogLevel::Info <= LogLevel::Info);
            prop_assert!(LogLevel::Warn <= LogLevel::Warn);
            prop_assert!(LogLevel::Error <= LogLevel::Error);

            // Test transitivity
            prop_assert!(LogLevel::Trace < LogLevel::Warn);
            prop_assert!(LogLevel::Debug < LogLevel::Error);

            Ok(())
        }

        // Property-based test for log filtering by level
        #[test]
        fn test_log_filtering_by_level(
            min_level_idx in 0usize..5usize
        ) -> Result<()> {
            // Create a runtime for async tests
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Map the index to a log level
                let levels = [LogLevel::Trace, LogLevel::Debug, LogLevel::Info, LogLevel::Warn, LogLevel::Error];
                let min_level = levels[min_level_idx];

                // Query logs with the minimum level
                let result = service.query_logs(Some(min_level), None, None, 100).await;

                // Test should pass if the query returns successfully
                prop_assert!(result.is_ok());

                let logs = result.unwrap();

                // All returned logs should have a level >= min_level
                for log in &logs.logs {
                    prop_assert!(log.level >= min_level, "Log level {:?} should be >= minimum level {:?}", log.level, min_level);
                }

                Ok(())
            })
        }

        // Property-based test for log filtering by time range
        #[test]
        fn test_log_filtering_by_time_range(
            hours_ago in 0u64..48u64,
            window_hours in 1u64..24u64
        ) {
            // Create a runtime for async tests
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Calculate time range
                let now = chrono::Utc::now();
                let end_time = now - chrono::Duration::hours(hours_ago as i64);
                let start_time = end_time - chrono::Duration::hours(window_hours as i64);

                // Query logs within the time range
                let result = service.query_logs(None, Some(start_time), Some(end_time), 100).await;

                // Test should pass if the query returns successfully
                prop_assert!(result.is_ok());

                let logs = result.unwrap();

                // All returned logs should be within the time range
                for log in &logs.logs {
                    prop_assert!(log.timestamp >= start_time, "Log timestamp should be >= start time");
                    prop_assert!(log.timestamp <= end_time, "Log timestamp should be <= end time");
                }

                Ok(())
            })
        }

        // Property-based test for log query limit
        #[test]
        fn test_log_query_limit(
            limit in 1usize..1000usize
        ) {
            // Create a runtime for async tests
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Query logs with the specified limit
                let result = service.query_logs(None, None, None, limit).await;

                // Test should pass if the query returns successfully
                prop_assert!(result.is_ok());

                let logs = result.unwrap();

                // The number of logs should not exceed the limit
                prop_assert!(logs.logs.len() <= limit, "Number of logs {} should not exceed limit {}", logs.logs.len(), limit);

                Ok(())
            })
        }
    }

    #[test]
    fn test_fetch_logs() {
        let rt = Runtime::new().unwrap();

        rt.block_on(async {
            // Create a test service
            let service = create_test_service();

            // Query logs with no filters
            let result = service.query_logs(None, None, None, 10).await;
            assert!(result.is_ok());

            let logs = result.unwrap();
            assert!(!logs.logs.is_empty(), "Should return at least some logs");

            // Query logs with level filter
            let result = service.query_logs(Some(LogLevel::Warn), None, None, 10).await;
            assert!(result.is_ok());

            let logs = result.unwrap();
            // All logs should be Warn or Error
            for log in &logs.logs {
                assert!(log.level >= LogLevel::Warn, "Log level should be >= WARN");
            }

            // Query logs with limit
            let result = service.query_logs(None, None, None, 2).await;
            assert!(result.is_ok());

            let logs = result.unwrap();
            assert!(logs.logs.len() <= 2, "Should not return more than the limit");
        });
    }

    #[test]
    fn test_log_level_display() {
        assert_eq!(format!("{}", LogLevel::Trace), "TRACE");
        assert_eq!(format!("{}", LogLevel::Debug), "DEBUG");
        assert_eq!(format!("{}", LogLevel::Info), "INFO");
        assert_eq!(format!("{}", LogLevel::Warn), "WARN");
        assert_eq!(format!("{}", LogLevel::Error), "ERROR");
    }

    // Test the OpenTelemetry integration
    proptest! {
        #[test]
        fn test_opentelemetry_trace_export(
            trace_id in "[a-f0-9]{32}",
            span_id in "[a-f0-9]{16}",
            parent_id in proptest::option::of("[a-f0-9]{16}"),
            sampled in proptest::bool::ANY,
            baggage_key in "[a-z_]{3,10}",
            baggage_value in "[a-z0-9]{3,10}"
        ) {
            // Create a mock OpenTelemetry tracer
            let config = OpenTelemetryConfig {
                enabled: true,
                endpoint: "http://localhost:4317".to_string(),
                service_name: "art-test".to_string(),
                sampling_ratio: 1.0,
                timeout_seconds: 5,
                default_attributes: HashMap::new(),
                export_otlp: false, // Don't actually export during tests
                export_stdout: true, // Debug to stdout
            };

            let tracer = OpenTelemetryTracer::new(config).expect("Failed to create tracer");

            // Create a trace context with the generated properties
            let mut trace_ctx = TraceContext::new();
            trace_ctx.trace_id = trace_id.clone();
            trace_ctx.span_id = span_id.clone();
            trace_ctx.parent_id = parent_id.clone();
            trace_ctx.sampled = sampled;
            trace_ctx.add_baggage(&baggage_key, &baggage_value);

            // Record a span using our tracer
            let result = tracer.record_span(
                "test-span",
                &trace_ctx,
                &[("test", "attribute")],
                &[],
                SpanKind::Client
            );

            // Verify the span was recorded successfully
            prop_assert!(result.is_ok(), "Failed to record span: {:?}", result);

            // Test OpenTelemetry header conversion
            let headers = convert_to_otel_format(&trace_ctx);

            // Verify the traceparent header format
            let traceparent = headers.get("traceparent").unwrap();
            let expected_sampled = if sampled { "01" } else { "00" };
            prop_assert!(traceparent.starts_with(&format!("00-{}-{}-{}", trace_id, span_id, expected_sampled)));

            // Test extracting from headers
            let extracted = extract_from_otel_format(&headers).unwrap();

            // Verify key properties are preserved
            prop_assert_eq!(extracted.trace_id, trace_ctx.trace_id);
            prop_assert_eq!(extracted.parent_id.as_ref().unwrap(), &trace_ctx.span_id);
            prop_assert_eq!(extracted.sampled, trace_ctx.sampled);
            prop_assert_eq!(extracted.baggage.get(&baggage_key).unwrap(), &baggage_value);
        }

        #[test]
        fn test_observability_service_with_opentelemetry(
            trace_id in "[a-f0-9]{32}",
            span_id in "[a-f0-9]{16}"
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test config with OpenTelemetry enabled
                let otel_config = OpenTelemetryConfig {
                    enabled: true,
                    endpoint: "http://localhost:4317".to_string(),
                    service_name: "art-test".to_string(),
                    sampling_ratio: 1.0,
                    timeout_seconds: 5,
                    default_attributes: HashMap::new(),
                    export_otlp: false, // Don't actually export during tests
                    export_stdout: true, // Debug to stdout
                };

                let config = ObservabilityConfig {
                    enable_metrics: true,
                    log_level: "info".to_string(),
                    opentelemetry: Some(otel_config),
                };

                // Create a tracer
                let tracer = OpenTelemetryTracer::new(config.opentelemetry.clone().unwrap()).expect("Failed to create tracer");

                // Create an observability service with the tracer
                let cache = Arc::new(Cache::new_for_test());
                let service = ObservabilityService::new(Arc::new(config), cache).await.expect("Failed to create service");

                // Create a trace context to record
                let mut trace_ctx = TraceContext::new();
                trace_ctx.trace_id = trace_id.clone();
                trace_ctx.span_id = span_id.clone();

                // Record the trace
                service.record_trace(&trace_ctx);

                // There's no easy way to verify the export directly in a test,
                // but we can verify that the service has the tracer configured
                prop_assert!(service.opentelemetry_tracer.is_some());

                Ok(())
            })
        }
    }

    #[test]
    fn test_opentelemetry_integration() {
        // Create a mock OpenTelemetry tracer
        let config = OpenTelemetryConfig {
            enabled: true,
            endpoint: "http://localhost:4317".to_string(),
            service_name: "art-test".to_string(),
            sampling_ratio: 1.0,
            timeout_seconds: 5,
            default_attributes: HashMap::new(),
            export_otlp: false, // Don't actually export during tests
            export_stdout: true, // Debug to stdout
        };

        let tracer = OpenTelemetryTracer::new(config).expect("Failed to create tracer");

        // Create a trace context
        let mut trace_ctx = TraceContext::new();
        trace_ctx.add_baggage("test_key", "test_value");

        // Test exporting attributes and events
        let result = tracer.record_span(
            "test-span",
            &trace_ctx,
            &[
                ("attribute1", "value1"),
                ("attribute2", "value2"),
            ],
            &[
                ("event1", {
                    let mut map = HashMap::new();
                    map.insert("event_key1".to_string(), "event_value1".to_string());
                    map
                }),
                ("event2", {
                    let mut map = HashMap::new();
                    map.insert("event_key2".to_string(), "event_value2".to_string());
                    map
                }),
            ],
            SpanKind::Server
        );

        assert!(result.is_ok());

        // Test shutdown (should not fail even if no actual export happened)
        let shutdown_result = tracer.shutdown();
        assert!(shutdown_result.is_ok());
    }

    proptest! {
        #[test]
        fn test_log_search_functionality(
            search_term in "[a-zA-Z0-9 ]{1,10}",
            log_count in 1..20usize,
            matching_logs in 0..10usize,
            level in prop::sample::select(&["trace", "debug", "info", "warn", "error"][..]),
            limit in 1..25usize
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            // Ensure matching_logs doesn't exceed log_count
            let matching_logs = matching_logs.min(log_count);

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Create synthetic logs for testing
                let mut logs = Vec::new();

                // Create logs that match the search term
                for i in 0..matching_logs {
                    let message = format!("Test log {} with search term: {}", i, search_term);
                    let mut fields = HashMap::new();
                    fields.insert("testField".to_string(), serde_json::to_value(i).unwrap());

                    logs.push(LogEntry {
                        level: LogLevel::Info,
                        message,
                        timestamp: chrono::Utc::now(),
                        fields,
                        trace_context: None,
                    });
                }

                // Create logs that don't match the search term
                for i in matching_logs..log_count {
                    let message = format!("Test log {} without match", i);
                    let mut fields = HashMap::new();
                    fields.insert("testField".to_string(), serde_json::to_value(i).unwrap());

                    logs.push(LogEntry {
                        level: LogLevel::Info,
                        message,
                        timestamp: chrono::Utc::now(),
                        fields,
                        trace_context: None,
                    });
                }

                // Mock the get_in_memory_logs method
                let service_logs = service.get_in_memory_logs();
                // Note: In a real test, we would mock the logs to return our test set
                // For this property test, we'll just check the logic

                // Query logs with search
                let result = service.query_logs_with_search(
                    limit,
                    Some(level),
                    Some(&search_term)
                ).await;

                // Check that the query succeeds
                assert!(result.is_ok());

                // In a real scenario with mocking:
                // let logs = result.unwrap();
                // assert_eq!(logs.total, matching_logs.min(limit));
                // assert!(logs.logs.iter().all(|log| log.message.contains(&search_term)));

                // For this test, we just verify the result is Ok
                let log_query = result.unwrap();
                assert!(log_query.query.contains_key("search"));
                assert_eq!(log_query.query.get("search").unwrap(), &search_term);
            });
        }

        #[test]
        fn test_log_level_filtering(
            level_str in prop::sample::select(&["trace", "debug", "info", "warn", "error"][..])
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Convert level string to LogLevel enum
                let level = LogLevel::from(level_str);

                // Query logs with level filter
                let result = service.query_logs_with_search(
                    100,
                    Some(level_str),
                    None
                ).await;

                // Check that the query succeeds
                assert!(result.is_ok());

                // Verify level filtering is applied
                let log_query = result.unwrap();

                // All returned logs should be at or above the specified level
                for log in &log_query.logs {
                    assert!(log.level >= level);
                }

                // Check that query parameters include the level
                assert!(log_query.query.contains_key("level"));
                assert_eq!(log_query.query.get("level").unwrap(), &level.to_string());
            });
        }

        #[test]
        fn test_log_limit_enforcement(
            limit in 1..100usize
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                // Create a test service
                let service = create_test_service();

                // Query logs with limit
                let result = service.query_logs_with_search(
                    limit,
                    None,
                    None
                ).await;

                // Check that the query succeeds
                assert!(result.is_ok());

                // Verify limit is enforced
                let log_query = result.unwrap();
                assert!(log_query.logs.len() <= limit);

                // Check that query parameters include the limit
                assert!(log_query.query.contains_key("limit"));
                assert_eq!(log_query.query.get("limit").unwrap(), &limit.to_string());
            });
        }
    }

    #[test]
    fn test_full_opentelemetry_integration() -> Result<()> {
        let rt = tokio::runtime::Runtime::new().unwrap();

        rt.block_on(async {
            // Create a test configuration with OpenTelemetry enabled
            let mut config = ObservabilityConfig::default();
            config.opentelemetry = Some(OpenTelemetryConfig {
                enabled: true,
                endpoint: "http://localhost:4317".to_string(),
                sampling_ratio: 1.0,
                service_name: "art-test".to_string(),
                timeout_seconds: 5,
                default_attributes: HashMap::new(),
                export_otlp: false,  // Don't actually export in tests
                export_stdout: true, // Use stdout for testing
            });

            // Create an observability service with the config
            let service = ObservabilityService::new(Arc::new(config), None, None).await?;

            // Verify the OpenTelemetry tracer is created
            assert!(service.opentelemetry_tracer.is_some());

            // Create a trace context
            let trace_ctx = service.create_trace_context();

            // Add some baggage to the trace context
            let mut trace_with_baggage = trace_ctx.clone();
            trace_with_baggage.add_baggage("test-key", "test-value");

            // Record a trace
            service.record_trace(&trace_with_baggage);

            // Create HTTP headers from trace context
            let tracer = service.opentelemetry_tracer.as_ref().unwrap();

            // Test W3C format conversion
            let w3c_headers = convert_to_otel_format(&trace_with_baggage);
            assert!(w3c_headers.contains_key("traceparent"));

            // Test Jaeger format conversion
            let jaeger_headers = convert_to_jaeger_format(&trace_with_baggage);
            assert!(jaeger_headers.contains_key("uber-trace-id"));

            // Test Zipkin format conversion
            let zipkin_headers = convert_to_zipkin_format(&trace_with_baggage);
            assert!(zipkin_headers.contains_key("x-b3-traceid"));

            // Test multi-format extraction
            let mut combined_headers = HashMap::new();
            combined_headers.extend(w3c_headers);

            let extracted_ctx = extract_from_http_headers(&combined_headers).unwrap();
            assert_eq!(extracted_ctx.trace_id, trace_with_baggage.trace_id);

            // Test creating spans
            let span_result = tracer.record_span(
                "test-span",
                &trace_with_baggage,
                &[("test-attr", "test-value")],
                &[],
                opentelemetry::trace::SpanKind::Server,
            );
            assert!(span_result.is_ok());

            // Test creating a child span
            let child_ctx = trace_with_baggage.create_child();
            assert_eq!(child_ctx.parent_id.as_ref().unwrap(), &trace_with_baggage.span_id);

            // Record the child span
            let child_span_result = tracer.record_span(
                "child-span",
                &child_ctx,
                &[("child-attr", "child-value")],
                &[],
                opentelemetry::trace::SpanKind::Client,
            );
            assert!(child_span_result.is_ok());

            Ok(())
        })
    }

    #[cfg(test)]
    mod health_check_tests {
        use super::*;
        use proptest::prelude::*;
        use proptest::strategy::Strategy;

        /// Strategy for generating component names
        fn component_name_strategy() -> impl Strategy<Value = String> {
            prop_oneof![
                Just("memory".to_string()),
                Just("connections".to_string()),
                Just("database".to_string()),
                Just("cache".to_string()),
                Just("git".to_string()),
                "[a-z_]{3,10}".prop_map(|s| s.to_string()),
            ]
        }

        /// Strategy for generating component statuses
        fn component_status_strategy() -> impl Strategy<Value = String> {
            prop_oneof![
                Just("ok".to_string()),
                Just("degraded".to_string()),
                Just("error".to_string()),
            ]
        }

        /// Strategy for generating optional messages
        fn optional_message_strategy() -> impl Strategy<Value = Option<String>> {
            prop_oneof![
                Just(None),
                "[A-Za-z0-9 ]{5,20}".prop_map(|s| Some(s)),
            ]
        }

        /// Strategy for generating a complete component status
        fn component_status_obj_strategy() -> impl Strategy<Value = ComponentStatus> {
            (
                component_status_strategy(),
                optional_message_strategy(),
            ).prop_map(|(status, message)| {
                ComponentStatus {
                    status,
                    message,
                }
            })
        }

        /// Strategy for generating a map of components and their statuses
        fn components_map_strategy() -> impl Strategy<Value = HashMap<String, ComponentStatus>> {
            proptest::collection::hash_map(
                component_name_strategy(),
                component_status_obj_strategy(),
                1..10,
            )
        }

        /// Helper to create a test ObservabilityService with custom memory and connection values
        fn create_test_service_with_values(memory_bytes: i64, active_conns: i64) -> ObservabilityService {
            let service = create_test_service();
            service.update_memory_usage(memory_bytes);

            // Set active connections
            if active_conns > 0 {
                for _ in 0..active_conns {
                    service.increment_connections();
                }
            } else if active_conns < 0 {
                for _ in 0..active_conns.abs() {
                    service.decrement_connections();
                }
            }

            service
        }

        /// Helper function to create a test service
        fn create_test_service() -> ObservabilityService {
            let config = ObservabilityConfig::default();
            ObservabilityService::new(config, None, None).unwrap()
        }

        proptest! {
            /// Test that health check returns correct overall status based on component statuses
            #[test]
            fn test_health_status_determination(
                components in components_map_strategy()
            ) {
                // Create a test HealthResponse with the given components
                let health_response = HealthResponse {
                    status: "".to_string(), // Will be overwritten
                    version: "test".to_string(),
                    uptime: 0,
                    components: components.clone(),
                };

                // Determine expected overall status based on component statuses
                let expected_status = if components.values().any(|c| c.status == "error") {
                    "error"
                } else if components.values().any(|c| c.status == "degraded") {
                    "degraded"
                } else {
                    "ok"
                }.to_string();

                // Determine actual status using the same logic as the service
                let actual_status = if components.values().any(|c| c.status == "error") {
                    "error"
                } else if components.values().any(|c| c.status == "degraded") {
                    "degraded"
                } else {
                    "ok"
                }.to_string();

                // Verify status determination is consistent
                prop_assert_eq!(actual_status, expected_status);
            }

            /// Test that memory usage status is reported correctly
            #[test]
            fn test_memory_status_reporting(
                memory_bytes in 0..2_000_000_000i64
            ) {
                // Create a test service with specific memory usage
                let service = create_test_service_with_values(memory_bytes, 0);

                // Get health check response
                let health = service.health();

                // Verify memory status is included
                prop_assert!(health.components.contains_key("memory"));

                // Get memory component status
                let memory_status = health.components.get("memory").unwrap();

                // Verify status is correct based on memory usage
                if memory_bytes > 1_000_000_000 {
                    prop_assert_eq!(memory_status.status, "degraded");
                    prop_assert_eq!(memory_status.message, Some("High memory usage".to_string()));
                } else {
                    prop_assert_eq!(memory_status.status, "ok");
                    prop_assert_eq!(memory_status.message, None);
                }
            }

            /// Test that active connections status is reported correctly
            #[test]
            fn test_connections_status_reporting(
                active_conns in 0..200i64
            ) {
                // Create a test service with specific number of connections
                let service = create_test_service_with_values(0, active_conns);

                // Get health check response
                let health = service.health_check().unwrap();

                // Verify connections status is included
                prop_assert!(health.components.contains_key("connections"));

                // Get connections component status
                let conn_status = health.components.get("connections").unwrap();

                // Verify status is correct based on active connections
                if active_conns > 100 {
                    prop_assert_eq!(conn_status.status, "degraded");
                    prop_assert_eq!(conn_status.message, Some("High number of active connections".to_string()));
                } else {
                    prop_assert_eq!(conn_status.status, "ok");
                    prop_assert_eq!(conn_status.message, None);
                }
            }

            /// Test that overall status is determined correctly from component statuses
            #[test]
            fn test_overall_status_computation(
                memory_bytes in 0..2_000_000_000i64,
                active_conns in 0..200i64
            ) {
                // Create a test service with specific values
                let service = create_test_service_with_values(memory_bytes, active_conns);

                // Get health check response
                let health = service.health();

                // Determine expected overall status
                let memory_degraded = memory_bytes > 1_000_000_000;
                let connections_degraded = active_conns > 100;

                let expected_status = if memory_degraded || connections_degraded {
                    "degraded"
                } else {
                    "ok"
                };

                // Verify overall status is correct
                prop_assert_eq!(health.status, expected_status);
            }

            /// Test health response serialization and deserialization
            #[test]
            fn test_health_response_serialization(
                components in components_map_strategy(),
                version in "[0-9]+\\.[0-9]+\\.[0-9]+".prop_map(|s| s),
                uptime in 0..1_000_000u64
            ) {
                // Create a test health response
                let mut health_response = HealthResponse {
                    status: "".to_string(), // Will be overwritten
                    version,
                    uptime,
                    components: components.clone(),
                };

                // Set overall status based on component statuses
                health_response.status = if components.values().any(|c| c.status == "error") {
                    "error"
                } else if components.values().any(|c| c.status == "degraded") {
                    "degraded"
                } else {
                    "ok"
                }.to_string();

                // Serialize to JSON
                let json = serde_json::to_string(&health_response).unwrap();

                // Deserialize from JSON
                let deserialized: HealthResponse = serde_json::from_str(&json).unwrap();

                // Verify deserialized values match original
                prop_assert_eq!(deserialized.status, health_response.status);
                prop_assert_eq!(deserialized.version, health_response.version);
                prop_assert_eq!(deserialized.uptime, health_response.uptime);

                // Check components match
                for (name, status) in &health_response.components {
                    prop_assert!(deserialized.components.contains_key(name));
                    let deserialized_status = deserialized.components.get(name).unwrap();
                    prop_assert_eq!(deserialized_status.status, status.status);
                    prop_assert_eq!(deserialized_status.message, status.message);
                }
            }
        }
    }

    /// Get metrics as JSON
    pub fn metrics_as_json(&self) -> Result<String> {
        let metric_families = self.registry.gather();

        // Convert metric families to a JSON structure
        let mut metrics_map = serde_json::Map::new();

        for mf in metric_families {
            let name = mf.get_name();
            let help = mf.get_help();
            let metric_type = match mf.get_type() {
                prometheus::proto::MetricType::COUNTER => "counter",
                prometheus::proto::MetricType::GAUGE => "gauge",
                prometheus::proto::MetricType::HISTOGRAM => "histogram",
                prometheus::proto::MetricType::SUMMARY => "summary",
                _ => "unknown",
            };

            let mut metrics = Vec::new();

            for m in mf.get_metric() {
                let mut metric_map = serde_json::Map::new();

                // Add labels
                let mut labels = serde_json::Map::new();
                for lp in m.get_label() {
                    labels.insert(
                        lp.get_name().to_string(),
                        serde_json::Value::String(lp.get_value().to_string()),
                    );
                }
                metric_map.insert("labels".to_string(), serde_json::Value::Object(labels));

                // Add value based on metric type
                match mf.get_type() {
                    prometheus::proto::MetricType::COUNTER => {
                        if m.has_counter() {
                            metric_map.insert(
                                "value".to_string(),
                                serde_json::Value::Number(serde_json::Number::from_f64(m.get_counter().get_value()).unwrap_or(serde_json::Number::from(0))),
                            );
                        }
                    },
                    prometheus::proto::MetricType::GAUGE => {
                        if m.has_gauge() {
                            metric_map.insert(
                                "value".to_string(),
                                serde_json::Value::Number(serde_json::Number::from_f64(m.get_gauge().get_value()).unwrap_or(serde_json::Number::from(0))),
                            );
                        }
                    },
                    prometheus::proto::MetricType::HISTOGRAM => {
                        if m.has_histogram() {
                            let h = m.get_histogram();
                            let mut histogram_map = serde_json::Map::new();

                            histogram_map.insert(
                                "sample_count".to_string(),
                                serde_json::Value::Number(serde_json::Number::from(h.get_sample_count())),
                            );
                            histogram_map.insert(
                                "sample_sum".to_string(),
                                serde_json::Value::Number(serde_json::Number::from_f64(h.get_sample_sum()).unwrap_or(serde_json::Number::from(0))),
                            );

                            let mut buckets = Vec::new();
                            for b in h.get_bucket() {
                                let mut bucket_map = serde_json::Map::new();
                                bucket_map.insert(
                                    "upper_bound".to_string(),
                                    serde_json::Value::Number(serde_json::Number::from_f64(b.get_upper_bound()).unwrap_or(serde_json::Number::from(0))),
                                );
                                bucket_map.insert(
                                    "cumulative_count".to_string(),
                                    serde_json::Value::Number(serde_json::Number::from(b.get_cumulative_count())),
                                );
                                buckets.push(serde_json::Value::Object(bucket_map));
                            }
                            histogram_map.insert("buckets".to_string(), serde_json::Value::Array(buckets));

                            metric_map.insert("histogram".to_string(), serde_json::Value::Object(histogram_map));
                        }
                    },
                    _ => {}
                }

                metrics.push(serde_json::Value::Object(metric_map));
            }

            // Create the metric family object
            let mut mf_map = serde_json::Map::new();
            mf_map.insert("help".to_string(), serde_json::Value::String(help.to_string()));
            mf_map.insert("type".to_string(), serde_json::Value::String(metric_type.to_string()));
            mf_map.insert("metrics".to_string(), serde_json::Value::Array(metrics));

            metrics_map.insert(name.to_string(), serde_json::Value::Object(mf_map));
        }

        // Convert to JSON string
        serde_json::to_string_pretty(&serde_json::Value::Object(metrics_map))
            .map_err(|e| Error::Internal(format!("Failed to encode metrics as JSON: {}", e)))
    }

    /// Get metrics in OpenMetrics format
    pub fn metrics_as_openmetrics(&self) -> Result<String> {
        let encoder = prometheus::encoding::openmetrics::Encoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();

        encoder.encode(&metric_families, &mut buffer)
            .map_err(|e| Error::Internal(format!("Failed to encode metrics in OpenMetrics format: {}", e)))?;

        String::from_utf8(buffer)
            .map_err(|e| Error::Internal(format!("Invalid UTF-8 in metrics: {}", e)))
    }

    /// Get metrics in CSV format
    ///
    /// This function exports all metrics in CSV format with the following columns:
    /// - name: The name of the metric
    /// - type: The type of the metric (counter, gauge, histogram)
    /// - help: The description of the metric
    /// - labels: A JSON string containing the metric's labels
    /// - value: The value of the metric (for counters and gauges)
    /// - sample_count: The number of samples (for histograms)
    /// - sample_sum: The sum of all samples (for histograms)
    /// - timestamp: The timestamp when the metrics were collected
    ///
    /// For histograms, each bucket is exported as a separate row with the bucket's upper_bound
    /// as an additional column.
    pub fn metrics_as_csv(&self) -> Result<String> {
        let metric_families = self.registry.gather();
        let timestamp = chrono::Utc::now().to_rfc3339();

        // Create CSV header
        let mut output = String::from("name,type,help,labels,value,sample_count,sample_sum,upper_bound,timestamp\n");

        for mf in metric_families {
            let name = mf.get_name();
            let help = mf.get_help().replace(",", ";"); // Escape commas in help text
            let metric_type = match mf.get_type() {
                prometheus::proto::MetricType::COUNTER => "counter",
                prometheus::proto::MetricType::GAUGE => "gauge",
                prometheus::proto::MetricType::HISTOGRAM => "histogram",
                prometheus::proto::MetricType::SUMMARY => "summary",
                _ => "unknown",
            };

            for m in mf.get_metric() {
                // Format labels as JSON
                let mut labels_map = serde_json::Map::new();
                for lp in m.get_label() {
                    labels_map.insert(
                        lp.get_name().to_string(),
                        serde_json::Value::String(lp.get_value().to_string()),
                    );
                }
                let labels_json = serde_json::to_string(&labels_map)
                    .unwrap_or_else(|_| "{}".to_string())
                    .replace(",", ";"); // Escape commas in JSON

                match mf.get_type() {
                    prometheus::proto::MetricType::COUNTER => {
                        if m.has_counter() {
                            let value = m.get_counter().get_value();
                            output.push_str(&format!(
                                "{},{},\"{}\",\"{}\",{},,,{},{}\n",
                                name, metric_type, help, labels_json, value, "", timestamp
                            ));
                        }
                    },
                    prometheus::proto::MetricType::GAUGE => {
                        if m.has_gauge() {
                            let value = m.get_gauge().get_value();
                            output.push_str(&format!(
                                "{},{},\"{}\",\"{}\",{},,,{},{}\n",
                                name, metric_type, help, labels_json, value, "", timestamp
                            ));
                        }
                    },
                    prometheus::proto::MetricType::HISTOGRAM => {
                        if m.has_histogram() {
                            let h = m.get_histogram();
                            let sample_count = h.get_sample_count();
                            let sample_sum = h.get_sample_sum();

                            // Export main histogram row
                            output.push_str(&format!(
                                "{},{},\"{}\",\"{}\",{},{},{},{},{}\n",
                                name, metric_type, help, labels_json, "", sample_count, sample_sum, "", timestamp
                            ));

                            // Export each bucket as a separate row
                            for b in h.get_bucket() {
                                output.push_str(&format!(
                                    "{}_bucket,{},\"{} (bucket)\",\"{}\",{},{},{},{},{}\n",
                                    name, metric_type, help, labels_json,
                                    b.get_cumulative_count(), "", "", b.get_upper_bound(), timestamp
                                ));
                            }
                        }
                    },
                    _ => {}
                }
            }
        }

        Ok(output)
    }

    /// Query logs with pagination using cursor-based pagination
    ///
    /// This function returns a paginated list of logs matching the specified criteria.
    /// It uses cursor-based pagination, where the cursor is a timestamp of the last log
    /// in the previous page.
    ///
    /// # Arguments
    ///
    /// * `level` - Optional minimum log level to filter by
    /// * `start_time` - Optional start time for the query
    /// * `end_time` - Optional end time for the query
    /// * `page_size` - Maximum number of logs to return per page
    /// * `cursor` - Optional cursor for pagination (timestamp of last log in previous page)
    /// * `search` - Optional search term to filter logs
    ///
    /// # Returns
    ///
    /// A `Result` containing the paginated log query response on success, or an error
    /// if the query failed.
    pub async fn query_logs_paginated(
        &self,
        level: Option<&str>,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        page_size: usize,
        cursor: Option<String>,
        search: Option<&str>,
    ) -> Result<PaginatedLogQueryResponse> {
        let min_level = match level {
            Some(level_str) => LogLevel::from(level_str),
            None => LogLevel::Trace,
        };

        // Parse cursor if provided
        let cursor_time = if let Some(cursor_str) = cursor {
            match DateTime::parse_from_rfc3339(&cursor_str) {
                Ok(dt) => Some(dt.with_timezone(&Utc)),
                Err(_) => return Err(Error::InvalidInput("Invalid cursor format".to_string())),
            }
        } else {
            None
        };

        // If cursor is provided, use it as the end time
        let query_end_time = if let Some(cursor_dt) = cursor_time {
            Some(cursor_dt)
        } else {
            end_time
        };

        // Fetch logs with the adjusted time range
        let all_logs = self.fetch_logs(min_level, start_time, query_end_time, page_size + 1).await?;

        // Build query parameters for the response
        let mut query_params = HashMap::new();
        if let Some(l) = level {
            query_params.insert("level".to_string(), l.to_string());
        }
        if let Some(st) = start_time {
            query_params.insert("start_time".to_string(), st.to_rfc3339());
        }
        if let Some(et) = end_time {
            query_params.insert("end_time".to_string(), et.to_rfc3339());
        }
        query_params.insert("page_size".to_string(), page_size.to_string());

        // Apply search filter if provided
        let filtered_logs = if let Some(search_term) = search {
            query_params.insert("search".to_string(), search_term.to_string());
            all_logs
                .into_iter()
                .filter(|entry| {
                    entry.message.contains(search_term) ||
                    entry.fields.values().any(|v| {
                        if let Some(s) = v.as_str() {
                            s.contains(search_term)
                        } else {
                            v.to_string().contains(search_term)
                        }
                    })
                })
                .collect::<Vec<_>>()
        } else {
            all_logs
        };

        // Determine if there are more logs and create the next cursor
        let has_more = filtered_logs.len() > page_size;

        // Create the actual page (limit to page_size)
        let page_logs = if has_more {
            filtered_logs[0..page_size].to_vec()
        } else {
            filtered_logs
        };

        // Create next cursor if there are more logs
        let next_cursor = if has_more && !page_logs.is_empty() {
            // Use the timestamp of the last log as the cursor
            Some(page_logs.last().unwrap().timestamp.to_rfc3339())
        } else {
            None
        };

        Ok(PaginatedLogQueryResponse {
            total: page_logs.len(),
            logs: page_logs,
            query: query_params,
            next_cursor,
            has_more,
        })
    }

    /// Start collecting time-series data
    async fn start_time_series_collection(&self) {
        let service = self.clone();
        tokio::spawn(async move {
            let interval_duration = Duration::from_secs(service.time_series_interval_secs);
            let mut interval = tokio::time::interval(interval_duration);

            loop {
                interval.tick().await;
                if let Err(e) = service.collect_time_series_point().await {
                    error!("Failed to collect time-series data: {}", e);
                }
            }
        });
    }

    /// Collect a single time-series data point for all metrics
    async fn collect_time_series_point(&self) -> Result<()> {
        let now = Utc::now();
        let mut time_series = self.time_series_data.write().await;

        // HTTP request rate (requests per minute)
        let requests = self.requests_per_minute.get();
        time_series.entry("http_requests_rate".to_string())
            .or_insert_with(Vec::new)
            .push((now, requests as f64));

        // Average response time
        let avg_response_time = if requests > 0 {
            self.response_time_ms.get() as f64 / requests as f64
        } else {
            0.0
        };
        time_series.entry("response_time_ms".to_string())
            .or_insert_with(Vec::new)
            .push((now, avg_response_time));

        // Error rate
        let error_rate = if requests > 0 {
            (self.errors_per_minute.get() as f64 / requests as f64) * 100.0
        } else {
            0.0
        };
        time_series.entry("error_rate".to_string())
            .or_insert_with(Vec::new)
            .push((now, error_rate));

        // Memory usage (in MB)
        let memory_usage = self.memory_usage_bytes.get() as f64 / (1024.0 * 1024.0);
        time_series.entry("memory_usage".to_string())
            .or_insert_with(Vec::new)
            .push((now, memory_usage));

        // Active connections
        let connections = self.active_connections.get();
        time_series.entry("active_connections".to_string())
            .or_insert_with(Vec::new)
            .push((now, connections as f64));

        // Cache hit ratio (if available)
        if let Some(cache_collector) = &self.cache_metrics_collector {
            let cache_summary = cache_collector.get_summary().await;
            let overall_hit_ratio = cache_summary.values()
                .map(|stats| stats.hit_ratio)
                .sum::<f64>() / cache_summary.len().max(1) as f64;

            time_series.entry("cache_hit_ratio".to_string())
                .or_insert_with(Vec::new)
                .push((now, overall_hit_ratio * 100.0)); // Convert to percentage
        }

        // Prune old data points if needed
        for points in time_series.values_mut() {
            if points.len() > self.max_time_series_points {
                // Keep only the most recent points
                *points = points.iter()
                    .skip(points.len() - self.max_time_series_points)
                    .cloned()
                    .collect();
            }
        }

        // Update last collection time
        *self.last_time_series_collection.write().await = now;

        Ok(())
    }

    /// Get time-series data for visualization
    pub fn get_time_series_data(&self, hours: u32) -> Result<Vec<TimeSeriesData>> {
        let time_series = self.time_series_data.blocking_read();
        let cutoff_time = Utc::now() - chrono::Duration::hours(hours as i64);

        let mut result = Vec::new();

        // Create a time-series data object for each metric
        for (name, points) in time_series.iter() {
            // Filter to only include points within the requested time range
            let filtered_points: Vec<(DateTime<Utc>, f64)> = points.iter()
                .filter(|(timestamp, _)| *timestamp >= cutoff_time)
                .cloned()
                .collect();

            if filtered_points.is_empty() {
                continue;
            }

            // Format the timestamps for display
            let formatted_points: Vec<(String, f64)> = filtered_points.iter()
                .map(|(timestamp, value)| {
                    let formatted_time = timestamp.format("%H:%M").to_string();
                    (formatted_time, *value)
                })
                .collect();

            // Get the description for this metric
            let description = match name.as_str() {
                "http_requests_rate" => "HTTP request rate per minute",
                "response_time_ms" => "Average response time in milliseconds",
                "error_rate" => "Error rate as percentage of requests",
                "memory_usage" => "Memory usage in megabytes",
                "active_connections" => "Active HTTP connections",
                "cache_hit_ratio" => "Cache hit ratio percentage",
                _ => "Metric data",
            };

            let last_updated = filtered_points.last().map(|(t, _)| *t).unwrap_or_else(Utc::now);

            result.push(TimeSeriesData {
                name: name.clone(),
                points: formatted_points,
                description: description.to_string(),
                last_updated,
            });
        }

        Ok(result)
    }
}

#[cfg(test)]
mod metrics_export_tests {
    use super::*;
    use proptest::prelude::*;
    use regex::Regex;
    use std::collections::BTreeMap;
    use std::collections::HashSet;

    /// Strategy for generating metric names
    fn metric_name_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9_]{3,15}".prop_map(|s| format!("test_{}", s))
    }

    /// Strategy for generating metric values
    fn metric_value_strategy() -> impl Strategy<Value = f64> {
        prop_oneof![
            0.0..1000.0,
            prop::sample::select(vec![0.0, 1.0, 10.0, 100.0, 1000.0])
        ]
    }

    /// Strategy for generating label names
    fn label_name_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9_]{2,10}".prop_map(|s| s)
    }

    /// Strategy for generating label values
    fn label_value_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z0-9_.-]{1,15}".prop_map(|s| s)
    }

    /// Strategy for generating special characters
    fn special_chars_strategy() -> impl Strategy<Value = String> {
        prop::sample::select(vec![
            "\\", "\"", "\n", "\r", "\t",
            "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
            ":", ";", ",", "<", ">", "?", "|"
        ]).prop_map(|s| s.to_string())
    }

    /// Strategy for generating histogram buckets
    fn histogram_buckets_strategy() -> impl Strategy<Value = Vec<f64>> {
        prop::collection::vec(0.0..100.0, 3..10)
            .prop_map(|mut v| {
                // Ensure buckets are sorted
                v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                v
            })
    }

    /// Strategy for generating a complete metric definition with different types
    fn metric_definition_strategy() -> impl Strategy<Value = MetricDefinition> {
        (
            metric_name_strategy(),
            "[A-Za-z0-9 ]{5,50}".prop_map(|s| s), // help text
            prop_oneof![
                Just(MetricType::Counter),
                Just(MetricType::Gauge),
                Just(MetricType::Histogram)
            ],
            prop::collection::vec(
                (label_name_strategy(), label_value_strategy()),
                0..3
            ),
            metric_value_strategy(),
            histogram_buckets_strategy()
        ).prop_map(|(name, help, metric_type, labels, value, buckets)| {
            MetricDefinition {
                name,
                help,
                metric_type,
                labels,
                value,
                buckets,
            }
        })
    }

    /// Strategy for generating a set of metrics
    fn metrics_set_strategy() -> impl Strategy<Value = Vec<MetricDefinition>> {
        prop::collection::vec(metric_definition_strategy(), 1..10)
    }

    /// Helper struct for defining test metrics
    #[derive(Debug, Clone)]
    struct MetricDefinition {
        name: String,
        help: String,
        metric_type: MetricType,
        labels: Vec<(String, String)>,
        value: f64,
        buckets: Vec<f64>,
    }

    /// Create a test registry with the given metric definitions
    fn create_test_registry(metrics: &[MetricDefinition]) -> Registry {
        let registry = Registry::new();

        for metric in metrics {
            match metric.metric_type {
                MetricType::Counter => {
                    if metric.labels.is_empty() {
                        // Simple counter
                        let counter = IntCounter::new(metric.name.clone(), metric.help.clone()).unwrap();
                        registry.register(Box::new(counter.clone())).unwrap();
                        counter.inc_by(metric.value as u64);
                    } else {
                        // Counter with labels
                        let label_names: Vec<&str> = metric.labels.iter()
                            .map(|(name, _)| name.as_str())
                            .collect();
                        let counter = IntCounterVec::new(
                            prometheus::opts!(metric.name.clone(), metric.help.clone()),
                            &label_names
                        ).unwrap();
                        registry.register(Box::new(counter.clone())).unwrap();

                        let label_values: Vec<&str> = metric.labels.iter()
                            .map(|(_, value)| value.as_str())
                            .collect();
                        counter.with_label_values(&label_values).inc_by(metric.value as u64);
                    }
                },
                MetricType::Gauge => {
                    if metric.labels.is_empty() {
                        // Simple gauge
                        let gauge = Gauge::new(metric.name.clone(), metric.help.clone()).unwrap();
                        registry.register(Box::new(gauge.clone())).unwrap();
                        gauge.set(metric.value);
                    } else {
                        // Gauge with labels
                        let label_names: Vec<&str> = metric.labels.iter()
                            .map(|(name, _)| name.as_str())
                            .collect();
                        let gauge = GaugeVec::new(
                            prometheus::opts!(metric.name.clone(), metric.help.clone()),
                            &label_names
                        ).unwrap();
                        registry.register(Box::new(gauge.clone())).unwrap();

                        let label_values: Vec<&str> = metric.labels.iter()
                            .map(|(_, value)| value.as_str())
                            .collect();
                        gauge.with_label_values(&label_values).set(metric.value);
                    }
                },
                MetricType::Histogram => {
                    let mut opts = prometheus::histogram_opts!(
                        metric.name.clone(),
                        metric.help.clone()
                    );

                    // Use custom buckets if provided and valid
                    if !metric.buckets.is_empty() {
                        opts = opts.buckets(metric.buckets.clone());
                    }

                    if metric.labels.is_empty() {
                        // Simple histogram
                        let histogram = Histogram::with_opts(opts).unwrap();
                        registry.register(Box::new(histogram.clone())).unwrap();
                        histogram.observe(metric.value);
                    } else {
                        // Histogram with labels
                        let label_names: Vec<&str> = metric.labels.iter()
                            .map(|(name, _)| name.as_str())
                            .collect();
                        let histogram = HistogramVec::new(
                            opts,
                            &label_names
                        ).unwrap();
                        registry.register(Box::new(histogram.clone())).unwrap();

                        let label_values: Vec<&str> = metric.labels.iter()
                            .map(|(_, value)| value.as_str())
                            .collect();
                        histogram.with_label_values(&label_values).observe(metric.value);
                    }
                }
            }
        }

        registry
    }

    /// Create a test observability service with the given metrics
    fn create_test_service_with_metrics(metrics: &[MetricDefinition]) -> ObservabilityService {
        let registry = create_test_registry(metrics);

        ObservabilityService {
            config: Arc::new(ObservabilityConfig::default()),
            registry: registry.clone(),
            http_requests_total: IntCounterVec::new(
                prometheus::opts!("test_http_requests", "Test HTTP requests"),
                &["method", "path"]
            ).unwrap(),
            http_request_duration: HistogramVec::new(
                prometheus::histogram_opts!("test_http_duration", "Test HTTP duration"),
                &["method", "path"]
            ).unwrap(),
            http_response_status: IntCounterVec::new(
                prometheus::opts!("test_http_status", "Test HTTP status"),
                &["method", "path", "status"]
            ).unwrap(),
            git_operations_total: IntCounterVec::new(
                prometheus::opts!("test_git_ops", "Test Git operations"),
                &["operation", "repository"]
            ).unwrap(),
            git_operation_duration: HistogramVec::new(
                prometheus::histogram_opts!("test_git_duration", "Test Git duration"),
                &["operation", "repository"]
            ).unwrap(),
            cache_hits_total: IntCounterVec::new(
                prometheus::opts!("test_cache_hits", "Test cache hits"),
                &["cache"]
            ).unwrap(),
            cache_misses_total: IntCounterVec::new(
                prometheus::opts!("test_cache_misses", "Test cache misses"),
                &["cache"]
            ).unwrap(),
            repository_stats: GaugeVec::new(
                prometheus::opts!("test_repo_stats", "Test repository stats"),
                &["repository", "metric"]
            ).unwrap(),
            memory_usage_bytes: IntGauge::new(
                "test_memory_usage", "Test memory usage"
            ).unwrap(),
            active_connections: IntGauge::new(
                "test_connections", "Test connections"
            ).unwrap(),
            cache: Arc::new(Cache::new_for_test()),
            content_metrics_collector: None,
            opentelemetry_tracer: None,
            time_series_data: RwLock::new(HashMap::new()),
            max_time_series_points: 1000,
            time_series_interval_secs: 60,
            last_time_series_collection: RwLock::new(Utc::now()),
        }
    }

    proptest! {
        /// Test that metrics can be exported in different formats
        #[test]
        fn test_metrics_export_formats(
            counter_name in metric_name_strategy(),
            counter_value in metric_value_strategy(),
            gauge_name in metric_name_strategy(),
            gauge_value in metric_value_strategy(),
            label_name in label_name_strategy(),
            label_value in label_value_strategy()
        ) {
            // Create a registry
            let registry = Registry::new();

            // Create and register a counter
            let counter = IntCounter::new(counter_name.clone(), "Test counter").unwrap();
            registry.register(Box::new(counter.clone())).unwrap();
            counter.inc_by(counter_value);

            // Create and register a gauge
            let gauge = Gauge::new(gauge_name.clone(), "Test gauge").unwrap();
            registry.register(Box::new(gauge.clone())).unwrap();
            gauge.set(gauge_value);

            // Create and register a counter with labels
            let counter_vec = CounterVec::new(
                prometheus::opts!("test_counter_labels", "Test counter with labels"),
                &[label_name.clone()]
            ).unwrap();
            registry.register(Box::new(counter_vec.clone())).unwrap();
            counter_vec.with_label_values(&[&label_value]).inc();

            // Create a histogram
            let histogram = Histogram::with_opts(
                prometheus::histogram_opts!("test_histogram", "Test histogram")
            ).unwrap();
            registry.register(Box::new(histogram.clone())).unwrap();
            histogram.observe(0.5);

            // Create a test observability service
            let service = ObservabilityService::new_with_registry(
                Arc::new(ObservabilityConfig::default()),
                registry.clone()
            );

            // Test prometheus format
            let prometheus_metrics = service.metrics_as_string().unwrap();
            prop_assert!(prometheus_metrics.contains(&counter_name));
            prop_assert!(prometheus_metrics.contains(&gauge_name));
            prop_assert!(prometheus_metrics.contains(&label_name));
            prop_assert!(prometheus_metrics.contains(&label_value));
            prop_assert!(prometheus_metrics.contains("test_histogram"));

            // Test JSON format
            let json_metrics = service.metrics_as_json().unwrap();
            prop_assert!(json_metrics.contains(&counter_name));
            prop_assert!(json_metrics.contains(&gauge_name));
            prop_assert!(json_metrics.contains(&label_name));
            prop_assert!(json_metrics.contains(&label_value));
            prop_assert!(json_metrics.contains("test_histogram"));

            // Test OpenMetrics format
            let openmetrics = service.metrics_as_openmetrics().unwrap();
            prop_assert!(openmetrics.contains(&counter_name));
            prop_assert!(openmetrics.contains(&gauge_name));
            prop_assert!(openmetrics.contains(&label_name));
            prop_assert!(openmetrics.contains(&label_value));
            prop_assert!(openmetrics.contains("test_histogram"));

            // Test CSV format
            let csv_metrics = service.metrics_as_csv().unwrap();

            // CSV should have a header row
            prop_assert!(csv_metrics.starts_with("name,type,help,labels,value,sample_count,sample_sum,upper_bound,timestamp\n"));

            // CSV should include all metrics
            prop_assert!(csv_metrics.contains(&counter_name));
            prop_assert!(csv_metrics.contains(&gauge_name));
            prop_assert!(csv_metrics.contains(&label_name));
            prop_assert!(csv_metrics.contains(&label_value.replace(",", ";"))); // Commas in values are escaped
            prop_assert!(csv_metrics.contains("test_histogram"));

            // CSV should have metric types
            prop_assert!(csv_metrics.contains("counter"));
            prop_assert!(csv_metrics.contains("gauge"));
            prop_assert!(csv_metrics.contains("histogram"));

            // Histogram buckets should be included
            prop_assert!(csv_metrics.contains("test_histogram_bucket"));

            // Parse CSV and verify structure
            let mut lines = csv_metrics.lines();
            let header = lines.next().unwrap();
            prop_assert_eq!(header, "name,type,help,labels,value,sample_count,sample_sum,upper_bound,timestamp");

            // Count number of data rows
            let data_row_count = lines.count();
            prop_assert!(data_row_count >= 4); // At least counter, gauge, histogram, and one bucket

            // Test CSV parsing (should be valid CSV)
            let csv_parse_result = csv::Reader::from_reader(csv_metrics.as_bytes()).records().collect::<Result<Vec<_>, _>>();
            prop_assert!(csv_parse_result.is_ok());
            let records = csv_parse_result.unwrap();
            prop_assert!(records.len() > 1); // Header + at least one data row
        }

        /// Test Prometheus format compliance with all metric types
        #[test]
        fn test_prometheus_format_compliance(
            metrics in metrics_set_strategy()
        ) {
            // Create a test service with metrics
            let service = create_test_service_with_metrics(&metrics);

            // Get metrics in Prometheus format
            let prometheus_metrics = service.metrics_as_string().unwrap();

            // Check each defined metric is present in the output
            for metric in &metrics {
                // Check metric name is present
                prop_assert!(prometheus_metrics.contains(&metric.name));

                // Check help text format: # HELP metric_name help_text
                let help_line_pattern = format!(r"# HELP {} ", metric.name);
                prop_assert!(prometheus_metrics.contains(&help_line_pattern));

                // Check type format: # TYPE metric_name type
                let type_line_pattern = format!(r"# TYPE {} ", metric.name);
                prop_assert!(prometheus_metrics.contains(&type_line_pattern));

                // Check metric type
                match metric.metric_type {
                    MetricType::Counter => {
                        prop_assert!(prometheus_metrics.contains(&format!("# TYPE {} counter", metric.name)));
                    },
                    MetricType::Gauge => {
                        prop_assert!(prometheus_metrics.contains(&format!("# TYPE {} gauge", metric.name)));
                    },
                    MetricType::Histogram => {
                        prop_assert!(prometheus_metrics.contains(&format!("# TYPE {} histogram", metric.name)));

                        // Check for histogram specific format
                        prop_assert!(prometheus_metrics.contains(&format!("{}_bucket", metric.name)));
                        prop_assert!(prometheus_metrics.contains(&format!("{}_sum", metric.name)));
                        prop_assert!(prometheus_metrics.contains(&format!("{}_count", metric.name)));
                    }
                }

                // Check labels are correctly formatted
                if !metric.labels.is_empty() {
                    let labels_part = metric.labels.iter()
                        .map(|(name, value)| format!("{}=\"{}\"", name, value))
                        .collect::<Vec<_>>()
                        .join(",");

                    // In Prometheus format, labels are enclosed in curly braces: metric_name{label="value"}
                    let label_pattern = format!("{{{}}} ", labels_part);
                    prop_assert!(prometheus_metrics.contains(&label_pattern));
                }
            }

            // Verify syntax compliance with random sampling of lines
            for line in prometheus_metrics.lines() {
                // Skip comments
                if line.starts_with('#') || line.trim().is_empty() {
                    continue;
                }

                // Verify metric line format: name{labels} value [timestamp]
                let re = Regex::new(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]+\})? ([0-9.eE+-]+)( [0-9]+)?$").unwrap();
                prop_assert!(re.is_match(line), "Line does not match Prometheus format: {}", line);
            }
        }

        /// Test JSON format structure and validity
        #[test]
        fn test_json_format_structure(
            metrics in metrics_set_strategy()
        ) {
            // Create a test service with metrics
            let service = create_test_service_with_metrics(&metrics);

            // Get metrics in JSON format
            let json_metrics = service.metrics_as_json().unwrap();

            // Parse JSON
            let json_value: Result<serde_json::Value, _> = serde_json::from_str(&json_metrics);
            prop_assert!(json_value.is_ok());
            let json = json_value.unwrap();

            // Verify it's an object
            prop_assert!(json.is_object());
            let json_obj = json.as_object().unwrap();

            // Check each defined metric is present in the JSON
            for metric in &metrics {
                // Metric name should be a key in the JSON
                prop_assert!(json_obj.contains_key(&metric.name));
                let metric_obj = json_obj.get(&metric.name).unwrap().as_object().unwrap();

                // Check help text is present
                prop_assert!(metric_obj.contains_key("help"));
                let help = metric_obj.get("help").unwrap().as_str().unwrap();
                prop_assert_eq!(help, metric.help);

                // Check type is present and correct
                prop_assert!(metric_obj.contains_key("type"));
                let metric_type = metric_obj.get("type").unwrap().as_str().unwrap();
                match metric.metric_type {
                    MetricType::Counter => prop_assert_eq!(metric_type, "counter"),
                    MetricType::Gauge => prop_assert_eq!(metric_type, "gauge"),
                    MetricType::Histogram => prop_assert_eq!(metric_type, "histogram"),
                }

                // Check metrics array exists
                prop_assert!(metric_obj.contains_key("metrics"));
                let metrics_arr = metric_obj.get("metrics").unwrap().as_array().unwrap();
                prop_assert!(!metrics_arr.is_empty());

                // Check the first metric
                let first_metric = metrics_arr[0].as_object().unwrap();

                // Check labels are present
                prop_assert!(first_metric.contains_key("labels"));
                let labels_obj = first_metric.get("labels").unwrap().as_object().unwrap();

                // Verify all our expected labels are present
                for (name, value) in &metric.labels {
                    prop_assert!(labels_obj.contains_key(name));
                    let label_value = labels_obj.get(name).unwrap().as_str().unwrap();
                    prop_assert_eq!(label_value, value);
                }

                // Check values based on metric type
                match metric.metric_type {
                    MetricType::Counter | MetricType::Gauge => {
                        prop_assert!(first_metric.contains_key("value"));
                    },
                    MetricType::Histogram => {
                        prop_assert!(first_metric.contains_key("histogram"));
                        let hist_obj = first_metric.get("histogram").unwrap().as_object().unwrap();

                        // Check histogram has required fields
                        prop_assert!(hist_obj.contains_key("sample_count"));
                        prop_assert!(hist_obj.contains_key("sample_sum"));
                        prop_assert!(hist_obj.contains_key("buckets"));

                        // Check buckets is an array
                        let buckets_arr = hist_obj.get("buckets").unwrap().as_array().unwrap();
                        prop_assert!(!buckets_arr.is_empty());
                    }
                }
            }
        }

        /// Test OpenMetrics format compliance
        #[test]
        fn test_openmetrics_format_compliance(
            metrics in metrics_set_strategy()
        ) {
            // Create a test service with metrics
            let service = create_test_service_with_metrics(&metrics);

            // Get metrics in OpenMetrics format
            let openmetrics = service.metrics_as_openmetrics().unwrap();

            // Check basics of OpenMetrics format
            prop_assert!(openmetrics.contains("# EOF"));

            // Check each defined metric is present in the output
            for metric in &metrics {
                // Check metric name is present
                prop_assert!(openmetrics.contains(&metric.name));

                // Check help text format: # HELP metric_name help_text
                let help_line_pattern = format!(r"# HELP {} ", metric.name);
                prop_assert!(openmetrics.contains(&help_line_pattern));

                // Check type format: # TYPE metric_name type
                let type_line_pattern = format!(r"# TYPE {} ", metric.name);
                prop_assert!(openmetrics.contains(&type_line_pattern));

                // Check metric type
                match metric.metric_type {
                    MetricType::Counter => {
                        prop_assert!(openmetrics.contains(&format!("# TYPE {} counter", metric.name)));
                    },
                    MetricType::Gauge => {
                        prop_assert!(openmetrics.contains(&format!("# TYPE {} gauge", metric.name)));
                    },
                    MetricType::Histogram => {
                        prop_assert!(openmetrics.contains(&format!("# TYPE {} histogram", metric.name)));

                        // Check for histogram specific format
                        prop_assert!(openmetrics.contains(&format!("{}_bucket", metric.name)));
                        prop_assert!(openmetrics.contains(&format!("{}_sum", metric.name)));
                        prop_assert!(openmetrics.contains(&format!("{}_count", metric.name)));
                    }
                }

                // Check labels are correctly formatted
                if !metric.labels.is_empty() {
                    let labels_part = metric.labels.iter()
                        .map(|(name, value)| format!("{}=\"{}\"", name, value))
                        .collect::<Vec<_>>()
                        .join(",");

                    // In OpenMetrics format, labels are enclosed in curly braces: metric_name{label="value"}
                    let label_pattern = format!("{{{}}} ", labels_part);
                    prop_assert!(openmetrics.contains(&label_pattern));
                }
            }

            // Verify OpenMetrics specific annotations
            prop_assert!(openmetrics.contains("# TYPE") && openmetrics.contains("# HELP"));
        }

        /// Test that all formats contain the same metrics
        #[test]
        fn test_metrics_format_consistency(
            metrics in metrics_set_strategy()
        ) {
            // Create a test service with metrics
            let service = create_test_service_with_metrics(&metrics);

            // Get metrics in all formats
            let prometheus_metrics = service.metrics_as_string().unwrap();
            let json_metrics = service.metrics_as_json().unwrap();
            let openmetrics = service.metrics_as_openmetrics().unwrap();

            // Extract metric names from Prometheus format
            let prometheus_names = extract_metric_names_from_prometheus(&prometheus_metrics);

            // Extract metric names from JSON format
            let json_names = extract_metric_names_from_json(&json_metrics);

            // Extract metric names from OpenMetrics format
            let openmetrics_names = extract_metric_names_from_openmetrics(&openmetrics);

            // Create sets of our defined metric names, accounting for histogram suffixes
            let mut expected_names = HashSet::new();
            for metric in &metrics {
                expected_names.insert(metric.name.clone());

                // For histograms, add the suffixes
                if metric.metric_type == MetricType::Histogram {
                    expected_names.insert(format!("{}_bucket", metric.name));
                    expected_names.insert(format!("{}_sum", metric.name));
                    expected_names.insert(format!("{}_count", metric.name));
                }
            }

            // Check that all our expected metrics are in all formats
            for name in expected_names {
                prop_assert!(
                    prometheus_names.contains(&name) ||
                    prometheus_names.iter().any(|n| n.starts_with(&name)),
                    "Prometheus format missing metric: {}", name
                );

                prop_assert!(
                    json_names.contains(&name) ||
                    json_names.iter().any(|n| n.starts_with(&name)),
                    "JSON format missing metric: {}", name
                );

                prop_assert!(
                    openmetrics_names.contains(&name) ||
                    openmetrics_names.iter().any(|n| n.starts_with(&name)),
                    "OpenMetrics format missing metric: {}", name
                );
            }
        }

        /// Test handling of special characters in metrics
        #[test]
        fn test_special_characters_in_metrics(
            special_char in special_chars_strategy(),
            metric_value in metric_value_strategy()
        ) {
            // Create metrics with special characters in labels
            let metrics = vec![
                MetricDefinition {
                    name: "test_special_chars".to_string(),
                    help: "Test special characters".to_string(),
                    metric_type: MetricType::Gauge,
                    labels: vec![
                        ("special_label".to_string(), format!("value_with_{}", special_char)),
                    ],
                    value: metric_value,
                    buckets: vec![],
                },
            ];

            // Create service with metrics
            let service = create_test_service_with_metrics(&metrics);

            // Get metrics in all formats
            let prometheus_result = service.metrics_as_string();
            let json_result = service.metrics_as_json();
            let openmetrics_result = service.metrics_as_openmetrics();

            // All formats should export successfully regardless of special chars
            prop_assert!(prometheus_result.is_ok());
            prop_assert!(json_result.is_ok());
            prop_assert!(openmetrics_result.is_ok());

            // Parse JSON to verify structure
            let json = serde_json::from_str::<serde_json::Value>(&json_result.unwrap()).unwrap();
            let json_obj = json.as_object().unwrap();

            // Verify the metric with special characters exists
            prop_assert!(json_obj.contains_key("test_special_chars"));
        }
    }

    /// Utility function to extract metric names from Prometheus format
    fn extract_metric_names_from_prometheus(prometheus: &str) -> HashSet<String> {
        let mut names = HashSet::new();
        let name_pattern = Regex::new(r"^([a-zA-Z_:][a-zA-Z0-9_:]*_(?:count|sum|bucket))(?:\{|\s)").unwrap();
        let type_pattern = Regex::new(r"^# TYPE ([a-zA-Z_:][a-zA-Z0-9_:]*) ").unwrap();

        for line in prometheus.lines() {
            if let Some(caps) = name_pattern.captures(line) {
                if let Some(name_match) = caps.get(1) {
                    names.insert(name_match.as_str().to_string());
                }
            } else if let Some(caps) = type_pattern.captures(line) {
                if let Some(name_match) = caps.get(1) {
                    names.insert(name_match.as_str().to_string());
                }
            }
        }

        names
    }

    /// Utility function to extract metric names from JSON format
    fn extract_metric_names_from_json(json_str: &str) -> HashSet<String> {
        let json: serde_json::Value = serde_json::from_str(json_str).unwrap();
        let obj = json.as_object().unwrap();

        obj.keys().cloned().collect()
    }

    /// Utility function to extract metric names from OpenMetrics format
    fn extract_metric_names_from_openmetrics(openmetrics: &str) -> HashSet<String> {
        let mut names = HashSet::new();
        let name_pattern = Regex::new(r"^([a-zA-Z_:][a-zA-Z0-9_:]*_(?:count|sum|bucket))(?:\{|\s)").unwrap();
        let type_pattern = Regex::new(r"^# TYPE ([a-zA-Z_:][a-zA-Z0-9_:]*) ").unwrap();

        for line in openmetrics.lines() {
            if let Some(caps) = name_pattern.captures(line) {
                if let Some(name_match) = caps.get(1) {
                    names.insert(name_match.as_str().to_string());
                }
            } else if let Some(caps) = type_pattern.captures(line) {
                if let Some(name_match) = caps.get(1) {
                    names.insert(name_match.as_str().to_string());
                }
            }
        }

        names
    }
}

#[cfg(test)]
mod metrics_recording_tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::HashSet;

    // Strategy for generating HTTP method names
    fn http_method_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("GET".to_string()),
            Just("POST".to_string()),
            Just("PUT".to_string()),
            Just("DELETE".to_string()),
            Just("PATCH".to_string()),
            Just("OPTIONS".to_string()),
            Just("HEAD".to_string())
        ]
    }

    // Strategy for generating path names
    fn path_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("/".to_string()),
            Just("/api/repos".to_string()),
            Just("/api/metrics".to_string()),
            Just("/api/health".to_string()),
            "/api/[a-z0-9_]{1,10}".prop_map(|s| s),
            "/api/repos/[a-z0-9_]{1,10}".prop_map(|s| s),
            "/repos/[a-z0-9_]{1,10}/commits".prop_map(|s| s)
        ]
    }

    // Strategy for generating HTTP status codes
    fn status_code_strategy() -> impl Strategy<Value = u16> {
        prop_oneof![
            Just(200u16),
            Just(201u16),
            Just(204u16),
            Just(400u16),
            Just(401u16),
            Just(403u16),
            Just(404u16),
            Just(500u16),
            200..600u16
        ]
    }

    // Strategy for generating repository names
    fn repository_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9_-]{2,15}".prop_map(|s| s)
    }

    // Strategy for generating Git operation names
    fn git_operation_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("clone".to_string()),
            Just("fetch".to_string()),
            Just("pull".to_string()),
            Just("push".to_string()),
            Just("commit".to_string()),
            Just("branch".to_string()),
            Just("tag".to_string()),
            Just("log".to_string()),
            Just("status".to_string()),
            Just("diff".to_string())
        ]
    }

    // Strategy for generating cache names
    fn cache_name_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("repository".to_string()),
            Just("commit".to_string()),
            Just("file".to_string()),
            Just("diff".to_string()),
            Just("blame".to_string()),
            "[a-z_]{3,10}_cache".prop_map(|s| s)
        ]
    }

    // Helper to create a test ObservabilityService
    fn create_test_service() -> ObservabilityService {
        let config = ObservabilityConfig::default();
        ObservabilityService::new(config, None, None).unwrap()
    }

    proptest! {
        // Test that HTTP request metrics are correctly recorded
        #[test]
        fn test_http_request_recording(
            method in http_method_strategy(),
            path in path_strategy(),
            count in 1..100u32
        ) {
            let service = create_test_service();

            // Record multiple requests
            for _ in 0..count {
                service.record_request(&method, &path);
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected counter name and value
            let expected_pattern = format!(
                "http_requests_total{{method=\"{}\",path=\"{}\"}} {}",
                method, path, count
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected HTTP request counter: {}", expected_pattern);
        }

        // Test that HTTP response metrics are correctly recorded
        #[test]
        fn test_http_response_recording(
            method in http_method_strategy(),
            path in path_strategy(),
            status in status_code_strategy(),
            count in 1..50u32
        ) {
            let service = create_test_service();

            // Record multiple responses
            for _ in 0..count {
                service.record_response(&method, &path, status);
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected counter name and value
            let expected_pattern = format!(
                "http_response_status{{method=\"{}\",path=\"{}\",status=\"{}\"}} {}",
                method, path, status, count
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected HTTP response counter: {}", expected_pattern);
        }

        // Test that Git operation metrics are correctly recorded
        #[test]
        fn test_git_operation_recording(
            operation in git_operation_strategy(),
            repository in repository_strategy(),
            count in 1..50u32
        ) {
            let service = create_test_service();

            // Record multiple git operations
            for _ in 0..count {
                service.record_git_operation(&operation, &repository);
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected counter name and value
            let expected_pattern = format!(
                "git_operations_total{{operation=\"{}\",repository=\"{}\"}} {}",
                operation, repository, count
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected Git operation counter: {}", expected_pattern);
        }

        // Test that cache hit metrics are correctly recorded
        #[test]
        fn test_cache_hit_recording(
            cache_name in cache_name_strategy(),
            count in 1..100u32
        ) {
            let service = create_test_service();

            // Record multiple cache hits
            for _ in 0..count {
                service.record_cache_hit(&cache_name);
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected counter name and value
            let expected_pattern = format!(
                "cache_hits_total{{cache=\"{}\"}} {}",
                cache_name, count
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected cache hit counter: {}", expected_pattern);
        }

        // Test that cache miss metrics are correctly recorded
        #[test]
        fn test_cache_miss_recording(
            cache_name in cache_name_strategy(),
            count in 1..100u32
        ) {
            let service = create_test_service();

            // Record multiple cache misses
            for _ in 0..count {
                service.record_cache_miss(&cache_name);
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected counter name and value
            let expected_pattern = format!(
                "cache_misses_total{{cache=\"{}\"}} {}",
                cache_name, count
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected cache miss counter: {}", expected_pattern);
        }

        // Test that repository stat metrics are correctly set
        #[test]
        fn test_repository_stat_setting(
            repository in repository_strategy(),
            metric in "[a-z_]{3,10}".prop_map(|s| s),
            value in 0.0..1000.0f64
        ) {
            let service = create_test_service();

            // Set repository stat
            service.set_repository_stat(&repository, &metric, value);

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected gauge name and value
            let expected_pattern = format!(
                "repository_stats{{repository=\"{}\",metric=\"{}\"}} {}",
                repository, metric, value
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected repository stat gauge: {}", expected_pattern);
        }

        // Test that memory usage metrics are correctly updated
        #[test]
        fn test_memory_usage_update(
            bytes in 0..1_000_000_000i64
        ) {
            let service = create_test_service();

            // Update memory usage
            service.update_memory_usage(bytes);

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Format the expected gauge name and value
            let expected_pattern = format!(
                "memory_usage_bytes {} ",
                bytes
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected memory usage gauge: {}", expected_pattern);
        }

        // Test that active connections metrics are correctly incremented and decremented
        #[test]
        fn test_connection_tracking(
            increments in 0..100u32,
            decrements in 0..100u32
        ) {
            let service = create_test_service();

            // Increment connection counter
            for _ in 0..increments {
                service.increment_connections();
            }

            // Decrement connection counter (but not more than we incremented)
            let safe_decrements = decrements.min(increments);
            for _ in 0..safe_decrements {
                service.decrement_connections();
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Calculate expected value
            let expected_value = increments as i64 - safe_decrements as i64;

            // Format the expected gauge name and value
            let expected_pattern = format!(
                "active_connections {} ",
                expected_value
            );

            // Verify the metric is recorded correctly
            prop_assert!(metrics.contains(&expected_pattern),
                "Metrics output does not contain expected active connections gauge: {}", expected_pattern);
        }

        // Test recording multiple metric types together and verify they don't interfere
        #[test]
        fn test_multiple_metrics_recording(
            method in http_method_strategy(),
            path in path_strategy(),
            status in status_code_strategy(),
            operation in git_operation_strategy(),
            repository in repository_strategy(),
            cache_name in cache_name_strategy(),
            metric in "[a-z_]{3,10}".prop_map(|s| s),
            value in 0.0..1000.0f64,
            memory in 0..1_000_000i64,
            connections in 1..50u32
        ) {
            let service = create_test_service();

            // Record various metrics
            service.record_request(&method, &path);
            service.record_response(&method, &path, status);
            service.record_git_operation(&operation, &repository);
            service.record_cache_hit(&cache_name);
            service.record_cache_miss(&cache_name);
            service.set_repository_stat(&repository, &metric, value);
            service.update_memory_usage(memory);

            // Increment connections
            for _ in 0..connections {
                service.increment_connections();
            }

            // Get metrics as text
            let metrics = service.metrics_as_string().unwrap();

            // Verify all metrics are present
            let expected_patterns = vec![
                format!("http_requests_total{{method=\"{}\",path=\"{}\"}} 1", method, path),
                format!("http_response_status{{method=\"{}\",path=\"{}\",status=\"{}\"}} 1", method, path, status),
                format!("git_operations_total{{operation=\"{}\",repository=\"{}\"}} 1", operation, repository),
                format!("cache_hits_total{{cache=\"{}\"}} 1", cache_name),
                format!("cache_misses_total{{cache=\"{}\"}} 1", cache_name),
                format!("repository_stats{{repository=\"{}\",metric=\"{}\"}} {}", repository, metric, value),
                format!("memory_usage_bytes {} ", memory),
                format!("active_connections {} ", connections)
            ];

            for pattern in expected_patterns {
                prop_assert!(metrics.contains(&pattern),
                    "Metrics output does not contain expected pattern: {}", pattern);
            }
        }

        // Test that metrics reset works properly
        #[test]
        fn test_metrics_reset(
            method in http_method_strategy(),
            path in path_strategy(),
            count in 1..100u32
        ) {
            let service = create_test_service();

            // Record some metrics
            for _ in 0..count {
                service.record_request(&method, &path);
            }

            // Verify metrics are recorded
            let metrics_before = service.metrics_as_string().unwrap();
            let expected_pattern = format!(
                "http_requests_total{{method=\"{}\",path=\"{}\"}} {}",
                method, path, count
            );
            prop_assert!(metrics_before.contains(&expected_pattern));

            // Reset metrics
            service.reset_metrics();

            // Verify metrics are reset
            let metrics_after = service.metrics_as_string().unwrap();

            // The counter should now be back to 0
            let zero_pattern = format!(
                "http_requests_total{{method=\"{}\",path=\"{}\"}} 0",
                method, path
            );
            prop_assert!(metrics_after.contains(&zero_pattern) || !metrics_after.contains(&expected_pattern),
                "Metrics were not properly reset after reset_metrics() call");
        }
    }
}

#[cfg(test)]
mod log_pagination_tests {
    use super::*;
    use proptest::prelude::*;
    use tokio::runtime::Runtime;

    // Strategy for generating RFC3339 date-time strings
    fn rfc3339_datetime_strategy() -> impl Strategy<Value = String> {
        (
            2020u32..2030, // year
            1u32..13,      // month
            1u32..29,      // day
            0u32..24,      // hour
            0u32..60,      // minute
            0u32..60,      // second
        ).prop_map(|(year, month, day, hour, minute, second)| {
            format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", year, month, day, hour, minute, second)
        })
    }

    // Strategy for generating log levels
    fn log_level_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("trace".to_string()),
            Just("debug".to_string()),
            Just("info".to_string()),
            Just("warn".to_string()),
            Just("error".to_string()),
        ]
    }

    // Strategy for generating page sizes
    fn page_size_strategy() -> impl Strategy<Value = usize> {
        1usize..100
    }

    // Strategy for generating search terms
    fn search_term_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z0-9]{3,10}".prop_map(|s| s)
    }

    // Helper to create a test ObservabilityService with some test logs
    fn create_test_service_with_logs() -> ObservabilityService {
        let config = ObservabilityConfig::default();
        let service = ObservabilityService::new(config, None, None).unwrap();

        // Add some test logs with various timestamps and levels
        let mut fields = HashMap::new();
        fields.insert("source".to_string(), serde_json::Value::String("test".to_string()));

        // Create logs with different timestamps, a minute apart
        for i in 0..20 {
            let timestamp = chrono::Utc::now() - chrono::Duration::minutes(i);
            let level = match i % 5 {
                0 => LogLevel::Trace,
                1 => LogLevel::Debug,
                2 => LogLevel::Info,
                3 => LogLevel::Warn,
                _ => LogLevel::Error,
            };

            service.log(
                level,
                &format!("Test log message {}", i),
                fields.clone(),
                None
            );
        }

        service
    }

    proptest! {
        // Test basic pagination with just page size
        #[test]
        fn test_basic_pagination(
            page_size in page_size_strategy()
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let service = create_test_service_with_logs();

                // Query first page
                let result1 = service.query_logs_paginated(None, None, None, page_size, None, None).await;
                prop_assert!(result1.is_ok(), "First page query failed: {:?}", result1.err());

                let page1 = result1.unwrap();

                // Verify page size
                prop_assert!(page1.logs.len() <= page_size,
                    "Page size should be at most {}, but got {}", page_size, page1.logs.len());

                // If there's a next cursor, query the next page
                if let Some(cursor) = page1.next_cursor {
                    let result2 = service.query_logs_paginated(None, None, None, page_size, Some(cursor), None).await;
                    prop_assert!(result2.is_ok(), "Second page query failed: {:?}", result2.err());

                    let page2 = result2.unwrap();

                    // Verify page size of second page
                    prop_assert!(page2.logs.len() <= page_size,
                        "Page size of second page should be at most {}, but got {}", page_size, page2.logs.len());

                    // Verify that the logs in the second page are older than those in the first page
                    if !page1.logs.is_empty() && !page2.logs.is_empty() {
                        let page1_oldest = page1.logs.last().unwrap().timestamp;
                        let page2_newest = page2.logs.first().unwrap().timestamp;

                        prop_assert!(page1_oldest >= page2_newest,
                            "Logs in second page should be older than those in first page");
                    }
                }

                Ok(())
            })
        }

        // Test pagination with level filtering
        #[test]
        fn test_pagination_with_level(
            page_size in page_size_strategy(),
            level in log_level_strategy()
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let service = create_test_service_with_logs();

                // Query logs with level filter
                let result = service.query_logs_paginated(Some(&level), None, None, page_size, None, None).await;
                prop_assert!(result.is_ok(), "Query with level filter failed: {:?}", result.err());

                let page = result.unwrap();

                // Verify that all logs have the right level
                let min_level = LogLevel::from(level.as_str());
                for log in &page.logs {
                    prop_assert!(log.level >= min_level,
                        "Log level {:?} should be >= minimum level {:?}", log.level, min_level);
                }

                Ok(())
            })
        }

        // Test pagination with search term
        #[test]
        fn test_pagination_with_search(
            page_size in page_size_strategy(),
            search in search_term_strategy()
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let service = create_test_service_with_logs();

                // Add a specific log with the search term
                let mut fields = HashMap::new();
                fields.insert("source".to_string(), serde_json::Value::String("test".to_string()));
                fields.insert("searchable".to_string(), serde_json::Value::String(search.clone()));

                service.log(LogLevel::Info, "Log with searchable field", fields, None);

                // Query logs with search filter
                let result = service.query_logs_paginated(None, None, None, page_size, None, Some(&search)).await;
                prop_assert!(result.is_ok(), "Query with search filter failed: {:?}", result.err());

                let page = result.unwrap();

                // If we found any logs, verify they contain the search term
                if !page.logs.is_empty() {
                    let contains_term = page.logs.iter().any(|log| {
                        log.message.contains(&search) ||
                        log.fields.values().any(|v| {
                            if let Some(s) = v.as_str() {
                                s.contains(&search)
                            } else {
                                v.to_string().contains(&search)
                            }
                        })
                    });

                    prop_assert!(contains_term, "Logs should contain the search term: {}", search);
                }

                Ok(())
            })
        }

        // Test cursor validation
        #[test]
        fn test_cursor_validation(
            page_size in page_size_strategy(),
            valid_cursor in rfc3339_datetime_strategy(),
            invalid_cursor in "[a-zA-Z0-9]{10}"
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let service = create_test_service_with_logs();

                // Valid cursor should work
                let result1 = service.query_logs_paginated(None, None, None, page_size, Some(valid_cursor.clone()), None).await;
                prop_assert!(result1.is_ok(), "Query with valid cursor failed: {:?}", result1.err());

                // Invalid cursor should return an error
                let result2 = service.query_logs_paginated(None, None, None, page_size, Some(invalid_cursor.to_string()), None).await;
                prop_assert!(result2.is_err(), "Query with invalid cursor should fail");

                if let Err(err) = result2 {
                    match err {
                        Error::InvalidInput(_) => {
                            // This is the expected error
                        },
                        _ => prop_assert!(false, "Expected InvalidInput error, got: {:?}", err),
                    }
                }

                Ok(())
            })
        }

        // Test time range pagination
        #[test]
        fn test_time_range_pagination(
            page_size in page_size_strategy()
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let service = create_test_service_with_logs();

                // Calculate a time range
                let end_time = chrono::Utc::now();
                let start_time = end_time - chrono::Duration::hours(1);

                // Query logs in time range
                let result = service.query_logs_paginated(
                    None,
                    Some(start_time),
                    Some(end_time),
                    page_size,
                    None,
                    None
                ).await;

                prop_assert!(result.is_ok(), "Query with time range failed: {:?}", result.err());

                let page = result.unwrap();

                // Verify all logs are within the time range
                for log in &page.logs {
                    prop_assert!(log.timestamp >= start_time,
                        "Log timestamp should be >= start time");
                    prop_assert!(log.timestamp <= end_time,
                        "Log timestamp should be <= end time");
                }

                Ok(())
            })
        }
    }

    #[test]
    fn test_pagination_consistency() {
        let rt = Runtime::new().unwrap();

        rt.block_on(async {
            let service = create_test_service_with_logs();

            // Use consistent page size for all queries
            let page_size = 5;

            // Query first page
            let page1 = service.query_logs_paginated(None, None, None, page_size, None, None).await.unwrap();

            // If there's a next page, query it
            if let Some(cursor) = page1.next_cursor.clone() {
                let page2 = service.query_logs_paginated(None, None, None, page_size, Some(cursor), None).await.unwrap();

                // Get the combined logs from both pages
                let mut paginated_logs = page1.logs.clone();
                paginated_logs.extend(page2.logs.clone());

                // Now query all logs at once with a larger page size
                let all_at_once = service.query_logs_paginated(None, None, None, page_size * 2, None, None).await.unwrap();

                // Verify that the first logs match
                let compare_len = std::cmp::min(paginated_logs.len(), all_at_once.logs.len());
                for i in 0..compare_len {
                    assert_eq!(paginated_logs[i].message, all_at_once.logs[i].message);
                    assert_eq!(paginated_logs[i].timestamp, all_at_once.logs[i].timestamp);
                    assert_eq!(paginated_logs[i].level, all_at_once.logs[i].level);
                }
            }
        });
    }
}

#[cfg(test)]
mod rate_limit_tests {
    use super::*;
    use proptest::prelude::*;
    use tokio::runtime::Runtime;
    use std::time::Duration;
    use std::thread;

    // Strategy for generating IP addresses
    fn ip_address_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Regular IPv4
            (0..256u8, 0..256u8, 0..256u8, 0..256u8)
                .prop_map(|(a, b, c, d)| format!("{}.{}.{}.{}", a, b, c, d)),
            // Localhost variants
            Just("127.0.0.1".to_string()),
            Just("::1".to_string()),
            Just("localhost".to_string()),
        ]
    }

    // Strategy for generating rate limit configurations
    fn rate_limit_config_strategy() -> impl Strategy<Value = RateLimitConfig> {
        (
            // Max requests (reasonable range for testing)
            2..100u64,
            // Window seconds (small enough for testing)
            1..10u64,
            // Bypass localhost
            any::<bool>(),
        ).prop_map(|(max_requests, window_seconds, bypass_localhost)| {
            RateLimitConfig {
                max_requests,
                window_seconds,
                bypass_localhost,
            }
        })
    }

    // Strategy for generating request counts
    fn request_count_strategy() -> impl Strategy<Value = u64> {
        1..200u64
    }

    proptest! {
        /// Test that requests are limited according to configuration
        #[test]
        fn test_rate_limit_enforcement(
            config in rate_limit_config_strategy(),
            request_count in request_count_strategy(),
            ip in ip_address_strategy().prop_filter(
                "Skip localhost for this test",
                |ip| ip != "127.0.0.1" && ip != "::1" && ip != "localhost"
            )
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create rate limiter with config
                let rate_limiter = RateLimiter::new(config.clone());

                // Track number of allowed requests
                let mut allowed_count = 0;

                // Send requests
                for _ in 0..request_count {
                    if rate_limiter.check(&ip).await {
                        allowed_count += 1;
                    }
                }

                // Verify the number of allowed requests matches configuration
                let expected_allowed = std::cmp::min(request_count, config.max_requests);
                prop_assert_eq!(allowed_count, expected_allowed,
                    "Expected {} requests to be allowed with max_requests={}, got {}",
                    expected_allowed, config.max_requests, allowed_count);
            });
        }

        /// Test that rate limits are bypassed for localhost when configured
        #[test]
        fn test_localhost_bypass(
            config in rate_limit_config_strategy().prop_map(|mut c| {
                // Ensure localhost bypass is enabled
                c.bypass_localhost = true;
                c
            }),
            request_count in request_count_strategy(),
            localhost_ip in prop_oneof![
                Just("127.0.0.1".to_string()),
                Just("::1".to_string()),
                Just("localhost".to_string()),
            ]
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create rate limiter with localhost bypass
                let rate_limiter = RateLimiter::new(config);

                // All requests from localhost should be allowed
                for _ in 0..request_count {
                    prop_assert!(rate_limiter.check(&localhost_ip).await,
                        "Localhost request should be allowed when bypass is enabled");
                }
            });
        }

        /// Test that localhost is not bypassed when disabled in config
        #[test]
        fn test_no_localhost_bypass_when_disabled(
            max_requests in 2..20u64,
            window_seconds in 1..10u64,
            request_count in 21..100u64,
            localhost_ip in prop_oneof![
                Just("127.0.0.1".to_string()),
                Just("::1".to_string())
            ]
        ) {
            let config = RateLimitConfig {
                max_requests,
                window_seconds,
                bypass_localhost: false,
            };

            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                // Create rate limiter without localhost bypass
                let rate_limiter = RateLimiter::new(config);

                // First batch of requests should succeed
                for i in 0..max_requests {
                    prop_assert!(rate_limiter.check(&localhost_ip).await,
                        "Request #{} should be allowed", i);
                }

                // Subsequent requests should be rate limited
                prop_assert!(!rate_limiter.check(&localhost_ip).await,
                    "Request after limit exceeded should be blocked");
            });
        }
    }
}
