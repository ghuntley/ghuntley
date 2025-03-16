# Observability Features

## Overview

This document outlines the observability features implemented in the Art application. These features help in monitoring, debugging, and understanding the behavior of the application in production environments.

## Features

### 1. Prometheus Metrics

Art exposes a Prometheus-compatible `/metrics` endpoint that provides detailed metrics about the application's performance and state.

#### System Metrics
- `art_memory_usage_bytes`: Memory usage of the Art application
- `art_active_connections`: Number of active connections
- `art_http_requests_total`: Total number of HTTP requests
- `art_http_request_duration_seconds`: HTTP request duration histogram
- `art_http_response_status`: HTTP response status codes

#### Git Operation Metrics
- `art_git_operations_total`: Total number of Git operations
- `art_git_operation_duration_seconds`: Git operation duration histogram

#### Cache Metrics
- `art_cache_hits_total`: Total number of cache hits
- `art_cache_misses_total`: Total number of cache misses

#### Repository Content Metrics
- `repository_file_count`: Number of files in repository
- `repository_size_bytes`: Total size of all files in repository in bytes
- `repository_commit_count`: Number of commits in repository by timeframe
- `repository_contributor_count`: Number of contributors to repository
- `repository_age_days`: Age of repository in days
- `repository_file_type_count`: Number of files of each type in repository
- `repository_file_size_distribution`: Distribution of file sizes in repository

### 2. Repository Content Metrics API

Dedicated API endpoints to access repository content metrics:

- `GET /api/repo/:repo/metrics`: Get metrics for a specific repository
- `GET /api/repos/metrics`: Get metrics for all repositories
- `POST /api/repos/metrics/refresh`: Force a refresh of repository metrics

### 3. Structured Logging

Art uses structured JSON logging with the following features:

- JSON format for easy parsing
- Trace context included in all logs
- Contextual information such as request path, user, and repository
- Log levels to filter by importance
- Query logs through the `/api/logs` endpoint

### 4. Distributed Tracing

Art supports distributed tracing with the following features:

- Trace context propagation in HTTP headers
- OpenTelemetry integration for exporting traces
- Recording of spans for key operations
- Correlation IDs to link related operations

### 5. Health Checks

A health check endpoint at `/api/health` provides the following information:

- Application status (up/down)
- Uptime
- Version
- Component health status
- Memory usage

### 6. Rate Limiting for Observability Endpoints

To prevent abuse, all observability endpoints are protected by rate limiting:

- 60 requests per minute per IP address
- Bypasses rate limits for localhost
- Returns 429 Too Many Requests when limit exceeded

## Configuration

### Prometheus Configuration

Configuration file: `prometheus.yml`

```yaml
scrape_configs:
  - job_name: 'art'
    scrape_interval: 15s
    metrics_path: '/api/metrics'
    static_configs:
      - targets: ['art:3000']
        labels:
          instance: 'art'
          service: 'art'
```

### OpenTelemetry Integration

```toml
[observability.opentelemetry]
enabled = true
service_name = "art"
endpoint = "http://otel-collector:4317"
sample_all = true

[observability.opentelemetry.resource_attributes]
deployment.environment = "production"
```

### Repository Content Metrics Configuration

```toml
[observability.content_metrics]
enabled = true
collection_interval_seconds = 3600
max_repositories = 100
track_file_types = true
track_file_sizes = true
track_commit_stats = true
track_contributor_stats = true
track_activity_stats = true
```

### Rate Limiting Configuration

```toml
[observability.rate_limit]
max_requests = 60
window_seconds = 60
bypass_localhost = true
```

## Implementation Details

### Metrics Implementation

Metrics are collected and exposed using the `prometheus` crate. The `ObservabilityService` manages metric registration and collection:

- HTTP metrics are collected in the `MetricsMiddleware`
- Git operation metrics are recorded in the `Git` implementation
- Repository content metrics are collected by the `ContentMetricsCollector`
- System metrics are recorded in the `ObservabilityService`

### Logging Implementation

Structured logging is implemented using the `tracing` crate with a JSON formatter. Log entries include:

- Timestamp
- Log level
- Message
- Context fields
- Trace context for correlation with distributed traces

### Distributed Tracing Implementation

Distributed tracing is implemented with the following components:

- `OpenTelemetryTracer` for managing trace contexts
- `TraceContext` struct for storing trace information
- Trace context propagation in HTTP headers
- Integration with OpenTelemetry for exporting traces

### Health Check Implementation

Health checks are exposed via the `/api/health` endpoint, providing:

- Overall status
- Application version
- Uptime
- Component statuses
- Memory usage

### Rate Limiting Implementation

Rate limiting is implemented using the `RateLimitMiddleware` that:

- Tracks request counts per IP address
- Enforces rate limits based on configuration
- Allows bypass for localhost connections
- Returns appropriate status codes when limits are exceeded

## Testing

All observability features include comprehensive property-based tests to ensure their correctness:

- Tests for metrics recording and retrieval
- Tests for log entry creation and querying
- Tests for trace context propagation
- Tests for health check responses
- Tests for rate limiting behavior

## Future Extensions

Potential future extensions to observability features:

1. Integration with additional tracing backends
2. Enhanced metrics for specific application features
3. More sophisticated alerting rules
4. Enhanced visualization options
5. Machine learning for anomaly detection
