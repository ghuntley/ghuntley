use axum::{
    body::Body,
    extract::Request,
    middleware::Next,
    response::{IntoResponse, Response},
};
use http::StatusCode;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tracing::{debug, warn};
use hyper::body;
use proptest::prelude::*;
use proptest::strategy::Strategy;

/// Configuration for rate limiting
#[derive(Debug, Clone)]
pub struct RateLimitConfig {
    /// Maximum number of requests allowed per time window
    pub max_requests: u32,

    /// Time window in seconds
    pub window_seconds: u64,

    /// Whether to bypass rate limits for localhost
    pub bypass_localhost: bool,

    /// Response message when rate limited
    pub rate_limit_message: String,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 100,
            window_seconds: 60,
            bypass_localhost: true,
            rate_limit_message: "Rate limit exceeded. Please try again later.".to_string(),
        }
    }
}

/// Rate limiting middleware
#[derive(Debug, Clone)]
pub struct RateLimitMiddleware {
    /// Rate limit configuration
    config: RateLimitConfig,

    /// Rate limit state per IP address
    state: Arc<Mutex<HashMap<IpAddr, RateLimitState>>>,
}

/// State for a single client (IP address)
#[derive(Debug, Clone)]
struct RateLimitState {
    /// Number of requests in the current window
    count: u32,

    /// When the current window started
    window_start: Instant,
}

impl RateLimitMiddleware {
    /// Create a new rate limit middleware
    pub fn new(config: RateLimitConfig) -> Self {
        Self {
            config,
            state: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Check if a request from the given IP is allowed
    async fn is_allowed(&self, ip: IpAddr) -> bool {
        // Bypass rate limiting for localhost if configured
        if self.config.bypass_localhost && (ip.is_loopback() || ip.is_unspecified()) {
            return true;
        }

        let mut state = self.state.lock().await;
        let now = Instant::now();

        // Get or create rate limit state for this IP
        let entry = state.entry(ip).or_insert_with(|| RateLimitState {
            count: 0,
            window_start: now,
        });

        // Check if we need to reset the window
        let window_duration = Duration::from_secs(self.config.window_seconds);
        if now.duration_since(entry.window_start) >= window_duration {
            entry.count = 0;
            entry.window_start = now;
        }

        // Check if we've hit the limit
        if entry.count >= self.config.max_requests {
            warn!("Rate limit exceeded for IP: {}", ip);
            return false;
        }

        // Increment the counter and allow the request
        entry.count += 1;
        true
    }
}

/// Middleware implementation for rate limiting
pub async fn rate_limit(
    rate_limiter: &RateLimitMiddleware,
    request: Request,
    next: Next,
) -> Response {
    // Get client IP from the X-Forwarded-For header or socket address
    let ip = get_client_ip(&request).unwrap_or_else(|| "0.0.0.0".parse().unwrap());

    // Check if the request is allowed
    if rate_limiter.is_allowed(ip).await {
        // Allow the request to proceed
        next.run(request).await
    } else {
        // Return a rate limit exceeded response
        (
            StatusCode::TOO_MANY_REQUESTS,
            rate_limiter.config.rate_limit_message.clone(),
        )
            .into_response()
    }
}

/// Get the client IP from the request
fn get_client_ip(request: &Request) -> Option<IpAddr> {
    // First try X-Forwarded-For header
    if let Some(forwarded_for) = request.headers().get("X-Forwarded-For") {
        if let Ok(forwarded_for) = forwarded_for.to_str() {
            if let Some(ip) = forwarded_for.split(',').next() {
                if let Ok(ip) = ip.trim().parse() {
                    return Some(ip);
                }
            }
        }
    }

    // Fall back to connection info
    request.extensions().get::<IpAddr>().cloned()
}

/// Custom middleware to extract and store client IP in request extensions
pub async fn extract_client_ip(mut request: Request, next: Next) -> Response {
    // Get the socket address from the connection info
    if let Some(addr) = request.extensions().get::<std::net::SocketAddr>().cloned() {
        request.extensions_mut().insert(addr.ip());
    }

    next.run(request).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::middleware::Next;
    use axum::response::Response;
    use hyper::body;
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
    use proptest::prelude::*;
    use proptest::strategy::Strategy;

    // Helper function to create a test request with a specific IP
    async fn create_test_response(
        rate_limiter: &RateLimitMiddleware,
        ip: IpAddr,
    ) -> Response {
        let request = Request::builder()
            .header("x-forwarded-for", ip.to_string())
            .body(Body::empty())
            .unwrap();

        let next = Next::new(|_req: Request<Body>| async move {
            Response::builder()
                .status(StatusCode::OK)
                .body(Body::from("OK"))
                .unwrap()
        });

        rate_limit(rate_limiter, request, next).await
    }

    // Strategy for generating non-localhost IP addresses
    fn non_localhost_ip_strategy() -> impl Strategy<Value = IpAddr> {
        prop_oneof![
            any::<u32>().prop_filter_map("Non-localhost IPv4", |n| {
                let ip = Ipv4Addr::from(n);
                if !ip.is_loopback() && !ip.is_unspecified() {
                    Some(IpAddr::V4(ip))
                } else {
                    None
                }
            }),
            any::<u128>().prop_filter_map("Non-localhost IPv6", |n| {
                let ip = Ipv6Addr::from(n);
                if !ip.is_loopback() && !ip.is_unspecified() {
                    Some(IpAddr::V6(ip))
                } else {
                    None
                }
            })
        ]
    }

    // Strategy for generating rate limit configurations
    fn rate_limit_config_strategy() -> impl Strategy<Value = RateLimitConfig> {
        (10..1000u32, 1..120u64, any::<bool>()).prop_map(|(max_requests, window_seconds, bypass_localhost)| {
            RateLimitConfig {
                max_requests,
                window_seconds,
                bypass_localhost,
                rate_limit_message: "Rate limit exceeded".to_string(),
        }
        })
    }

    proptest! {
        /// Test that the rate limiter allows requests under the limit
        #[test]
        fn prop_rate_limiter_allows_requests_under_limit(
            config in rate_limit_config_strategy(),
            ip in non_localhost_ip_strategy(),
            request_count in 1..100u32
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                // Use the minimum of the generated request count and max_requests - 1
                // to ensure we're always under the limit
                let actual_request_count = std::cmp::min(request_count, config.max_requests - 1);
                let rate_limiter = RateLimitMiddleware::new(config.clone());

                // Send multiple requests, all should be allowed
                for _ in 0..actual_request_count {
                    let response = create_test_response(&rate_limiter, ip).await;
                    assert_eq!(response.status(), StatusCode::OK);
                    }
            });
        }

        /// Test that the rate limiter blocks requests over the limit
        #[test]
        fn prop_rate_limiter_blocks_requests_over_limit(
            config in rate_limit_config_strategy(),
            ip in non_localhost_ip_strategy()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let rate_limiter = RateLimitMiddleware::new(config.clone());

                // Send max_requests, all should be allowed
                for _ in 0..config.max_requests {
                    let response = create_test_response(&rate_limiter, ip).await;
                    assert_eq!(response.status(), StatusCode::OK);
                }

                // The next request should be blocked
                let response = create_test_response(&rate_limiter, ip).await;
                assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
            });
        }

        /// Test that localhost bypasses rate limiting when configured
        #[test]
        fn prop_localhost_bypass(
            max_requests in 10..1000u32,
            request_count in 1001..2000u32
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let config = RateLimitConfig {
                    max_requests,
                    window_seconds: 60,
                    bypass_localhost: true,
                    rate_limit_message: "Rate limit exceeded".to_string(),
                };

                let rate_limiter = RateLimitMiddleware::new(config);
                let localhost = IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1));

                // Send many more requests than the limit allows
                for _ in 0..request_count {
                    let response = create_test_response(&rate_limiter, localhost).await;
                    assert_eq!(response.status(), StatusCode::OK);
                }
            });
        }
    }
}
