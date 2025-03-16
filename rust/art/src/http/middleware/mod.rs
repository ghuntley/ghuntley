//! HTTP middleware for the Art application

use crate::service::observability::ObservabilityService;
use crate::error::Result;

use std::sync::Arc;
use std::time::Instant;
use std::task::{Context, Poll};
use std::future::Future;
use std::pin::Pin;
use std::collections::HashMap;
use std::net::SocketAddr;

use axum::body::{Body, HttpBody};
use axum::http::{Request, Response, StatusCode};
use axum::http::header::{HeaderValue, HeaderName};
use axum::response::IntoResponse;
use tower::{Layer, Service};
use futures::future::BoxFuture;
use futures::FutureExt;
use uuid::Uuid;
use serde_json;
use crate::service::observability::{RateLimiter, RateLimitConfig, TraceContext};
use crate::service::observability::opentelemetry::{
    extract_from_http_headers, convert_to_otel_format, convert_to_jaeger_format, convert_to_zipkin_format
};
use axum::extract::ConnectInfo;
use axum::middleware::Next;
use crate::service::observability::opentelemetry::OpenTelemetryTracer;
use opentelemetry::trace::SpanKind;
use tracing::warn;
use crate::service::user::UserService;
use axum::http::header::{AUTHORIZATION, COOKIE};
use base64::Engine;

/// Middleware for collecting metrics about HTTP requests
#[derive(Clone)]
pub struct MetricsMiddleware {
    observability_service: Arc<ObservabilityService>,
}

impl MetricsMiddleware {
    /// Create a new metrics middleware
    pub fn new(observability_service: Arc<ObservabilityService>) -> Self {
        Self { observability_service }
    }
}

impl<S> Layer<S> for MetricsMiddleware
where
    S: Service<Request<Body>> + Send + 'static,
    S::Response: IntoResponse + Send + 'static,
    S::Future: Send + 'static,
{
    type Service = MetricsService<S>;

    fn layer(&self, service: S) -> Self::Service {
        MetricsService {
            inner: service,
            observability_service: self.observability_service.clone(),
        }
    }
}

/// Service for collecting metrics about HTTP requests
#[derive(Clone)]
pub struct MetricsService<S> {
    inner: S,
    observability_service: Arc<ObservabilityService>,
}

impl<S> Service<Request<Body>> for MetricsService<S>
where
    S: Service<Request<Body>> + Send + 'static,
    S::Response: IntoResponse + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = Response<Body>;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut req: Request<Body>) -> Self::Future {
        // Clone the request method and path for metrics
        let method = req.method().to_string();
        let path = req.uri().path().to_string();

        // Generate a unique request ID
        let request_id = Uuid::new_v4().to_string();

        // Extract trace context from headers if present
        let trace_ctx = self.extract_trace_context_from_headers(&req);
        let trace_ctx = match trace_ctx {
            Some(ctx) => ctx,
            None => self.observability_service.create_trace_context(),
        };

        // Extract user agent and remote address
        let user_agent = req.headers()
            .get("user-agent")
            .and_then(|v| v.to_str().ok())
            .map(String::from);

        let remote_addr = req.extensions()
            .get::<std::net::SocketAddr>()
            .map(|addr| addr.to_string());

        // Create a request span for distributed tracing
        let span = self.observability_service.create_request_span(&request_id, &path, &method);

        // Record the request in metrics
        self.observability_service.record_request(&method, &path);

        // Attach trace context to request extensions for use in handlers
        req.extensions_mut().insert(trace_ctx.clone());
        req.extensions_mut().insert(request_id.clone());

        // Start a timer to track request duration
        let timer = self.observability_service.start_request_timer(&method, &path);
        let start_time = Instant::now();

        // Increment active connections counter
        self.observability_service.increment_connections();

        // Log request with structured data
        let mut fields = std::collections::HashMap::new();
        fields.insert("method".to_string(), serde_json::to_value(&method).unwrap());
        fields.insert("path".to_string(), serde_json::to_value(&path).unwrap());
        fields.insert("request_id".to_string(), serde_json::to_value(&request_id).unwrap());

        if let Some(ua) = &user_agent {
            fields.insert("user_agent".to_string(), serde_json::to_value(ua).unwrap());
        }

        if let Some(addr) = &remote_addr {
            fields.insert("remote_addr".to_string(), serde_json::to_value(addr).unwrap());
        }

        self.observability_service.log(
            crate::service::observability::LogLevel::Info,
            &format!("Request received: {} {}", method, path),
            fields,
            Some(trace_ctx.clone())
        );

        // Record the trace
        self.observability_service.record_trace(&trace_ctx);

        // Create a cloned reference to the observability service for the response handling
        let observability_service = self.observability_service.clone();

        // Call the inner service
        let future = self.inner.call(req);

        // Process the response
        async move {
            let result = future.await;

            match result {
                Ok(mut response) => {
                    // Get the status code
                    let status = response.status().as_u16();

                    // Record the response in metrics
                    observability_service.record_response(&method, &path, status);

                    // Calculate the request duration
                    let duration = start_time.elapsed();
                    let duration_ms = duration.as_millis() as u64;

                    // Stop the timer
                    let _ = timer;

                    // Create a child trace context for the response
                    let response_trace = trace_ctx.create_child();

                    // Add trace headers to the response
                    self.add_trace_headers_to_response(&mut response, &response_trace, &request_id);

                    // Create structured log fields for the response
                    let mut resp_fields = std::collections::HashMap::new();
                    resp_fields.insert("method".to_string(), serde_json::to_value(&method).unwrap());
                    resp_fields.insert("path".to_string(), serde_json::to_value(&path).unwrap());
                    resp_fields.insert("status".to_string(), serde_json::to_value(&status).unwrap());
                    resp_fields.insert("duration_ms".to_string(), serde_json::to_value(&duration_ms).unwrap());
                    resp_fields.insert("request_id".to_string(), serde_json::to_value(&request_id).unwrap());

                    // Determine log level based on status code
                    let log_level = if status >= 500 {
                        crate::service::observability::LogLevel::Error
                    } else if status >= 400 {
                        crate::service::observability::LogLevel::Warn
                    } else {
                        crate::service::observability::LogLevel::Info
                    };

                    // Log the response with structured data
                    observability_service.log(
                        log_level,
                        &format!("Response sent: {} {} => {} ({} ms)", method, path, status, duration_ms),
                        resp_fields,
                        Some(response_trace.clone())
                    );

                    // Record the trace
                    observability_service.record_trace(&response_trace);

                    // Track business metrics based on the request
                    if path.starts_with("/api/") {
                        let _ = observability_service.track_business_metric(
                            "api_response_time",
                            duration.as_secs_f64(),
                            &[("method", &method), ("path", &path), ("status", &status.to_string())]
                        ).await;
                    }

                    // Decrement active connections counter
                    observability_service.decrement_connections();

                    // Convert to our response type and return
                    Ok(response.into_response())
                }
                Err(err) => {
                    // Record the error in metrics
                    observability_service.record_response(&method, &path, 500);

                    // Calculate duration
                    let duration = start_time.elapsed();
                    let duration_ms = duration.as_millis() as u64;

                    // Stop the timer
                    let _ = timer;

                    // Create a child trace context for the error
                    let error_trace = trace_ctx.create_child();

                    // Create structured log fields for the error
                    let mut err_fields = std::collections::HashMap::new();
                    err_fields.insert("method".to_string(), serde_json::to_value(&method).unwrap());
                    err_fields.insert("path".to_string(), serde_json::to_value(&path).unwrap());
                    err_fields.insert("error".to_string(), serde_json::to_value(&format!("{:?}", err)).unwrap());
                    err_fields.insert("duration_ms".to_string(), serde_json::to_value(&duration_ms).unwrap());
                    err_fields.insert("request_id".to_string(), serde_json::to_value(&request_id).unwrap());

                    // Log the error with structured data
                    observability_service.log(
                        crate::service::observability::LogLevel::Error,
                        &format!("Request failed: {} {} => error ({} ms)", method, path, duration_ms),
                        err_fields,
                        Some(error_trace.clone())
                    );

                    // Record the trace
                    observability_service.record_trace(&error_trace);

                    // Decrement active connections counter
                    observability_service.decrement_connections();

                    // Re-throw the error
                    Err(err)
                }
            }
        }
        .boxed()
    }
}

// Helper methods for MetricsService
impl<S> MetricsService<S> {
    /// Extract trace context from headers
    fn extract_trace_context_from_headers(&self, req: &Request<Body>) -> Option<TraceContext> {
        let headers = req.headers();

        // Convert headers to a HashMap for easier processing
        let mut header_map = std::collections::HashMap::new();
        for (name, value) in headers.iter() {
            if let Ok(v) = value.to_str() {
                header_map.insert(name.as_str().to_string(), v.to_string());
            }
        }

        // Use the multi-format extractor to handle different tracing systems
        extract_from_http_headers(&header_map)
    }

    /// Add trace headers to response in multiple formats
    fn add_trace_headers_to_response(&self, response: &mut Response<Body>, trace_ctx: &TraceContext, request_id: &str) {
        // Get trace headers in all supported formats
        let mut all_headers = HashMap::new();

        // Add W3C Trace Context headers
        all_headers.extend(convert_to_otel_format(trace_ctx));

        // Add Jaeger headers
        all_headers.extend(convert_to_jaeger_format(trace_ctx));

        // Add Zipkin headers
        all_headers.extend(convert_to_zipkin_format(trace_ctx));

        // Add request ID
        all_headers.insert("X-Request-ID".to_string(), request_id.to_string());

        // Add all headers to the response
        if let Some(headers) = response.headers_mut() {
            for (name, value) in all_headers {
                headers.insert(
                    HeaderName::from_bytes(name.as_bytes()).unwrap_or(HeaderName::from_static("x-trace-id")),
                    HeaderValue::from_str(&value).unwrap_or_default()
                );
            }
        }
    }
}

/// Error handler for converting errors to responses
pub async fn error_handler(err: crate::error::Error) -> impl IntoResponse {
    // Log the error
    tracing::error!("Error: {:?}", err);

    // Convert to an HTTP response
    let (status, message) = match err {
        crate::error::Error::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
        crate::error::Error::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
        crate::error::Error::Unauthorized(msg) => (StatusCode::UNAUTHORIZED, msg),
        crate::error::Error::Forbidden(msg) => (StatusCode::FORBIDDEN, msg),
        crate::error::Error::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        crate::error::Error::Git(msg) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Git error: {}", msg)),
        crate::error::Error::Database(msg) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", msg)),
        // Add more error types as needed
    };

    // Return the response
    (status, message)
}

/// Layer that adds rate limiting to protected endpoints
#[derive(Clone)]
pub struct RateLimitLayer {
    /// Rate limiter
    rate_limiter: Arc<RateLimiter>,

    /// Path prefix for protected endpoints
    protected_path_prefix: String,
}

impl RateLimitLayer {
    /// Create a new rate limit layer
    pub fn new(rate_limiter: RateLimiter, protected_path_prefix: impl Into<String>) -> Self {
        Self {
            rate_limiter: Arc::new(rate_limiter),
            protected_path_prefix: protected_path_prefix.into(),
        }
    }

    /// Create a new rate limit layer for observability endpoints
    pub fn for_observability(observability: &ObservabilityService) -> Self {
        Self::new(
            observability.create_default_rate_limiter(),
            "/api/metrics".into(),
        )
    }

    /// Create a new rate limit layer with custom configuration
    pub fn with_config(
        observability: &ObservabilityService,
        config: RateLimitConfig,
        protected_path_prefix: impl Into<String>
    ) -> Self {
        Self::new(
            observability.create_rate_limiter(config),
            protected_path_prefix.into(),
        )
    }
}

impl<S> Layer<S> for RateLimitLayer {
    type Service = RateLimitMiddleware<S>;

    fn layer(&self, service: S) -> Self::Service {
        RateLimitMiddleware {
            inner: service,
            rate_limiter: Arc::clone(&self.rate_limiter),
            protected_path_prefix: self.protected_path_prefix.clone(),
        }
    }
}

/// Middleware that implements rate limiting
#[derive(Clone)]
pub struct RateLimitMiddleware<S> {
    /// Inner service
    inner: S,

    /// Rate limiter
    rate_limiter: Arc<RateLimiter>,

    /// Path prefix for protected endpoints
    protected_path_prefix: String,
}

impl<S, B> Service<Request<B>> for RateLimitMiddleware<S>
where
    S: Service<Request<B>, Response = Response> + Send + 'static,
    S::Future: Send + 'static,
    B: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request<B>) -> Self::Future {
        // Only apply rate limiting to protected paths
        let path = request.uri().path().to_string();
        if !path.starts_with(&self.protected_path_prefix) {
            // Not a protected path, pass through
            return Box::pin(self.inner.call(request));
        }

        // Extract client IP - use forwarded header if available, otherwise connection info
        let ip = get_client_ip(&request).unwrap_or_else(|| "unknown".to_string());

        // Clone necessary state for async block
        let rate_limiter = Arc::clone(&self.rate_limiter);
        let mut inner = std::mem::take(&mut self.inner);

        Box::pin(async move {
            // Check rate limit
            let allowed = rate_limiter.check(&ip).await;

            if allowed {
                // Allow the request to proceed
                inner.call(request).await
            } else {
                // Return 429 Too Many Requests
                Ok(too_many_requests_response())
            }
        })
    }
}

/// Get client IP from request
fn get_client_ip<B>(request: &Request<B>) -> Option<String> {
    // Try to get IP from X-Forwarded-For header
    if let Some(forwarded) = request.headers().get("X-Forwarded-For") {
        if let Ok(forwarded_str) = forwarded.to_str() {
            if let Some(ip) = forwarded_str.split(',').next() {
                return Some(ip.trim().to_string());
            }
        }
    }

    // Fall back to connection info
    request.extensions().get::<ConnectInfo<SocketAddr>>()
        .map(|conn| conn.0.ip().to_string())
}

/// Create a 429 Too Many Requests response
fn too_many_requests_response() -> Response {
    let body = serde_json::json!({
        "error": "Too Many Requests",
        "message": "Rate limit exceeded. Please try again later.",
        "status": 429
    });

    (
        StatusCode::TOO_MANY_REQUESTS,
        axum::Json(body)
    ).into_response()
}

/// OpenTelemetry middleware for distributed tracing
#[derive(Clone)]
pub struct OpenTelemetryMiddleware {
    /// OpenTelemetry tracer
    opentelemetry_tracer: Arc<OpenTelemetryTracer>,
}

impl OpenTelemetryMiddleware {
    /// Create a new OpenTelemetry middleware
    pub fn new(opentelemetry_tracer: Arc<OpenTelemetryTracer>) -> Self {
        Self { opentelemetry_tracer }
    }
}

impl<S> Layer<S> for OpenTelemetryMiddleware
where
    S: Service<Request<Body>> + Send + 'static,
    S::Response: IntoResponse + Send + 'static,
    S::Future: Send + 'static,
{
    type Service = OpenTelemetryService<S>;

    fn layer(&self, service: S) -> Self::Service {
        OpenTelemetryService {
            inner: service,
            opentelemetry_tracer: self.opentelemetry_tracer.clone(),
        }
    }
}

/// Service for integrating with OpenTelemetry
#[derive(Clone)]
pub struct OpenTelemetryService<S> {
    inner: S,
    opentelemetry_tracer: Arc<OpenTelemetryTracer>,
}

impl<S> Service<Request<Body>> for OpenTelemetryService<S>
where
    S: Service<Request<Body>> + Send + 'static,
    S::Response: IntoResponse + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = Response<Body>;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<Body>) -> Self::Future {
        // Extract method and path for span attributes
        let method = req.method().to_string();
        let path = req.uri().path().to_string();

        // Generate a unique request ID
        let request_id = Uuid::new_v4().to_string();

        // Extract trace context from headers if present
        let trace_ctx = self.extract_trace_context_from_headers(&req);

        // Clone necessary references for async block
        let tracer = self.opentelemetry_tracer.clone();

        // Call the inner service
        let future = self.inner.call(req);

        // Process the response and create OpenTelemetry spans
        async move {
            // Create a span for the request
            let span_result = tracer.record_span(
                "http.request",
                &trace_ctx,
                &[
                    ("http.method", &method),
                    ("http.path", &path),
                    ("request_id", &request_id),
                ],
                &[],
                opentelemetry::trace::SpanKind::Server,
            );

            // Log any span creation errors
            if let Err(e) = span_result {
                warn!("Failed to create OpenTelemetry span: {}", e);
            }

            // Process the response
            match future.await {
                Ok(response) => {
                    // Create a span for the response
                    let status = response.status().as_u16();
                    let status_str = status.to_string();

                    let response_span_result = tracer.record_span(
                        "http.response",
                        &trace_ctx,
                        &[
                            ("http.method", &method),
                            ("http.path", &path),
                            ("http.status", &status_str),
                            ("request_id", &request_id),
                        ],
                        &[],
                        opentelemetry::trace::SpanKind::Server,
                    );

                    // Log any span creation errors
                    if let Err(e) = response_span_result {
                        warn!("Failed to create OpenTelemetry response span: {}", e);
                    }

                    Ok(response)
                }
                Err(err) => {
                    // Create a span for the error
                    let error_span_result = tracer.record_span(
                        "http.error",
                        &trace_ctx,
                        &[
                            ("http.method", &method),
                            ("http.path", &path),
                            ("request_id", &request_id),
                            ("error", &format!("{:?}", err)),
                        ],
                        &[],
                        opentelemetry::trace::SpanKind::Server,
                    );

                    // Log any span creation errors
                    if let Err(e) = error_span_result {
                        warn!("Failed to create OpenTelemetry error span: {}", e);
                    }

                    Err(err)
                }
            }
        }
        .boxed()
    }
}

impl<S> OpenTelemetryService<S> {
    /// Extract trace context from headers
    fn extract_trace_context_from_headers(&self, req: &Request<Body>) -> TraceContext {
        let headers = req.headers();

        // Convert headers to a HashMap for easier processing
        let mut header_map = std::collections::HashMap::new();
        for (name, value) in headers.iter() {
            if let Ok(v) = value.to_str() {
                header_map.insert(name.as_str().to_string(), v.to_string());
            }
        }

        // Use the multi-format extractor to handle different tracing systems
        extract_from_http_headers(&header_map).unwrap_or_else(TraceContext::new)
    }
}

/// Authentication middleware
///
/// This middleware handles HTTP authentication using either:
/// 1. HTTP Basic Auth (username/password)
/// 2. Session token (via cookie or Authorization header)
#[derive(Clone)]
pub struct AuthMiddleware<S> {
    /// Inner service
    inner: S,

    /// User service for authentication
    user_service: Arc<UserService>,

    /// Routes that are exempt from authentication
    public_routes: Vec<String>,
}

/// Authentication layer for adding authentication to routes
#[derive(Clone)]
pub struct AuthLayer {
    /// User service for authentication
    user_service: Arc<UserService>,

    /// Routes that are exempt from authentication
    public_routes: Vec<String>,
}

/// Authentication data extracted from request
#[derive(Debug, Clone)]
pub struct AuthData {
    /// Authenticated user ID (if any)
    pub user_id: Option<i64>,

    /// Username (if authenticated)
    pub username: Option<String>,

    /// User roles (if authenticated)
    pub roles: Vec<String>,

    /// Session token (if authenticated via session)
    pub session_token: Option<String>,
}

impl Default for AuthData {
    fn default() -> Self {
        Self {
            user_id: None,
            username: None,
            roles: Vec::new(),
            session_token: None,
        }
    }
}

impl AuthLayer {
    /// Create a new authentication layer
    pub fn new(user_service: Arc<UserService>) -> Self {
        Self {
            user_service,
            public_routes: Vec::new(),
        }
    }

    /// Add public routes that don't require authentication
    pub fn with_public_routes(mut self, routes: Vec<String>) -> Self {
        self.public_routes = routes;
        self
    }
}

impl<S> Layer<S> for AuthLayer {
    type Service = AuthMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        AuthMiddleware {
            inner,
            user_service: Arc::clone(&self.user_service),
            public_routes: self.public_routes.clone(),
        }
    }
}

impl<S> Service<Request<Body>> for AuthMiddleware<S>
where
    S: Service<Request<Body>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut req: Request<Body>) -> Self::Future {
        let inner = self.inner.clone();
        let mut inner = std::mem::replace(&mut self.inner, inner);
        let user_service = Arc::clone(&self.user_service);
        let public_routes = self.public_routes.clone();

        Box::pin(async move {
            let path = req.uri().path().to_string();

            // Check if the route is public and doesn't require authentication
            let is_public = public_routes.iter().any(|r| path.starts_with(r));
            if is_public {
                // Add empty auth data for public routes
                req.extensions_mut().insert(AuthData::default());
                return inner.call(req).await;
            }

            // Extract authentication data from the request
            let auth_data = match authenticate_request(&req, &user_service).await {
                Ok(data) => data,
                Err(e) => {
                    // Return 401 Unauthorized response
                    return Ok(Response::builder()
                        .status(StatusCode::UNAUTHORIZED)
                        .header("WWW-Authenticate", "Basic realm=\"Art Git Server\"")
                        .body(Body::from(format!("Unauthorized: {}", e)))
                        .unwrap());
                }
            };

            // If we reach here and don't have a user_id, the route requires authentication
            if auth_data.user_id.is_none() {
                return Ok(Response::builder()
                    .status(StatusCode::UNAUTHORIZED)
                    .header("WWW-Authenticate", "Basic realm=\"Art Git Server\"")
                    .body(Body::from("Authentication required"))
                    .unwrap());
            }

            // Add authentication data to request extensions
            req.extensions_mut().insert(auth_data);

            // Continue with the request
            inner.call(req).await
        })
    }
}

/// Authenticate a request using available authentication methods
async fn authenticate_request(req: &Request<Body>, user_service: &UserService) -> Result<AuthData, String> {
    // First try session token (from cookie or Authorization header)
    if let Some(auth_data) = authenticate_with_session(req, user_service).await {
        return Ok(auth_data);
    }

    // Then try HTTP Basic Authentication
    if let Some(auth_data) = authenticate_with_basic(req, user_service).await {
        return Ok(auth_data);
    }

    // If no authentication provided, return empty auth data
    Ok(AuthData::default())
}

/// Authenticate with session token from cookie or Authorization header
async fn authenticate_with_session(req: &Request<Body>, user_service: &UserService) -> Option<AuthData> {
    // Try to get session token from cookie
    let session_token = if let Some(cookie_header) = req.headers().get(COOKIE) {
        if let Ok(cookie_str) = cookie_header.to_str() {
            cookie_str.split(';')
                .map(|c| c.trim())
                .find_map(|c| {
                    if c.starts_with("session=") {
                        Some(c.trim_start_matches("session=").to_string())
                    } else {
                        None
                    }
                })
        } else {
            None
        }
    } else {
        None
    };

    // If no session token in cookie, try Authorization header with Bearer token
    let session_token = if session_token.is_none() {
        if let Some(auth_header) = req.headers().get(AUTHORIZATION) {
            if let Ok(auth_str) = auth_header.to_str() {
                if auth_str.starts_with("Bearer ") {
                    Some(auth_str.trim_start_matches("Bearer ").to_string())
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        }
    } else {
        session_token
    };

    // If we have a session token, verify it
    if let Some(token) = session_token {
        // Get user info from session
        if let Ok(Some(user)) = user_service.get_session_user(&token).await {
            return Some(AuthData {
                user_id: Some(user.id),
                username: Some(user.username),
                roles: vec![user.role.to_string()],
                session_token: Some(token),
            });
        }
    }

    None
}

/// Authenticate with HTTP Basic Authentication
async fn authenticate_with_basic(req: &Request<Body>, user_service: &UserService) -> Option<AuthData> {
    if let Some(auth_header) = req.headers().get(AUTHORIZATION) {
        if let Ok(auth_str) = auth_header.to_str() {
            if auth_str.starts_with("Basic ") {
                let credentials = auth_str.trim_start_matches("Basic ");
                if let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(credentials) {
                    if let Ok(credentials_str) = String::from_utf8(decoded) {
                        if let Some((username, password)) = credentials_str.split_once(':') {
                            // Get client info for the login
                            let ip_address = req.extensions()
                                .get::<ClientInfo>()
                                .map(|info| info.ip.clone())
                                .unwrap_or_else(|| "unknown".to_string());

                            let user_agent = req.headers()
                                .get(header::USER_AGENT)
                                .and_then(|h| h.to_str().ok())
                                .unwrap_or("unknown")
                                .to_string();

                            // Attempt login
                            if let Ok((user, session)) = user_service.login(username, password, ip_address, user_agent).await {
                                return Some(AuthData {
                                    user_id: Some(user.id),
                                    username: Some(user.username),
                                    roles: vec![user.role.to_string()],
                                    session_token: Some(session.token),
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    None
}

/// Client information from the request
#[derive(Debug, Clone)]
pub struct ClientInfo {
    /// Client IP address
    pub ip: String,

    /// Client user agent
    pub user_agent: Option<String>,
}

/// Extract client information from the request
pub async fn extract_client_info(
    req: Request<Body>,
    next: Next<Body>,
) -> Response {
    let ip = req.headers()
        .get("x-forwarded-for")
        .and_then(|h| h.to_str().ok())
        .map(|s| s.split(',').next().unwrap_or("").trim().to_string())
        .unwrap_or_else(|| {
            req.extensions()
                .get::<ConnectInfo<SocketAddr>>()
                .map(|addr| addr.0.ip().to_string())
                .unwrap_or_else(|| "unknown".to_string())
        });

    let user_agent = req.headers()
        .get(header::USER_AGENT)
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string());

    let client_info = ClientInfo {
        ip,
        user_agent,
    };

    req.extensions_mut().insert(client_info);
    next.run(req).await
}

/// Role-based authorization middleware
pub async fn require_role(
    req: Request<Body>,
    next: Next<Body>,
    required_roles: Vec<String>,
) -> Response {
    // Get authentication data from request
    let auth_data = req.extensions()
        .get::<AuthData>()
        .cloned()
        .unwrap_or_default();

    // Check if user is authenticated
    if auth_data.user_id.is_none() {
        return Response::builder()
            .status(StatusCode::UNAUTHORIZED)
            .body(Body::from("Authentication required"))
            .unwrap();
    }

    // Check if user has one of the required roles
    let has_required_role = auth_data.roles.iter()
        .any(|role| required_roles.contains(role));

    if !has_required_role {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .body(Body::from("Insufficient permissions"))
            .unwrap();
    }

    // Continue with the request
    next.run(req).await
}

/// Admin role authorization - shorthand for requiring the "admin" role
pub async fn require_admin_role(
    req: Request<Body>,
    next: Next<Body>,
) -> Response {
    require_role(req, next, vec!["admin".to_string()]).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ObservabilityConfig;
    use crate::data::cache::Cache;
    use crate::service::observability::ObservabilityService;
    use axum::{routing::get, Router};
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use hyper::body;
    use std::sync::Arc;
    use tower::ServiceExt;
    use crate::service::observability::ObservabilityService;
    use axum::extract::Extension;
    use axum::http::Request;
    use axum::routing::get;
    use axum::{Router, Json};
    use axum::body::Body;
    use axum::http::StatusCode;
    use hyper::header::HeaderValue;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use std::net::SocketAddr;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;
    use std::time::Duration;
    use tokio::runtime::Runtime;
    use tower::ServiceExt;

    // Helper function to create a test app with rate limiting
    async fn test_app(max_requests: u64) -> Router {
        // Create rate limiter config
        let config = RateLimitConfig {
            max_requests,
            window_seconds: 60,
            bypass_localhost: false,
        };

        // Create observability service
        let observability = ObservabilityService::new(
            Arc::new(crate::config::ObservabilityConfig {
            enable_metrics: true,
            log_level: "info".to_string(),
            }),
            Arc::new(crate::data::cache::Cache::new_for_test()),
        );

        // Create app with rate limiting middleware
        Router::new()
            .route("/api/metrics", get(metrics_handler))
            .layer(axum::middleware::from_fn(metrics_rate_limit_middleware))
            .layer(Extension(Arc::new(
                observability.create_rate_limiter(config)
            )))
    }

    // Test metrics handler
    async fn metrics_handler() -> Json<serde_json::Value> {
        Json(serde_json::json!({ "metrics": "data" }))
    }

    // Middleware implementation for metrics endpoint rate limiting
    async fn metrics_rate_limit_middleware<B>(
        Extension(rate_limiter): Extension<Arc<RateLimiter>>,
        ConnectInfo(addr): Option<ConnectInfo<SocketAddr>>,
        request: Request<B>,
        next: Next<B>,
    ) -> Response {
        let ip = if let Some(conn_info) = addr {
            conn_info.ip().to_string()
        } else if let Some(ip) = get_client_ip(&request) {
            ip
        } else {
            "unknown".to_string()
        };

        // Check rate limit
        if rate_limiter.check(&ip).await {
            // Allowed, proceed with request
            next.run(request).await
        } else {
            // Rate limited
            too_many_requests_response()
        }
    }

    // Property-based test for rate limiting middleware
    proptest! {
        #[test]
        fn test_rate_limit_middleware_properties(
            max_requests in 1..10u64,
            request_count in 1..20u64
        ) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create app with rate limiting
                let app = test_app(max_requests).await;

                // Create a request
                let req = Request::builder()
                    .uri("/api/metrics")
                    .header("X-Forwarded-For", "192.168.1.1")
                    .body(Body::empty())
                    .unwrap();

                // Make multiple requests
                let mut responses = Vec::new();
                for _ in 0..request_count {
                    let response = app.clone().oneshot(req.clone()).await.unwrap();
                    responses.push(response.status());
                }

                // Count successful responses
                let success_count = responses.iter()
                    .filter(|status| **status == StatusCode::OK)
                    .count() as u64;

                // Count rate limited responses
                let limited_count = responses.iter()
                    .filter(|status| **status == StatusCode::TOO_MANY_REQUESTS)
                    .count() as u64;

                // Verify expected behavior
                prop_assert_eq!(success_count, max_requests.min(request_count));
                prop_assert_eq!(limited_count, if request_count > max_requests { request_count - max_requests } else { 0 });

                Ok(())
            })
        }
    }

        #[test]
    fn test_bypass_localhost() {
        let rt = Runtime::new().unwrap();

            rt.block_on(async {
            // Create rate limiter that bypasses localhost
            let config = RateLimitConfig {
                max_requests: 1,
                window_seconds: 60,
                bypass_localhost: true,
            };

            let observability = ObservabilityService::new(
                Arc::new(crate::config::ObservabilityConfig {
                    enable_metrics: true,
                    log_level: "info".to_string(),
                }),
                Arc::new(crate::data::cache::Cache::new_for_test()),
            );

            let rate_limiter = observability.create_rate_limiter(config);

            // Localhost requests should always be allowed
            for _ in 0..10 {
                assert!(rate_limiter.check("127.0.0.1").await);
                assert!(rate_limiter.check("::1").await);
                assert!(rate_limiter.check("localhost").await);
            }

            // Non-localhost should be rate limited
            assert!(rate_limiter.check("192.168.1.1").await);
            assert!(!rate_limiter.check("192.168.1.1").await);
            });
        }

        #[test]
    fn test_client_ip_extraction() {
        // Test with X-Forwarded-For header
        let mut req = Request::builder()
            .uri("/api/metrics")
            .body(())
            .unwrap();

        req.headers_mut().insert(
            "X-Forwarded-For",
            HeaderValue::from_static("203.0.113.195, 70.41.3.18, 150.172.238.178")
        );

        let ip = get_client_ip(&req);
        assert_eq!(ip, Some("203.0.113.195".to_string()));

        // Test with ConnectInfo
        let mut req = Request::builder()
            .uri("/api/metrics")
            .body(())
                    .unwrap();

        let socket_addr: SocketAddr = "127.0.0.1:12345".parse().unwrap();
        req.extensions_mut().insert(ConnectInfo(socket_addr));

        let ip = get_client_ip(&req);
        assert_eq!(ip, Some("127.0.0.1".to_string()));
    }

    // Add more existing tests here...
}
