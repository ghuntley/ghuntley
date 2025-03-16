//! Metrics visualization charts
//!
//! This module provides functions for generating SVG charts from metrics data.
//! These charts are embedded directly in the HTML and don't require any JavaScript.

use std::collections::HashMap;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use crate::service::observability::content_metrics::RepositoryMetric;

/// Time-series data point for visualization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeSeriesData {
    /// Metric name
    pub name: String,

    /// Data points (timestamp, value)
    pub points: Vec<(String, f64)>,

    /// Metric description
    pub description: String,

    /// Last updated timestamp
    pub last_updated: DateTime<Utc>,
}

/// Repository activity data for visualization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryActivityData {
    /// Repository name
    pub name: String,

    /// Commit count by day of week
    pub commits_by_day: HashMap<String, usize>,

    /// File type distribution
    pub file_types: HashMap<String, usize>,

    /// File size distribution
    pub file_size_distribution: HashMap<String, usize>,

    /// Commit activity by month
    pub commit_activity_by_month: HashMap<String, usize>,
}

/// Create mock time-series data for visualization
/// This is temporary until the real metrics time-series API is implemented
pub fn create_mock_time_series_data() -> Vec<TimeSeriesData> {
    let mut data = Vec::new();
    let now = Utc::now();

    // HTTP Request Rate
    let mut http_points = Vec::new();
    for i in 0..24 {
        let time = format!("{:02}:00", i);
        let value = 20.0 + (i as f64 * 2.5).sin() * 15.0 + (rand::random::<f64>() * 5.0);
        http_points.push((time, value));
    }
    data.push(TimeSeriesData {
        name: "http_requests_rate".to_string(),
        points: http_points,
        description: "HTTP request rate per minute".to_string(),
        last_updated: now,
    });

    // Response Time
    let mut resp_points = Vec::new();
    for i in 0..24 {
        let time = format!("{:02}:00", i);
        let value = 50.0 + (i as f64 * 0.3).cos() * 20.0 + (rand::random::<f64>() * 10.0);
        resp_points.push((time, value));
    }
    data.push(TimeSeriesData {
        name: "response_time_ms".to_string(),
        points: resp_points,
        description: "Average response time in milliseconds".to_string(),
        last_updated: now,
    });

    // Error Rate
    let mut error_points = Vec::new();
    for i in 0..24 {
        let time = format!("{:02}:00", i);
        let value = 0.5 + (i as f64 * 0.5).sin() * 0.5 + (rand::random::<f64>() * 0.5);
        error_points.push((time, value));
    }
    data.push(TimeSeriesData {
        name: "error_rate".to_string(),
        points: error_points,
        description: "Error rate as percentage of requests".to_string(),
        last_updated: now,
    });

    // Memory Usage
    let mut memory_points = Vec::new();
    for i in 0..24 {
        let time = format!("{:02}:00", i);
        let base = 100.0 + (i as f64 * 0.1) * 5.0;
        let value = base.min(300.0) + (rand::random::<f64>() * 20.0);
        memory_points.push((time, value));
    }
    data.push(TimeSeriesData {
        name: "memory_usage".to_string(),
        points: memory_points,
        description: "Memory usage in megabytes".to_string(),
        last_updated: now,
    });

    // Cache Hit Ratio
    let mut cache_points = Vec::new();
    for i in 0..24 {
        let time = format!("{:02}:00", i);
        let value = 85.0 + (i as f64 * 0.2).cos() * 10.0 + (rand::random::<f64>() * 5.0);
        cache_points.push((time, value.min(100.0)));
    }
    data.push(TimeSeriesData {
        name: "cache_hit_ratio".to_string(),
        points: cache_points,
        description: "Cache hit ratio percentage".to_string(),
        last_updated: now,
    });

    data
}

/// Generate SVG charts for time-series data
pub fn generate_time_series_charts(data: &[TimeSeriesData]) -> String {
    if data.is_empty() {
        return String::new();
    }

    let mut charts = Vec::new();

    // HTTP Request Rate Chart
    if let Some(http_data) = data.iter().find(|d| d.name == "http_requests_rate") {
        charts.push(generate_line_chart(
            "HTTP Request Rate",
            &http_data.points,
            "#3498db",
            "Requests/min",
            false,
        ));
    }

    // Response Time Chart
    if let Some(resp_time_data) = data.iter().find(|d| d.name == "response_time_ms") {
        charts.push(generate_line_chart(
            "Average Response Time",
            &resp_time_data.points,
            "#e74c3c",
            "Milliseconds",
            false,
        ));
    }

    // Error Rate Chart
    if let Some(error_data) = data.iter().find(|d| d.name == "error_rate") {
        charts.push(generate_line_chart(
            "Error Rate",
            &error_data.points,
            "#e67e22",
            "Errors (%)",
            false,
        ));
    }

    // Memory Usage Chart
    if let Some(memory_data) = data.iter().find(|d| d.name == "memory_usage") {
        charts.push(generate_line_chart(
            "Memory Usage",
            &memory_data.points,
            "#2ecc71",
            "MB",
            false,
        ));
    }

    // Cache Hit Ratio Chart
    if let Some(cache_data) = data.iter().find(|d| d.name == "cache_hit_ratio") {
        charts.push(generate_line_chart(
            "Cache Hit Ratio",
            &cache_data.points,
            "#9b59b6",
            "Hit Ratio (%)",
            false,
        ));
    }

    charts.join("\n")
}

/// Generate repository activity charts
pub fn generate_repository_charts(repo_metrics: &[RepositoryMetric]) -> String {
    if repo_metrics.is_empty() {
        return String::new();
    }

    let mut charts = Vec::new();

    // Commits by Day of Week Chart (aggregated across repos)
    let mut commits_by_day = HashMap::new();
    for repo in repo_metrics {
        for (day, count) in &repo.stats.commits_by_day_of_week {
            *commits_by_day.entry(day.clone()).or_insert(0) += *count;
        }
    }

    // Convert to data points for bar chart
    let days = vec!["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    let commit_data_points: Vec<(String, f64)> = days.iter()
        .map(|&day| {
            let count = commits_by_day.get(day).cloned().unwrap_or(0);
            (day.to_string(), count as f64)
        })
        .collect();

    charts.push(generate_bar_chart(
        "Commits by Day of Week",
        &commit_data_points,
        "#3498db",
        "Commits",
    ));

    // File Type Distribution Chart (aggregated)
    let mut file_types = HashMap::new();
    for repo in repo_metrics {
        for (file_type, count) in &repo.stats.file_types {
            *file_types.entry(file_type.clone()).or_insert(0) += *count;
        }
    }

    // Get top 10 file types by count
    let mut file_type_data: Vec<(String, f64)> = file_types.into_iter()
        .map(|(k, v)| (k, v as f64))
        .collect();
    file_type_data.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    let file_type_data = file_type_data.into_iter().take(10).collect::<Vec<_>>();

    charts.push(generate_bar_chart(
        "Top 10 File Types",
        &file_type_data,
        "#2ecc71",
        "Files",
    ));

    // Repository Size Comparison
    let repo_sizes: Vec<(String, f64)> = repo_metrics.iter()
        .map(|r| (r.name.clone(), r.stats.total_size_bytes as f64 / 1024.0 / 1024.0)) // Convert to MB
        .collect();

    charts.push(generate_bar_chart(
        "Repository Sizes",
        &repo_sizes,
        "#9b59b6",
        "MB",
    ));

    // Commit Activity Over Time
    // For this example, we'll use the commit activity by month
    if let Some(repo) = repo_metrics.first() {
        let commit_activity: Vec<(String, f64)> = repo.stats.commit_activity_by_month.iter()
            .map(|(month, count)| (month.clone(), *count as f64))
            .collect();

        if !commit_activity.is_empty() {
            charts.push(generate_line_chart(
                &format!("Commit Activity: {}", repo.name),
                &commit_activity,
                "#e74c3c",
                "Commits",
                false,
            ));
        }
    }

    charts.join("\n")
}

/// Generate a line chart as SVG
pub fn generate_line_chart(title: &str, data: &[(String, f64)], color: &str, y_label: &str, fill: bool) -> String {
    if data.is_empty() {
        return format!(r#"<div class="chart"><div class="chart-title">{}</div><p>No data available</p></div>"#, title);
    }

    const WIDTH: usize = 600;
    const HEIGHT: usize = 300;
    const MARGIN: usize = 50;
    const INNER_WIDTH: usize = WIDTH - 2 * MARGIN;
    const INNER_HEIGHT: usize = HEIGHT - 2 * MARGIN;

    // Find min/max values
    let y_values: Vec<f64> = data.iter().map(|(_, y)| *y).collect();
    let y_min = y_values.iter().cloned().fold(f64::INFINITY, f64::min);
    let y_max = y_values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

    // Add padding to y range
    let y_min = if y_min > 0.0 { 0.0 } else { y_min - (y_max - y_min) * 0.1 };
    let y_max = y_max + (y_max - y_min) * 0.1;

    // Generate points for the line
    let mut points = String::new();
    let mut points_str = String::new();
    let mut area_points = String::new();

    for (i, (x_label, y)) in data.iter().enumerate() {
        let x = MARGIN + (i * INNER_WIDTH) / (data.len() - 1).max(1);
        let y_normalized = if y_max > y_min {
            1.0 - (*y - y_min) / (y_max - y_min)
        } else {
            0.5
        };
        let y_pos = MARGIN + (y_normalized * INNER_HEIGHT as f64) as usize;

        // Add to line points
        if i == 0 {
            points.push_str(&format!("M{},{}", x, y_pos));
            area_points.push_str(&format!("M{},{} L{},{}", x, HEIGHT - MARGIN, x, y_pos));
        } else {
            points.push_str(&format!(" L{},{}", x, y_pos));
            area_points.push_str(&format!(" L{},{}", x, y_pos));
        }

        // Add point coordinates
        points_str.push_str(&format!(
            r#"<circle class="chart-point" cx="{}" cy="{}" style="stroke: {}" />"#,
            x, y_pos, color
        ));
    }

    // Close the area path
    if !data.is_empty() {
        let last_x = MARGIN + INNER_WIDTH;
        area_points.push_str(&format!(" L{},{} Z", last_x, HEIGHT - MARGIN));
    }

    // Generate X axis labels
    let x_labels = if data.len() <= 6 {
        // Show all labels if there are few points
        data.iter().enumerate().map(|(i, (label, _))| {
            let x = MARGIN + (i * INNER_WIDTH) / (data.len() - 1).max(1);
            format!(
                r#"<text class="chart-label" x="{}" y="{}" text-anchor="middle">{}</text>"#,
                x, HEIGHT - MARGIN + 20, label
            )
        }).collect::<Vec<_>>()
    } else {
        // Show only some labels if there are many points
        let step = data.len() / 5;
        data.iter().enumerate()
            .filter(|(i, _)| *i % step == 0 || *i == data.len() - 1)
            .map(|(i, (label, _))| {
                let x = MARGIN + (i * INNER_WIDTH) / (data.len() - 1).max(1);
                format!(
                    r#"<text class="chart-label" x="{}" y="{}" text-anchor="middle">{}</text>"#,
                    x, HEIGHT - MARGIN + 20, label
                )
            }).collect::<Vec<_>>()
    };

    // Generate Y axis labels
    let y_labels = (0..=5).map(|i| {
        let y_val = y_min + (i as f64 / 5.0) * (y_max - y_min);
        let y_pos = MARGIN + ((1.0 - i as f64 / 5.0) * INNER_HEIGHT as f64) as usize;
        format!(
            r#"<text class="chart-label" x="{}" y="{}" text-anchor="end" dominant-baseline="middle">{:.1}</text>"#,
            MARGIN - 10, y_pos, y_val
        )
    }).collect::<Vec<_>>();

    format!(
        r#"<div class="chart">
            <div class="chart-title">{title}</div>
            <svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">
                <!-- Axis -->
                <line class="chart-axis" x1="{margin}" y1="{y_start}" x2="{margin}" y2="{y_end}" />
                <line class="chart-axis" x1="{margin}" y1="{y_end}" x2="{x_end}" y2="{y_end}" />

                <!-- Y label -->
                <text class="chart-label" x="{label_x}" y="{margin_half}" text-anchor="middle" transform="rotate(-90, {label_x}, {margin_half})">{y_label}</text>

                <!-- Grid lines -->
                {grid_lines}

                <!-- Area under the curve -->
                {area_path}

                <!-- Line -->
                <path class="chart-line" d="{points}" style="stroke: {color}" />

                <!-- Points -->
                {points_str}

                <!-- X axis labels -->
                {x_labels}

                <!-- Y axis labels -->
                {y_labels}
            </svg>
        </div>"#,
        title = title,
        width = WIDTH,
        height = HEIGHT,
        margin = MARGIN,
        y_start = MARGIN,
        y_end = HEIGHT - MARGIN,
        x_end = WIDTH - MARGIN,
        label_x = MARGIN / 2,
        margin_half = HEIGHT / 2,
        y_label = y_label,
        grid_lines = (0..=5).map(|i| {
            let y_pos = MARGIN + ((1.0 - i as f64 / 5.0) * INNER_HEIGHT as f64) as usize;
            format!(
                r#"<line class="chart-axis" x1="{}" y1="{}" x2="{}" y2="{}" style="stroke-dasharray: 5,5" />"#,
                MARGIN, y_pos, WIDTH - MARGIN, y_pos
            )
        }).collect::<Vec<_>>().join("\n"),
        area_path = if fill {
            format!(r#"<path d="{}" style="fill: {}; stroke: none" class="chart-area" />"#, area_points, color)
        } else {
            String::new()
        },
        points = points,
        color = color,
        points_str = points_str,
        x_labels = x_labels.join("\n"),
        y_labels = y_labels.join("\n"),
    )
}

/// Generate a bar chart as SVG
pub fn generate_bar_chart(title: &str, data: &[(String, f64)], color: &str, y_label: &str) -> String {
    if data.is_empty() {
        return format!(r#"<div class="chart"><div class="chart-title">{}</div><p>No data available</p></div>"#, title);
    }

    const WIDTH: usize = 600;
    const HEIGHT: usize = 300;
    const MARGIN: usize = 50;
    const INNER_WIDTH: usize = WIDTH - 2 * MARGIN;
    const INNER_HEIGHT: usize = HEIGHT - 2 * MARGIN;

    // Find max value for scaling
    let y_max = data.iter().map(|(_, v)| *v).fold(0.0, f64::max) * 1.1;

    // Calculate bar width
    let bar_width = (INNER_WIDTH / data.len()).min(60);
    let bar_spacing = bar_width / 4;

    // Generate bars
    let bars = data.iter().enumerate().map(|(i, (label, value))| {
        let x = MARGIN + i * (bar_width + bar_spacing);
        let bar_height = ((value / y_max) * INNER_HEIGHT as f64) as usize;
        let y = HEIGHT - MARGIN - bar_height;

        format!(
            r#"<g>
                <rect class="chart-bar" x="{}" y="{}" width="{}" height="{}" style="fill: {}" />
                <text class="chart-label" x="{}" y="{}" text-anchor="middle" transform="rotate(-45, {}, {})">{}</text>
            </g>"#,
            x, y, bar_width, bar_height, color,
            x + bar_width / 2, HEIGHT - MARGIN + 15, x + bar_width / 2, HEIGHT - MARGIN + 15, label
        )
    }).collect::<Vec<_>>().join("\n");

    // Generate Y axis labels
    let y_labels = (0..=5).map(|i| {
        let y_val = (i as f64 / 5.0) * y_max;
        let y_pos = HEIGHT - MARGIN - ((i as f64 / 5.0) * INNER_HEIGHT as f64) as usize;
        format!(
            r#"<text class="chart-label" x="{}" y="{}" text-anchor="end" dominant-baseline="middle">{:.1}</text>"#,
            MARGIN - 10, y_pos, y_val
        )
    }).collect::<Vec<_>>().join("\n");

    format!(
        r#"<div class="chart">
            <div class="chart-title">{title}</div>
            <svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">
                <!-- Axis -->
                <line class="chart-axis" x1="{margin}" y1="{y_start}" x2="{margin}" y2="{y_end}" />
                <line class="chart-axis" x1="{margin}" y1="{y_end}" x2="{x_end}" y2="{y_end}" />

                <!-- Y label -->
                <text class="chart-label" x="{label_x}" y="{margin_half}" text-anchor="middle" transform="rotate(-90, {label_x}, {margin_half})">{y_label}</text>

                <!-- Grid lines -->
                {grid_lines}

                <!-- Bars -->
                {bars}

                <!-- Y axis labels -->
                {y_labels}
            </svg>
        </div>"#,
        title = title,
        width = WIDTH,
        height = HEIGHT,
        margin = MARGIN,
        y_start = MARGIN,
        y_end = HEIGHT - MARGIN,
        x_end = WIDTH - MARGIN,
        label_x = MARGIN / 2,
        margin_half = HEIGHT / 2,
        y_label = y_label,
        grid_lines = (0..=5).map(|i| {
            let y_pos = HEIGHT - MARGIN - ((i as f64 / 5.0) * INNER_HEIGHT as f64) as usize;
            format!(
                r#"<line class="chart-axis" x1="{}" y1="{}" x2="{}" y2="{}" style="stroke-dasharray: 5,5" />"#,
                MARGIN, y_pos, WIDTH - MARGIN, y_pos
            )
        }).collect::<Vec<_>>().join("\n"),
        bars = bars,
        y_labels = y_labels,
    )
}
