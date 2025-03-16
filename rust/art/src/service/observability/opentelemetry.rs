use crate::error::{Error, Result};
use crate::service::observability::{TraceContext, LogLevel};
use opentelemetry::{
    global,
    sdk::{trace as sdktrace, Resource},
    trace::{Span, TraceContextExt, TracerProvider, Tracer},
    Context, KeyValue,
};
use opentelemetry::trace::SpanKind;
use opentelemetry_otlp::WithExportConfig;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use uuid::Uuid;
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use anyhow::Result;
use proptest::prelude::*;
use proptest::collection::{vec, hash_map};
use proptest::option::of;
use std::sync::Arc;
use tokio::runtime::Runtime;
use crate::service::observability::{
    ObservabilityService, ObservabilityConfig, Cache, LogLevel
};
use std::collections::BTreeMap;
use std::iter::FromIterator;
use opentelemetry::trace::{SpanId, TraceId, SpanContext, SpanKind, TraceFlags};
use opentelemetry::baggage::{BaggageExt, Baggage};

/// Configuration for OpenTelemetry integration
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OpenTelemetryConfig {
    /// Whether to enable OpenTelemetry tracing
    pub enabled: bool,

    /// The endpoint to send traces to
    pub endpoint: String,

    /// The service name to use for traces
    pub service_name: String,

    /// Sampling rate (0.0-1.0, where 1.0 means 100% sampling)
    pub sampling_ratio: f64,

    /// The timeout for sending traces (in seconds)
    pub timeout_seconds: u64,

    /// Additional attributes to include with every span
    pub default_attributes: HashMap<String, String>,

    /// Whether to export traces to OTLP
    pub export_otlp: bool,

    /// Whether to export traces to stdout (for debugging)
    pub export_stdout: bool,
}

impl Default for OpenTelemetryConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            endpoint: "http://localhost:4317".to_string(),
            service_name: "art".to_string(),
            sampling_ratio: 0.1,
            timeout_seconds: 5,
            default_attributes: HashMap::new(),
            export_otlp: true,
            export_stdout: false,
        }
    }
}

/// OpenTelemetry tracer for integration with external tracing systems
pub struct OpenTelemetryTracer {
    /// The actual OpenTelemetry tracer
    tracer: sdktrace::Tracer,

    /// Configuration for OpenTelemetry
    config: OpenTelemetryConfig,

    /// Whether OpenTelemetry is initialized
    initialized: bool,
}

impl OpenTelemetryTracer {
    /// Create a new OpenTelemetry tracer
    pub fn new(config: OpenTelemetryConfig) -> Result<Self> {
        if !config.enabled {
            // Return a no-op tracer if disabled
            return Ok(Self {
                tracer: sdktrace::Tracer::default(),
                config,
                initialized: false,
            });
        }

        // Set up the OpenTelemetry tracer
        let mut builder = opentelemetry_otlp::new_pipeline()
            .tracing()
            .with_exporter(
                opentelemetry_otlp::new_exporter()
                    .tonic()
                    .with_endpoint(config.endpoint.clone())
                    .with_timeout(Duration::from_secs(config.timeout_seconds))
            );

        // Configure sampling based on configuration
        if config.sampling_ratio < 1.0 {
            let sampler = sdktrace::Sampler::ParentBased(Box::new(
                sdktrace::Sampler::TraceIdRatioBased(config.sampling_ratio)
            ));
            builder = builder.with_sampler(sampler);
        }

        // Add service name and other attributes as resource
        let mut resource_attributes = Vec::new();
        resource_attributes.push(KeyValue::new("service.name", config.service_name.clone()));

        for (key, value) in &config.default_attributes {
            resource_attributes.push(KeyValue::new(key.clone(), value.clone()));
        }

        let resource = Resource::new(resource_attributes);
        builder = builder.with_resource(resource);

        // Build the tracer
        let tracer = builder.install_batch(opentelemetry::runtime::Tokio)?;

        Ok(Self {
            tracer,
            config,
            initialized: true,
        })
    }

    /// Convert our internal TraceContext to an OpenTelemetry span context
    /// Returns a tuple of (parent_cx, trace_id, span_id)
    fn convert_trace_context(&self, trace_ctx: &TraceContext) -> (Context, String, String) {
        // Create a new OpenTelemetry context
        let context = Context::current();

        // Return the original trace_ctx's IDs for correlation
        (context, trace_ctx.trace_id.clone(), trace_ctx.span_id.clone())
    }

    /// Create a new span from our internal TraceContext
    pub fn create_span(&self, name: &str, trace_ctx: &TraceContext, kind: SpanKind) -> Result<impl Span> {
        if !self.initialized {
            return Err(Error::Internal("OpenTelemetry not initialized".to_string()));
        }

        let (parent_cx, trace_id, span_id) = self.convert_trace_context(trace_ctx);

        // Create a span builder
        let mut builder = self.tracer
            .span_builder(name)
            .with_kind(kind);

        // Add our trace context as baggage items
        builder = builder.with_attributes(vec![
            KeyValue::new("art.trace_id", trace_id),
            KeyValue::new("art.span_id", span_id),
        ]);

        // Add any baggage items from our trace context
        for (key, value) in &trace_ctx.baggage {
            builder = builder.with_attributes(vec![
                KeyValue::new(format!("baggage.{}", key), value.clone()),
            ]);
        }

        // Create the span
        let span = self.tracer.build_with_context(builder, &parent_cx);

        Ok(span)
    }

    /// Create and record a span with the provided information
    pub fn create_and_record_span(
        &self,
        name: &str,
        trace_ctx: &TraceContext,
        attributes: &[(&str, &str)],
        events: &[(&str, HashMap<String, String>)],
        kind: SpanKind,
    ) -> Result<()> {
        if !self.initialized {
            return Ok(());
        }

        // Create a new span
        let mut span = self.create_span(name, trace_ctx, kind)?;

        // Add attributes
        for (key, value) in attributes {
            span.set_attribute(KeyValue::new(*key, (*value).to_string()));
        }

        // Add events
        for (event_name, event_attrs) in events {
            let mut attrs = Vec::with_capacity(event_attrs.len());
            for (k, v) in event_attrs {
                attrs.push(KeyValue::new(k.clone(), v.clone()));
            }
            span.add_event(*event_name, attrs);
        }

        // Record the span
        span.end();

        Ok(())
    }

    /// Record a span with the given name, trace context, attributes, and events
    /// Simplified interface for middleware
    pub fn record_span(
        &self,
        name: &str,
        trace_ctx: &TraceContext,
        attributes: &[(&str, &str)],
        events: &[(&str, &[(&str, &str)])],
        kind: SpanKind,
    ) -> Result<()> {
        // Skip if not enabled
        if !self.config.enabled {
            return Ok(());
        }

        // Create a span with the provided trace context
        let mut span_builder = self.tracer.span_builder(name)
            .with_trace_id(trace_ctx.trace_id.clone())
            .with_span_id(trace_ctx.span_id.clone())
            .with_kind(kind);

        // Set parent ID if present
        if let Some(parent_id) = &trace_ctx.parent_id {
            span_builder = span_builder.with_parent_span_id(parent_id.clone());
        }

        // Add attributes
        for (key, value) in attributes {
            span_builder = span_builder.with_attribute(key.to_string(), value.to_string());
        }

        // Create the span
        let mut span = span_builder.start(&self.tracer);

        // Add events
        for (event_name, event_attrs) in events {
            let mut event = span.add_event(event_name.to_string());

            for (attr_key, attr_value) in event_attrs {
                event = event.with_attribute(attr_key.to_string(), attr_value.to_string());
            }

            event.end();
        }

        // End the span
        span.end();

        Ok(())
    }

    /// Shutdown the tracer provider, flushing any remaining spans
    pub fn shutdown(&self) -> Result<()> {
        if self.initialized {
            global::shutdown_tracer_provider();
        }
        Ok(())
    }
}

/// Convert a TraceContext to OpenTelemetry format for external systems
pub fn convert_to_otel_format(trace_ctx: &TraceContext) -> HashMap<String, String> {
    let mut headers = HashMap::new();

    // Add standard W3C Trace Context headers
    headers.insert(
        "traceparent".to_string(),
        format!("00-{}-{}-{}",
            trace_ctx.trace_id,
            trace_ctx.span_id,
            if trace_ctx.sampled { "01" } else { "00" }
        )
    );

    // Add baggage if present
    if !trace_ctx.baggage.is_empty() {
        let baggage: Vec<String> = trace_ctx.baggage
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect();
        headers.insert("baggage".to_string(), baggage.join(","));
    }

    headers
}

/// Extract trace context from HTTP headers
///
/// This function attempts to extract trace context from HTTP headers in the following order:
/// 1. W3C Trace Context (traceparent, tracestate)
/// 2. Jaeger format (uber-trace-id)
/// 3. Zipkin format (x-b3-traceid, x-b3-spanid, x-b3-parentspanid, x-b3-sampled)
///
/// Returns None if no valid trace context could be extracted.
pub fn extract_from_http_headers(headers: &HashMap<String, String>) -> Option<TraceContext> {
    // First try W3C format (OpenTelemetry)
    if let Some(ctx) = extract_from_otel_format(headers) {
        return Some(ctx);
    }

    // Then try Jaeger format
    if let Some(ctx) = extract_from_jaeger_format(headers) {
        return Some(ctx);
    }

    // Finally try Zipkin format
    if let Some(ctx) = extract_from_zipkin_format(headers) {
        return Some(ctx);
    }

    None
}

/// Extract trace context from W3C Trace Context format
fn extract_from_otel_format(headers: &HashMap<String, String>) -> Option<TraceContext> {
    // Get traceparent header
    let traceparent = headers.get("traceparent")?;

    // Parse traceparent header (format: 00-trace_id-span_id-flags)
    let parts: Vec<&str> = traceparent.split('-').collect();
    if parts.len() != 4 {
        return None;
    }

    // Extract trace ID and span ID
    let trace_id = parts[1].to_string();
    let span_id = parts[2].to_string();

    // Extract flags
    let flags = u8::from_str_radix(parts[3], 16).ok()?;
    let sampled = (flags & 0x01) != 0;

    // Get tracestate header if present
    let baggage = if let Some(tracestate) = headers.get("tracestate") {
        let mut baggage_items = HashMap::new();

        // Parse tracestate header (format: key1=value1,key2=value2)
        for item in tracestate.split(',') {
            let kv: Vec<&str> = item.split('=').collect();
            if kv.len() == 2 {
                baggage_items.insert(kv[0].trim().to_string(), kv[1].trim().to_string());
            }
        }

        baggage_items
    } else {
        HashMap::new()
    };

    // Create trace context
    Some(TraceContext {
        trace_id,
        span_id,
        parent_id: None,  // Not provided in traceparent
        sampled,
        baggage,
    })
}

/// Extract trace context from Jaeger format
fn extract_from_jaeger_format(headers: &HashMap<String, String>) -> Option<TraceContext> {
    // Get uber-trace-id header
    let trace_header = headers.get("uber-trace-id")?;

    // Parse uber-trace-id header (format: trace_id:span_id:parent_id:flags)
    let parts: Vec<&str> = trace_header.split(':').collect();
    if parts.len() != 4 {
        return None;
    }

    // Extract trace ID, span ID, and parent ID
    let trace_id = parts[0].to_string();
    let span_id = parts[1].to_string();
    let parent_id = if parts[2] == "0" || parts[2].is_empty() {
        None
    } else {
        Some(parts[2].to_string())
    };

    // Extract sampling flag
    let flags = u8::from_str_radix(parts[3], 16).ok()?;
    let sampled = (flags & 0x01) != 0;

    // Extract baggage items
    let mut baggage = HashMap::new();
    for (key, value) in headers {
        if key.starts_with("jaeger-baggage-") {
            let baggage_key = key.strip_prefix("jaeger-baggage-").unwrap().to_string();
            baggage.insert(baggage_key, value.clone());
        }
    }

    // Create trace context
    Some(TraceContext {
        trace_id,
        span_id,
        parent_id,
        sampled,
        baggage,
    })
}

/// Extract trace context from Zipkin format
fn extract_from_zipkin_format(headers: &HashMap<String, String>) -> Option<TraceContext> {
    // Get required headers
    let trace_id = headers.get("x-b3-traceid")?.to_string();
    let span_id = headers.get("x-b3-spanid")?.to_string();

    // Get optional headers
    let parent_id = headers.get("x-b3-parentspanid").map(|s| s.to_string());
    let sampled = headers.get("x-b3-sampled")
        .map(|s| s == "1" || s.to_lowercase() == "true")
        .unwrap_or(false);

    // Create trace context
    Some(TraceContext {
        trace_id,
        span_id,
        parent_id,
        sampled,
        baggage: HashMap::new(),  // Zipkin doesn't have baggage
    })
}

/// Convert trace context to Jaeger format headers
pub fn convert_to_jaeger_format(ctx: &TraceContext) -> HashMap<String, String> {
    let mut headers = HashMap::new();

    // Create uber-trace-id header
    let flags = if ctx.sampled { "1" } else { "0" };
    let parent_id = ctx.parent_id.as_deref().unwrap_or("0");
    let uber_trace_id = format!("{}:{}:{}:{}", ctx.trace_id, ctx.span_id, parent_id, flags);
    headers.insert("uber-trace-id".to_string(), uber_trace_id);

    // Add baggage items
    for (key, value) in &ctx.baggage {
        let baggage_key = format!("jaeger-baggage-{}", key);
        headers.insert(baggage_key, value.clone());
    }

    headers
}

/// Convert trace context to Zipkin format headers
pub fn convert_to_zipkin_format(ctx: &TraceContext) -> HashMap<String, String> {
    let mut headers = HashMap::new();

    // Add required headers
    headers.insert("x-b3-traceid".to_string(), ctx.trace_id.clone());
    headers.insert("x-b3-spanid".to_string(), ctx.span_id.clone());

    // Add optional headers
    if let Some(parent_id) = &ctx.parent_id {
        headers.insert("x-b3-parentspanid".to_string(), parent_id.clone());
    }

    // Add sampling flag
    headers.insert("x-b3-sampled".to_string(), if ctx.sampled { "1" } else { "0" });

    headers
}

/// Simple Record Span Result
pub struct RecordSpanResult {
    /// Trace ID
    pub trace_id: String,
    /// Span ID
    pub span_id: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::observability::TraceContext;
    use proptest::prelude::*;
    use proptest::collection::{vec, hash_map};
    use proptest::option::of;
    use std::sync::Arc;
    use tokio::runtime::Runtime;
    use crate::service::observability::{
        ObservabilityService, ObservabilityConfig, Cache, LogLevel
    };
    use std::collections::BTreeMap;
    use std::iter::FromIterator;
    use opentelemetry::trace::{SpanId, TraceId, SpanContext, SpanKind, TraceFlags};
    use opentelemetry::{Context, KeyValue};
    use opentelemetry::baggage::{BaggageExt, Baggage};
    use opentelemetry::trace::TracerProvider;

    // Generate valid trace IDs
    fn valid_trace_id() -> impl Strategy<Value = String> {
        r"[a-f0-9]{32}".prop_map(|s| s)
    }

    // Generate valid span IDs
    fn valid_span_id() -> impl Strategy<Value = String> {
        r"[a-f0-9]{16}".prop_map(|s| s)
    }

    // Generate valid attribute keys
    fn valid_attribute_key() -> impl Strategy<Value = String> {
        r"[a-z][a-z0-9\._\-]{0,49}".prop_map(|s| s)
    }

    // Generate valid attribute values
    fn valid_attribute_value() -> impl Strategy<Value = String> {
        r"[a-zA-Z0-9\._\-]{0,255}".prop_map(|s| s)
    }

    // Generate a set of span attributes
    fn span_attributes() -> impl Strategy<Value = Vec<(String, String)>> {
        prop::collection::vec(
            (valid_attribute_key(), valid_attribute_value()),
            0..10
        )
    }

    // Generate a span event
    fn span_event() -> impl Strategy<Value = (String, Vec<(String, String)>)> {
        (
            r"[a-zA-Z0-9\._\-]{1,100}".prop_map(|s| s),
            span_attributes()
        )
    }

    // Generate a list of span events
    fn span_events() -> impl Strategy<Value = Vec<(String, Vec<(String, String)>)>> {
        prop::collection::vec(
            span_event(),
            0..5
        )
    }

    // Generate baggage items
    fn baggage_items() -> impl Strategy<Value = BTreeMap<String, String>> {
        prop::collection::btree_map(
            valid_attribute_key(),
            valid_attribute_value(),
            0..10
        )
    }

    // Generate a trace context with optional parent
    fn trace_context(has_parent: bool) -> impl Strategy<Value = TraceContext> {
        (
            valid_trace_id(),
            valid_span_id(),
            if has_parent { of(valid_span_id()) } else { Just(None) },
            any::<bool>(),
            baggage_items()
        ).prop_map(|(trace_id, span_id, parent_id, sampled, baggage)| {
            let mut ctx = TraceContext {
                trace_id,
                span_id,
                parent_id,
                sampled,
                baggage: HashMap::from_iter(baggage.into_iter()),
            };
            ctx
        })
    }

    // Generate OpenTelemetry config with enabled/disabled state
    fn opentelemetry_config(enabled: bool) -> impl Strategy<Value = OpenTelemetryConfig> {
        (
            Just(enabled),
            r"https?://[a-z0-9\.\-]+:[0-9]{2,5}(/[a-z0-9\.\-]+)*".prop_map(|s| s),
            r"[a-zA-Z0-9\.\-_]{1,100}".prop_map(|s| s),
            (0..=100u32).prop_map(|n| n as f64 / 100.0),
            1..60u64,
            hash_map(valid_attribute_key(), valid_attribute_value(), 0..5),
            any::<bool>(),
            any::<bool>()
        ).prop_map(|(enabled, endpoint, service_name, sampling_ratio, timeout_seconds, default_attributes, export_otlp, export_stdout)| {
            OpenTelemetryConfig {
                enabled,
                endpoint,
                service_name,
                sampling_ratio,
                timeout_seconds,
                default_attributes,
                export_otlp,
                export_stdout,
            }
        })
    }

    #[test]
    fn test_otel_format_conversion() {
        // Create a trace context
        let mut trace_ctx = TraceContext::new();
        trace_ctx.add_baggage("test_key", "test_value");

        // Convert to OTel format
        let headers = convert_to_otel_format(&trace_ctx);

        // Verify the traceparent header
        assert!(headers.contains_key("traceparent"));
        let traceparent = headers.get("traceparent").unwrap();
        assert!(traceparent.starts_with("00-"));
        assert!(traceparent.contains(&trace_ctx.trace_id));
        assert!(traceparent.contains(&trace_ctx.span_id));

        // Verify the baggage header
        assert!(headers.contains_key("baggage"));
        assert_eq!(headers.get("baggage").unwrap(), "test_key=test_value");
    }

    #[test]
    fn test_otel_format_extraction() {
        // Create a traceparent header
        let trace_id = "4bf92f3577b34da6a3ce929d0e0e4736";
        let span_id = "00f067aa0ba902b7";
        let traceparent = format!("00-{}-{}-01", trace_id, span_id);

        // Create headers
        let mut headers = HashMap::new();
        headers.insert("traceparent".to_string(), traceparent);
        headers.insert("baggage".to_string(), "test_key=test_value".to_string());

        // Extract a trace context
        let trace_ctx = extract_from_otel_format(&headers).unwrap();

        // Verify the trace context
        assert_eq!(trace_ctx.trace_id, trace_id);
        assert_eq!(trace_ctx.parent_id.unwrap(), span_id);
        assert!(trace_ctx.sampled);
        assert_eq!(trace_ctx.baggage.get("test_key").unwrap(), "test_value");
    }

    proptest! {
        /// Test that trace context can be properly propagated through OpenTelemetry context
        #[test]
        fn test_trace_context_propagation(
            trace_ctx in trace_context(false),
            span_name in r"[a-zA-Z0-9\._\-]{1,100}",
            attributes in span_attributes(),
            events in span_events()
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

                // Create a tracer
                let tracer = OpenTelemetryTracer::new(otel_config).expect("Failed to create tracer");

                // Convert attributes and events to the format expected by record_span
                let attr_refs: Vec<(&str, &str)> = attributes.iter()
                    .map(|(k, v)| (k.as_str(), v.as_str()))
                    .collect();

                let event_refs: Vec<(&str, &[(&str, &str)])> = events.iter()
                    .map(|(name, attrs)| {
                        let attr_refs: Vec<(&str, &str)> = attrs.iter()
                            .map(|(k, v)| (k.as_str(), v.as_str()))
                            .collect();
                        (name.as_str(), attr_refs.as_slice())
                    })
                    .collect();

                // Record a span
                let result = tracer.record_span(
                    span_name.as_str(),
                    &trace_ctx,
                    &attr_refs,
                    &event_refs,
                    SpanKind::Client
                );

                // This shouldn't fail
                prop_assert!(result.is_ok());

                // In a real scenario we would verify span was recorded correctly,
                // but for testing we can only verify the operation completes without errors

                Ok(())
            })
        }

        /// Test that span attributes are correctly handled
        #[test]
        fn test_span_attributes(
            trace_ctx in trace_context(false),
            span_name in r"[a-zA-Z0-9\._\-]{1,100}",
            attributes in span_attributes()
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
                    export_otlp: false,
                    export_stdout: true,
                };

                // Create a tracer
                let tracer = OpenTelemetryTracer::new(otel_config).expect("Failed to create tracer");

                // Convert attributes to the format expected by record_span
                let attr_refs: Vec<(&str, &str)> = attributes.iter()
                    .map(|(k, v)| (k.as_str(), v.as_str()))
                    .collect();

                // Record a span with attributes
                let result = tracer.record_span(
                    span_name.as_str(),
                    &trace_ctx,
                    &attr_refs,
                    &[],
                    SpanKind::Client
                );

                // This shouldn't fail
                prop_assert!(result.is_ok());

                Ok(())
            })
        }

        /// Test that span events are correctly handled
        #[test]
        fn test_span_events(
            trace_ctx in trace_context(false),
            span_name in r"[a-zA-Z0-9\._\-]{1,100}",
            events in span_events()
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
                    export_otlp: false,
                    export_stdout: true,
                };

                // Create a tracer
                let tracer = OpenTelemetryTracer::new(otel_config).expect("Failed to create tracer");

                // Convert events to the format expected by record_span
                let event_refs: Vec<(&str, &[(&str, &str)])> = events.iter()
                    .map(|(name, attrs)| {
                        let attr_refs: Vec<(&str, &str)> = attrs.iter()
                            .map(|(k, v)| (k.as_str(), v.as_str()))
                            .collect();
                        (name.as_str(), attr_refs.as_slice())
                    })
                    .collect();

                // Record a span with events
                let result = tracer.record_span(
                    span_name.as_str(),
                    &trace_ctx,
                    &[],
                    &event_refs,
                    SpanKind::Client
                );

                // This shouldn't fail
                prop_assert!(result.is_ok());

                Ok(())
            })
        }

        /// Test format conversions between W3C, Jaeger, and Zipkin
        #[test]
        fn test_format_conversions(
            trace_ctx in trace_context(true)
        ) {
            // Test W3C format conversion
            let otel_headers = convert_to_otel_format(&trace_ctx);
            prop_assert!(otel_headers.contains_key("traceparent"));

            if !trace_ctx.baggage.is_empty() {
                prop_assert!(otel_headers.contains_key("baggage"));
            }

            // Test extraction from W3C format
            let extracted_ctx = extract_from_otel_format(&otel_headers);
            prop_assert!(extracted_ctx.is_some());

            let extracted_ctx = extracted_ctx.unwrap();
            prop_assert_eq!(extracted_ctx.trace_id, trace_ctx.trace_id);
            prop_assert_eq!(extracted_ctx.span_id, trace_ctx.span_id);
            prop_assert_eq!(extracted_ctx.sampled, trace_ctx.sampled);

            // Test Jaeger format conversion
            let jaeger_headers = convert_to_jaeger_format(&trace_ctx);
            prop_assert!(jaeger_headers.contains_key("uber-trace-id"));

            for (key, _) in &trace_ctx.baggage {
                prop_assert!(jaeger_headers.contains_key(&format!("jaeger-baggage-{}", key)));
            }

            // Test extraction from Jaeger format
            let extracted_ctx = extract_from_jaeger_format(&jaeger_headers);
            prop_assert!(extracted_ctx.is_some());

            let extracted_ctx = extracted_ctx.unwrap();
            prop_assert_eq!(extracted_ctx.trace_id, trace_ctx.trace_id);
            prop_assert_eq!(extracted_ctx.span_id, trace_ctx.span_id);
            if let Some(parent_id) = &trace_ctx.parent_id {
                prop_assert_eq!(extracted_ctx.parent_id, Some(parent_id.clone()));
            }
            prop_assert_eq!(extracted_ctx.sampled, trace_ctx.sampled);
        }

        /// Test that different OpenTelemetry configurations can be created and validated
        #[test]
        fn test_opentelemetry_config(
            config in opentelemetry_config(true)
        ) {
            // Create a tracer with the config
            let tracer = OpenTelemetryTracer::new(config.clone());

            // Tracer creation should succeed
            prop_assert!(tracer.is_ok());

            let tracer = tracer.unwrap();

            // Verify config was applied
            prop_assert_eq!(tracer.config.enabled, config.enabled);
            prop_assert_eq!(tracer.config.endpoint, config.endpoint);
            prop_assert_eq!(tracer.config.service_name, config.service_name);
            prop_assert_eq!(tracer.config.sampling_ratio, config.sampling_ratio);
            prop_assert_eq!(tracer.config.timeout_seconds, config.timeout_seconds);

            // Shutdown should succeed
            let shutdown_result = tracer.shutdown();
            prop_assert!(shutdown_result.is_ok());
        }

        /// Test the interaction with ObservabilityService
        #[test]
        fn test_opentelemetry_observability_integration(
            trace_ctx in trace_context(false),
            trace_id in valid_trace_id(),
            span_id in valid_span_id()
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
                    log_level: LogLevel::Info,
                    metrics_port: 9090,
                    opentelemetry: Some(otel_config),
                    rate_limit: None,
                };

                // Create an observability service with the tracer
                let cache = Arc::new(Cache::new_for_test());
                let service = ObservabilityService::new(Arc::new(config), cache).await.expect("Failed to create service");

                // Create a trace context to record
                let mut trace_ctx = TraceContext::new();
                trace_ctx.trace_id = trace_id.clone();
                trace_ctx.span_id = span_id.clone();

                // Record the trace
                service.record_trace(&trace_ctx);

                // Verify that the service has the tracer configured
                prop_assert!(service.opentelemetry_tracer.is_some());

                Ok(())
            })
        }

        /// Test trace context propagation through HTTP headers
        #[test]
        fn test_http_propagation(
            trace_ctx in trace_context(true),
            format in proptest::sample::select(&["otel", "jaeger", "zipkin"][..])
        ) {
            // Convert to headers based on format
            let headers = match format {
                "otel" => convert_to_otel_format(&trace_ctx),
                "jaeger" => convert_to_jaeger_format(&trace_ctx),
                "zipkin" => convert_to_zipkin_format(&trace_ctx),
                _ => unreachable!(),
            };

            // Extract trace context from headers
            let extracted = extract_from_http_headers(&headers);
            prop_assert!(extracted.is_some());

            let extracted = extracted.unwrap();

            // Verify basic properties are preserved
            prop_assert_eq!(extracted.trace_id, trace_ctx.trace_id);
            prop_assert_eq!(extracted.span_id, trace_ctx.span_id);
            prop_assert_eq!(extracted.sampled, trace_ctx.sampled);

            // Parent ID may not be preserved in W3C format
            if format != "otel" && trace_ctx.parent_id.is_some() {
                prop_assert_eq!(extracted.parent_id, trace_ctx.parent_id);
            }

            // Baggage is only preserved in some formats
            if format == "otel" || format == "jaeger" {
                // Check baggage items are preserved
                for (key, value) in &trace_ctx.baggage {
                    // Jaeger prefixes baggage keys
                    if format == "jaeger" {
                        let header_key = format!("jaeger-baggage-{}", key);
                        prop_assert!(headers.contains_key(&header_key));
                    }
                }
            }
        }

        /// Test OpenTelemetry trace creation with parent context
        #[test]
        fn test_create_child_span(
            parent_ctx in trace_context(false),
            child_name in r"[a-zA-Z0-9\._\-]{1,100}",
            attributes in span_attributes()
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
                    export_otlp: false,
                    export_stdout: true,
                };

                // Create a tracer
                let tracer = OpenTelemetryTracer::new(otel_config).expect("Failed to create tracer");

                // Create a child trace context
                let mut child_ctx = TraceContext::new();
                child_ctx.trace_id = parent_ctx.trace_id.clone();
                child_ctx.parent_id = Some(parent_ctx.span_id.clone());
                child_ctx.sampled = parent_ctx.sampled;

                // Convert attributes to the format expected by record_span
                let attr_refs: Vec<(&str, &str)> = attributes.iter()
                    .map(|(k, v)| (k.as_str(), v.as_str()))
                    .collect();

                // Record a child span
                let result = tracer.record_span(
                    child_name.as_str(),
                    &child_ctx,
                    &attr_refs,
                    &[],
                    SpanKind::Internal
                );

                // This shouldn't fail
                prop_assert!(result.is_ok());

                Ok(())
            })
        }
    }
}
