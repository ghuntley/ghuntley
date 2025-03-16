use art::service::observability::{
    ObservabilityService, ObservabilityConfig, OpenTelemetryConfig,
    TraceContext, LogLevel
};
use art::error::Result;

use std::collections::HashMap;
use std::sync::Arc;
use chrono::Utc;
use serde_json::json;
use futures::future::join_all;
use tokio::time::{sleep, Duration};

#[tokio::test]
async fn test_opentelemetry_trace_context_propagation() -> Result<()> {
    // Create a test OpenTelemetry configuration
    let opentelemetry_config = OpenTelemetryConfig {
        enabled: true,
        endpoint: "http://localhost:4317".to_string(),
        service_name: "art-test".to_string(),
        sampling_ratio: 1.0, // Sample all traces for testing
        timeout_seconds: 5,
        default_attributes: HashMap::new(),
        export_otlp: true,
        export_stdout: true, // Export to stdout for test verification
    };

    // Create a test observability configuration
    let mut config = ObservabilityConfig::default();
    config.opentelemetry = Some(opentelemetry_config);

    // Create the observability service
    let service = ObservabilityService::new(
        config,
        None, // Use default Prometheus registry
        None, // No content metrics for this test
    ).await?;

    // Create a root trace context
    let root_context = service.create_trace_context();

    // Verify the root context properties
    assert!(!root_context.trace_id.is_empty(), "Trace ID should not be empty");
    assert!(!root_context.span_id.is_empty(), "Span ID should not be empty");
    assert!(root_context.parent_id.is_none(), "Root context should not have parent");

    // Create child spans
    let child_context = root_context.create_child();

    // Verify child context properties
    assert_eq!(child_context.trace_id, root_context.trace_id, "Child should have same trace ID");
    assert!(child_context.span_id != root_context.span_id, "Child should have different span ID");
    assert_eq!(child_context.parent_id, Some(root_context.span_id.clone()), "Child's parent ID should be root's span ID");

    // Add baggage items
    let mut context_with_baggage = child_context.clone();
    context_with_baggage.add_baggage("test-key", "test-value");

    // Verify baggage
    let baggage_value = context_with_baggage.get_baggage("test-key");
    assert_eq!(baggage_value, Some(&"test-value".to_string()), "Baggage item not set correctly");

    // Record traces
    service.record_trace(&root_context);
    service.record_trace(&child_context);
    service.record_trace(&context_with_baggage);

    // Log entries with trace context
    let fields = HashMap::from([
        ("operation".to_string(), json!("test_operation")),
        ("duration_ms".to_string(), json!(42)),
    ]);

    service.log(LogLevel::Info, "Test log with trace context", fields.clone(), Some(root_context.clone()));

    Ok(())
}

#[tokio::test]
async fn test_opentelemetry_span_creation() -> Result<()> {
    // Create a test OpenTelemetry configuration
    let opentelemetry_config = OpenTelemetryConfig {
        enabled: true,
        endpoint: "http://localhost:4317".to_string(),
        service_name: "art-test".to_string(),
        sampling_ratio: 1.0,
        timeout_seconds: 5,
        default_attributes: HashMap::new(),
        export_otlp: true,
        export_stdout: true,
    };

    // Create a test observability configuration
    let mut config = ObservabilityConfig::default();
    config.opentelemetry = Some(opentelemetry_config);

    // Create the observability service
    let service = ObservabilityService::new(
        config,
        None,
        None,
    ).await?;

    // Get the OpenTelemetry tracer
    let tracer = service.opentelemetry_tracer();
    assert!(tracer.is_some(), "OpenTelemetry tracer should be available");

    let tracer = tracer.unwrap();

    // Create a trace context
    let context = service.create_trace_context();

    // Create spans using the tracer
    let span_result = tracer.create_span("test_span", &context, opentelemetry::trace::SpanKind::Server);
    assert!(span_result.is_ok(), "Should be able to create span");

    // Create a span and add attributes
    let mut span = span_result.unwrap();
    span.set_attribute(opentelemetry::KeyValue::new("test_attribute", "test_value"));

    // Record events within the span
    span.add_event("test_event", vec![opentelemetry::KeyValue::new("event_detail", "details")]);

    // End the span
    span.end();

    Ok(())
}

#[tokio::test]
async fn test_distributed_tracing_across_components() -> Result<()> {
    // Create a test OpenTelemetry configuration
    let opentelemetry_config = OpenTelemetryConfig {
        enabled: true,
        endpoint: "http://localhost:4317".to_string(),
        service_name: "art-test".to_string(),
        sampling_ratio: 1.0,
        timeout_seconds: 5,
        default_attributes: HashMap::new(),
        export_otlp: true,
        export_stdout: true,
    };

    // Create a test observability configuration
    let mut config = ObservabilityConfig::default();
    config.opentelemetry = Some(opentelemetry_config);

    // Create the observability service
    let service = Arc::new(ObservabilityService::new(
        config,
        None,
        None,
    ).await?);

    // Simulate a request flowing through multiple components

    // Component 1: HTTP server receives request
    let trace_context = service.create_trace_context();

    let fields1 = HashMap::from([
        ("component".to_string(), json!("http_server")),
        ("method".to_string(), json!("GET")),
        ("path".to_string(), json!("/api/repo/test/metrics")),
    ]);

    service.log(LogLevel::Info, "Received HTTP request", fields1, Some(trace_context.clone()));

    // Component 2: Repository service processes request
    let repo_context = trace_context.create_child();

    let fields2 = HashMap::from([
        ("component".to_string(), json!("repository_service")),
        ("repository".to_string(), json!("test")),
        ("operation".to_string(), json!("get_metrics")),
    ]);

    service.log(LogLevel::Info, "Processing repository metrics request", fields2, Some(repo_context.clone()));

    // Component 3: Git service interacts with repository
    let git_context = repo_context.create_child();

    let fields3 = HashMap::from([
        ("component".to_string(), json!("git_service")),
        ("repository".to_string(), json!("test")),
        ("operation".to_string(), json!("stat")),
    ]);

    service.log(LogLevel::Info, "Executing Git operation", fields3, Some(git_context.clone()));

    // Verify trace context propagation
    assert_eq!(git_context.trace_id, trace_context.trace_id, "Trace ID should be consistent across components");
    assert_eq!(git_context.parent_id, Some(repo_context.span_id.clone()), "Parent IDs should form a chain");
    assert_eq!(repo_context.parent_id, Some(trace_context.span_id.clone()), "Parent IDs should form a chain");

    // Query traces (this will work only if a real OpenTelemetry backend is available)
    if cfg!(feature = "integration_tests") {
        // Give some time for traces to be exported
        sleep(Duration::from_secs(1)).await;

        // Query traces by the trace ID
        let traces = service.query_traces(10, Some("art-test")).await;

        // We can't assert much here without a real backend, but we can check if the function runs
        if let Ok(traces) = traces {
            println!("Found {} traces", traces.len());
        }
    }

    Ok(())
}

#[tokio::test]
async fn test_concurrent_trace_context_creation() -> Result<()> {
    // Create a test OpenTelemetry configuration
    let opentelemetry_config = OpenTelemetryConfig {
        enabled: true,
        endpoint: "http://localhost:4317".to_string(),
        service_name: "art-test".to_string(),
        sampling_ratio: 1.0,
        timeout_seconds: 5,
        default_attributes: HashMap::new(),
        export_otlp: true,
        export_stdout: true,
    };

    // Create a test observability configuration
    let mut config = ObservabilityConfig::default();
    config.opentelemetry = Some(opentelemetry_config);

    // Create the observability service
    let service = Arc::new(ObservabilityService::new(
        config,
        None,
        None,
    ).await?);

    // Create many trace contexts concurrently
    let tasks = (0..100).map(|_| {
        let service_clone = service.clone();
        tokio::spawn(async move {
            service_clone.create_trace_context()
        })
    }).collect::<Vec<_>>();

    // Wait for all tasks to complete
    let contexts = join_all(tasks).await;

    // Verify that all trace contexts have unique trace IDs and span IDs
    let mut trace_ids = std::collections::HashSet::new();
    let mut span_ids = std::collections::HashSet::new();

    for context_result in contexts {
        let context = context_result.unwrap();
        trace_ids.insert(context.trace_id.clone());
        span_ids.insert(context.span_id.clone());
    }

    // All trace IDs and span IDs should be unique
    assert_eq!(trace_ids.len(), 100, "Should have 100 unique trace IDs");
    assert_eq!(span_ids.len(), 100, "Should have 100 unique span IDs");

    Ok(())
}
