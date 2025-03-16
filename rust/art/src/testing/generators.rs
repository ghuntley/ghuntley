// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Property-based testing generators for Art
//!
//! This module provides custom generators for property-based testing.

use crate::prelude::*;
use proptest::prelude::*;
use proptest::collection::{vec, hash_map};
use proptest::option;
use chrono::{DateTime, Utc, Duration};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Generate a valid repository name
pub fn repository_name() -> impl Strategy<Value = String> {
    "[a-zA-Z][a-zA-Z0-9_-]{1,39}"
}

/// Generate a valid file path for a repository
pub fn repo_file_path() -> impl Strategy<Value = String> {
    // Generate path segments, avoiding ".." to prevent directory traversal
    let segment = "[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,20}";
    let segments = vec(segment, 1..5);

    segments.prop_map(|segs| segs.join("/"))
}

/// Generate a valid Git reference (branch, tag, commit hash)
pub fn git_reference() -> impl Strategy<Value = String> {
    prop_oneof![
        // Branch name
        "[a-zA-Z][a-zA-Z0-9_/.-]{1,39}",

        // Tag name
        "v[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9_.]+)?",

        // Commit hash
        "[0-9a-f]{7,40}"
    ]
}

/// Generate a valid Git commit message
pub fn commit_message() -> impl Strategy<Value = String> {
    // First line (50 chars max) + optional body
    let first_line = "[A-Z][^\\n]{5,49}";
    let body = "\\n\\n([^\\n]{1,72}\\n?)+";

    prop_oneof![
        // Just a subject line
        first_line,

        // Subject + body
        format!("{}({})?", first_line, body)
    ]
}

/// Generate a valid email address
pub fn email_address() -> impl Strategy<Value = String> {
    let username = "[a-zA-Z0-9][a-zA-Z0-9._%+-]{1,20}";
    let domain = "[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}";

    format!("{}@{}", username, domain)
}

/// Generate HTTP methods
pub fn http_method() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("GET".to_string()),
        Just("POST".to_string()),
        Just("PUT".to_string()),
        Just("DELETE".to_string()),
        Just("HEAD".to_string()),
        Just("OPTIONS".to_string())
    ]
}

/// Generate HTTP paths
pub fn http_path() -> impl Strategy<Value = String> {
    let segment = "[a-zA-Z0-9_-]+";
    let segments = vec(segment, 1..5);

    segments.prop_map(|segs| format!("/{}", segs.join("/")))
}

/// Generate HTTP status codes
pub fn http_status() -> impl Strategy<Value = u16> {
    prop_oneof![
        // 2xx Success
        200..300u16,

        // 3xx Redirection
        300..400u16,

        // 4xx Client Error
        400..500u16,

        // 5xx Server Error
        500..600u16
    ]
}

/// Generate a date-time within a reasonable range
pub fn datetime_recent() -> impl Strategy<Value = DateTime<Utc>> {
    // Generate a datetime from 1 year ago to now
    let now = Utc::now();
    let one_year_ago = now - Duration::days(365);

    // Convert to timestamp for proptest
    let min_secs = one_year_ago.timestamp();
    let max_secs = now.timestamp();

    (min_secs..=max_secs).prop_map(|secs| {
        DateTime::<Utc>::from_timestamp(secs, 0).unwrap_or(now)
    })
}

/// Generate a path that exists in the temp directory
pub fn existing_path(base_dir: PathBuf) -> impl Strategy<Value = PathBuf> {
    repo_file_path().prop_map(move |path| {
        let full_path = base_dir.join(&path);

        // Ensure parent directory exists
        if let Some(parent) = full_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        // Create an empty file
        let _ = std::fs::write(&full_path, b"test content");

        full_path
    })
}

/// Generate a map of key-value pairs for testing
pub fn key_value_map() -> impl Strategy<Value = HashMap<String, String>> {
    // Generate up to 10 key-value pairs with reasonable strings
    hash_map("[a-zA-Z][a-zA-Z0-9_-]{0,19}", "[a-zA-Z0-9_. -]{0,50}", 0..10)
}

/// Generate a SQL query with proper syntax
pub fn sql_query() -> impl Strategy<Value = String> {
    // Simple SELECT queries for testing
    let table = "(repositories|commits|refs|blobs|authors|contributors)";
    let column = "(id|name|email|path|hash|message|timestamp|size|content)";
    let columns = vec(column, 1..5);
    let where_clause = format!("WHERE {} = ?", column);

    (columns, option::of(where_clause)).prop_map(|(cols, where_c)| {
        let columns_str = cols.join(", ");
        let mut query = format!("SELECT {} FROM {}", columns_str, table);

        if let Some(where_clause) = where_c {
            query = format!("{} {}", query, where_clause);
        }

        query
    })
}

/// Generate Git operation types for testing
pub fn git_operation() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("clone".to_string()),
        Just("fetch".to_string()),
        Just("pull".to_string()),
        Just("push".to_string()),
        Just("log".to_string()),
        Just("show".to_string()),
        Just("diff".to_string()),
        Just("blame".to_string())
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_repository_name_generator() {
        proptest!(|(name in repository_name())| {
            // Should start with a letter
            assert!(name.chars().next().unwrap().is_alphabetic());

            // Should only contain allowed characters
            for c in name.chars() {
                assert!(c.is_alphanumeric() || c == '_' || c == '-');
            }

            // Should be within allowed length
            assert!(name.len() <= 40);
            assert!(name.len() >= 2);
        });
    }

    #[test]
    fn test_repo_file_path_generator() {
        proptest!(|(path in repo_file_path())| {
            // Shouldn't contain path traversal
            assert!(!path.contains(".."));
            assert!(!path.contains("./"));
            assert!(!path.starts_with('/'));

            // Should be a valid path
            let path_buf = PathBuf::from(&path);
            assert!(path_buf.components().count() >= 1);
        });
    }

    #[test]
    fn test_git_reference_generator() {
        proptest!(|(reference in git_reference())| {
            // Should be a valid git reference
            if reference.len() >= 7 && reference.len() <= 40 {
                // Likely a commit hash
                for c in reference.chars() {
                    assert!(c.is_digit(16) && !c.is_uppercase());
                }
            } else if reference.starts_with('v') {
                // Likely a version tag
                let parts: Vec<&str> = reference[1..].split('.').collect();
                assert!(parts.len() >= 2);
                // Major version should parse as a number
                assert!(parts[0].parse::<u32>().is_ok());
            } else {
                // Likely a branch name
                assert!(reference.chars().next().unwrap().is_alphabetic());
            }
        });
    }

    #[test]
    fn test_email_address_generator() {
        proptest!(|(email in email_address())| {
            // Should contain exactly one @
            assert_eq!(email.matches('@').count(), 1);

            // Should have a domain with at least one dot
            let parts: Vec<&str> = email.split('@').collect();
            assert_eq!(parts.len(), 2);
            assert!(parts[1].contains('.'));

            // Domain should end with at least a 2-letter TLD
            let domain_parts: Vec<&str> = parts[1].split('.').collect();
            assert!(domain_parts.last().unwrap().len() >= 2);
        });
    }

    #[test]
    fn test_existing_path_generator() {
        let temp_dir = tempdir().unwrap();

        proptest!(|(path in existing_path(temp_dir.path().to_path_buf()))| {
            // Path should exist
            assert!(path.exists());

            // Path should be within the temp dir
            assert!(path.starts_with(temp_dir.path()));
        });
    }
}
