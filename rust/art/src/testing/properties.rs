// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Property assertions for Art
//!
//! This module provides common property assertions for property-based testing.

use crate::prelude::*;
use proptest::prelude::*;
use std::collections::HashMap;
use std::path::Path;
use std::time::{Duration, Instant};

/// Check that a function is idempotent (f(f(x)) == f(x))
pub fn check_idempotent<F, T>(mut f: F, value: T) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(T) -> T,
    T: Clone + PartialEq + std::fmt::Debug,
{
    let once = f(value.clone());
    let twice = f(once.clone());

    prop_assert_eq!(once, twice, "Function should be idempotent");

    Ok(())
}

/// Check that a function is commutative (f(a, b) == f(b, a))
pub fn check_commutative<F, T>(mut f: F, a: T, b: T) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(T, T) -> T,
    T: Clone + PartialEq + std::fmt::Debug,
{
    let ab = f(a.clone(), b.clone());
    let ba = f(b, a);

    prop_assert_eq!(ab, ba, "Function should be commutative");

    Ok(())
}

/// Check that a function preserves the inverse relationship (f(g(x)) == x)
pub fn check_inverse<F, G, T>(mut f: F, mut g: G, value: T) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(T) -> T,
    G: FnMut(T) -> T,
    T: Clone + PartialEq + std::fmt::Debug,
{
    let result = f(g(value.clone()));

    prop_assert_eq!(result, value, "Functions should be inverses");

    Ok(())
}

/// Check that a function execution time is within an expected range
pub fn check_performance<F, T, R>(
    mut f: F,
    value: T,
    max_duration: Duration,
) -> Result<R, TestCaseError>
where
    F: FnMut(T) -> R,
{
    let start = Instant::now();
    let result = f(value);
    let elapsed = start.elapsed();

    prop_assert!(
        elapsed <= max_duration,
        "Function execution time ({:?}) exceeded maximum allowed duration ({:?})",
        elapsed,
        max_duration
    );

    Ok(result)
}

/// Check that a path sanitization function prevents path traversal attacks
pub fn check_path_sanitization<F>(mut sanitize: F, path: String) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(&str) -> String,
{
    let sanitized = sanitize(&path);

    // Should not contain parent directory references
    prop_assert!(!sanitized.contains(".."), "Sanitized path should not contain '..'");

    // Should not start with a slash
    prop_assert!(!sanitized.starts_with('/'), "Sanitized path should not start with '/'");

    // Should not contain null bytes
    prop_assert!(!sanitized.contains('\0'), "Sanitized path should not contain null bytes");

    // Resulting path should be valid
    prop_assert!(
        Path::new(&sanitized).components().count() > 0,
        "Sanitized path should be valid"
    );

    Ok(())
}

/// Check that a function is atomic and all-or-nothing
pub async fn check_atomicity<F, T, R>(
    mut operation: F,
    state: T,
    verify_unchanged: impl Fn(&T) -> std::result::Result<(), TestCaseError>,
    verify_changed: impl Fn(&T, &R) -> std::result::Result<(), TestCaseError>,
) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(&T) -> impl std::future::Future<Output = std::result::Result<R, crate::error::Error>>,
    T: Clone + std::fmt::Debug,
    R: std::fmt::Debug,
{
    // Clone the initial state for verification
    let initial_state = state.clone();

    // Run the operation
    let result = operation(&state).await;

    match result {
        Ok(result) => {
            // Operation succeeded, verify state changed correctly
            verify_changed(&state, &result)?;
        }
        Err(_) => {
            // Operation failed, verify state is unchanged
            verify_unchanged(&initial_state)?;
        }
    }

    Ok(())
}

/// Check that an HTTP handler produces the expected response
pub async fn check_http_handler<F, T>(
    mut handler: F,
    request: T,
    expected_status: u16,
) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(T) -> impl std::future::Future<Output = axum::response::Response>,
{
    let response = handler(request).await;

    // Check status code
    let status = response.status().as_u16();
    prop_assert_eq!(status, expected_status, "Unexpected HTTP status code");

    Ok(())
}

/// Check that a cache behaves correctly (stores and retrieves values)
pub async fn check_cache_behavior<C, K, V>(
    cache: &C,
    key: K,
    value: V,
) -> std::result::Result<(), TestCaseError>
where
    C: CacheBehavior<K, V>,
    K: Clone + std::fmt::Debug,
    V: Clone + PartialEq + std::fmt::Debug,
{
    // Clear key if it exists
    cache.remove(&key).await;

    // Check that key doesn't exist
    let result = cache.get(&key).await;
    prop_assert!(result.is_none(), "Key should not exist in cache before insertion");

    // Insert the value
    cache.put(&key, value.clone()).await;

    // Check that the value is in the cache
    let result = cache.get(&key).await;
    prop_assert!(result.is_some(), "Key should exist in cache after insertion");
    prop_assert_eq!(result.unwrap(), value, "Cache returned wrong value");

    // Remove the key
    cache.remove(&key).await;

    // Check that key is gone
    let result = cache.get(&key).await;
    prop_assert!(result.is_none(), "Key should not exist in cache after removal");

    Ok(())
}

/// Trait defining the cache behavior methods required by the property test
#[async_trait::async_trait]
pub trait CacheBehavior<K, V> {
    /// Get a value from the cache
    async fn get(&self, key: &K) -> Option<V>;

    /// Put a value in the cache
    async fn put(&self, key: &K, value: V);

    /// Remove a value from the cache
    async fn remove(&self, key: &K);
}

/// Check that a SQL query sanitization function prevents SQL injection
pub fn check_sql_sanitization<F>(mut sanitize: F, input: String) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(&str) -> String,
{
    let sanitized = sanitize(&input);

    // Check common SQL injection patterns
    prop_assert!(!sanitized.contains("--"), "Sanitized SQL should not contain comments");
    prop_assert!(!sanitized.contains(';'), "Sanitized SQL should not contain semicolons");
    prop_assert!(!sanitized.to_uppercase().contains(" OR 1=1"), "Sanitized SQL should not contain OR 1=1");
    prop_assert!(!sanitized.to_uppercase().contains("DROP TABLE"), "Sanitized SQL should not contain DROP TABLE");
    prop_assert!(!sanitized.to_uppercase().contains("DELETE FROM"), "Sanitized SQL should not contain DELETE FROM");

    Ok(())
}

/// Check that a function reacts correctly to rate limiting
pub async fn check_rate_limiting<F>(
    mut operation: F,
    count: usize,
    expected_success: usize,
) -> std::result::Result<(), TestCaseError>
where
    F: FnMut() -> impl std::future::Future<Output = bool>,
{
    let mut success_count = 0;

    // Run the operation count times
    for _ in 0..count {
        if operation().await {
            success_count += 1;
        }
    }

    // Check that we had the expected number of successes
    prop_assert_eq!(
        success_count,
        expected_success,
        "Rate limiting did not allow the expected number of operations"
    );

    Ok(())
}

/// Check property invariants for a state-changing operation
pub async fn check_state_invariants<F, T>(
    mut operation: F,
    state: T,
    verify_invariants: impl Fn(&T) -> std::result::Result<(), TestCaseError>,
) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(&T) -> impl std::future::Future<Output = std::result::Result<(), crate::error::Error>>,
    T: Clone + std::fmt::Debug,
{
    // Verify invariants on initial state
    verify_invariants(&state)?;

    // Apply the operation
    operation(&state).await?;

    // Verify invariants still hold
    verify_invariants(&state)?;

    Ok(())
}

/// Check that a concurrent operation maintains consistency
pub async fn check_concurrent_consistency<F, G, T>(
    mut setup: F,
    mut concurrent_ops: G,
    state: T,
    verify_consistent: impl Fn(&T) -> std::result::Result<(), TestCaseError>,
) -> std::result::Result<(), TestCaseError>
where
    F: FnMut(&T) -> impl std::future::Future<Output = std::result::Result<(), crate::error::Error>>,
    G: FnMut(&T) -> impl std::future::Future<Output = std::result::Result<(), crate::error::Error>>,
    T: Clone + std::fmt::Debug + Send + Sync + 'static,
{
    // Initialize state
    setup(&state).await?;

    // Verify state is initially consistent
    verify_consistent(&state)?;

    // Run concurrent operations
    let handles = (0..10).map(|_| {
        let state_clone = state.clone();
        let mut ops = concurrent_ops.clone();
        tokio::spawn(async move {
            ops(&state_clone).await
        })
    }).collect::<Vec<_>>();

    // Wait for all operations to complete
    for handle in handles {
        handle.await??;
    }

    // Verify state remains consistent
    verify_consistent(&state)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn test_check_idempotent() {
        // Test with a function that is idempotent
        let f = |x: String| x.trim().to_lowercase();

        proptest!(|(s in "\\PC{1,100}")| {
            check_idempotent(f, s)?;
        });

        // Test with a function that is not idempotent
        let bad_f = |mut x: Vec<i32>| {
            x.push(0);
            x
        };

        // This should fail
        let result = check_idempotent(bad_f, vec![1, 2, 3]);
        assert!(result.is_err());
    }

    #[test]
    fn test_check_commutative() {
        // Test with a function that is commutative
        let add = |a: i32, b: i32| a + b;

        proptest!(|(a in -1000..1000i32, b in -1000..1000i32)| {
            check_commutative(add, a, b)?;
        });

        // Test with a function that is not commutative
        let subtract = |a: i32, b: i32| a - b;

        // This should fail for non-equal values
        let result = check_commutative(subtract, 5, 3);
        assert!(result.is_err());
    }

    #[test]
    fn test_check_inverse() {
        // Test with functions that are inverses
        let encode = |s: String| base64::encode(s);
        let decode = |s: String| String::from_utf8(base64::decode(s).unwrap_or_default()).unwrap_or_default();

        proptest!(|(s in "\\PC{1,100}")| {
            // Check encode -> decode roundtrip
            check_inverse(decode, encode, s)?;
        });
    }

    #[tokio::test]
    async fn test_check_cache_behavior() {
        // Create a simple in-memory cache implementation for testing
        struct TestCache {
            data: Arc<tokio::sync::Mutex<HashMap<String, String>>>,
        }

        impl TestCache {
            fn new() -> Self {
                Self {
                    data: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
                }
            }
        }

        #[async_trait::async_trait]
        impl CacheBehavior<String, String> for TestCache {
            async fn get(&self, key: &String) -> Option<String> {
                self.data.lock().await.get(key).cloned()
            }

            async fn put(&self, key: &String, value: String) {
                self.data.lock().await.insert(key.clone(), value);
            }

            async fn remove(&self, key: &String) {
                self.data.lock().await.remove(key);
            }
        }

        // Test the cache behavior
        let cache = TestCache::new();

        proptest!(|(key in "[a-zA-Z0-9]{1,20}", value in "[a-zA-Z0-9]{1,50}")| {
            let fut = async {
                check_cache_behavior(&cache, key, value).await
            };
            tokio::runtime::Runtime::new().unwrap().block_on(fut)?;
        });
    }
}
