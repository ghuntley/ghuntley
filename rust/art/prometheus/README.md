# Art Observability

This directory contains configuration and documentation for the observability features of the Art application.

## Observability Features in Art

Art provides comprehensive observability features to help you monitor, debug, and understand your application's behavior:

### 1. Prometheus Metrics

Art exposes detailed metrics through a Prometheus-compatible `/metrics` endpoint. These metrics are categorized as follows:

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

Art provides dedicated API endpoints to access repository content metrics:

- `GET /api/repo/:repo/metrics`: Get metrics for a specific repository
- `GET /api/repos/metrics`: Get metrics for all repositories
- `POST /api/repos/metrics/refresh`: Force a refresh of repository metrics

These endpoints allow you to monitor the growth and composition of your repositories over time, helping you understand usage patterns and resource requirements.

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

## Setup and Configuration

### Prometheus Configuration

The `prometheus.yml` file is configured to scrape the Art application's metrics endpoint. It includes:

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

Art supports OpenTelemetry for distributed tracing. To enable it, add the following to your configuration:

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

To configure the repository content metrics collector:

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

### Alerting Rules

The `rules/alerting_rules.yml` file contains Prometheus alerting rules for critical conditions such as:

- High error rates
- Slow response times
- Memory usage thresholds
- Repository size anomalies

### Recording Rules

The `rules/recording_rules.yml` file pre-calculates metrics for efficient querying, including:

- Request rates over time
- Error percentages
- Cache hit ratios
- Repository growth rates

## Using Grafana for Visualization

A pre-configured Grafana dashboard is available in `grafana_dashboard.json`. This dashboard provides:

- Overview of system metrics
- HTTP request statistics
- Git operation performance
- Cache efficiency
- Repository content metrics

## Practical Usage Examples

### Monitoring Repository Growth

Track the growth of repositories over time to plan for storage needs:

```promql
repository_size_bytes{repository="main-repo"}[1w]
```

### Tracking File Types Distribution

Understand what types of files are stored in your repositories:

```promql
repository_file_type_count{repository="main-repo"}
```

### Analyzing Commit Patterns

Monitor commit frequency to understand development patterns:

```promql
repository_commit_count{repository="main-repo", timeframe="day"}
```

### Distributed Tracing Analysis

1. Identify slow operations in trace spans
2. Correlate logs with trace IDs
3. Track request flows across system boundaries

### Log Query Examples

Query logs for a specific trace ID:

```
GET /api/logs?trace_id=4bf92f3577b34da6a3ce929d0e0e4736
```

Filter logs by repository:

```
GET /api/logs?repository=main-repo&level=error
```

## Rate Limiting for Observability Endpoints

To prevent abuse, all observability endpoints are protected by rate limiting:

- 60 requests per minute per IP address
- Bypasses rate limits for localhost
- Returns 429 Too Many Requests when limit exceeded
