//! Custom filters for template rendering

use crate::util::time;
use askama::Result as AskamaResult;
use chrono::{NaiveDateTime, Utc, DateTime};

/// Format a file size into a human-readable string
///
/// # Arguments
/// * `size` - Size in bytes
///
/// # Returns
/// * Formatted string like "1.5 KiB" or "3.2 MiB"
pub fn filesize(size: &i64) -> AskamaResult<String> {
    let size = *size as f64;

    if size < 1024.0 {
        Ok(format!("{:.0} B", size))
    } else if size < 1024.0 * 1024.0 {
        Ok(format!("{:.1} KiB", size / 1024.0))
    } else if size < 1024.0 * 1024.0 * 1024.0 {
        Ok(format!("{:.1} MiB", size / (1024.0 * 1024.0)))
    } else {
        Ok(format!("{:.1} GiB", size / (1024.0 * 1024.0 * 1024.0)))
    }
}

/// Format a timestamp as a relative time string (e.g., "2 hours ago")
///
/// # Arguments
/// * `timestamp` - Unix timestamp
///
/// # Returns
/// * Formatted relative time string
pub fn relative_time(timestamp: &i64) -> AskamaResult<String> {
    let datetime = DateTime::<Utc>::from_naive_utc_and_offset(
        NaiveDateTime::from_timestamp_opt(*timestamp, 0).unwrap_or_default(),
        Utc,
    );

    Ok(time::format_relative_time(datetime))
}

/// Format a timestamp as a date string (e.g., "Jan 1, 2023")
///
/// # Arguments
/// * `timestamp` - Unix timestamp
///
/// # Returns
/// * Formatted date string
pub fn date_format(timestamp: &i64) -> AskamaResult<String> {
    let datetime = DateTime::<Utc>::from_naive_utc_and_offset(
        NaiveDateTime::from_timestamp_opt(*timestamp, 0).unwrap_or_default(),
        Utc,
    );

    Ok(datetime.format("%b %d, %Y").to_string())
}

/// Format a timestamp as a full datetime string (e.g., "Jan 1, 2023 12:34:56")
///
/// # Arguments
/// * `timestamp` - Unix timestamp
///
/// # Returns
/// * Formatted datetime string
pub fn datetime_format(timestamp: &i64) -> AskamaResult<String> {
    let datetime = DateTime::<Utc>::from_naive_utc_and_offset(
        NaiveDateTime::from_timestamp_opt(*timestamp, 0).unwrap_or_default(),
        Utc,
    );

    Ok(datetime.format("%b %d, %Y %H:%M:%S").to_string())
}

/// Truncate a string to a maximum length and add an ellipsis if truncated
///
/// # Arguments
/// * `s` - String to truncate
/// * `len` - Maximum length
///
/// # Returns
/// * Truncated string with ellipsis if needed
pub fn truncate(s: &str, len: usize) -> AskamaResult<String> {
    if s.len() <= len {
        Ok(s.to_string())
    } else {
        let truncated = s.chars().take(len).collect::<String>();
        Ok(format!("{}...", truncated))
    }
}

/// Format a git commit ID to show just the first few characters
///
/// # Arguments
/// * `commit_id` - Full commit ID
/// * `len` - Number of characters to show (default is 7)
///
/// # Returns
/// * Shortened commit ID
pub fn short_commit_id(commit_id: &str, len: usize) -> AskamaResult<String> {
    if commit_id.len() <= len {
        Ok(commit_id.to_string())
    } else {
        Ok(commit_id[..len].to_string())
    }
}

/// Convert a UNIX path to a web-friendly path
///
/// # Arguments
/// * `path` - UNIX path
///
/// # Returns
/// * URL-encoded path
pub fn path_to_url(path: &str) -> AskamaResult<String> {
    // Simple URL encoding for path components
    let components: Vec<String> = path.split('/')
        .map(|component| urlencoding::encode(component).to_string())
        .collect();

    Ok(components.join("/"))
}

/// Create a breadcrumb path from a file path
///
/// # Arguments
/// * `path` - File path (e.g., "src/main.rs")
///
/// # Returns
/// * Vector of (name, path) tuples for breadcrumb navigation
pub fn breadcrumbs(path: &str) -> AskamaResult<Vec<(String, String)>> {
    if path.is_empty() {
        return Ok(Vec::new());
    }

    let components: Vec<&str> = path.split('/').collect();
    let mut breadcrumbs = Vec::with_capacity(components.len());
    let mut current_path = String::new();

    for (i, component) in components.iter().enumerate() {
        if i > 0 {
            current_path.push('/');
        }
        current_path.push_str(component);
        breadcrumbs.push((component.to_string(), current_path.clone()));
    }

    Ok(breadcrumbs)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use chrono::Utc;

    #[test]
    fn test_filesize() {
        // Test cases for various file sizes
        let cases = [
            (0, "0 B"),
            (100, "100 B"),
            (1023, "1023 B"),
            (1024, "1.0 KiB"),
            (1500, "1.5 KiB"),
            (1024 * 1024, "1.0 MiB"),
            (1024 * 1024 * 1024, "1.0 GiB"),
            (1024 * 1024 * 1024 * 2, "2.0 GiB"),
        ];

        for (size, expected) in cases {
            let result = filesize(&size).unwrap();
            assert_eq!(result, expected, "Failed for size: {}", size);
        }
    }

    #[test]
    fn test_relative_time() {
        // Get current time
        let now = Utc::now().timestamp();

        // Test cases for various time differences
        let cases = [
            (now, "just now"),
            (now - 30, "just now"),
            (now - 60, "1 minute ago"),
            (now - 60 * 5, "5 minutes ago"),
            (now - 60 * 60, "1 hour ago"),
            (now - 60 * 60 * 5, "5 hours ago"),
            (now - 60 * 60 * 24, "1 day ago"),
            (now - 60 * 60 * 24 * 5, "5 days ago"),
            (now - 60 * 60 * 24 * 30, "1 month ago"),
            (now - 60 * 60 * 24 * 30 * 5, "5 months ago"),
            (now - 60 * 60 * 24 * 365, "1 year ago"),
            (now - 60 * 60 * 24 * 365 * 5, "5 years ago"),
        ];

        for (time, expected) in cases {
            let result = relative_time(&time).unwrap();
            assert!(result.contains(expected.split_whitespace().next().unwrap()),
                    "Failed for time diff: {}, got: {}, expected to contain: {}",
                    now - time, result, expected);
        }
    }

    #[test]
    fn test_short_commit_id() {
        // Test short hash filter with different lengths
        let hash = "e1c2d3b4a5f6e7d8c9b0a1b2c3d4e5f6a7b8c9d0";

        assert_eq!(short_commit_id(hash, 7).unwrap(), "e1c2d3b");
        assert_eq!(short_commit_id(hash, 4).unwrap(), "e1c2");
        assert_eq!(short_commit_id(hash, 10).unwrap(), "e1c2d3b4a5");

        // Test with a short hash (less than 7 chars)
        let short_hash = "abc123";
        assert_eq!(short_commit_id(short_hash, 7).unwrap(), short_hash);
    }

    #[test]
    fn test_truncate() {
        // Test truncate filter
        let text = "This is a very long text that needs to be truncated";

        assert_eq!(truncate(text, 10).unwrap(), "This is a...");
        assert_eq!(truncate(text, 20).unwrap(), "This is a very long...");

        // Test with short text (no truncation needed)
        let short_text = "Short text";
        assert_eq!(truncate(short_text, 20).unwrap(), short_text);
    }

    #[test]
    fn test_breadcrumbs() {
        // Test breadcrumb generation
        let path = "src/main.rs";
        let result = breadcrumbs(path).unwrap();

        assert_eq!(result.len(), 2);
        assert_eq!(result[0], ("src".to_string(), "src".to_string()));
        assert_eq!(result[1], ("main.rs".to_string(), "src/main.rs".to_string()));

        // Test with empty path
        let result = breadcrumbs("").unwrap();
        assert!(result.is_empty());

        // Test with single component
        let result = breadcrumbs("file.txt").unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0], ("file.txt".to_string(), "file.txt".to_string()));
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use chrono::{DateTime, Utc, TimeZone, Duration};

    proptest! {
        /// Test that filesize filter properly formats different sizes
        #[test]
        fn filesize_formatting(size in 0u64..10_000_000_000u64) {
            let formatted = filesize(size);

            // The output should not be empty
            assert!(!formatted.is_empty());

            // The output should contain a number
            assert!(formatted.chars().any(|c| c.is_ascii_digit()));

            // For known sizes, verify specific formatting
            match size {
                0 => assert_eq!(formatted, "0 B"),
                1 => assert_eq!(formatted, "1 B"),
                1023 => assert_eq!(formatted, "1023 B"),
                1024 => assert_eq!(formatted, "1.0 KiB"),
                1024 * 1024 => assert_eq!(formatted, "1.0 MiB"),
                1024 * 1024 * 1024 => assert_eq!(formatted, "1.0 GiB"),
                _ => {
                    // For other sizes, verify the format includes a unit
                    assert!(
                        formatted.contains(" B") ||
                        formatted.contains(" KiB") ||
                        formatted.contains(" MiB") ||
                        formatted.contains(" GiB") ||
                        formatted.contains(" TiB")
                    );
                }
            }

            // Make sure larger sizes use the right units
            if size < 1024 {
                assert!(formatted.contains(" B"));
            } else if size < 1024 * 1024 {
                assert!(formatted.contains(" KiB"));
            } else if size < 1024 * 1024 * 1024 {
                assert!(formatted.contains(" MiB"));
            } else if size < 1024u64.pow(4) {
                assert!(formatted.contains(" GiB"));
            } else {
                assert!(formatted.contains(" TiB"));
            }
        }

        /// Test that relative_time properly formats timestamps
        #[test]
        fn relative_time_formatting(days_ago in 0i64..10000i64) {
            // Create a timestamp in the past
            let now = Utc::now();
            let past_time = now - Duration::days(days_ago);
            let timestamp = past_time.timestamp();

            // Format as relative time
            let formatted = relative_time(timestamp);

            // The output should not be empty
            assert!(!formatted.is_empty());

            // For certain known durations, check specific format
            match days_ago {
                0 => assert!(
                    formatted.contains("just now") ||
                    formatted.contains("second") ||
                    formatted.contains("minute") ||
                    formatted.contains("hour"),
                    "Recent time should be 'just now' or contain units of hours or less"
                ),
                1 => assert!(
                    formatted.contains("day") || formatted.contains("hour"),
                    "One day ago should contain 'day' or 'hour'"
                ),
                7 => assert!(
                    formatted.contains("week") || formatted.contains("day"),
                    "One week ago should contain 'week' or 'day'"
                ),
                30 => assert!(
                    formatted.contains("month") || formatted.contains("week"),
                    "30 days ago should contain 'month' or 'week'"
                ),
                365 => assert!(
                    formatted.contains("year") || formatted.contains("month"),
                    "365 days ago should contain 'year' or 'month'"
                ),
                _ => {
                    // For other durations, format should include appropriate time unit
                    if days_ago < 1 {
                        assert!(
                            formatted.contains("just now") ||
                            formatted.contains("second") ||
                            formatted.contains("minute") ||
                            formatted.contains("hour"),
                            "Recent time should use small units"
                        );
                    } else if days_ago < 7 {
                        assert!(
                            formatted.contains("day") || formatted.contains("hour"),
                            "Few days ago should use days or hours"
                        );
                    } else if days_ago < 30 {
                        assert!(
                            formatted.contains("week") || formatted.contains("day"),
                            "Few weeks ago should use weeks or days"
                        );
                    } else if days_ago < 365 {
                        assert!(
                            formatted.contains("month") || formatted.contains("week"),
                            "Few months ago should use months or weeks"
                        );
                    } else {
                        assert!(
                            formatted.contains("year") || formatted.contains("month"),
                            "Long time ago should use years or months"
                        );
                    }
                }
            }
        }

        /// Test that short_commit_id truncates commit IDs correctly
        #[test]
        fn short_commit_id_truncation(
            commit_id in "[0-9a-f]{40}",
            length in 6usize..40usize,
        ) {
            let truncated = short_commit_id(&commit_id, length);

            // The truncated ID should have the requested length
            assert_eq!(truncated.len(), length, "Truncated commit ID length mismatch");

            // The truncated ID should be a prefix of the original
            assert!(commit_id.starts_with(&truncated), "Truncated ID should be a prefix of the original");

            // Edge cases
            assert_eq!(short_commit_id(&commit_id, 40).len(), 40, "No truncation needed for full length");
            assert_eq!(short_commit_id(&commit_id, 7).len(), 7, "Standard short SHA-1 length should be 7");
        }

        /// Test that truncate properly limits text length
        #[test]
        fn truncate_text_length(
            text in ".*",
            max_length in 5usize..100usize,
        ) {
            let truncated = truncate(&text, max_length);

            // If the original text is shorter than max_length, it should be unchanged
            if text.len() <= max_length {
                assert_eq!(truncated, text, "Short text should not be truncated");
            } else {
                // If truncated, the length should be at most max_length + 3 (for the ellipsis)
                assert!(truncated.len() <= max_length + 3, "Truncated text too long");

                // The truncated text should end with ellipsis
                assert!(truncated.ends_with("..."), "Truncated text should end with ellipsis");

                // The truncated text should start with the beginning of the original text
                let prefix = &text[..truncated.len() - 3];
                assert!(truncated.starts_with(prefix), "Truncated text should start with original text prefix");
            }
        }

        /// Test that breadcrumbs properly formats paths
        #[test]
        fn breadcrumbs_path_formatting(
            // Generate a path with 1-5 segments
            segments in prop::collection::vec("[a-zA-Z0-9_-]+", 1..5),
        ) {
            // Create a path from the segments
            let path = format!("/{}", segments.join("/"));

            // Generate breadcrumbs
            let crumbs = breadcrumbs(&path);

            // Breadcrumbs should not be empty
            assert!(!crumbs.is_empty(), "Breadcrumbs should not be empty");

            // Breadcrumbs should include all segments
            for segment in &segments {
                assert!(crumbs.contains(segment), "Breadcrumbs should include segment: {}", segment);
            }

            // Breadcrumbs should start with a root link
            assert!(crumbs.starts_with("<a href=\"/\">/</a>"), "Breadcrumbs should start with root link");

            // Number of links should match number of segments + 1 (for root)
            let link_count = crumbs.matches("<a").count();
            assert_eq!(link_count, segments.len() + 1, "Breadcrumbs should have the right number of links");

            // The last segment should not be a link (except for the root path)
            if !segments.is_empty() {
                assert!(!crumbs.ends_with("</a>"), "Last segment should not be a link");
            }
        }
    }
}
