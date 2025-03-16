//! Time and date formatting utilities

use chrono::{DateTime, Utc, TimeZone, Duration, Local};

/// Format a UTC datetime for display
pub fn format_datetime(time: DateTime<Utc>) -> String {
    // Format the time in the local timezone
    let local_time = time.with_timezone(&Local);
    local_time.format("%Y-%m-%d %H:%M:%S").to_string()
}

/// Format a UTC datetime with relative time
pub fn format_datetime_relative(time: DateTime<Utc>) -> String {
    let now = Utc::now();
    let diff = now.signed_duration_since(time);

    let formatted = format_datetime(time);
    let relative = format_relative_time(diff);

    format!("{} ({})", formatted, relative)
}

/// Format a duration as a relative time string
pub fn format_relative_time(duration: Duration) -> String {
    let abs_seconds = duration.num_seconds().abs();

    if abs_seconds < 60 {
        return "just now".to_string();
    }

    let abs_minutes = duration.num_minutes().abs();
    if abs_minutes < 60 {
        let plural = if abs_minutes == 1 { "" } else { "s" };
        return format!("{} minute{} ago", abs_minutes, plural);
    }

    let abs_hours = duration.num_hours().abs();
    if abs_hours < 24 {
        let plural = if abs_hours == 1 { "" } else { "s" };
        return format!("{} hour{} ago", abs_hours, plural);
    }

    let abs_days = duration.num_days().abs();
    if abs_days < 30 {
        let plural = if abs_days == 1 { "" } else { "s" };
        return format!("{} day{} ago", abs_days, plural);
    }

    let abs_months = abs_days / 30;
    if abs_months < 12 {
        let plural = if abs_months == 1 { "" } else { "s" };
        return format!("{} month{} ago", abs_months, plural);
    }

    let abs_years = abs_days / 365;
    let plural = if abs_years == 1 { "" } else { "s" };
    format!("{} year{} ago", abs_years, plural)
}

/// Format a timestamp as a UTC datetime
pub fn format_timestamp(timestamp: i64) -> String {
    if let Some(datetime) = Utc.timestamp_opt(timestamp, 0).single() {
        format_datetime(datetime)
    } else {
        "Invalid timestamp".to_string()
    }
}

/// Format a timestamp with relative time
pub fn format_timestamp_relative(timestamp: i64) -> String {
    if let Some(datetime) = Utc.timestamp_opt(timestamp, 0).single() {
        format_datetime_relative(datetime)
    } else {
        "Invalid timestamp".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn test_format_timestamp() {
        // Test with a known timestamp
        let timestamp = 1609459200; // 2021-01-01 00:00:00 UTC
        let formatted = format_timestamp(timestamp);
        assert!(!formatted.is_empty(), "Formatted timestamp should not be empty");
    }

    #[test]
    fn test_format_timestamp_relative() {
        // Test with a timestamp from the past
        let now = Utc::now().timestamp();
        let one_hour_ago = now - 3600;
        let formatted = format_timestamp_relative(one_hour_ago);
        assert!(formatted.contains("hour") || formatted.contains("minute"),
                "Relative time should contain hour or minute: {}", formatted);

        // Test with a very old timestamp
        let one_year_ago = now - 31536000; // Approx. 1 year in seconds
        let formatted = format_timestamp_relative(one_year_ago);
        assert!(formatted.contains("year") || formatted.contains("month"),
                "Relative time should contain year or month: {}", formatted);
    }

    #[test]
    fn test_format_relative_time() {
        // Test various durations
        let now = Utc::now();

        // Test seconds
        let seconds_ago = now - chrono::Duration::seconds(30);
        let formatted = format_relative_time(seconds_ago);
        assert!(formatted.contains("seconds ago") || formatted.contains("just now"),
                "Expected seconds in relative time: {}", formatted);

        // Test minutes
        let minutes_ago = now - chrono::Duration::minutes(5);
        let formatted = format_relative_time(minutes_ago);
        assert!(formatted.contains("minutes ago"),
                "Expected minutes in relative time: {}", formatted);

        // Test hours
        let hours_ago = now - chrono::Duration::hours(3);
        let formatted = format_relative_time(hours_ago);
        assert!(formatted.contains("hours ago"),
                "Expected hours in relative time: {}", formatted);

        // Test days
        let days_ago = now - chrono::Duration::days(4);
        let formatted = format_relative_time(days_ago);
        assert!(formatted.contains("days ago"),
                "Expected days in relative time: {}", formatted);

        // Test months (approximate)
        let months_ago = now - chrono::Duration::days(90);
        let formatted = format_relative_time(months_ago);
        assert!(formatted.contains("months ago"),
                "Expected months in relative time: {}", formatted);

        // Test years (approximate)
        let years_ago = now - chrono::Duration::days(400);
        let formatted = format_relative_time(years_ago);
        assert!(formatted.contains("year ago") || formatted.contains("years ago"),
                "Expected years in relative time: {}", formatted);
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use chrono::{Utc, TimeZone, Duration};

    proptest! {
        /// Test that format_timestamp produces valid output for all inputs
        #[test]
        fn format_timestamp_validity(
            // Use a reasonable range of timestamp values
            timestamp in -62135596800i64..32503680000i64 // roughly year 0 to year 3000
        ) {
            // This should never panic
            let formatted = format_timestamp(timestamp);

            // The result should never be empty
            assert!(!formatted.is_empty(), "Formatted timestamp should not be empty");

            // For valid timestamps, should contain date components (year, month, day)
            if timestamp > 0 {
                // Should have numbers and separators
                assert!(formatted.chars().any(|c| c.is_numeric()),
                       "Formatted timestamp should contain numbers: {}", formatted);
                assert!(formatted.contains('-') || formatted.contains('/') || formatted.contains(' '),
                       "Formatted timestamp should contain date separators: {}", formatted);
            }
        }

        /// Test that format_timestamp_relative handles all inputs reasonably
        #[test]
        fn format_timestamp_relative_validity(
            // Generate a timestamp within last 100 years
            seconds_ago in 0i64..3153600000i64 // up to 100 years in seconds
        ) {
            // Calculate timestamp in the past
            let now = Utc::now().timestamp();
            let past_timestamp = now - seconds_ago;

            // Format the relative timestamp
            let formatted = format_timestamp_relative(past_timestamp);

            // The result should never be empty
            assert!(!formatted.is_empty(), "Formatted relative timestamp should not be empty");

            // For different time ranges, check that appropriate units are used
            if seconds_ago < 60 {
                // Less than a minute ago
                assert!(formatted.contains("second") || formatted.contains("just now"),
                       "Recent timestamps should mention seconds or 'just now': {}", formatted);
            } else if seconds_ago < 3600 {
                // Less than an hour ago
                assert!(formatted.contains("minute"),
                       "Timestamps from minutes ago should mention minutes: {}", formatted);
            } else if seconds_ago < 86400 {
                // Less than a day ago
                assert!(formatted.contains("hour"),
                       "Timestamps from hours ago should mention hours: {}", formatted);
            } else if seconds_ago < 2592000 {
                // Less than a month ago
                assert!(formatted.contains("day"),
                       "Timestamps from days ago should mention days: {}", formatted);
            } else if seconds_ago < 31536000 {
                // Less than a year ago
                assert!(formatted.contains("month"),
                       "Timestamps from months ago should mention months: {}", formatted);
            } else {
                // More than a year ago
                assert!(formatted.contains("year"),
                       "Timestamps from years ago should mention years: {}", formatted);
            }
        }

        /// Test that format_relative_time produces output proportional to input duration
        #[test]
        fn format_relative_time_proportional(
            // Generate a duration from 1 second to 100 years
            seconds in 1i64..3153600000i64
        ) {
            let duration = Duration::seconds(seconds);
            let formatted = format_relative_time(duration);

            // The result should never be empty
            assert!(!formatted.is_empty(), "Formatted duration should not be empty");

            // The output should include a number
            assert!(formatted.chars().any(|c| c.is_numeric()),
                   "Formatted duration should contain numbers: {}", formatted);

            // For different duration ranges, check that appropriate units are used
            if seconds < 60 {
                assert!(formatted.contains("second"),
                       "Duration in seconds should mention seconds: {}", formatted);
            } else if seconds < 3600 {
                assert!(formatted.contains("minute"),
                       "Duration in minutes should mention minutes: {}", formatted);
            } else if seconds < 86400 {
                assert!(formatted.contains("hour"),
                       "Duration in hours should mention hours: {}", formatted);
            } else if seconds < 2592000 {
                assert!(formatted.contains("day"),
                       "Duration in days should mention days: {}", formatted);
            } else if seconds < 31536000 {
                assert!(formatted.contains("month"),
                       "Duration in months should mention months: {}", formatted);
            } else {
                assert!(formatted.contains("year"),
                       "Duration in years should mention years: {}", formatted);
            }
        }

        /// Test that time formatting is deterministic
        #[test]
        fn time_formatting_determinism(timestamp in 0i64..2000000000i64) {
            // Format the timestamp twice
            let first = format_timestamp(timestamp);
            let second = format_timestamp(timestamp);

            // Results should be identical
            assert_eq!(first, second,
                      "Time formatting should be deterministic for the same input");

            // Also check relative formatting
            let first_rel = format_timestamp_relative(timestamp);
            let second_rel = format_timestamp_relative(timestamp);

            // Results should be identical
            assert_eq!(first_rel, second_rel,
                      "Relative time formatting should be deterministic for the same input");
        }

        /// Test that format_datetime and format_datetime_relative handle all valid dates
        #[test]
        fn datetime_formatting_validity(
            // Use a reasonable range of years
            year in 1970i32..3000i32,
            month in 1u32..13,
            day in 1u32..29, // Avoid dealing with month length differences
            hour in 0u32..24,
            minute in 0u32..60,
            second in 0u32..60
        ) {
            // Create a valid DateTime
            let dt = chrono::Utc.with_ymd_and_hms(year, month, day, hour, minute, second).unwrap();

            // Format it
            let formatted = format_datetime(dt);
            let formatted_rel = format_datetime_relative(dt);

            // Results should not be empty
            assert!(!formatted.is_empty(), "Formatted datetime should not be empty");
            assert!(!formatted_rel.is_empty(), "Formatted relative datetime should not be empty");

            // Formatted datetime should contain the year
            assert!(formatted.contains(&year.to_string()),
                   "Formatted datetime should contain the year: {}", formatted);
        }
    }
}
