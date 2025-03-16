// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Format service for handling code formatting and syntax highlighting
//!
//! This module provides formatting and syntax highlighting functionality for
//! code displayed in the Art application.

use crate::data::git::{FileContent, FileInfo};
use crate::error::{Error, Result};
use crate::util::highlight;

use std::path::Path;
use std::sync::Arc;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use syntect::highlighting::Theme;
use syntect::parsing::SyntaxReference;
use std::borrow::Cow;
use syntect::highlighting::ThemeSet;
use crate::util::highlight::{self, DEFAULT_THEME};
use std::time::Duration;
use once_cell::sync::Lazy;
use std::time::Instant;
use std::hash::{Hash, Hasher};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashSet;
use std::str::FromStr;
use csscolorparser::{Color, ParseColorError};
use tokio::sync::RwLock;
use std::sync::atomic::{AtomicUsize, Ordering};
use futures::future::{self, Future};
use std::pin::Pin;
use regex::Regex;
use lazy_static::lazy_static;
use tokio::time::interval;
use std::sync::mpsc::{channel, Sender, Receiver};
use std::thread;
use uuid;

// Add this at the top of the file, after existing imports
pub mod accessibility;
use accessibility::{AccessibilityFeatures, AccessibilityManager};
use prometheus::Registry;

/// Global ThemeSet instance
static THEME_SET: Lazy<ThemeSet> = Lazy::new(|| ThemeSet::load_defaults());

/// Cache entry for syntax themes
struct ThemeCacheEntry {
    /// The loaded theme
    theme: Arc<Theme>,
    /// When this entry was last accessed
    last_accessed: Instant,
}

/// Cache entry for formatted content
struct FormattedCacheEntry<T> {
    /// The formatted content
    content: Arc<T>,
    /// When this entry was last accessed
    last_accessed: Instant,
}

/// Performance metrics for formatting operations
#[derive(Debug, Default, Clone)]
pub struct FormatMetrics {
    /// Total number of format requests
    pub total_requests: AtomicUsize,

    /// Number of cache hits
    pub cache_hits: AtomicUsize,

    /// Number of cache misses
    pub cache_misses: AtomicUsize,

    /// Total time spent formatting (in milliseconds)
    pub total_format_time_ms: AtomicUsize,

    /// Maximum time spent on a single format operation (in milliseconds)
    pub max_format_time_ms: AtomicUsize,

    /// Number of async format operations
    pub async_operations: AtomicUsize,

    /// Number of incremental format operations
    pub incremental_operations: AtomicUsize,

    /// Number of sanitized HTML outputs
    pub sanitized_content_count: AtomicUsize,

    /// Number of cache cleanups performed
    pub cache_cleanup_count: AtomicUsize,

    /// Total bytes processed
    pub total_bytes_processed: AtomicUsize,
}

/// Telemetry format for exporting metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormatTelemetry {
    /// Total number of format requests
    pub total_requests: usize,

    /// Number of cache hits
    pub cache_hits: usize,

    /// Number of cache misses
    pub cache_misses: usize,

    /// Cache hit ratio (0.0-1.0)
    pub cache_hit_ratio: f64,

    /// Total time spent formatting (in milliseconds)
    pub total_format_time_ms: usize,

    /// Average time per format operation (in milliseconds)
    pub avg_format_time_ms: f64,

    /// Maximum time spent on a single format operation (in milliseconds)
    pub max_format_time_ms: usize,

    /// Number of async format operations
    pub async_operations: usize,

    /// Number of incremental format operations
    pub incremental_operations: usize,

    /// Number of sanitized HTML outputs
    pub sanitized_content_count: usize,

    /// Number of cache cleanups performed
    pub cache_cleanup_count: usize,

    /// Total bytes processed
    pub total_bytes_processed: usize,

    /// Cache size summary
    pub cache_sizes: HashMap<String, usize>,

    /// Timestamp when metrics were collected
    pub timestamp: String,
}

/// Security settings for content formatting
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityOptions {
    /// Whether to sanitize output HTML for XSS prevention
    pub sanitize_html: bool,

    /// Maximum content size (in bytes) to format synchronously
    pub max_sync_content_size: usize,

    /// Maximum number of lines to format in a single chunk
    pub max_chunk_size: usize,

    /// List of allowed HTML tags (if sanitization is enabled)
    pub allowed_html_tags: Vec<String>,

    /// List of allowed HTML attributes (if sanitization is enabled)
    pub allowed_html_attributes: Vec<String>,
}

impl Default for SecurityOptions {
    fn default() -> Self {
        Self {
            sanitize_html: true,
            max_sync_content_size: 1_000_000, // 1MB
            max_chunk_size: 1000, // 1000 lines
            allowed_html_tags: vec![
                "div".to_string(), "span".to_string(), "pre".to_string(),
                "code".to_string(), "table".to_string(), "tr".to_string(),
                "td".to_string(), "th".to_string(), "tbody".to_string(),
                "thead".to_string(), "a".to_string(), "br".to_string(),
            ],
            allowed_html_attributes: vec![
                "class".to_string(), "id".to_string(), "role".to_string(),
                "aria-label".to_string(), "aria-current".to_string(),
                "tabindex".to_string(), "href".to_string(),
            ],
        }
    }
}

/// Format status for asynchronous operations
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FormatStatus {
    /// Formatting is in progress
    InProgress,

    /// Formatting is complete
    Complete,

    /// Formatting failed
    Failed(String),
}

/// Incremental formatting chunk
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormattedChunk {
    /// HTML content for this chunk
    pub html: String,

    /// Line range in the original content (1-based, inclusive)
    pub line_range: (usize, usize),

    /// Whether this is the last chunk
    pub is_last: bool,

    /// Status of the formatting operation
    pub status: FormatStatus,
}

/// Asynchronous formatting result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AsyncFormatResult {
    /// Unique ID for this formatting operation
    pub operation_id: String,

    /// Current status of the operation
    pub status: FormatStatus,

    /// Formatted chunks available so far
    pub chunks: Vec<FormattedChunk>,

    /// Total number of lines in the content
    pub total_lines: usize,

    /// Time spent formatting so far (in milliseconds)
    pub elapsed_ms: u64,

    /// Percentage complete (0-100)
    pub percent_complete: u8,
}

/// Format service for code formatting and syntax highlighting
pub struct FormatService {
    /// Default theme for syntax highlighting
    default_theme: String,

    /// Theme cache
    themes: HashMap<String, Arc<Theme>>,

    /// Language detection and syntax cache
    syntax_cache: HashMap<String, Arc<SyntaxReference>>,

    /// Mapping of file extensions to syntax names
    extension_map: HashMap<String, String>,

    /// Cache for formatted code
    code_cache: HashMap<String, FormattedCacheEntry<FormattedCode>>,

    /// Cache for formatted diffs
    diff_cache: HashMap<String, FormattedCacheEntry<FormattedDiff>>,

    /// Cache for formatted markdown
    markdown_cache: HashMap<String, FormattedCacheEntry<String>>,

    /// Cache for formatted blame view
    blame_cache: HashMap<String, FormattedCacheEntry<FormattedBlame>>,

    /// Maximum cache size (entries)
    max_cache_size: usize,

    /// Cache TTL (time to live)
    cache_ttl: Duration,

    /// Metrics for performance tracking
    metrics: FormatMetrics,

    /// Async format operations in progress
    async_operations: RwLock<HashMap<String, AsyncFormatResult>>,

    /// Last cache cleanup time
    last_cache_cleanup: Instant,

    /// Automatic cache cleanup interval (None = no auto cleanup)
    cache_cleanup_interval: Option<Duration>,

    /// Accessibility manager for enhanced accessibility features
    accessibility_manager: Option<AccessibilityManager>,
}

/// Define more detailed syntax highlighting errors
#[derive(Debug, Clone)]
pub enum FormatError {
    /// Theme not found
    ThemeNotFound(String),

    /// Syntax not supported
    SyntaxNotSupported(String),

    /// Content error (invalid UTF-8, etc.)
    ContentError(String),

    /// Binary content
    BinaryContent,

    /// Accessibility error (poor color contrast, etc.)
    AccessibilityError(String),

    /// Other internal error
    Internal(String),
}

/// Accessibility settings for formatting
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityOptions {
    /// Minimum contrast ratio for syntax highlighting
    pub min_contrast_ratio: f64,

    /// Add ARIA attributes to help screen readers
    pub add_aria_attributes: bool,

    /// Use alternative text for icons
    pub use_alt_text: bool,

    /// Add tabindex attributes for keyboard navigation
    pub add_tabindex: bool,
}

impl Default for AccessibilityOptions {
    fn default() -> Self {
        Self {
            min_contrast_ratio: 4.5, // WCAG AA standard
            add_aria_attributes: true,
            use_alt_text: true,
            add_tabindex: true,
        }
    }
}

/// Code formatting options with caching
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormatOptions {
    /// Syntax highlighting theme
    pub theme: Option<String>,

    /// Whether to show line numbers
    pub show_line_numbers: bool,

    /// Whether to wrap long lines
    pub wrap_lines: bool,

    /// Tab size (number of spaces)
    pub tab_size: usize,

    /// Whether to highlight the current line
    pub highlight_current_line: bool,

    /// Line to highlight (1-based)
    pub highlight_line: Option<usize>,

    /// Enable caching of formatted content (default true)
    pub enable_cache: bool,

    /// Format for rendering markdown (html, plain, or github)
    pub markdown_format: Option<String>,

    /// Accessibility options
    pub accessibility: AccessibilityOptions,

    /// Custom file extension to language mappings
    pub custom_extensions: HashMap<String, String>,

    /// Security options
    pub security: SecurityOptions,

    /// Whether to process asynchronously if content is large
    pub process_async: bool,

    /// Whether to format incrementally
    pub incremental: bool,

    /// Maximum chunk size for incremental formatting
    pub chunk_size: usize,
}

/// Blame line information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlameLine {
    /// The commit hash for this line
    pub commit_hash: String,

    /// The author of this line
    pub author: String,

    /// The date this line was last modified
    pub date: String,

    /// Line content
    pub content: String,

    /// Line number
    pub line_number: usize,
}

/// Formatted blame result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormattedBlame {
    /// HTML content with syntax highlighting and blame information
    pub html: String,

    /// Language detected
    pub language: Option<String>,

    /// Theme used
    pub theme: String,

    /// Number of lines
    pub line_count: usize,

    /// Number of characters
    pub char_count: usize,
}

/// Formatted code result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormattedCode {
    /// HTML content with syntax highlighting
    pub html: String,

    /// Language detected
    pub language: Option<String>,

    /// Theme used
    pub theme: String,

    /// Number of lines
    pub line_count: usize,

    /// Number of characters
    pub char_count: usize,
}

/// Diff format result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormattedDiff {
    /// HTML content with syntax highlighting
    pub html: String,

    /// Number of files changed
    pub files_changed: usize,

    /// Number of lines added
    pub lines_added: usize,

    /// Number of lines removed
    pub lines_removed: usize,
}

/// Formatted line result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormattedLine {
    /// HTML content with syntax highlighting
    pub html: String,

    /// Line number
    pub line_number: usize,

    /// Whether this line is highlighted
    pub is_highlighted: bool,
}

impl Default for FormatOptions {
    fn default() -> Self {
        Self {
            theme: None,
            show_line_numbers: true,
            wrap_lines: true,
            tab_size: 4,
            highlight_current_line: false,
            highlight_line: None,
            enable_cache: true,
            markdown_format: Some("html".to_string()),
            accessibility: AccessibilityOptions::default(),
            custom_extensions: HashMap::new(),
            security: SecurityOptions::default(),
            process_async: true,
            incremental: true,
            chunk_size: 1000,
        }
    }
}

impl FormatService {
    /// Create a new format service with default settings.
    ///
    /// # Returns
    /// A new FormatService instance with default theme, cache size, and TTL settings.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let format_service = FormatService::new();
    /// ```
    pub fn new() -> Self {
        Self {
            default_theme: "Solarized (dark)".to_string(),
            themes: HashMap::new(),
            syntax_cache: HashMap::new(),
            extension_map: Self::build_extension_map(),
            code_cache: HashMap::new(),
            diff_cache: HashMap::new(),
            markdown_cache: HashMap::new(),
            blame_cache: HashMap::new(),
            max_cache_size: 100,
            cache_ttl: Duration::from_secs(30),
            metrics: FormatMetrics::default(),
            async_operations: RwLock::new(HashMap::new()),
            last_cache_cleanup: Instant::now(),
            cache_cleanup_interval: None,
            accessibility_manager: None,
        }
    }

    /// Create a new format service with the specified default theme.
    ///
    /// # Arguments
    /// * `default_theme` - The name of the default syntax highlighting theme to use.
    ///
    /// # Returns
    /// A new FormatService instance with the specified theme and default cache settings.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let format_service = FormatService::with_theme("Solarized (light)");
    /// ```
    pub fn with_theme(default_theme: &str) -> Self {
        Self {
            default_theme: default_theme.to_string(),
            themes: HashMap::new(),
            syntax_cache: HashMap::new(),
            extension_map: Self::build_extension_map(),
            code_cache: HashMap::new(),
            diff_cache: HashMap::new(),
            markdown_cache: HashMap::new(),
            blame_cache: HashMap::new(),
            max_cache_size: 100,
            cache_ttl: Duration::from_secs(30),
            metrics: FormatMetrics::default(),
            async_operations: RwLock::new(HashMap::new()),
            last_cache_cleanup: Instant::now(),
            cache_cleanup_interval: None,
            accessibility_manager: None,
        }
    }

    /// Create a new format service with custom cache settings.
    ///
    /// # Arguments
    /// * `max_cache_size` - The maximum number of entries to store in each cache.
    /// * `cache_ttl_secs` - The time-to-live for cache entries in seconds.
    ///
    /// # Returns
    /// A new FormatService instance with custom cache settings.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// // Create a service with a larger cache and longer TTL
    /// let format_service = FormatService::with_cache_settings(500, 3600);
    /// ```
    pub fn with_cache_settings(max_cache_size: usize, cache_ttl_secs: u64) -> Self {
        Self {
            default_theme: "Solarized (dark)".to_string(),
            themes: HashMap::new(),
            syntax_cache: HashMap::new(),
            extension_map: Self::build_extension_map(),
            code_cache: HashMap::new(),
            diff_cache: HashMap::new(),
            markdown_cache: HashMap::new(),
            blame_cache: HashMap::new(),
            max_cache_size,
            cache_ttl: Duration::from_secs(cache_ttl_secs),
            metrics: FormatMetrics::default(),
            async_operations: RwLock::new(HashMap::new()),
            last_cache_cleanup: Instant::now(),
            cache_cleanup_interval: None,
            accessibility_manager: None,
        }
    }

    /// Set the automatic cache cleanup interval.
    ///
    /// # Arguments
    /// * `seconds` - The cleanup interval in seconds.
    ///
    /// # Returns
    /// A Result indicating success or an error if the interval is invalid.
    ///
    /// # Errors
    /// Returns an error if `seconds` is zero.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let mut format_service = FormatService::new();
    /// format_service.set_cache_cleanup_interval(600); // Clean every 10 minutes
    /// ```
    pub fn set_cache_cleanup_interval(&mut self, seconds: u64) -> Result<()> {
        if seconds == 0 {
            return Err(Error::Internal("Cache cleanup interval must be greater than zero".to_string()));
        }

        self.cache_cleanup_interval = Some(Duration::from_secs(seconds));
        self.last_cache_cleanup = Instant::now();

        Ok(())
    }

    /// Disable automatic cache cleanup.
    ///
    /// After calling this method, cache cleanup will only happen manually
    /// or when the cache size limits are exceeded.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let mut format_service = FormatService::new();
    /// format_service.disable_cache_cleanup();
    /// ```
    pub fn disable_cache_cleanup(&mut self) {
        self.cache_cleanup_interval = None;
    }

    /// Get available syntax highlighting themes.
    ///
    /// # Returns
    /// A vector of theme names that can be used for syntax highlighting.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let format_service = FormatService::new();
    /// let themes = format_service.available_themes();
    /// println!("Available themes: {:?}", themes);
    /// ```
    pub fn available_themes(&self) -> Vec<String> {
        highlight::available_themes()
    }

    /// Get supported file extensions for syntax highlighting.
    ///
    /// # Returns
    /// A vector of file extensions that can be syntax highlighted.
    ///
    /// # Example
    /// ```
    /// use art::service::format::FormatService;
    ///
    /// let format_service = FormatService::new();
    /// let extensions = format_service.supported_extensions();
    /// println!("Supported extensions: {:?}", extensions);
    /// ```
    pub fn supported_extensions(&self) -> Vec<String> {
        highlight::supported_extensions()
    }

    /// Format code with syntax highlighting.
    ///
    /// This method applies syntax highlighting to the provided content based on
    /// the file path and options. It supports caching, line numbering, and
    /// accessibility features.
    ///
    /// # Arguments
    /// * `content` - The code content to format.
    /// * `path` - The file path, used for language detection and cache key generation.
    /// * `options` - Formatting options controlling highlighting, line numbers, etc.
    ///
    /// # Returns
    /// A FormattedCode struct containing the HTML output and metadata.
    ///
    /// # Errors
    /// Returns an error if formatting fails for any reason, such as:
    /// - Invalid theme
    /// - Unsupported language
    /// - Syntax highlighting errors
    ///
    /// # Examples
    /// ```
    /// use art::service::format::{FormatService, FormatOptions};
    ///
    /// let mut format_service = FormatService::new();
    /// let options = FormatOptions::default();
    ///
    /// let result = format_service.format_code("fn main() { println!(\"Hello\"); }", "example.rs", &options);
    /// if let Ok(formatted) = result {
    ///     println!("Formatted HTML: {}", formatted.html);
    /// }
    /// ```
    pub fn format_code(&mut self, content: &str, path: &str, options: &FormatOptions) -> Result<FormattedCode> {
        // Track metrics
        self.metrics.total_requests.fetch_add(1, Ordering::Relaxed);
        self.metrics.total_bytes_processed.fetch_add(content.len(), Ordering::Relaxed);
        let start = Instant::now();

        // Check for auto cache cleanup
        self.check_auto_cache_cleanup();

        // Generate cache key
        let cache_key = self.generate_cache_key(content, path, options);

        // Check cache if enabled
        if options.enable_cache {
            if let Some(entry) = self.code_cache.get_mut(&cache_key) {
                // Update last accessed time
                entry.last_accessed = Instant::now();

                // Track cache hit
                self.metrics.cache_hits.fetch_add(1, Ordering::Relaxed);

                return Ok(entry.content.as_ref().clone());
            }
        }

        // Track cache miss
        self.metrics.cache_misses.fetch_add(1, Ordering::Relaxed);

        // Check if content is binary
        if self.is_binary_content(content) {
            return Ok(FormattedCode {
                html: self.format_binary_placeholder(path),
                language: None,
                theme: options.theme.clone().unwrap_or_else(|| self.default_theme.clone()),
                line_count: 0,
                char_count: content.len(),
            });
        }

        // Detect language
        let language = match Path::new(path).extension() {
            Some(ext) => self.detect_language_from_extension(&ext.to_string_lossy()),
            None => None,
        };

        // Get theme
        let theme_name = options.theme.clone().unwrap_or_else(|| self.default_theme.clone());
        let theme = self.get_theme(&theme_name)?;

        // Apply syntax highlighting
        let highlighted = self.highlight_code(content, &language, theme.as_ref(), options)?;

        // Wrap with line numbers if requested
        let html = if options.show_line_numbers {
            self.add_line_numbers(&highlighted, options)
        } else {
            highlighted
        };

        // Count lines
        let line_count = content.lines().count();

        // Create result
        let result = FormattedCode {
            html,
            language,
            theme: theme_name,
            line_count,
            char_count: content.len(),
        };

        // Add to cache if enabled
        if options.enable_cache {
            self.code_cache.insert(
                cache_key,
                FormattedCacheEntry {
                    content: Arc::new(result.clone()),
                    last_accessed: Instant::now(),
                },
            );
        }

        // Track formatting time
        let elapsed = start.elapsed();
        let elapsed_ms = elapsed.as_millis() as usize;
        self.metrics.total_format_time_ms.fetch_add(elapsed_ms, Ordering::Relaxed);

        // Update max time if larger
        let mut current_max = self.metrics.max_format_time_ms.load(Ordering::Relaxed);
        while elapsed_ms > current_max {
            match self.metrics.max_format_time_ms.compare_exchange(
                current_max,
                elapsed_ms,
                Ordering::SeqCst,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(actual) => current_max = actual,
            }
        }

        Ok(result)
    }

    /// Generate a cache key for the given content and options
    fn generate_cache_key(&self, content: &str, path: &str, options: &FormatOptions) -> String {
        let mut hasher = DefaultHasher::new();
        content.hash(&mut hasher);
        path.hash(&mut hasher);
        options.theme.hash(&mut hasher);
        options.show_line_numbers.hash(&mut hasher);
        options.wrap_lines.hash(&mut hasher);
        options.tab_size.hash(&mut hasher);
        options.highlight_line.hash(&mut hasher);

        // For accessibility options, only include the ones that affect rendering
        options.accessibility.add_aria_attributes.hash(&mut hasher);
        options.accessibility.min_contrast_ratio.to_bits().hash(&mut hasher);

        format!("code:{}:{}", path, hasher.finish())
    }

    /// Get current metrics for testing
    pub fn get_metrics(&self) -> &FormatMetrics {
        &self.metrics
    }

    /// Reset metrics (primarily for testing)
    pub fn reset_metrics(&mut self) {
        self.metrics = FormatMetrics::default();
    }

    /// Enable automatic cache cleanup at the specified interval (in seconds)
    pub fn enable_auto_cache_cleanup(&mut self, seconds: u64) -> Result<()> {
        if seconds == 0 {
            return Err(Error::Internal("Cache cleanup interval must be greater than zero".to_string()));
        }

        self.cache_cleanup_interval = Some(Duration::from_secs(seconds));
        self.last_cache_cleanup = Instant::now();

        Ok(())
    }

    /// Evict oldest entries when cache exceeds size limit
    fn evict_oldest_entries<T>(&mut self, cache: &mut HashMap<String, FormattedCacheEntry<T>>, max_size: usize) {
        if cache.len() <= max_size {
            return;
        }

        // Convert to vector for sorting
        let mut entries: Vec<(String, Instant)> = cache
            .iter()
            .map(|(key, entry)| (key.clone(), entry.last_accessed))
            .collect();

        // Sort by last accessed time (oldest first)
        entries.sort_by(|a, b| a.1.cmp(&b.1));

        // Calculate how many entries to remove
        let remove_count = cache.len().saturating_sub(max_size);

        // Remove oldest entries
        for i in 0..remove_count {
            if i < entries.len() {
                cache.remove(&entries[i].0);
            }
        }
    }

    /// Get current metrics and stats as telemetry data
    pub fn get_telemetry(&self) -> FormatTelemetry {
        let total_requests = self.metrics.total_requests.load(Ordering::Relaxed);
        let cache_hits = self.metrics.cache_hits.load(Ordering::Relaxed);
        let cache_misses = self.metrics.cache_misses.load(Ordering::Relaxed);
        let total_format_time_ms = self.metrics.total_format_time_ms.load(Ordering::Relaxed);

        // Calculate derived metrics
        let cache_hit_ratio = if total_requests > 0 {
            cache_hits as f64 / total_requests as f64
        } else {
            0.0
        };

        let avg_format_time_ms = if total_requests > 0 {
            total_format_time_ms as f64 / total_requests as f64
            } else {
            0.0
        };

        // Get cache sizes
        let mut cache_sizes = HashMap::new();
        cache_sizes.insert("code".to_string(), self.code_cache.len());
        cache_sizes.insert("diff".to_string(), self.diff_cache.len());
        cache_sizes.insert("markdown".to_string(), self.markdown_cache.len());
        cache_sizes.insert("blame".to_string(), self.blame_cache.len());

        // Create current timestamp
        let timestamp = chrono::Local::now().to_rfc3339();

        FormatTelemetry {
            total_requests,
            cache_hits,
            cache_misses,
            cache_hit_ratio,
            total_format_time_ms,
            avg_format_time_ms,
            max_format_time_ms: self.metrics.max_format_time_ms.load(Ordering::Relaxed),
            async_operations: self.metrics.async_operations.load(Ordering::Relaxed),
            incremental_operations: self.metrics.incremental_operations.load(Ordering::Relaxed),
            sanitized_content_count: self.metrics.sanitized_content_count.load(Ordering::Relaxed),
            cache_cleanup_count: self.metrics.cache_cleanup_count.load(Ordering::Relaxed),
            total_bytes_processed: self.metrics.total_bytes_processed.load(Ordering::Relaxed),
            cache_sizes,
            timestamp,
        }
    }

    /// Export telemetry data as JSON
    pub fn export_telemetry_json(&self) -> Result<String> {
        let telemetry = self.get_telemetry();
        serde_json::to_string_pretty(&telemetry)
            .map_err(|e| Error::Internal(format!("Failed to serialize telemetry: {}", e)))
    }

    /// Export telemetry data in Prometheus format
    pub fn export_telemetry_prometheus(&self) -> String {
        let telemetry = self.get_telemetry();

        let mut output = String::new();

        // Add metrics in Prometheus format
        output.push_str(&format!("# HELP format_total_requests Total number of format requests\n"));
        output.push_str(&format!("# TYPE format_total_requests counter\n"));
        output.push_str(&format!("format_total_requests {}\n", telemetry.total_requests));

        output.push_str(&format!("# HELP format_cache_hits Number of cache hits\n"));
        output.push_str(&format!("# TYPE format_cache_hits counter\n"));
        output.push_str(&format!("format_cache_hits {}\n", telemetry.cache_hits));

        output.push_str(&format!("# HELP format_cache_misses Number of cache misses\n"));
        output.push_str(&format!("# TYPE format_cache_misses counter\n"));
        output.push_str(&format!("format_cache_misses {}\n", telemetry.cache_misses));

        output.push_str(&format!("# HELP format_cache_hit_ratio Cache hit ratio\n"));
        output.push_str(&format!("# TYPE format_cache_hit_ratio gauge\n"));
        output.push_str(&format!("format_cache_hit_ratio {}\n", telemetry.cache_hit_ratio));

        output.push_str(&format!("# HELP format_total_time_ms Total time spent formatting in milliseconds\n"));
        output.push_str(&format!("# TYPE format_total_time_ms counter\n"));
        output.push_str(&format!("format_total_time_ms {}\n", telemetry.total_format_time_ms));

        output.push_str(&format!("# HELP format_avg_time_ms Average time per format operation in milliseconds\n"));
        output.push_str(&format!("# TYPE format_avg_time_ms gauge\n"));
        output.push_str(&format!("format_avg_time_ms {}\n", telemetry.avg_format_time_ms));

        output.push_str(&format!("# HELP format_max_time_ms Maximum time spent on a single format operation in milliseconds\n"));
        output.push_str(&format!("# TYPE format_max_time_ms gauge\n"));
        output.push_str(&format!("format_max_time_ms {}\n", telemetry.max_format_time_ms));

        output.push_str(&format!("# HELP format_async_operations Number of async format operations\n"));
        output.push_str(&format!("# TYPE format_async_operations counter\n"));
        output.push_str(&format!("format_async_operations {}\n", telemetry.async_operations));

        output.push_str(&format!("# HELP format_incremental_operations Number of incremental format operations\n"));
        output.push_str(&format!("# TYPE format_incremental_operations counter\n"));
        output.push_str(&format!("format_incremental_operations {}\n", telemetry.incremental_operations));

        output.push_str(&format!("# HELP format_sanitized_content_count Number of sanitized HTML outputs\n"));
        output.push_str(&format!("# TYPE format_sanitized_content_count counter\n"));
        output.push_str(&format!("format_sanitized_content_count {}\n", telemetry.sanitized_content_count));

        output.push_str(&format!("# HELP format_cache_cleanup_count Number of cache cleanups performed\n"));
        output.push_str(&format!("# TYPE format_cache_cleanup_count counter\n"));
        output.push_str(&format!("format_cache_cleanup_count {}\n", telemetry.cache_cleanup_count));

        output.push_str(&format!("# HELP format_total_bytes_processed Total bytes processed\n"));
        output.push_str(&format!("# TYPE format_total_bytes_processed counter\n"));
        output.push_str(&format!("format_total_bytes_processed {}\n", telemetry.total_bytes_processed));

        // Add cache size metrics
        for (cache_type, size) in &telemetry.cache_sizes {
            output.push_str(&format!("# HELP format_cache_size_{} Size of {} cache\n", cache_type, cache_type));
            output.push_str(&format!("# TYPE format_cache_size_{} gauge\n", cache_type));
            output.push_str(&format!("format_cache_size_{} {}\n", cache_type, size));
        }

        output
    }

    /// Check if content is binary
    fn is_binary_content(&self, content: &str) -> bool {
        // 1. First check: if content contains too many null bytes or non-utf8 characters
        let mut null_count = 0;
        let mut binary_chars = 0;
        let total_chars = content.len();

        if total_chars == 0 {
            return false;
        }

        // Limit the check to the first 8KB or the entire content, whichever is smaller
        let check_limit = std::cmp::min(8 * 1024, total_chars);
        let content_sample = &content[0..check_limit];

        for byte in content_sample.bytes() {
            if byte == 0 {
                null_count += 1;
            }
            // Check for control characters (except whitespace) and high ascii
            if (byte < 9 || (byte > 13 && byte < 32) || byte > 127) && byte != 0 {
                binary_chars += 1;
            }
        }

        // If more than 5% of characters are nulls or 30% are binary, consider it binary
        if null_count as f64 / check_limit as f64 > 0.05 || binary_chars as f64 / check_limit as f64 > 0.3 {
            return true;
        }

        // 2. Second check: look for file magic numbers at the beginning
        if content.len() >= 4 {
            let first_bytes = content.as_bytes();
            // PDF signature
            if first_bytes.starts_with(b"%PDF") {
                return true;
            }
            // PNG signature
            if first_bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
                return true;
            }
            // JPEG signature
            if first_bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
                return true;
            }
            // GIF signature
            if first_bytes.starts_with(b"GIF8") {
                return true;
            }
            // ZIP, JAR, etc signatures
            if first_bytes.starts_with(&[0x50, 0x4B, 0x03, 0x04]) {
                return true;
            }
            // ELF signature
            if first_bytes.starts_with(&[0x7F, b'E', b'L', b'F']) {
                return true;
            }
        }

        false
    }

    /// Format binary content placeholder
    fn format_binary_placeholder(&self, path: &str) -> String {
        let extension = Path::new(path)
            .extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("");

        let file_type = match extension.to_lowercase().as_str() {
            "pdf" => "PDF Document",
            "png" | "jpg" | "jpeg" | "gif" | "bmp" | "webp" => "Image",
            "zip" | "tar" | "gz" | "tgz" | "bz2" | "xz" => "Archive",
            "exe" | "dll" => "Executable",
            "doc" | "docx" => "Word Document",
            "xls" | "xlsx" => "Excel Document",
            "ppt" | "pptx" => "PowerPoint Document",
            _ => "Binary File",
        };

        let file_name = Path::new(path).file_name().and_then(|f| f.to_str()).unwrap_or(path);

        let html = format!(
            r#"<div class="binary-content" aria-label="{} {}">
                <div class="binary-icon">{}</div>
                <div class="binary-info">
                    <span class="binary-filename">{}</span>
                    <span class="binary-type">{}</span>
                    <span class="binary-notice">This is a binary file. Download it to view its contents.</span>
                </div>
            </div>"#,
            file_type, file_name, // For aria-label
            self.get_binary_icon(extension),
            self.html_escape(file_name),
            file_type
        );

        html
    }

    /// Get appropriate icon for binary file
    fn get_binary_icon(&self, extension: &str) -> &'static str {
        match extension.to_lowercase().as_str() {
            "pdf" => "📄",
            "png" | "jpg" | "jpeg" | "gif" | "bmp" | "webp" => "🖼️",
            "zip" | "tar" | "gz" | "tgz" | "bz2" | "xz" => "📦",
            "exe" | "dll" => "⚙️",
            "doc" | "docx" => "📝",
            "xls" | "xlsx" => "📊",
            "ppt" | "pptx" => "📽️",
            _ => "📁",
        }
    }

    /// Escape HTML special characters
    pub fn html_escape(&self, content: &str) -> String {
        content
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
            .replace('\'', "&#39;")
    }

    /// Get theme by name, with fallback to default
    fn get_theme(&self, theme_name: &str) -> Result<Arc<Theme>> {
        // Check if we have it in cache
        if let Some(theme) = self.themes.get(theme_name) {
            return Ok(theme.clone());
        }

        // Load theme from global set
        let theme_set = &*THEME_SET;
        if let Some(theme) = theme_set.themes.get(theme_name) {
            // This is a clone of the theme from the static ThemeSet
            let theme_arc = Arc::new(theme.clone());
            // It's OK if another thread also inserted this theme; we'd just be wasting a clone
            return Ok(theme_arc);
        }

        // Try default theme if not found
        if theme_name != &self.default_theme {
            return self.get_theme(&self.default_theme);
        }

        // If default theme isn't found either, use first available theme
        if let Some((_, theme)) = theme_set.themes.iter().next() {
            return Ok(Arc::new(theme.clone()));
        }

        Err(Error::Internal(format!("Theme not found: {}", theme_name)))
    }

    /// Build map of file extensions to syntax names
    fn build_extension_map() -> HashMap<String, String> {
        let mut map = HashMap::new();

        // Common programming languages
        map.insert("rs".to_string(), "Rust".to_string());
        map.insert("go".to_string(), "Go".to_string());
        map.insert("js".to_string(), "JavaScript".to_string());
        map.insert("jsx".to_string(), "JavaScript (React)".to_string());
        map.insert("ts".to_string(), "TypeScript".to_string());
        map.insert("tsx".to_string(), "TypeScript (React)".to_string());
        map.insert("py".to_string(), "Python".to_string());
        map.insert("rb".to_string(), "Ruby".to_string());
        map.insert("php".to_string(), "PHP".to_string());
        map.insert("java".to_string(), "Java".to_string());
        map.insert("c".to_string(), "C".to_string());
        map.insert("h".to_string(), "C".to_string());
        map.insert("cpp".to_string(), "C++".to_string());
        map.insert("hpp".to_string(), "C++".to_string());
        map.insert("cs".to_string(), "C#".to_string());
        map.insert("swift".to_string(), "Swift".to_string());
        map.insert("kt".to_string(), "Kotlin".to_string());
        map.insert("dart".to_string(), "Dart".to_string());

        // Markup & config
        map.insert("html".to_string(), "HTML".to_string());
        map.insert("xml".to_string(), "XML".to_string());
        map.insert("css".to_string(), "CSS".to_string());
        map.insert("scss".to_string(), "SCSS".to_string());
        map.insert("sass".to_string(), "Sass".to_string());
        map.insert("json".to_string(), "JSON".to_string());
        map.insert("yaml".to_string(), "YAML".to_string());
        map.insert("yml".to_string(), "YAML".to_string());
        map.insert("toml".to_string(), "TOML".to_string());
        map.insert("md".to_string(), "Markdown".to_string());
        map.insert("markdown".to_string(), "Markdown".to_string());
        map.insert("tex".to_string(), "LaTeX".to_string());

        // Shell & scripts
        map.insert("sh".to_string(), "Bash".to_string());
        map.insert("bash".to_string(), "Bash".to_string());
        map.insert("fish".to_string(), "Fish".to_string());
        map.insert("zsh".to_string(), "Bash".to_string());
        map.insert("ps1".to_string(), "PowerShell".to_string());
        map.insert("bat".to_string(), "Batch".to_string());
        map.insert("cmd".to_string(), "Batch".to_string());

        // Other
        map.insert("sql".to_string(), "SQL".to_string());
        map.insert("nix".to_string(), "Nix".to_string());
        map.insert("hs".to_string(), "Haskell".to_string());
        map.insert("ml".to_string(), "OCaml".to_string());
        map.insert("pl".to_string(), "Perl".to_string());
        map.insert("lua".to_string(), "Lua".to_string());
        map.insert("r".to_string(), "R".to_string());

        map
    }

    /// Detect language from file extension
    pub fn detect_language(&self, path: &Path) -> Option<String> {
        let extension = path.extension().and_then(|e| e.to_str())?;
        self.detect_language_from_extension(extension)
    }

    /// Detect language from extension string
    fn detect_language_from_extension(&self, extension: &str) -> Option<String> {
        self.extension_map.get(&extension.to_lowercase()).cloned()
    }

    /// Highlight code with syntax highlighting
    fn highlight_code(
        &self,
        content: &str,
        language: &Option<String>,
        theme: &Theme,
        options: &FormatOptions,
    ) -> Result<String> {
        let lang = match language {
            Some(lang) => lang,
            None => return Ok(self.html_escape(content)),
        };

        // Get syntax
        let syntax_set = highlight::get_syntax_set();
        let syntax = syntax_set
            .find_syntax_by_name(lang)
            .or_else(|| syntax_set.find_syntax_by_extension(lang.to_lowercase().as_str()));

        let syntax = match syntax {
            Some(syntax) => syntax,
            None => return Ok(self.html_escape(content)),
        };

        // Perform highlighting
        let highlighted = highlight::highlight_text(content, syntax, theme, options.tab_size)?;

        // Check accessibility if needed
        if options.accessibility.add_aria_attributes {
            let highlighted_with_aria = self.add_accessibility_attributes(&highlighted, options);
            Ok(highlighted_with_aria)
        } else {
            Ok(highlighted)
        }
    }

    /// Add accessibility attributes to the HTML
    fn add_accessibility_attributes(&self, html: &str, options: &FormatOptions) -> String {
        let mut result = String::with_capacity(html.len() + 100);

        // Add wrapper with ARIA role
        result.push_str("<div role=\"code\" aria-label=\"Source code\"");

        // Add language if available
        if let Some(lang) = &options.theme {
            result.push_str(&format!(" data-language=\"{}\"", self.html_escape(lang)));
        }

        result.push_str(">\n");
        result.push_str(html);
        result.push_str("</div>");

        result
    }

    /// Add line numbers to code
    fn add_line_numbers(&self, html: &str, options: &FormatOptions) -> String {
        let mut result = String::with_capacity(html.len() * 2);
        let highlighted_line = options.highlight_line.unwrap_or(0);

        result.push_str("<table class=\"code-table\">\n<tbody>\n");

        for (i, line) in html.lines().enumerate() {
            let line_num = i + 1;
            let highlight_class = if line_num == highlighted_line { " class=\"highlighted\"" } else { "" };

            result.push_str(&format!(
                "<tr{}><td class=\"line-number\" id=\"L{}\" data-line-number=\"{}\">{}</td><td class=\"code-line\">",
                highlight_class, line_num, line_num, line_num
            ));

            // Add tabindex for keyboard navigation if enabled
            if options.accessibility.add_tabindex {
                result.push_str(&format!("<div tabindex=\"0\" class=\"line-content\">"));
            } else {
                result.push_str("<div class=\"line-content\">");
            }

            result.push_str(line);
            result.push_str("</div></td></tr>\n");
        }

        result.push_str("</tbody>\n</table>");

        result
    }

    /// Check if file should be highlighted
    pub fn should_highlight(&self, path: &Path) -> bool {
        // Skip directories
        if path.is_dir() {
            return false;
        }

        // Check extension against known binary types
        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("");
        let binary_extensions = [
            "png", "jpg", "jpeg", "gif", "bmp", "webp",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "zip", "tar", "gz", "tgz", "bz2", "xz",
            "exe", "dll", "so", "dylib", "bin", "class", "pyc",
        ];

        if binary_extensions.contains(&extension.to_lowercase().as_str()) {
            return false;
        }

        // Check if we can detect a language
        if self.detect_language(path).is_none() {
            // Still highlight if it's a common text format without syntax highlighting
            let text_extensions = ["txt", "log", "csv", "text"];
            return text_extensions.contains(&extension.to_lowercase().as_str());
        }

        true
    }

    /// Format a single line with syntax highlighting
    pub fn format_line(
        &mut self,
        content: &str,
        line_number: usize,
        path: &str,
        options: &FormatOptions,
    ) -> Result<FormattedLine> {
        // Detect language
        let language = match Path::new(path).extension() {
            Some(ext) => self.detect_language_from_extension(&ext.to_string_lossy()),
            None => None,
        };

        // Get theme
        let theme_name = options.theme.clone().unwrap_or_else(|| self.default_theme.clone());
        let theme = self.get_theme(&theme_name)?;

        // Highlight the line
        let highlighted = self.highlight_code(content, &language, theme.as_ref(), options)?;

        // Check if this is the highlighted line
        let is_highlighted = options.highlight_line.map_or(false, |hl| hl == line_number);

        Ok(FormattedLine {
            html: highlighted,
            line_number,
            is_highlighted,
        })
    }

    /// Sanitize HTML for security
    pub fn sanitize_html(&self, content: &str, options: &SecurityOptions) -> String {
        if !options.sanitize_html {
            return content.to_string();
        }

        // Track sanitization count
        self.metrics.sanitized_content_count.fetch_add(1, Ordering::Relaxed);

        // Use a regex-based approach for basic sanitization
        // In a real-world implementation, you'd use a proper HTML sanitizer library

        let mut result = content.to_string();

        // Remove script tags and their contents
        let script_re = Regex::new(r"<script\b[^<]*(?:(?!</script>)<[^<]*)*</script>").unwrap();
        result = script_re.replace_all(&result, "").to_string();

        // Remove dangerous attributes
        let event_attr_re = Regex::new(r#"(?i)\s(on\w+)=([\"'])((?:(?!\2).)*)\2"#).unwrap();
        result = event_attr_re.replace_all(&result, "").to_string();

        // Remove javascript: URLs
        let js_href_re = Regex::new(r#"(?i)(href|src|style|action)\s*=\s*(["'])\s*javascript:.*?\2"#).unwrap();
        result = js_href_re.replace_all(&result, r#"$1=$2#$2"#).to_string();

        // Remove other dangerous tags
        let dangerous_tags = [
            "iframe", "object", "embed", "form", "input", "button", "meta", "link",
            "base", "style", "frame", "frameset", "applet", "svg",
        ];

        for tag in &dangerous_tags {
            let tag_re = Regex::new(&format!(r"<{}\b[^<]*(?:(?!</{}>)<[^<]*)*</{}>", tag, tag, tag)).unwrap();
            result = tag_re.replace_all(&result, "").to_string();

            // Also remove self-closing versions
            let self_closing_re = Regex::new(&format!(r"<{}\b[^>]*/>", tag)).unwrap();
            result = self_closing_re.replace_all(&result, "").to_string();
        }

        result
    }

    /// Parse diff statistics
    pub fn parse_diff_stats(&self, diff: &str) -> (usize, usize, usize) {
        let mut files = 0;
        let mut added = 0;
        let mut removed = 0;

        // Count file headers
        for line in diff.lines() {
            if line.starts_with("diff --git ") {
                files += 1;
            } else if line.starts_with('+') && !line.starts_with("+++") {
                added += 1;
            } else if line.starts_with('-') && !line.starts_with("---") {
                removed += 1;
            }
        }

        (files, added, removed)
    }

    /// Format code asynchronously with chunked responses
    pub async fn format_code_async(&mut self, content: &str, path: &str, options: &FormatOptions) -> Result<AsyncFormatResult> {
        // Track metrics
        self.metrics.total_requests.fetch_add(1, Ordering::Relaxed);
        self.metrics.async_operations.fetch_add(1, Ordering::Relaxed);
        self.metrics.total_bytes_processed.fetch_add(content.len(), Ordering::Relaxed);

        // Generate a unique operation ID
        let operation_id = uuid::Uuid::new_v4().to_string();

        // Count total lines
        let lines: Vec<&str> = content.lines().collect();
        let total_lines = lines.len();

        // Create initial result
        let async_result = AsyncFormatResult {
            operation_id: operation_id.clone(),
            status: FormatStatus::InProgress,
            chunks: Vec::new(),
            total_lines,
            elapsed_ms: 0,
            percent_complete: 0,
        };

        // Store initial result
        {
            let mut operations = self.async_operations.write().await;
            operations.insert(operation_id.clone(), async_result.clone());
        }

        // Clone what we need for the async task
        let operation_id_clone = operation_id.clone();
        let content_clone = content.to_string();
        let path_clone = path.to_string();
        let options_clone = options.clone();
        let chunk_size = options.chunk_size.max(1);
        let async_ops = self.async_operations.clone();

        // Spawn a task to process the content in chunks
        tokio::spawn(async move {
            let start = Instant::now();
            let mut formatted_chunks = Vec::new();

            // Process content in chunks
            for (chunk_index, chunk) in lines.chunks(chunk_size).enumerate() {
                let chunk_content = chunk.join("\n");
                let start_line = chunk_index * chunk_size + 1;
                let end_line = start_line + chunk.len() - 1;

                // Apply format options specific to this chunk
                let mut chunk_options = options_clone.clone();
                if let Some(hl) = chunk_options.highlight_line {
                    // Only highlight if it's in this chunk
                    if hl < start_line || hl > end_line {
                        chunk_options.highlight_line = None;
                    }
                }

                // Format this chunk
                // Here we're using a synchronous function for simplicity
                // In a real implementation, you might want to make this fully async too
                let highlight_path = format!("{}:{}-{}", path_clone, start_line, end_line);

                // Try to format the chunk
                let formatted_chunk = match Self::format_chunk(&chunk_content, &highlight_path, &chunk_options) {
                    Ok(formatted) => FormattedChunk {
                        html: formatted,
                        line_range: (start_line, end_line),
                        is_last: end_line == total_lines,
                        status: FormatStatus::InProgress,
                    },
                    Err(err) => FormattedChunk {
                        html: format!("<div class=\"error\">Error formatting lines {}-{}: {}</div>",
                                       start_line, end_line, err),
                        line_range: (start_line, end_line),
                        is_last: end_line == total_lines,
                        status: FormatStatus::Failed(err.to_string()),
                    },
                };

                formatted_chunks.push(formatted_chunk);

                // Update the result with the new chunk
                let elapsed_ms = start.elapsed().as_millis() as u64;
                let percent_complete = ((end_line as f64 / total_lines as f64) * 100.0) as u8;

                // Update the stored result
                let mut operations = async_ops.write().await;
                if let Some(result) = operations.get_mut(&operation_id_clone) {
                    result.chunks = formatted_chunks.clone();
                    result.elapsed_ms = elapsed_ms;
                    result.percent_complete = percent_complete;

                    // Update status if the last chunk or if there was an error
                    if end_line == total_lines {
                        result.status = FormatStatus::Complete;
                        // Update all chunks to have Complete status
                        for chunk in &mut result.chunks {
                            chunk.status = FormatStatus::Complete;
                        }
                    } else if formatted_chunks.last().unwrap().status == FormatStatus::Failed(String::new()) {
                        result.status = formatted_chunks.last().unwrap().status.clone();
                    }
                }
            }
        });

        // Return the initial async result
        let operations = self.async_operations.read().await;
        if let Some(result) = operations.get(&operation_id) {
            Ok(result.clone())
                } else {
            Err(Error::Internal("Failed to create async format operation".to_string()))
        }
    }

    /// Get the current status of an async formatting operation
    pub async fn get_async_format_status(&self, operation_id: &str) -> Result<AsyncFormatResult> {
        let operations = self.async_operations.read().await;
        if let Some(result) = operations.get(operation_id) {
            Ok(result.clone())
            } else {
            Err(Error::NotFound(format!("Async operation not found: {}", operation_id)))
        }
    }

    /// Format a single chunk of code (helper for async formatting)
    fn format_chunk(content: &str, path: &str, options: &FormatOptions) -> Result<String> {
        // For this simplified implementation, we'll just escape HTML
        // In a real implementation, you would reuse the highlighting logic
        let html_escaped = content
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
            .replace('\'', "&#39;");

        let mut result = String::new();

        // Add line numbers if requested
        if options.show_line_numbers {
            result.push_str("<table class=\"code-table\">\n<tbody>\n");

            // Extract start line from path (format: "path:start-end")
            let mut start_line = 1;
            if let Some(line_pos) = path.rfind(':') {
                if let Some(range) = path[line_pos+1..].split('-').next() {
                    if let Ok(line) = range.parse::<usize>() {
                        start_line = line;
                    }
                }
            }

            for (i, line) in html_escaped.lines().enumerate() {
                let line_num = start_line + i;
                let highlight_class = if Some(line_num) == options.highlight_line {
                    " class=\"highlighted\""
                } else {
                    ""
                };

                result.push_str(&format!(
                    "<tr{}><td class=\"line-number\" id=\"L{}\" data-line-number=\"{}\">{}</td><td class=\"code-line\">",
                    highlight_class, line_num, line_num, line_num
                ));

                // Add tabindex for keyboard navigation if enabled
                if options.accessibility.add_tabindex {
                    result.push_str(&format!("<div tabindex=\"0\" class=\"line-content\">"));
                } else {
                    result.push_str("<div class=\"line-content\">");
                }

                result.push_str(line);
                result.push_str("</div></td></tr>\n");
            }

            result.push_str("</tbody>\n</table>");
        } else {
            // Just wrap in a pre tag
            result.push_str("<pre class=\"code\">");
            result.push_str(&html_escaped);
            result.push_str("</pre>");
        }

        Ok(result)
    }

    /// Format incrementally, returning a single chunk at a time
    pub fn format_incremental(&mut self, content: &str, path: &str, options: &FormatOptions, chunk_index: usize) -> Result<FormattedChunk> {
        // Track metrics
        self.metrics.total_requests.fetch_add(1, Ordering::Relaxed);
        self.metrics.incremental_operations.fetch_add(1, Ordering::Relaxed);

        // Split content into lines
        let lines: Vec<&str> = content.lines().collect();
        let total_lines = lines.len();
        let chunk_size = options.chunk_size.max(1);

        // Calculate chunk bounds
        let start_index = chunk_index * chunk_size;
        if start_index >= total_lines {
            return Err(Error::InvalidArgument(format!("Chunk index out of bounds: {}", chunk_index)));
        }

        let end_index = (start_index + chunk_size).min(total_lines);
        let chunk_lines = &lines[start_index..end_index];
        let chunk_content = chunk_lines.join("\n");

        // Line numbers are 1-based
        let start_line = start_index + 1;
        let end_line = end_index;

        // Apply format options specific to this chunk
        let mut chunk_options = options.clone();
        if let Some(hl) = chunk_options.highlight_line {
            // Only highlight if it's in this chunk
            if hl < start_line || hl > end_line {
                chunk_options.highlight_line = None;
            }
        }

        // Format the chunk
        let highlight_path = format!("{}:{}-{}", path, start_line, end_line);
        let formatted = Self::format_chunk(&chunk_content, &highlight_path, &chunk_options)?;

        // Create the formatted chunk
        let result = FormattedChunk {
            html: formatted,
            line_range: (start_line, end_line),
            is_last: end_line == total_lines,
            status: if end_line == total_lines {
                FormatStatus::Complete
            } else {
                FormatStatus::InProgress
            },
        };

        Ok(result)
    }

    /// Check if a color contrast meets accessibility standards
    pub fn check_color_contrast(&self, foreground: &str, background: &str, min_ratio: f64) -> Result<bool> {
        // Parse colors
        let fg = Color::from_str(foreground)
            .map_err(|e| Error::InvalidArgument(format!("Invalid foreground color: {}", e)))?;
        let bg = Color::from_str(background)
            .map_err(|e| Error::InvalidArgument(format!("Invalid background color: {}", e)))?;

        // Get luminance values
        let fg_lum = self.calculate_luminance(fg.r, fg.g, fg.b);
        let bg_lum = self.calculate_luminance(bg.r, bg.g, bg.b);

        // Calculate contrast ratio
        let contrast_ratio = if fg_lum > bg_lum {
            (fg_lum + 0.05) / (bg_lum + 0.05)
        } else {
            (bg_lum + 0.05) / (fg_lum + 0.05)
        };

        Ok(contrast_ratio >= min_ratio)
    }

    /// Calculate relative luminance of an RGB color (for WCAG contrast)
    fn calculate_luminance(&self, r: f64, g: f64, b: f64) -> f64 {
        // Convert RGB to sRGB
        let r_srgb = if r <= 0.03928 { r / 12.92 } else { ((r + 0.055) / 1.055).powf(2.4) };
        let g_srgb = if g <= 0.03928 { g / 12.92 } else { ((g + 0.055) / 1.055).powf(2.4) };
        let b_srgb = if b <= 0.03928 { b / 12.92 } else { ((b + 0.055) / 1.055).powf(2.4) };

        // Calculate luminance
        0.2126 * r_srgb + 0.7152 * g_srgb + 0.0722 * b_srgb
    }

    /// Add custom extension to language mapping
    pub fn add_custom_extension(&mut self, extension: &str, language: &str) -> Result<()> {
        // Validate extension format
        if extension.is_empty() || extension.contains('/') || extension.contains('\\') {
            return Err(Error::InvalidArgument(format!("Invalid extension format: {}", extension)));
        }

        // Normalize extension (remove leading dot if present)
        let normalized_ext = extension.trim_start_matches('.');

        // Add to the extension map
        self.extension_map.insert(normalized_ext.to_string(), language.to_string());

        Ok(())
    }

    /// Remove custom extension mapping
    pub fn remove_custom_extension(&mut self, extension: &str) -> Result<()> {
        // Normalize extension (remove leading dot if present)
        let normalized_ext = extension.trim_start_matches('.');

        // Remove from extension map
        if !self.extension_map.contains_key(normalized_ext) {
            return Err(Error::NotFound(format!("Extension mapping not found: {}", normalized_ext)));
        }

        self.extension_map.remove(normalized_ext);

        Ok(())
    }

    /// Get all custom extension mappings
    pub fn get_custom_extensions(&self) -> HashMap<String, String> {
        self.extension_map.clone()
    }

    /// Apply custom extensions from format options
    fn apply_custom_extensions(&mut self, options: &FormatOptions) {
        for (ext, lang) in &options.custom_extensions {
            let _ = self.add_custom_extension(ext, lang);
        }
    }

    /// Initialize with the accessibility manager
    pub fn with_accessibility(default_theme: &str, registry: &Registry) -> Result<Self> {
        let mut service = Self::with_theme(default_theme);

        // Create default accessibility features
        let features = AccessibilityFeatures::default();

        // Create accessibility manager
        let accessibility_manager = AccessibilityManager::new(features, registry)?;

        service.accessibility_manager = Some(accessibility_manager);

        Ok(service)
    }

    /// Get the accessibility manager
    pub fn accessibility_manager(&self) -> Option<&AccessibilityManager> {
        self.accessibility_manager.as_ref()
    }

    /// Get mutable reference to the accessibility manager
    pub fn accessibility_manager_mut(&mut self) -> Option<&mut AccessibilityManager> {
        self.accessibility_manager.as_mut()
    }

    /// Update accessibility features
    pub fn update_accessibility_features(&mut self, features: AccessibilityFeatures) -> Result<()> {
        if let Some(manager) = &mut self.accessibility_manager {
            manager.update_features(features);
            Ok(())
        } else {
            Err(Error::Internal("Accessibility manager not initialized".to_string()))
        }
    }

    /// Format code with accessibility enhancements
    pub fn format_accessible_code(&mut self, content: &str, path: &str, options: &FormatOptions) -> Result<FormattedCode> {
        // First format the code normally
        let formatted = self.format_code(content, path, options)?;

        // Then apply accessibility enhancements if manager is available
        if let Some(manager) = &self.accessibility_manager {
            let enhanced_html = manager.enhance_code_snippet(&formatted.html);

            // Return the enhanced version
            Ok(FormattedCode {
                html: enhanced_html,
                language: formatted.language,
                theme: formatted.theme,
                line_count: formatted.line_count,
                char_count: formatted.char_count,
            })
        } else {
            // If no accessibility manager, return the normal formatted code
            Ok(formatted)
        }
    }

    /// Analyze the accessibility of formatted content
    pub fn analyze_accessibility(&self, html: &str) -> Result<accessibility::AccessibilityReport> {
        if let Some(manager) = &self.accessibility_manager {
            manager.analyze_content(html)
        } else {
            Err(Error::Internal("Accessibility manager not initialized".to_string()))
        }
    }

    /// Generate an accessible version of HTML content
    pub fn generate_accessible_version(&self, html: &str) -> Result<String> {
        if let Some(manager) = &self.accessibility_manager {
            manager.generate_accessible_version(html)
        } else {
            Err(Error::Internal("Accessibility manager not initialized".to_string()))
        }
    }

    /// Check color contrast and suggest improvements
    pub fn check_color_contrast_and_suggest(&self, foreground: &str, background: &str) -> Result<(bool, Option<String>)> {
        if let Some(manager) = &self.accessibility_manager {
            let has_sufficient_contrast = manager.has_sufficient_contrast(foreground, background)?;

            if has_sufficient_contrast {
                Ok((true, None))
            } else {
                let suggested_color = manager.suggest_better_color(foreground, background)?;
                Ok((false, Some(suggested_color)))
            }
        } else {
            Err(Error::Internal("Accessibility manager not initialized".to_string()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;
    use std::path::Path;
    use std::path::PathBuf;

    #[test]
    fn test_should_highlight() {
        let format_service = FormatService::new();

        // Supported extensions
        assert!(format_service.should_highlight(Path::new("test.rs")));
        assert!(format_service.should_highlight(Path::new("test.py")));
        assert!(format_service.should_highlight(Path::new("test.js")));

        // Unsupported extensions
        assert!(!format_service.should_highlight(Path::new("test.bin")));
        assert!(!format_service.should_highlight(Path::new("test.exe")));

        // Binary files
        assert!(!format_service.should_highlight(Path::new("image.png")));
        assert!(!format_service.should_highlight(Path::new("document.pdf")));
    }

    #[test]
    fn test_detect_language() {
        let format_service = FormatService::new();

        // Common file types
        assert_eq!(format_service.detect_language(Path::new("main.rs")), Some("Rust".to_string()));
        assert_eq!(format_service.detect_language(Path::new("script.py")), Some("Python".to_string()));

        // Unknown extension
        assert_eq!(format_service.detect_language(Path::new("test.unknown")), None);
    }

    #[test]
    fn test_html_escape() {
        let format_service = FormatService::new();

        assert_eq!(format_service.html_escape("Hello"), "Hello");
        assert_eq!(format_service.html_escape("<script>"), "&lt;script&gt;");
        assert_eq!(format_service.html_escape("a & b"), "a &amp; b");
        assert_eq!(format_service.html_escape("\"quoted\""), "&quot;quoted&quot;");
        assert_eq!(format_service.html_escape("don't"), "don&#39;t");
    }

    #[test]
    fn test_parse_diff_stats() {
        let format_service = FormatService::new();

        let diff = r#"diff --git a/file1.rs b/file1.rs
index 1234567..abcdefg 100644
--- a/file1.rs
+++ b/file1.rs
@@ -10,7 +10,7 @@ fn main() {
     println!("Hello, world!");
-    // Removed line
+    // Added line
+    println!("New line");
 }
diff --git a/file2.rs b/file2.rs
index 1234567..abcdefg 100644
--- a/file2.rs
+++ b/file2.rs
@@ -5,3 +5,4 @@ fn another() {
+    println!("Another function");
 }
"#;

        let (files, added, removed) = format_service.parse_diff_stats(diff);
        assert_eq!(files, 2);
        assert_eq!(added, 3);
        assert_eq!(removed, 1);
    }

    #[test]
    fn test_auto_cache_cleanup() {
        let mut format_service = FormatService::new();

        // Enable auto cleanup
        let result = format_service.enable_auto_cache_cleanup(1);
        assert!(result.is_ok());

        // Add some items to the cache
        let options = FormatOptions::default();
        let _ = format_service.format_code("Test content", "test.rs", &options);

        // Check initial cache size
        assert!(format_service.code_cache.len() > 0);

        // Wait for cleanup
        std::thread::sleep(Duration::from_secs(2));

        // Force check for cleanup commands
        format_service.check_auto_cache_cleanup();

        // Check that cleanup occurred
        assert!(format_service.metrics.cache_cleanup_count.load(Ordering::Relaxed) > 0);

        // Disable auto cleanup
        format_service.disable_auto_cache_cleanup();
    }

    #[test]
    fn test_telemetry_export() {
        let mut format_service = FormatService::new();

        // Generate some metrics
        let options = FormatOptions::default();
        let _ = format_service.format_code("Test content", "test.rs", &options);
        let _ = format_service.format_code("Another test", "test.py", &options);

        // Get telemetry
        let telemetry = format_service.get_telemetry();

        // Check basic metrics
        assert_eq!(telemetry.total_requests, 2);
        assert!(telemetry.total_format_time_ms > 0);

        // Check JSON export
        let json = format_service.export_telemetry_json().unwrap();
        assert!(json.contains("total_requests"));

        // Check Prometheus export
        let prometheus = format_service.export_telemetry_prometheus();
        assert!(prometheus.contains("format_total_requests"));
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use proptest::strategy::Strategy;

    // ... existing strategies ...

    // Add a strategy for generating valid hex color strings
    fn valid_hex_color_strategy() -> impl Strategy<Value = String> {
        prop_oneof![
            // Standard hex colors
            "[0-9a-fA-F]{6}".prop_map(|s| format!("#{}", s)),
            // Named colors
            prop::sample::select(vec![
                "black".to_string(), "white".to_string(), "red".to_string(),
                "green".to_string(), "blue".to_string(), "yellow".to_string(),
                "cyan".to_string(), "magenta".to_string(), "gray".to_string()
            ])
        ]
    }

    // ... existing property tests ...

    proptest! {
        /// Test that the color contrast checker correctly identifies accessible
        /// and inaccessible color combinations based on WCAG guidelines
        #[test]
        fn prop_test_color_contrast_checker(
            foreground in valid_hex_color_strategy(),
            background in valid_hex_color_strategy(),
            min_ratio in 1.0..21.0
        ) {
            // Create a format service
            let format_service = FormatService::new();

            // Check the contrast
            let result = format_service.check_color_contrast(&foreground, &background, min_ratio);

            // Test should not panic for valid colors
            prop_assert!(result.is_ok(),
                "Color contrast check failed for fg: {}, bg: {}, min_ratio: {}: {:?}",
                foreground, background, min_ratio, result.err());

            // The result should be consistent if we call it again
            let second_result = format_service.check_color_contrast(&foreground, &background, min_ratio);
            prop_assert!(second_result.is_ok());

            // Both calls should return the same result
            prop_assert_eq!(result.unwrap(), second_result.unwrap(),
                "Inconsistent results for fg: {}, bg: {}, min_ratio: {}",
                foreground, background, min_ratio);

            // If colors are the same, contrast should never pass for min_ratio > 1.0
            if foreground == background && min_ratio > 1.0 {
                prop_assert!(!result.unwrap(),
                    "Same colors should fail contrast check: {}, ratio: {}",
                    foreground, min_ratio);
            }

            // Symmetry check: swapping foreground and background should give same result
            let swapped_result = format_service.check_color_contrast(&background, &foreground, min_ratio);
            prop_assert!(swapped_result.is_ok());
            prop_assert_eq!(result.unwrap(), swapped_result.unwrap(),
                "Swapping colors gave different result: fg: {}, bg: {}, min_ratio: {}",
                foreground, background, min_ratio);
        }
    }

    proptest! {
        /// Test that the color contrast checker correctly handles invalid inputs
        #[test]
        fn prop_test_color_contrast_checker_invalid_inputs(
            invalid_color in "[^#][^0-9a-fA-F]+"
        ) {
            // Create a format service
            let format_service = FormatService::new();

            // Check with valid and invalid color
            let result1 = format_service.check_color_contrast(&invalid_color, "#FFFFFF", 4.5);
            let result2 = format_service.check_color_contrast("#000000", &invalid_color, 4.5);

            // Both should fail for invalid color
            prop_assert!(result1.is_err(), "Invalid color {} should cause error", invalid_color);
            prop_assert!(result2.is_err(), "Invalid color {} should cause error", invalid_color);
        }
    }
}
