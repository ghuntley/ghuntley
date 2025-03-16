//! Property tests for SVG chart generation
//!
//! This module contains property-based tests for the SVG chart generation functions.
//! It verifies correct handling of different data shapes, edge cases, and output formats.

use super::charts::{TimeSeriesData, generate_line_chart, generate_bar_chart, generate_time_series_charts};
use proptest::prelude::*;
use std::collections::HashMap;
use chrono::Utc;

/// Strategy for generating chart titles
fn chart_title_strategy() -> impl Strategy<Value = String> {
    "[A-Za-z0-9 ]{1,50}".prop_map(|s| s)
}

/// Strategy for generating chart y-axis labels
fn y_label_strategy() -> impl Strategy<Value = String> {
    "[A-Za-z0-9/%]{1,20}".prop_map(|s| s)
}

/// Strategy for generating chart colors
fn color_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("#3498db".to_string()),
        Just("#e74c3c".to_string()),
        Just("#2ecc71".to_string()),
        Just("#f39c12".to_string()),
        Just("#9b59b6".to_string()),
        Just("#1abc9c".to_string()),
        Just("#34495e".to_string()),
        Just("#e67e22".to_string()),
        Just("#7f8c8d".to_string()),
        Just("#c0392b".to_string()),
    ]
}

/// Strategy for generating time-series data points
fn data_points_strategy() -> impl Strategy<Value = Vec<(String, f64)>> {
    proptest::collection::vec(
        (
            "[0-2][0-9]:[0-5][0-9]".prop_map(|s| s),
            (-1000.0..1000.0)
        ),
        1..50
    )
}

/// Strategy for generating empty data points
fn empty_data_points_strategy() -> impl Strategy<Value = Vec<(String, f64)>> {
    Just(Vec::new())
}

/// Strategy for generating time-series data
fn time_series_data_strategy() -> impl Strategy<Value = TimeSeriesData> {
    (
        "[a-z_]{3,15}".prop_map(|s| s),
        data_points_strategy(),
        "[A-Za-z0-9 ]{5,50}".prop_map(|s| s),
        any::<i64>().prop_map(|ts| {
            // Generate a random timestamp within the last 24 hours
            let now = Utc::now();
            let random_offset = ts.abs() % (24 * 60 * 60); // Random seconds within 24 hours
            now - chrono::Duration::seconds(random_offset)
        })
    ).prop_map(|(name, points, description, last_updated)| {
        TimeSeriesData {
            name,
            points,
            description,
            last_updated,
        }
    })
}

proptest! {
    /// Test that line charts are generated correctly with various inputs
    #[test]
    fn test_line_chart_generation(
        title in chart_title_strategy(),
        data in data_points_strategy(),
        color in color_strategy(),
        y_label in y_label_strategy(),
        fill in proptest::bool::ANY,
    ) {
        let chart = generate_line_chart(&title, &data, &color, &y_label, fill);

        // Chart should include the title
        prop_assert!(chart.contains(&title), "Chart should contain the title");

        // Chart should include the y-axis label
        prop_assert!(chart.contains(&y_label), "Chart should contain the y-axis label");

        // Chart should include the color
        prop_assert!(chart.contains(&color), "Chart should contain the specified color");

        // Chart should be an SVG
        prop_assert!(chart.contains("<svg"), "Chart should be an SVG");

        // The SVG should close properly
        prop_assert!(chart.contains("</svg>"), "SVG should close properly");

        // Check for path for line
        prop_assert!(chart.contains(r#"<path class="chart-line""#), "Chart should contain a path for the line");

        // If fill is true, check for area path
        if fill {
            prop_assert!(chart.contains(r#"<path d=""#), "Chart should contain an area path when fill is true");
            prop_assert!(chart.contains(r#"class="chart-area""#), "Chart should have chart-area class when fill is true");
        }

        // There should be points for data
        if !data.is_empty() {
            prop_assert!(chart.contains(r#"<circle class="chart-point""#), "Chart should contain points");
        }
    }

    /// Test that line charts handle empty data properly
    #[test]
    fn test_line_chart_empty_data(
        title in chart_title_strategy(),
        color in color_strategy(),
        y_label in y_label_strategy(),
    ) {
        let chart = generate_line_chart(&title, &[], &color, &y_label, false);

        // Chart should still include the title
        prop_assert!(chart.contains(&title), "Chart should contain the title even with empty data");

        // Chart should indicate no data
        prop_assert!(chart.contains("No data available"), "Chart should indicate no data available");
    }

    /// Test that bar charts are generated correctly with various inputs
    #[test]
    fn test_bar_chart_generation(
        title in chart_title_strategy(),
        data in data_points_strategy(),
        color in color_strategy(),
        y_label in y_label_strategy(),
    ) {
        let chart = generate_bar_chart(&title, &data, &color, &y_label);

        // Chart should include the title
        prop_assert!(chart.contains(&title), "Chart should contain the title");

        // Chart should include the y-axis label
        prop_assert!(chart.contains(&y_label), "Chart should contain the y-axis label");

        // Chart should include the color
        prop_assert!(chart.contains(&color), "Chart should contain the specified color");

        // Chart should be an SVG
        prop_assert!(chart.contains("<svg"), "Chart should be an SVG");

        // The SVG should close properly
        prop_assert!(chart.contains("</svg>"), "SVG should close properly");

        // Check for rectangle elements for bars
        if !data.is_empty() {
            prop_assert!(chart.contains("<rect"), "Chart should contain rectangle elements for bars");

            // There should be one rectangle per data point
            let rect_count = chart.matches("<rect").count();
            prop_assert_eq!(rect_count, data.len(), "There should be one rectangle per data point");
        }
    }

    /// Test that bar charts handle empty data properly
    #[test]
    fn test_bar_chart_empty_data(
        title in chart_title_strategy(),
        color in color_strategy(),
        y_label in y_label_strategy(),
    ) {
        let chart = generate_bar_chart(&title, &[], &color, &y_label);

        // Chart should still include the title
        prop_assert!(chart.contains(&title), "Chart should contain the title even with empty data");

        // Chart should indicate no data
        prop_assert!(chart.contains("No data available"), "Chart should indicate no data available");
    }

    /// Test that time series charts handle normal data properly
    #[test]
    fn test_time_series_charts_generation(
        http_data in time_series_data_strategy(),
        resp_time_data in time_series_data_strategy(),
        error_data in time_series_data_strategy(),
    ) {
        // Ensure proper metric names for specific charts
        let http_data = TimeSeriesData {
            name: "http_requests_rate".to_string(),
            ..http_data
        };

        let resp_time_data = TimeSeriesData {
            name: "response_time_ms".to_string(),
            ..resp_time_data
        };

        let error_data = TimeSeriesData {
            name: "error_rate".to_string(),
            ..error_data
        };

        let time_series_data = vec![
            http_data.clone(),
            resp_time_data.clone(),
            error_data.clone(),
        ];

        let charts = generate_time_series_charts(&time_series_data);

        // Should include HTTP request rate chart
        prop_assert!(charts.contains("HTTP Request Rate"), "Should include HTTP request rate chart");

        // Should include response time chart
        prop_assert!(charts.contains("Average Response Time"), "Should include response time chart");

        // Should include error rate chart
        prop_assert!(charts.contains("Error Rate"), "Should include error rate chart");

        // Charts should be SVGs
        prop_assert!(charts.contains("<svg"), "Charts should contain SVG elements");

        // Multiple charts should be separate
        let chart_count = charts.matches("<div class=\"chart\">").count();
        prop_assert_eq!(chart_count, 3, "Should generate 3 separate charts");
    }

    /// Test that time series charts handle empty data properly
    #[test]
    fn test_time_series_charts_empty_data() {
        let charts = generate_time_series_charts(&[]);

        // Should return empty string for empty data
        prop_assert_eq!(charts, "", "Should return empty string for empty data");
    }

    /// Test edge cases for data scaling in line charts
    #[test]
    fn test_line_chart_data_scaling(
        title in chart_title_strategy(),
        y_label in y_label_strategy(),
    ) {
        // Test with all same values
        let same_values = vec![
            ("00:00".to_string(), 10.0),
            ("01:00".to_string(), 10.0),
            ("02:00".to_string(), 10.0),
        ];

        let chart = generate_line_chart(&title, &same_values, "#3498db", &y_label, false);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with all same values");

        // Test with extreme value ranges
        let extreme_values = vec![
            ("00:00".to_string(), 0.0001),
            ("01:00".to_string(), 1000000.0),
            ("02:00".to_string(), 500000.0),
        ];

        let chart = generate_line_chart(&title, &extreme_values, "#3498db", &y_label, false);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with extreme value ranges");

        // Test with negative values
        let negative_values = vec![
            ("00:00".to_string(), -10.0),
            ("01:00".to_string(), -5.0),
            ("02:00".to_string(), -20.0),
        ];

        let chart = generate_line_chart(&title, &negative_values, "#3498db", &y_label, false);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with negative values");

        // Test with mixed positive and negative values
        let mixed_values = vec![
            ("00:00".to_string(), -10.0),
            ("01:00".to_string(), 5.0),
            ("02:00".to_string(), -20.0),
        ];

        let chart = generate_line_chart(&title, &mixed_values, "#3498db", &y_label, false);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with mixed positive and negative values");
    }

    /// Test edge cases for data scaling in bar charts
    #[test]
    fn test_bar_chart_data_scaling(
        title in chart_title_strategy(),
        y_label in y_label_strategy(),
    ) {
        // Test with all same values
        let same_values = vec![
            ("Category A".to_string(), 10.0),
            ("Category B".to_string(), 10.0),
            ("Category C".to_string(), 10.0),
        ];

        let chart = generate_bar_chart(&title, &same_values, "#3498db", &y_label);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with all same values");

        // Test with extreme value ranges
        let extreme_values = vec![
            ("Category A".to_string(), 0.0001),
            ("Category B".to_string(), 1000000.0),
            ("Category C".to_string(), 500000.0),
        ];

        let chart = generate_bar_chart(&title, &extreme_values, "#3498db", &y_label);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with extreme value ranges");

        // Bar charts should handle a large number of categories
        let many_categories = (0..20).map(|i| (format!("Category {}", i), i as f64)).collect::<Vec<_>>();

        let chart = generate_bar_chart(&title, &many_categories, "#3498db", &y_label);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with many categories");

        // Bar chart should handle zero values
        let zero_values = vec![
            ("Category A".to_string(), 0.0),
            ("Category B".to_string(), 0.0),
            ("Category C".to_string(), 0.0),
        ];

        let chart = generate_bar_chart(&title, &zero_values, "#3498db", &y_label);

        // Chart should still render successfully
        prop_assert!(chart.contains("<svg"), "Chart should render with zero values");
    }

    /// Test that time series data last_updated field is properly handled
    #[test]
    fn test_time_series_data_last_updated(
        name in "[a-z_]{3,15}".prop_map(|s| s),
        points in data_points_strategy(),
        description in "[A-Za-z0-9 ]{5,50}".prop_map(|s| s),
    ) {
        // Create a TimeSeriesData with a known timestamp
        let now = Utc::now();
        let data = TimeSeriesData {
            name: name.clone(),
            points: points.clone(),
            description: description.clone(),
            last_updated: now,
        };

        // Verify that the last_updated field is properly set
        prop_assert_eq!(data.last_updated, now, "last_updated should match the provided timestamp");

        // Create a mock time series data set
        let mock_data = create_mock_time_series_data();

        // Verify that all mock data points have a last_updated field
        for data_point in mock_data {
            // The last_updated field should be a recent timestamp (within the last minute)
            let age = Utc::now().signed_duration_since(data_point.last_updated);
            prop_assert!(age.num_seconds() < 60, "last_updated should be a recent timestamp");
        }
    }
}

/// Tests for the SVG output format compliance
#[cfg(test)]
mod svg_tests {
    use super::*;

    /// Test that generated SVG is well-formed XML
    #[test]
    fn test_svg_well_formed() {
        let data = vec![
            ("00:00".to_string(), 10.0),
            ("01:00".to_string(), 20.0),
            ("02:00".to_string(), 15.0),
        ];

        let chart = generate_line_chart("Test Chart", &data, "#3498db", "Value", false);

        // Extract SVG content
        let start = chart.find("<svg");
        let end = chart.find("</svg>");

        assert!(start.is_some(), "SVG start tag not found");
        assert!(end.is_some(), "SVG end tag not found");

        let svg_content = &chart[start.unwrap()..end.unwrap() + 6];

        // Check for required SVG attributes
        assert!(svg_content.contains("viewBox"), "SVG should have viewBox attribute");
        assert!(svg_content.contains("xmlns"), "SVG should have xmlns attribute");

        // Check for balanced tags
        assert_eq!(
            svg_content.matches("<").count(),
            svg_content.matches("</").count() + svg_content.matches("/>").count(),
            "SVG should have balanced opening and closing tags"
        );
    }
}
