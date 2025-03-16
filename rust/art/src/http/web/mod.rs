use axum::Router;
use axum::routing::get;
use axum::extract::{Extension, Path, Query, State};
use axum::response::{Html, IntoResponse};
use axum::http::StatusCode;
use crate::http::server::ServerState;
use crate::config::Config;
use std::sync::Arc;
use serde::Deserialize;
use crate::service::observability::LogLevel;
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use crate::template::BaseTemplate;

mod charts;
#[cfg(test)]
mod charts_test;
mod notifications;
mod email;

/// Create web routes for the web UI
pub fn router() -> Router {
    Router::new()
        .route("/", get(index_handler))
        .route("/logs", get(logs_ui_handler))
        .route("/traces", get(traces_ui_handler))
        .route("/metrics", get(metrics_ui_handler))
        .route("/notifications", get(notifications::notification_center_handler))
        .route("/user/settings/email", get(email::email_settings_handler).post(email::update_email_settings_handler))
        .route("/user/settings/email/test", post(email::send_test_email_handler))
}

/// Index page handler
async fn index_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    // Get notification banner
    let notification_banner = render_notification_banner(&state).await;

    // Create the base template
    let base = BaseTemplate {
        title: "Art Git Repository Browser".to_string(),
        description: "Browse Git repositories with Art".to_string(),
        base_url: "/".to_string(),
        current_path: "/".to_string(),
        current_repo: None,
        notification_banner: Some(notification_banner),
    };

    Html(r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ART Observability Dashboard</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                }
                h1 {
                    color: #2c3e50;
                    border-bottom: 2px solid #ecf0f1;
                    padding-bottom: 10px;
                }
                .dashboard {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                    grid-gap: 20px;
                    margin-top: 30px;
                }
                .card {
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
                    padding: 20px;
                    transition: transform 0.3s ease;
                }
                .card:hover {
                    transform: translateY(-5px);
                }
                .card h2 {
                    margin-top: 0;
                    color: #3498db;
                }
                .card p {
                    color: #7f8c8d;
                }
                .card a {
                    display: inline-block;
                    margin-top: 15px;
                    padding: 8px 16px;
                    background-color: #3498db;
                    color: white;
                    text-decoration: none;
                    border-radius: 4px;
                    transition: background-color 0.3s ease;
                }
                .card a:hover {
                    background-color: #2980b9;
                }
            </style>
            <style>
                {notifications::notification_styles()}
            </style>
        </head>
        <body>
            <h1>ART Observability Dashboard</h1>
            <p>Welcome to the ART (Advanced Repository Tool) observability dashboard. Use the cards below to access different monitoring features.</p>

            <div class="dashboard">
                <div class="card">
                    <h2>Logs</h2>
                    <p>View and search structured logs from the ART service.</p>
                    <a href="/logs">View Logs</a>
                </div>

                <div class="card">
                    <h2>Metrics</h2>
                    <p>Analyze repository metrics and performance data.</p>
                    <a href="/metrics">View Metrics</a>
                </div>

                <div class="card">
                    <h2>Traces</h2>
                    <p>Visualize distributed traces and request flows.</p>
                    <a href="/traces">View Traces</a>
                </div>

                <div class="card">
                    <h2>Repository Activity</h2>
                    <p>Monitor repository activity and content statistics.</p>
                    <a href="/metrics#repository">View Activity</a>
                </div>
            </div>
        </body>
        </html>
    "#)
}

/// Query parameters for the logs page
#[derive(Debug, Deserialize, Default)]
pub struct LogsQuery {
    /// Log level filter
    pub level: Option<String>,

    /// Start time for filtering
    pub start: Option<String>,

    /// End time for filtering
    pub end: Option<String>,

    /// Number of logs to show
    pub limit: Option<usize>,

    /// Search query
    pub search: Option<String>,
}

/// Logs page handler
async fn logs_ui_handler(
    State(state): State<ServerState>,
    query: Option<Query<LogsQuery>>,
) -> impl IntoResponse {
    // Default query parameters if not provided
    let query = query.unwrap_or_default();
    let limit = query.limit.unwrap_or(100);
    let level = query.level.as_deref();
    let search = query.search.as_deref();

    // Get logs from the observability service
    let logs = match state.services.observability_service.query_logs(limit, level, search).await {
        Ok(logs) => logs,
        Err(_) => Vec::new(),
    };

    // Format logs into HTML
    let logs_html = logs.iter()
        .map(|log| format!(
            r#"<tr class="log-entry log-{level}">
                <td class="timestamp">{timestamp}</td>
                <td class="level">{level}</td>
                <td class="message">{message}</td>
            </tr>"#,
            timestamp = log.timestamp,
            level = log.level.to_lowercase(),
            message = log.message
        ))
        .collect::<Vec<String>>()
        .join("\n");

    Html(format!(r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ART Logs</title>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                h1 {{
                    color: #2c3e50;
                    border-bottom: 2px solid #ecf0f1;
                    padding-bottom: 10px;
                }}
                .controls {{
                    margin: 20px 0;
                    display: flex;
                    gap: 10px;
                    align-items: center;
                }}
                .controls select, .controls input, .controls button {{
                    padding: 8px;
                    border: 1px solid #ddd;
                    border-radius: 4px;
                }}
                .controls button {{
                    background-color: #3498db;
                    color: white;
                    border: none;
                    cursor: pointer;
                }}
                table {{
                    width: 100%;
                    border-collapse: collapse;
                    margin-top: 20px;
                }}
                th, td {{
                    text-align: left;
                    padding: 12px;
                    border-bottom: 1px solid #ddd;
                }}
                th {{
                    background-color: #f8f9fa;
                }}
                .log-entry {{
                    font-family: monospace;
                }}
                .log-error {{ background-color: #ffebee; }}
                .log-warn {{ background-color: #fff8e1; }}
                .log-info {{ background-color: #f1f8e9; }}
                .log-debug {{ background-color: #e8f5e9; }}
                .log-trace {{ background-color: #f3f3f3; }}
                .timestamp {{ width: 180px; }}
                .level {{ width: 80px; }}
                .nav {{
                    display: flex;
                    gap: 20px;
                    margin-bottom: 20px;
                }}
                .nav a {{
                    text-decoration: none;
                    color: #3498db;
                }}
            </style>
        </head>
        <body>
            <div class="nav">
                <a href="/">Home</a>
                <a href="/logs">Logs</a>
                <a href="/metrics">Metrics</a>
                <a href="/traces">Traces</a>
            </div>

            <h1>ART Logs</h1>

            <form class="controls">
                <select name="level">
                    <option value="">All Levels</option>
                    <option value="ERROR" {error_selected}>ERROR</option>
                    <option value="WARN" {warn_selected}>WARN</option>
                    <option value="INFO" {info_selected}>INFO</option>
                    <option value="DEBUG" {debug_selected}>DEBUG</option>
                    <option value="TRACE" {trace_selected}>TRACE</option>
                </select>

                <input type="text" name="search" placeholder="Search logs..." value="{search}">
                <input type="number" name="limit" placeholder="Limit" value="{limit}">
                <button type="submit">Apply</button>
            </form>

            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Level</th>
                        <th>Message</th>
                    </tr>
                </thead>
                <tbody>
                    {logs_html}
                </tbody>
            </table>
        </body>
        </html>
    "#,
        error_selected = if level == Some("ERROR") { "selected" } else { "" },
        warn_selected = if level == Some("WARN") { "selected" } else { "" },
        info_selected = if level == Some("INFO") { "selected" } else { "" },
        debug_selected = if level == Some("DEBUG") { "selected" } else { "" },
        trace_selected = if level == Some("TRACE") { "selected" } else { "" },
        search = search.unwrap_or(""),
        limit = limit,
        logs_html = logs_html,
    ))
}

async fn traces_ui_handler(
    State(state): State<ServerState>,
    query: Option<Query<TracesQuery>>,
) -> impl IntoResponse {
    // Default query parameters if not provided
    let query = query.unwrap_or_default();
    let limit = query.limit.unwrap_or(100);
    let service = query.service.as_deref();

    // Get traces from the observability service
    let traces = match state.services.observability_service.query_traces(limit, service).await {
        Ok(traces) => traces,
        Err(_) => Vec::new(),
    };

    // Format traces into HTML
    let traces_html = traces.iter()
        .map(|trace| {
            let events_html = trace.events.iter()
                .map(|event| format!(
                    r#"<div class="event">
                        <div class="event-name">{name}</div>
                        <div class="event-timestamp">{timestamp}</div>
                        <div class="event-attributes">
                            {attributes}
                        </div>
                    </div>"#,
                    name = event.name,
                    timestamp = event.timestamp,
                    attributes = event.attributes.iter()
                        .map(|(k, v)| format!("<span class=\"attr\"><span class=\"attr-key\">{}</span>: <span class=\"attr-value\">{}</span></span>", k, v))
                        .collect::<Vec<String>>()
                        .join(", ")
                ))
                .collect::<Vec<String>>()
                .join("\n");

            format!(
                r#"<div class="trace">
                    <div class="trace-header" onclick="toggleTrace('{trace_id}')">
                        <div class="trace-id">{trace_id}</div>
                        <div class="trace-service">{service}</div>
                        <div class="trace-operation">{operation}</div>
                        <div class="trace-duration">{duration}ms</div>
                    </div>
                    <div class="trace-details" id="trace-{trace_id}">
                        <div class="trace-info">
                            <div><strong>Span ID:</strong> {span_id}</div>
                            <div><strong>Parent ID:</strong> {parent_id}</div>
                            <div><strong>Timestamp:</strong> {timestamp}</div>
                        </div>
                        <div class="trace-attributes">
                            <h4>Attributes</h4>
                            {attributes}
                        </div>
                        <div class="trace-events">
                            <h4>Events</h4>
                            {events}
                        </div>
                    </div>
                </div>"#,
                trace_id = trace.trace_id,
                service = trace.service,
                operation = trace.operation,
                duration = trace.duration,
                span_id = trace.span_id,
                parent_id = trace.parent_id.as_deref().unwrap_or("None"),
                timestamp = trace.timestamp,
                attributes = trace.attributes.iter()
                    .map(|(k, v)| format!("<div class=\"attr\"><span class=\"attr-key\">{}</span>: <span class=\"attr-value\">{}</span></div>", k, v))
                    .collect::<Vec<String>>()
                    .join("\n"),
                events = events_html,
            )
        })
        .collect::<Vec<String>>()
        .join("\n");

    Html(format!(r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ART Traces</title>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                h1 {{
                    color: #2c3e50;
                    border-bottom: 2px solid #ecf0f1;
                    padding-bottom: 10px;
                }}
                .controls {{
                    margin: 20px 0;
                    display: flex;
                    gap: 10px;
                    align-items: center;
                }}
                .controls select, .controls input, .controls button {{
                    padding: 8px;
                    border: 1px solid #ddd;
                    border-radius: 4px;
                }}
                .controls button {{
                    background-color: #3498db;
                    color: white;
                    border: none;
                    cursor: pointer;
                }}
                .trace {{
                    margin-bottom: 10px;
                    border: 1px solid #ddd;
                    border-radius: 4px;
                }}
                .trace-header {{
                    display: flex;
                    justify-content: space-between;
                    padding: 10px;
                    background-color: #f8f9fa;
                    cursor: pointer;
                }}
                .trace-details {{
                    display: none;
                    padding: 15px;
                    border-top: 1px solid #ddd;
                }}
                .trace-info {{
                    margin-bottom: 15px;
                }}
                .trace-attributes, .trace-events {{
                    margin-top: 15px;
                }}
                .event {{
                    margin: 10px 0;
                    padding: 10px;
                    background-color: #f9f9f9;
                    border-radius: 4px;
                }}
                .event-name {{
                    font-weight: bold;
                }}
                .event-timestamp {{
                    color: #666;
                    font-size: 0.9em;
                }}
                .event-attributes {{
                    margin-top: 5px;
                }}
                .attr {{
                    margin-bottom: 5px;
                }}
                .attr-key {{
                    font-weight: bold;
                    color: #2980b9;
                }}
                .attr-value {{
                    color: #2c3e50;
                }}
                .nav {{
                    display: flex;
                    gap: 20px;
                    margin-bottom: 20px;
                }}
                .nav a {{
                    text-decoration: none;
                    color: #3498db;
                }}
            </style>
            <script>
                function toggleTrace(traceId) {{
                    const details = document.getElementById(`trace-${{traceId}}`);
                    if (details.style.display === 'block') {{
                        details.style.display = 'none';
                    }} else {{
                        details.style.display = 'block';
                    }}
                }}
            </script>
        </head>
        <body>
            <div class="nav">
                <a href="/">Home</a>
                <a href="/logs">Logs</a>
                <a href="/metrics">Metrics</a>
                <a href="/traces">Traces</a>
            </div>

            <h1>ART Distributed Traces</h1>

            <form class="controls">
                <input type="text" name="service" placeholder="Filter by service..." value="{service}">
                <input type="number" name="limit" placeholder="Limit" value="{limit}">
                <button type="submit">Apply</button>
            </form>

            <div class="traces-container">
                {traces_html}
            </div>
        </body>
        </html>
    "#,
        service = service.unwrap_or(""),
        limit = limit,
        traces_html = if traces.is_empty() { "<p>No traces found.</p>" } else { &traces_html },
    ))
}

async fn metrics_ui_handler(
    State(state): State<ServerState>,
) -> impl IntoResponse {
    // Get metrics from the observability service
    let metrics = match state.services.observability_service.get_metrics() {
        Ok(metrics) => metrics,
        Err(_) => vec![],
    };

    // Get repository metrics if the collector is available
    let repo_metrics = if let Some(collector) = state.services.observability_service.content_metrics_collector() {
        match collector.get_all_repository_metrics() {
            Ok(metrics) => metrics,
            Err(_) => vec![],
        }
    } else {
        vec![]
    };

    // Get time-series data for visualization
    // In a real implementation, this would come from the observability service's time series data
    // For now, we'll use our mock data generator
    let time_series_data = charts::create_mock_time_series_data();

    // Format metrics into HTML
    let metrics_html = metrics.iter()
        .map(|metric| format!(
            r#"<div class="metric">
                <div class="metric-name">{name}</div>
                <div class="metric-value">{value}</div>
                <div class="metric-description">{description}</div>
            </div>"#,
            name = metric.name,
            value = metric.value,
            description = metric.description,
        ))
        .collect::<Vec<String>>()
        .join("\n");

    // Format repository metrics into HTML
    let repo_metrics_html = repo_metrics.iter()
        .map(|metric| format!(
            r#"<div class="repo-metric">
                <div class="repo-name">{name}</div>
                <div class="repo-stats">
                    <div class="stat">Files: <span>{file_count}</span></div>
                    <div class="stat">Size: <span>{size}</span></div>
                    <div class="stat">Commits: <span>{commits}</span></div>
                    <div class="stat">Contributors: <span>{contributors}</span></div>
                    <div class="stat">Age: <span>{age} days</span></div>
                    <div class="stat">Activity: <span>{activity}</span></div>
                </div>
            </div>"#,
            name = metric.name,
            file_count = metric.stats.file_count,
            size = crate::cli::commands::format_size(metric.stats.total_size_bytes),
            commits = metric.stats.commit_count,
            contributors = metric.stats.contributor_count,
            age = metric.stats.age_days,
            activity = format!("{:.1} commits/day", metric.stats.avg_commits_per_day),
        ))
        .collect::<Vec<String>>()
        .join("\n");

    // Generate SVG charts for time-series data
    let charts_html = charts::generate_time_series_charts(&time_series_data);

    // Format last updated timestamps for each chart
    let last_updated_html = time_series_data.iter()
        .map(|data| format!(
            r#"<div class="last-updated-info">
                <span class="metric-name">{name}</span>: Last updated {time}
            </div>"#,
            name = data.name,
            time = data.last_updated.format("%Y-%m-%d %H:%M:%S UTC"),
        ))
        .collect::<Vec<String>>()
        .join("\n");

    // Generate repository activity charts
    let repo_charts_html = charts::generate_repository_charts(&repo_metrics);

    // Get notification banner
    let notification_banner = render_notification_banner(&state).await;

    // Create the base template with notification banner
    let mut base = BaseTemplate {
        title: "ART Metrics".to_string(),
        description: "Analyze repository metrics and performance data".to_string(),
        base_url: "/".to_string(),
        current_path: "/metrics".to_string(),
        current_repo: None,
        notification_banner: Some(notification_banner),
    };

    Html(format!(r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ART Metrics</title>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                h1, h2, h3 {{
                    color: #2c3e50;
                    border-bottom: 2px solid #ecf0f1;
                    padding-bottom: 10px;
                }}
                .metrics-container, .repo-metrics-container {{
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
                    grid-gap: 20px;
                    margin-top: 20px;
                }}
                .metric {{
                    background-color: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                    padding: 15px;
                }}
                .metric-name {{
                    font-weight: bold;
                    font-size: 1.1em;
                    margin-bottom: 5px;
                    color: #3498db;
                }}
                .metric-value {{
                    font-size: 1.5em;
                    font-weight: 300;
                    margin-bottom: 5px;
                }}
                .metric-description {{
                    color: #7f8c8d;
                    font-size: 0.9em;
                }}
                .repo-metric {{
                    background-color: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                    padding: 15px;
                }}
                .repo-name {{
                    font-weight: bold;
                    font-size: 1.1em;
                    margin-bottom: 10px;
                    color: #2c3e50;
                }}
                .repo-stats {{
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    grid-gap: 10px;
                }}
                .stat {{
                    color: #7f8c8d;
                }}
                .stat span {{
                    font-weight: bold;
                    color: #3498db;
                }}
                .tabs {{
                    display: flex;
                    border-bottom: 1px solid #ddd;
                    margin-bottom: 20px;
                }}
                .tab {{
                    padding: 10px 20px;
                    cursor: pointer;
                    border: 1px solid transparent;
                }}
                .tab.active {{
                    border: 1px solid #ddd;
                    border-bottom-color: white;
                    border-radius: 4px 4px 0 0;
                    margin-bottom: -1px;
                }}
                .tab-content {{
                    display: none;
                }}
                .tab-content.active {{
                    display: block;
                }}
                .nav {{
                    display: flex;
                    gap: 20px;
                    margin-bottom: 20px;
                }}
                .nav a {{
                    text-decoration: none;
                    color: #3498db;
                }}
                .charts-container {{
                    display: flex;
                    flex-wrap: wrap;
                    gap: 20px;
                    justify-content: space-between;
                }}
                .chart {{
                    background-color: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                    padding: 15px;
                    margin-bottom: 20px;
                    flex: 1 1 45%;
                    min-width: 300px;
                }}
                .chart-title {{
                    font-weight: bold;
                    font-size: 1.1em;
                    margin-bottom: 10px;
                    color: #2c3e50;
                    text-align: center;
                }}
                svg {{
                    width: 100%;
                    height: auto;
                    max-height: 250px;
                    overflow: visible;
                }}
                .chart-axis {{
                    stroke: #ccc;
                    stroke-width: 1;
                }}
                .chart-label {{
                    font-size: 10px;
                    fill: #666;
                }}
                .chart-line {{
                    fill: none;
                    stroke-width: 2;
                }}
                .chart-area {{
                    opacity: 0.2;
                }}
                .chart-point {{
                    fill: white;
                    stroke-width: 2;
                    r: 3;
                }}
                .chart-bar {{
                    stroke-width: 1;
                    stroke: white;
                }}
                .chart-legend {{
                    display: flex;
                    flex-wrap: wrap;
                    gap: 10px;
                    justify-content: center;
                    margin-top: 10px;
                }}
                .legend-item {{
                    display: flex;
                    align-items: center;
                    gap: 5px;
                }}
                .legend-color {{
                    width: 12px;
                    height: 12px;
                    border-radius: 2px;
                }}
                .download-section {{
                    margin-top: 20px;
                    padding: 15px;
                    background-color: #f8f9fa;
                    border-radius: 8px;
                }}
                .download-links {{
                    display: flex;
                    gap: 10px;
                    margin-top: 10px;
                }}
                .download-link {{
                    padding: 8px 16px;
                    background-color: #3498db;
                    color: white;
                    text-decoration: none;
                    border-radius: 4px;
                    display: inline-block;
                }}
                .download-link:hover {{
                    background-color: #2980b9;
                }}
                .last-updated-info {{
                    font-size: 0.9em;
                    color: #7f8c8d;
                    margin-bottom: 5px;
                }}
                .last-updated-container {{
                    background-color: #f8f9fa;
                    border-radius: 8px;
                    padding: 15px;
                    margin-bottom: 20px;
                }}
                @media print {{
                    .tabs, .nav {{
                        display: none;
                    }}
                    .tab-content {{
                        display: block;
                    }}
                    .chart svg {{
                        max-height: 200px;
                    }}
                }}
            </style>
            <script>
                function switchTab(tabId) {{
                    // Hide all tab content
                    document.querySelectorAll('.tab-content').forEach(content => {{
                        content.classList.remove('active');
                    }});

                    // Deactivate all tabs
                    document.querySelectorAll('.tab').forEach(tab => {{
                        tab.classList.remove('active');
                    }});

                    // Show selected tab content
                    document.getElementById(tabId).classList.add('active');

                    // Activate selected tab
                    document.querySelector(`[data-tab="${{tabId}}"]`).classList.add('active');

                    // Update URL hash
                    window.location.hash = tabId;
                }}

                window.onload = function() {{
                    // Check for hash in URL
                    const hash = window.location.hash.substring(1);
                    if (hash && document.getElementById(hash)) {{
                        switchTab(hash);
                    }} else {{
                        switchTab('system-metrics');
                    }}
                }};
            </script>
        </head>
        <body>
            <div class="nav">
                <a href="/">Home</a>
                <a href="/logs">Logs</a>
                <a href="/metrics">Metrics</a>
                <a href="/traces">Traces</a>
            </div>

            <h1>ART Metrics</h1>

            <div class="tabs">
                <div class="tab active" data-tab="system-metrics" onclick="switchTab('system-metrics')">System Metrics</div>
                <div class="tab" data-tab="repository" onclick="switchTab('repository')">Repository Metrics</div>
                <div class="tab" data-tab="charts" onclick="switchTab('charts')">Visualization</div>
                <div class="tab" data-tab="repo-charts" onclick="switchTab('repo-charts')">Repository Charts</div>
            </div>

            <div id="system-metrics" class="tab-content active">
                <h2>System Performance Metrics</h2>
                <div class="metrics-container">
                    {metrics_html}
                </div>
                <div class="download-section">
                    <h3>Download Metrics</h3>
                    <p>Export system metrics in different formats:</p>
                    <div class="download-links">
                        <a href="/api/metrics?format=prometheus" class="download-link">Prometheus Format</a>
                        <a href="/api/metrics?format=json" class="download-link">JSON Format</a>
                        <a href="/api/metrics?format=openmetrics" class="download-link">OpenMetrics Format</a>
                        <a href="/api/metrics?format=csv" class="download-link">CSV Format</a>
                    </div>
                </div>
            </div>

            <div id="repository" class="tab-content">
                <h2>Repository Metrics</h2>
                <div class="repo-metrics-container">
                    {repo_metrics_html}
                </div>
            </div>

            <div id="charts" class="tab-content">
                <h2>Metrics Visualization</h2>
                <p>Visual representation of key metrics over time:</p>
                <div class="last-updated-container">
                    <h3>Data Freshness</h3>
                    {last_updated_html}
                </div>
                <div class="charts-container">
                    {charts_html}
                </div>
            </div>

            <div id="repo-charts" class="tab-content">
                <h2>Repository Activity Visualization</h2>
                <p>Visual representation of repository activity patterns:</p>
                <div class="charts-container">
                    {repo_charts_html}
                </div>
            </div>
        </body>
        </html>
    "#,
        metrics_html = if metrics.is_empty() { "<p>No metrics available.</p>" } else { &metrics_html },
        repo_metrics_html = if repo_metrics.is_empty() { "<p>No repository metrics available.</p>" } else { &repo_metrics_html },
        charts_html = if time_series_data.is_empty() { "<p>No time-series data available for visualization.</p>" } else { &charts_html },
        repo_charts_html = if repo_metrics.is_empty() { "<p>No repository data available for visualization.</p>" } else { &repo_charts_html },
        last_updated_html = if time_series_data.is_empty() { "<p>No data available.</p>" } else { &last_updated_html },
    ))
}

#[derive(Debug, Deserialize, Default)]
struct TracesQuery {
    limit: Option<usize>,
    service: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;
    use std::sync::Arc;
    use crate::config::Config;
    use crate::data::database::Sqlite;
    use crate::data::git::Git;
    use crate::data::cache::Cache;
    use crate::service::observability::{ObservabilityService, ObservabilityConfig};

    // Helper function for tests
    fn create_test_server_state(enable_metrics: bool) -> ServerState {
        let config = Arc::new(ObservabilityConfig {
            enable_metrics,
            log_level: "info".to_string(),
        });

        let cache = Arc::new(Cache::new_for_test());
        let observability = Arc::new(ObservabilityService::new(config, cache.clone()));

        // Create a mock server state for testing
        ServerState {
            observability_service: if enable_metrics { Some(observability) } else { None },
            config: Arc::new(Config::default()),
            db: Arc::new(Sqlite::default()),
            git: Arc::new(Git::default()),
            cache,
            repository_service: None,
            commit_service: None,
            file_service: None,
            format_service: None,
            index_service: None,
            search_service: None,
            status_service: None,
            auth_service: None,
        }
    }

    #[tokio::test]
    async fn test_index_handler() {
        let response = index_handler().await;
        assert!(response.0.contains("<!DOCTYPE html>"));
    }

    #[tokio::test]
    async fn test_logs_page_handler_with_metrics_enabled() {
        // Create state with metrics enabled
        let state = create_test_server_state(true);

        // Create empty params
        let params = LogsQuery {
            level: None,
            start: None,
            end: None,
            limit: None,
            search: None,
        };

        // Call the handler
        let response = logs_ui_handler(Some(Query(params)), State(state)).await;

        // Check that it contains the logs page elements
        assert!(response.0.contains("<title>ART Logs</title>"));
        assert!(response.0.contains("<h1>ART Logs</h1>"));
    }

    #[tokio::test]
    async fn test_logs_page_handler_with_metrics_disabled() {
        // Create state with metrics disabled
        let state = create_test_server_state(false);

        // Create empty params
        let params = LogsQuery {
            level: None,
            start: None,
            end: None,
            limit: None,
            search: None,
        };

        // Call the handler
        let response = logs_ui_handler(Some(Query(params)), State(state)).await;

        // Check that it shows the error message
        assert!(response.0.contains("<title>ART Logs</title>"));
        assert!(response.0.contains("Observability Service Not Available"));
    }

    #[tokio::test]
    async fn test_web_routes() {
        // Create a router
        let app = router();

        // Test index route
        let req = Request::builder()
            .uri("/")
            .method("GET")
            .body(Body::empty())
            .unwrap();

        let response = app.clone().oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        // Test logs route
        let req = Request::builder()
            .uri("/logs")
            .method("GET")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }
}

// Helper function to render the notification banner in layouts
pub async fn render_notification_banner(state: &ServerState) -> String {
    notifications::render_notification_banner(state).await
}

// Helper function to include notification banner in any base template
pub async fn include_notification_banner(state: &ServerState, base: &mut BaseTemplate) {
    let notification_banner = render_notification_banner(state).await;
    if !notification_banner.is_empty() {
        base.notification_banner = Some(notification_banner);
    }
}
