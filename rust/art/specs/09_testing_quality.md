# Art: Testing and Quality Assurance

## Overview

This document outlines the testing strategy and quality assurance processes for the Art project. It covers different testing levels, methodologies, tools, and quality metrics to ensure a robust, reliable Git repository browser.

## Testing Principles

The Art testing strategy is guided by the following principles:

1. **Test Early, Test Often**: Integrate testing throughout the development process
2. **Automate Where Possible**: Maximize test automation for consistent results
3. **Coverage Matters**: Aim for high test coverage of critical paths and components
4. **Performance is a Feature**: Include performance testing as a core part of testing
5. **Security by Design**: Incorporate security testing throughout the development lifecycle
6. **Accessible to All**: Test for accessibility compliance
7. **Observable System**: Implement comprehensive logging and metrics for operational visibility
8. **Property-Based Testing**: Prioritize property-based testing to uncover edge cases and ensure correctness

## Observability Strategy

Art implements a comprehensive observability strategy using the tracing crate for structured logging and metrics collection.

### Tracing Implementation

The tracing crate provides a framework for collecting structured, contextual, and hierarchical diagnostic information about program execution.

#### Core Components

- **Spans**: Represent time spans during which program execution is in a particular context
- **Events**: Point-in-time occurrences with associated data
- **Fields**: Key-value pairs that provide context to spans and events
- **Subscribers**: Components that receive and process trace data
- **Layers**: Composable pieces of functionality for processing trace data

#### Configuration

```rust
fn setup_tracing() {
    // Create a registry for multiple subscribers
    let registry = tracing_subscriber::registry()
        // Add a fmt layer to output logs to the console
        .with(tracing_subscriber::fmt::layer())
        // Add a layer for OpenTelemetry export
        .with(tracing_opentelemetry::layer())
        // Filter spans and events based on level
        .with(tracing_subscriber::EnvFilter::from_default_env());

    // Set the registry as the global default
    registry.try_init().unwrap();
}
```

### Logging Strategy

#### Log Levels

- **ERROR**: Error conditions that prevent operation from continuing
- **WARN**: Warning conditions that don't prevent operation
- **INFO**: Informational messages about normal operation
- **DEBUG**: Detailed information for debugging
- **TRACE**: Very detailed information for tracing program execution

#### Structured Logging

All logs include structured context information:

```rust
tracing::info!(
    repository_id = repo.id,
    repository_name = repo.name,
    user_id = user.id,
    duration_ms = elapsed.as_millis(),
    "Completed repository indexing"
);
```

#### Contextual Information

Common contextual information included in logs:

- Request ID for tracking requests across components
- User ID for authenticated requests
- Repository ID for repository-specific operations
- Duration for performance tracking
- Resource usage information when relevant

### Metrics Collection

Art uses the tracing crate to collect metrics that are exposed via a Prometheus endpoint.

#### Core Metrics

1. **HTTP Metrics**
   - Request counts by endpoint
   - Request duration histograms
   - Error rates
   - Status code distributions

2. **Git Operation Metrics**
   - Clone/fetch/push operation counts
   - Operation duration
   - Error rates by operation type
   - Data transfer sizes

3. **Cache Metrics**
   - Hit/miss rates by cache type
   - Eviction counts
   - Cache size usage
   - Cache entry counts

4. **Database Metrics**
   - Query execution times
   - Transaction counts
   - Connection pool utilization
   - Error rates

5. **System Metrics**
   - Memory usage
   - CPU utilization
   - Open file descriptors
   - Garbage collection metrics

#### Implementation

```rust
// Define metrics
lazy_static! {
    static ref HTTP_REQUESTS_TOTAL: IntCounterVec = IntCounterVec::new(
        opts!("art_http_requests_total", "Total HTTP requests"),
        &["method", "path"]
    ).unwrap();

    static ref HTTP_REQUEST_DURATION: HistogramVec = HistogramVec::new(
        histogram_opts!("art_http_request_duration_seconds", "HTTP request duration"),
        &["method", "path"]
    ).unwrap();

    // Additional metrics...
}

// Record metrics during operation
async fn handle_request(req: Request) -> Response {
    let path = req.path().to_string();
    let method = req.method().to_string();

    HTTP_REQUESTS_TOTAL.with_label_values(&[&method, &path]).inc();

    let timer = HTTP_REQUEST_DURATION
        .with_label_values(&[&method, &path])
        .start_timer();

    let response = process_request(req).await;

    timer.observe_duration();

    response
}
```

### Health Endpoint

The `/health` endpoint provides information about the system's operational status:

```rust
async fn health_handler() -> Response {
    let health_status = HealthStatus {
        status: check_overall_health().await,
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime: get_uptime().as_secs(),
        components: collect_component_status().await,
    };

    Json(health_status).into_response()
}
```

### Prometheus Integration

The `/metrics` endpoint exposes all metrics in Prometheus format:

```rust
async fn metrics_handler() -> Response {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();

    Response::builder()
        .status(200)
        .header("Content-Type", "text/plain")
        .body(buffer.into())
        .unwrap()
}
```

## Testing Levels

### Unit Testing

Unit tests verify the functionality of individual components in isolation.

#### Scope

- Individual functions and methods
- Small, isolated modules
- Core algorithms
- Utility functions
- Data models

#### Implementation

- Use Rust's built-in testing framework
- Aim for >80% code coverage for critical components
- Implement both positive and negative test cases
- Mock external dependencies using appropriate mocking libraries
- Combine with property-based testing for exhaustive test coverage

#### Example Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_commit_parsing() {
        let raw_commit = "..."; // Sample commit data
        let commit = parse_commit(raw_commit).unwrap();

        assert_eq!(commit.hash, "a1b2c3d4e5f6");
        assert_eq!(commit.author, "John Doe <john@example.com>");
        assert_eq!(commit.message, "Fix bug in parser");
    }

    #[test]
    fn test_invalid_commit_handling() {
        let invalid_commit = "..."; // Invalid commit data
        let result = parse_commit(invalid_commit);

        assert!(result.is_err());
        assert_eq!(result.unwrap_err().to_string(), "Invalid commit format");
    }
}
```

### Property-Based Testing

Property-based testing is a core testing methodology for Art, helping ensure correctness across a wide range of inputs and scenarios that might be missed by traditional example-based testing.

#### Scope

- Complex algorithms and data structures
- Parsing and formatting functions
- Data validation logic
- State transitions
- Edge case handling
- Performance invariants
- Concurrency properties

#### Key Properties to Test

- **Bidirectional Transformations**: For any serialization/deserialization, `deserialize(serialize(x)) == x`
- **Idempotence**: For operations that should be idempotent, `f(f(x)) == f(x)`
- **Commutativity**: For operations where order shouldn't matter, `f(a, b) == f(b, a)`
- **Invariants**: Properties that should always hold true regardless of input
- **State Transitions**: System should maintain consistency across state changes
- **Error Handling**: System should handle all error cases gracefully

#### Implementation

- Use `proptest` crate for defining properties and generating test cases
- Define custom generators for domain-specific types
- Use shrinking to find minimal failing examples
- Combine with model checking for state transition testing
- Include property tests in CI/CD pipeline with seed preservation for reproducibility

#### Example Property Tests

```rust
use proptest::prelude::*;

proptest! {
    // Test that parsing and re-formatting a commit hash is idempotent
    #[test]
    fn commit_hash_parse_format_roundtrip(hash in "[0-9a-f]{40}") {
        let parsed = CommitHash::parse(&hash).unwrap();
        let formatted = parsed.to_string();
        assert_eq!(hash, formatted);
    }

    // Test that our path sanitization prevents path traversal
    #[test]
    fn path_sanitization_prevents_traversal(
        path in "(/\\.\\./)*[a-zA-Z0-9/._-]+"
    ) {
        let sanitized = sanitize_path(&path);
        assert!(!sanitized.contains(".."));
        assert!(!sanitized.starts_with('/'));
    }

    // Test that our cache behaves correctly under all inputs
    #[test]
    fn cache_operations_maintain_consistency(
        operations in vec(cache_operation_strategy(), 1..100)
    ) {
        let mut cache = Cache::new(50);
        let mut model = HashMap::new();

        for op in operations {
            match op {
                CacheOp::Insert(k, v) => {
                    cache.insert(k.clone(), v.clone());
                    model.insert(k, v);
                }
                CacheOp::Remove(k) => {
                    cache.remove(&k);
                    model.remove(&k);
                }
                CacheOp::Get(k) => {
                    assert_eq!(cache.get(&k), model.get(&k).cloned());
                }
            }
        }
    }

    // Test that our repository indexing is resilient to various inputs
    #[test]
    fn indexing_handles_all_repository_structures(
        repo_structure in repository_structure_strategy()
    ) {
        let temp_dir = TempDir::new().unwrap();
        create_test_repository(&temp_dir, &repo_structure);

        let result = block_on(async {
            let indexer = RepositoryIndexer::new();
            indexer.index(&temp_dir).await
        });

        assert!(result.is_ok());
        // Verify indexed content matches expected structure
        let indexed = result.unwrap();
        assert_eq!(indexed.branches.len(), repo_structure.branches.len());
        assert_eq!(indexed.tags.len(), repo_structure.tags.len());
        // More assertions...
    }
}

// Custom strategy for generating cache operations
fn cache_operation_strategy() -> impl Strategy<Value = CacheOp> {
    prop_oneof![
        // Insert operation with String key and usize value
        (any::<String>(), any::<usize>()).prop_map(|(k, v)| CacheOp::Insert(k, v)),
        // Remove operation with String key
        any::<String>().prop_map(|k| CacheOp::Remove(k)),
        // Get operation with String key
        any::<String>().prop_map(|k| CacheOp::Get(k)),
    ]
}

// Types for the cache operation test
#[derive(Debug, Clone)]
enum CacheOp {
    Insert(String, usize),
    Remove(String),
    Get(String),
}
```

#### Benefits of Property-Based Testing in Art

- **Exhaustive Testing**: Generates test cases that developers might not think of
- **Confidence in Correctness**: Provides strong guarantees about code correctness
- **Minimal Examples**: Automatically reduces failing cases to minimal reproducible examples
- **Documentation**: Properties serve as executable documentation of system invariants
- **Resilience to Changes**: Tests continue to check properties even as implementation details change

### Integration Testing

Integration tests verify that components work together correctly.

#### Scope

- API endpoints
- Service interactions
- Database operations
- Git operations chain
- End-to-end workflows

#### Implementation

- Use a testing framework like `tokio::test` for async tests
- Test with actual database connections (using test databases)
- Test real Git repositories (using test repositories)
- Verify multi-step processes like repository indexing

#### Example Integration Tests

```rust
#[tokio::test]
async fn test_repository_listing() {
    let app = create_test_app().await;
    let client = TestClient::new(app);

    // Create test repositories
    setup_test_repositories().await;

    // Test the repository listing endpoint
    let response = client
        .get("/api/v1/repositories")
        .send()
        .await;

    assert_eq!(response.status(), 200);

    let body = response.json::<Vec<Repository>>().await;
    assert_eq!(body.len(), 3); // Expecting 3 test repositories
    assert_eq!(body[0].name, "test-repo-1");
}
```

### System Testing

System tests verify the entire application as a complete system.

#### Scope

- Complete user workflows
- Browser interaction
- Git client interaction
- Performance under load
- Error handling

#### Implementation

- End-to-end testing with simulated user interactions
- Browser automation for UI testing
- Real Git client calls for testing Git operations
- Load testing with multiple concurrent users

### Observability Testing

Testing the observability capabilities of the system.

#### Scope

- Log generation and formatting
- Metrics collection and exposure
- Tracing context propagation
- Health check functionality

#### Implementation

- Verify that all critical operations produce appropriate logs
- Ensure metrics are properly collected and exposed
- Test health endpoint provides accurate status information
- Validate tracing context is properly propagated

#### Example Observability Tests

```rust
#[tokio::test]
async fn test_metrics_endpoint() {
    let app = create_test_app().await;
    let client = TestClient::new(app);

    // Perform some operations to generate metrics
    client.get("/api/v1/repositories").send().await;
    client.get("/api/v1/repositories").send().await;

    // Test metrics endpoint
    let response = client.get("/metrics").send().await;

    assert_eq!(response.status(), 200);

    let body = response.text().await;

    // Verify metrics include our HTTP requests
    assert!(body.contains("art_http_requests_total{method=\"get\",path=\"/api/v1/repositories\"} 2"));
}

#[tokio::test]
async fn test_health_endpoint() {
    let app = create_test_app().await;
    let client = TestClient::new(app);

    let response = client.get("/health").send().await;

    assert_eq!(response.status(), 200);

    let body = response.json::<HealthResponse>().await;

    assert_eq!(body.status, "healthy");
    assert!(body.components.contains_key("database"));
    assert!(body.components.contains_key("git"));
    assert!(body.components.contains_key("cache"));
}
```

### Performance Testing

Performance tests measure the system's responsiveness and resource utilization.

#### Scope

- Response time for common operations
- Throughput under different loads
- Resource utilization (CPU, memory, disk I/O)
- Scaling characteristics
- Database query performance

#### Implementation

- Benchmark core operations
- Load testing with realistic workloads
- Testing with repositories of different sizes
- Database performance analysis

#### Performance Metrics

- Page load time (< 500ms target)
- API response time (< 200ms target)
- Git operation completion time (depends on size)
- Maximum concurrent users supported
- CPU and memory consumption

### Security Testing

Security tests identify vulnerabilities and ensure data protection.

#### Scope

- Authentication and authorization
- Input validation
- Injection attacks (SQL, command)
- Path traversal
- Cross-site scripting (XSS)
- Cross-site request forgery (CSRF)

#### Implementation

- Security-focused code reviews
- Static analysis tools
- Dependency scanning
- Penetration testing
- Authorization bypass testing

### Accessibility Testing

Testing to ensure the application is usable by people with disabilities.

#### Scope

- WCAG 2.1 AA compliance
- Screen reader compatibility
- Keyboard navigation
- Color contrast
- Text scaling

#### Implementation

- Automated accessibility checks
- Manual testing with assistive technologies
- Keyboard-only testing
- Contrast ratio verification

## Testing Tools and Infrastructure

### Testing Frameworks and Libraries

- **Unit Testing**: Rust built-in test framework
- **Mocking**: `mockall` for mocking dependencies
- **Async Testing**: `tokio-test` for async code
- **HTTP Testing**: `reqwest` with test helpers
- **Property Testing**: `proptest` and `quickcheck` for comprehensive property-based testing
- **Performance Testing**: `criterion` for benchmarking
- **Browser Testing**: `fantoccini` or similar for WebDriver tests

### Observability Tools

- **Logging**: tracing crate with JSON formatting
- **Metrics**: Prometheus integration via tracing
- **Distributed Tracing**: OpenTelemetry integration
- **Visualization**: Grafana dashboards for metrics

### Continuous Integration

- Run tests on every pull request
- Run comprehensive test suite before merges
- Regular scheduled test runs for long-running tests
- Performance regression testing

### Test Environment

- Isolated test environment for integration tests
- Dockerized testing for consistent environments
- Seed data for realistic test scenarios
- Git test repositories of various sizes and complexities

## Test Coverage

### Code Coverage Goals

- **Core Components**: >80% line coverage
- **Critical Paths**: >90% branch coverage
- **Property-Tested Code**: 100% of critical algorithms covered by property tests
- **Utility Code**: >70% line coverage
- **UI Components**: >60% functional coverage

### Coverage Measurement

- Use `cargo-tarpaulin` or similar for Rust code coverage
- Generate coverage reports during CI runs
- Review coverage trends over time
- Identify uncovered critical paths

## Test Data Management

### Test Repositories

- Small test repositories for quick unit tests
- Medium-sized repositories for integration testing
- Large repositories for performance testing
- Repositories with specific characteristics for edge case testing

### Database Test Data

- Test fixtures for database testing
- Migration testing data
- Performance testing datasets

### Test Data Generation

- Utilities for generating test commits
- Repository generators for performance testing
- User and permission generators

## Quality Gates

### Pull Request Criteria

- All tests must pass
- Code coverage must not decrease
- No new linting errors
- Performance must not regress
- Security checks must pass
- Property tests must be written for new algorithms and data structures

### Release Criteria

- Full test suite passes
- Performance meets benchmarks
- Security scan completed
- Accessibility compliance verified
- No known critical bugs

## Continuous Monitoring

- Performance monitoring in production
- Error tracking and reporting
- User experience monitoring
- Security vulnerability scanning

## Defect Management

### Bug Severity Levels

1. **Critical**: System crash, data loss, security vulnerability
2. **Major**: Functionality broken, no workaround
3. **Minor**: Functionality issue with workaround
4. **Trivial**: Cosmetic issues, non-functional improvements

### Defect Lifecycle

1. Discovery and reporting
2. Triage and prioritization
3. Assignment
4. Fixing
5. Verification
6. Closure

## Documentation

### Test Documentation

- Test plan
- Test cases
- Test reports
- Coverage reports

### Quality Metrics Dashboard

- Test pass/fail rates
- Code coverage
- Performance metrics
- Bug counts and severity
- Technical debt indicators

### Observability Documentation

- Logging conventions and formats
- Available metrics and their interpretation
- Dashboard setup and configuration
- Alert rules and response procedures

## Implementation Examples

### Example: Repository Service Unit Tests

```rust
#[cfg(test)]
mod repository_service_tests {
    use super::*;
    use mockall::predicate::*;

    #[tokio::test]
    async fn test_get_repository_returns_repository_when_exists() {
        let mut mock_repo_dao = MockRepositoryDao::new();
        mock_repo_dao
            .expect_find_by_name()
            .with(eq("test-repo"))
            .times(1)
            .returning(|_| Ok(Some(Repository {
                id: 1,
                name: "test-repo".to_string(),
                description: Some("Test Repository".to_string()),
                // ... other fields
            })));

        let service = RepositoryService::new(mock_repo_dao);
        let result = service.get_repository("test-repo").await;

        assert!(result.is_ok());
        let repo = result.unwrap();
        assert_eq!(repo.name, "test-repo");
    }

    #[tokio::test]
    async fn test_get_repository_returns_error_when_not_exists() {
        let mut mock_repo_dao = MockRepositoryDao::new();
        mock_repo_dao
            .expect_find_by_name()
            .with(eq("non-existent"))
            .times(1)
            .returning(|_| Ok(None));

        let service = RepositoryService::new(mock_repo_dao);
        let result = service.get_repository("non-existent").await;

        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err().to_string(),
            "Repository 'non-existent' not found"
        );
    }
}
```

### Example: API Integration Test

```rust
#[tokio::test]
async fn test_repository_api_integration() {
    // Setup test app with real components
    let app = test_helpers::create_test_app().await;
    let client = reqwest::Client::new();

    // Create a test repository
    test_helpers::create_test_repository("api-test-repo").await;

    // Test repository info endpoint
    let response = client
        .get(&format!("{}/api/v1/repositories/api-test-repo", app.address))
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 200);

    let repo_info: RepositoryInfo = response.json().await.unwrap();
    assert_eq!(repo_info.name, "api-test-repo");

    // Test commit listing endpoint
    let commits_response = client
        .get(&format!(
            "{}/api/v1/repositories/api-test-repo/commits",
            app.address
        ))
        .send()
        .await
        .unwrap();

    assert_eq!(commits_response.status(), 200);

    let commits: Vec<CommitInfo> = commits_response.json().await.unwrap();
    assert!(!commits.is_empty());
}
```

### Example: Performance Test

```rust
use criterion::{criterion_group, criterion_main, Criterion};

fn benchmark_repository_indexing(c: &mut Criterion) {
    let runtime = tokio::runtime::Runtime::new().unwrap();

    c.bench_function("index_small_repository", |b| {
        b.iter(|| {
            runtime.block_on(async {
                let service = create_test_indexing_service().await;
                service.index_repository("small-test-repo").await.unwrap();
            });
        });
    });

    c.bench_function("index_large_repository", |b| {
        b.to_async(runtime).iter(|| async {
            let service = create_test_indexing_service().await;
            service.index_repository("large-test-repo").await.unwrap()
        });
    });
}

criterion_group!(benches, benchmark_repository_indexing);
criterion_main!(benches);
```

### Example: Property-Based Test for Path Handling

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn repository_path_normalization_is_correct(
        // Generate path with potential edge cases
        input in "(/?\\.?/?[a-zA-Z0-9_.-]+)*/?"
    ) {
        let normalized = normalize_repository_path(&input);

        // Properties that should always hold
        assert!(!normalized.contains("//"));
        assert!(!normalized.ends_with('/'));

        // Idempotence property
        assert_eq!(normalize_repository_path(&normalized), normalized);

        // Reference resolution property
        if !input.contains("..") {
            assert_eq!(
                std::path::Path::new(&input).components().count(),
                std::path::Path::new(&normalized).components().count()
            );
        }
    }
}
```

## Conclusion

The testing and quality assurance strategy for Art ensures comprehensive verification of functionality, performance, security, and accessibility. By implementing this testing approach with a strong emphasis on property-based testing, we can deliver a high-quality Git repository browser that meets user expectations, maintains reliability over time, and correctly handles edge cases that might otherwise be missed by traditional testing approaches.
