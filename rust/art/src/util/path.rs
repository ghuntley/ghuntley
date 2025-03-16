//! Path manipulation utilities

use std::path::{Path, PathBuf};
use percent_encoding::{percent_decode_str, percent_encode, NON_ALPHANUMERIC};

/// Normalize a path for Git operations
///
/// - Removes leading/trailing slashes
/// - Resolves '..' and '.' components
/// - Removes duplicate slashes
pub fn normalize_path(path: &str) -> String {
    let path = path.trim_start_matches('/').trim_end_matches('/');

    let mut result = Vec::new();
    for component in path.split('/') {
        match component {
            "" | "." => continue,
            ".." => {
                result.pop();
            }
            _ => result.push(component),
        }
    }

    result.join("/")
}

/// URL-encode a path for use in URLs
pub fn url_encode_path(path: &str) -> String {
    let path = normalize_path(path);

    // Encode each segment separately to preserve '/'
    let segments: Vec<String> = path
        .split('/')
        .map(|segment| {
            percent_encode(segment.as_bytes(), NON_ALPHANUMERIC)
                .to_string()
        })
        .collect();

    segments.join("/")
}

/// URL-decode a path from a URL
pub fn url_decode_path(path: &str) -> Option<String> {
    // Decode each segment separately to preserve '/'
    let segments: Option<Vec<String>> = path
        .split('/')
        .map(|segment| {
            percent_decode_str(segment)
                .decode_utf8()
                .ok()
                .map(|s| s.to_string())
        })
        .collect();

    segments.map(|s| s.join("/"))
}

/// Get the mime type for a file based on its extension
pub fn mime_type_for_path(path: &Path) -> String {
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        match ext.to_lowercase().as_str() {
            "html" | "htm" => "text/html; charset=utf-8",
            "css" => "text/css; charset=utf-8",
            "js" => "application/javascript; charset=utf-8",
            "json" => "application/json; charset=utf-8",
            "xml" => "application/xml; charset=utf-8",
            "png" => "image/png",
            "jpg" | "jpeg" => "image/jpeg",
            "gif" => "image/gif",
            "svg" => "image/svg+xml",
            "pdf" => "application/pdf",
            "md" | "markdown" => "text/markdown; charset=utf-8",
            "txt" => "text/plain; charset=utf-8",
            _ => mime_guess::from_ext(ext)
                .first_or_octet_stream()
                .essence_str(),
        }
    } else {
        // Use filename for special cases
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            match name {
                "LICENSE" | "README" | "AUTHORS" | "CONTRIBUTORS" | "COPYING" => {
                    return "text/plain; charset=utf-8";
                }
                _ => {}
            }
        }

        "application/octet-stream"
    }
}

/// Create a URL-safe version of a repository name
pub fn repo_name_to_url_path(name: &str) -> String {
    url_encode_path(name)
}

/// Split a path into directory and filename
pub fn split_path(path: &str) -> (String, Option<String>) {
    let path = normalize_path(path);
    if path.is_empty() {
        return (String::new(), None);
    }

    let path_buf = PathBuf::from(&path);

    if let Some(file_name) = path_buf.file_name() {
        let dir = path_buf.parent()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();

        (dir, Some(file_name.to_string_lossy().to_string()))
    } else {
        (path, None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn test_normalize_path() {
        // Test cases
        let cases = [
            ("", ""),
            ("file.txt", "file.txt"),
            ("/file.txt", "file.txt"),
            ("dir/file.txt", "dir/file.txt"),
            ("/dir/file.txt", "dir/file.txt"),
            ("./file.txt", "file.txt"),
            ("../file.txt", "file.txt"),
            ("dir/../file.txt", "file.txt"),
            ("dir/./file.txt", "dir/file.txt"),
            ("dir//file.txt", "dir/file.txt"),
            ("dir/sub/../file.txt", "dir/file.txt"),
        ];

        for (input, expected) in cases {
            let result = normalize_path(input);
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    #[test]
    fn test_mime_type_for_path() {
        // Test cases
        let cases = [
            ("file.txt", "text/plain"),
            ("file.html", "text/html"),
            ("file.css", "text/css"),
            ("file.js", "application/javascript"),
            ("file.json", "application/json"),
            ("file.png", "image/png"),
            ("file.jpg", "image/jpeg"),
            ("file.gif", "image/gif"),
            ("file.pdf", "application/pdf"),
            ("file.zip", "application/zip"),
            ("file.rs", "text/plain"),
            ("file.unknown", "application/octet-stream"),
        ];

        for (input, expected) in cases {
            let result = mime_type_for_path(Path::new(input));
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    #[test]
    fn test_is_binary_content() {
        // Test binary detection
        let binary_content = vec![0, 1, 2, 3, 4, 0, 255, 127];
        assert!(is_binary_content(&binary_content));

        // Test text content
        let text_content = "Hello, world!".as_bytes().to_vec();
        assert!(!is_binary_content(&text_content));

        // Test empty content
        let empty_content = vec![];
        assert!(!is_binary_content(&empty_content));

        // Test content with some non-printable characters but still text
        let mixed_content = "Hello\nworld!\r\n".as_bytes().to_vec();
        assert!(!is_binary_content(&mixed_content));
    }

    #[test]
    fn test_get_file_extension() {
        // Test cases
        let cases = [
            ("file.txt", Some("txt")),
            ("file.tar.gz", Some("gz")),
            ("file", None),
            ("file.", Some("")),
            (".gitignore", Some("gitignore")),
            ("/path/to/file.rs", Some("rs")),
            ("C:\\path\\to\\file.rs", Some("rs")),
        ];

        for (input, expected) in cases {
            let result = get_file_extension(Path::new(input));
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    #[test]
    fn test_is_binary_extension() {
        // Test cases
        let cases = [
            ("file.txt", false),
            ("file.png", true),
            ("file.jpg", true),
            ("file.jpeg", true),
            ("file.gif", true),
            ("file.pdf", true),
            ("file.zip", true),
            ("file.gz", true),
            ("file.rs", false),
            ("file.c", false),
            ("file.exe", true),
            ("file.bin", true),
            ("file", false), // No extension
        ];

        for (input, expected) in cases {
            let result = is_binary_extension(Path::new(input));
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    #[test]
    fn test_parent_path() {
        // Test cases
        let cases = [
            ("file.txt", ""),
            ("dir/file.txt", "dir"),
            ("dir/subdir/file.txt", "dir/subdir"),
            ("/absolute/path/file.txt", "absolute/path"),
            ("", ""),
        ];

        for (input, expected) in cases {
            let result = parent_path(input);
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    #[test]
    fn test_sanitize_branch_name() {
        // Test cases
        let cases = [
            ("main", "main"),
            ("feature/branch", "feature/branch"),
            ("feature..branch", "feature/branch"),
            ("feature//branch", "feature/branch"),
            ("feature/branch//", "feature/branch"),
            ("../feature/branch", "feature/branch"),
            ("feature/branch/..", "feature/branch"),
            (".git/hooks/pre-commit", "git/hooks/pre-commit"),
            ("@{upstream}", "upstream"),
            ("HEAD^", "HEAD"),
        ];

        for (input, expected) in cases {
            let result = sanitize_branch_name(input);
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use std::path::Path;

    proptest! {
        /// Test that normalize_path handles all inputs safely
        #[test]
        fn normalize_path_safety(path in ".*") {
            // This should never panic
            let _ = normalize_path(&path);
        }

        /// Test that normalize_path removes path traversal
        #[test]
        fn normalize_path_removes_traversal(
            base_path in "[a-zA-Z0-9_\\-/]+",
            traversal_count in 0..5usize,
        ) {
            // Create a path with ../
            let traversal = "../".repeat(traversal_count);
            let path_with_traversal = format!("{}{}", traversal, base_path);

            let normalized = normalize_path(&path_with_traversal);

            // Should never contain ../ after normalization
            assert!(!normalized.contains("../"),
                   "Normalized path should not contain directory traversal: {}", normalized);
        }

        /// Test that parent_path is consistent
        #[test]
        fn parent_path_properties(
            segments in prop::collection::vec("[a-zA-Z0-9_\\-]+", 0..5),
        ) {
            // Create a path with segments
            let path = segments.join("/");
            let parent = parent_path(&path);

            // Parent should be a prefix of path (unless path is empty/root)
            if !path.is_empty() && path != "/" && segments.len() > 1 {
                assert!(path.starts_with(&parent) || parent == "",
                       "Parent '{}' should be a prefix of path '{}'", parent, path);
            }

            // Parent should have fewer segments than original path
            let path_segments = path.split('/').filter(|s| !s.is_empty()).count();
            let parent_segments = parent.split('/').filter(|s| !s.is_empty()).count();

            if segments.len() > 0 {
                assert!(parent_segments < path_segments || (path_segments == 0 && parent_segments == 0),
                       "Parent should have fewer segments: parent={}, path={}",
                       parent_segments, path_segments);
            }
        }

        /// Test that url_encode_path and url_decode_path are inverses
        #[test]
        fn url_encoding_roundtrip(
            // Use a strategy that generates paths with special URL chars
            path in "[a-zA-Z0-9_\\-/. +%&?=]+"
        ) {
            let encoded = url_encode_path(&path);

            // Encoded path should not contain unsafe characters
            assert!(!encoded.contains(' '), "Encoded path should not contain spaces");
            assert!(!encoded.contains('?'), "Encoded path should not contain question marks");
            assert!(!encoded.contains('&'), "Encoded path should not contain ampersands");
            assert!(!encoded.contains('+'), "Encoded path should not contain plus signs");
            assert!(!encoded.contains('%') || encoded.matches('%').count() > path.matches('%').count(),
                   "Percent signs should be encoded unless they were part of an existing encoding");

            // Decoding should restore the original path
            let decoded = url_decode_path(&encoded);
            assert!(decoded.is_some(), "Decoding should succeed for encoded path: {}", encoded);
            assert_eq!(decoded.unwrap(), path, "Decoding should restore original path");
        }

        /// Test that mime_type_for_path returns consistent results
        #[test]
        fn mime_type_consistency(
            filename in "[a-zA-Z0-9_\\-]+\\.[a-z0-9]{1,5}",
        ) {
            let path = Path::new(&filename);
            let mime = mime_type_for_path(path);

            // MIME type should never be empty
            assert!(!mime.is_empty());

            // MIME type should be in the format type/subtype
            assert!(mime.contains('/'));
            let parts: Vec<&str> = mime.split('/').collect();
            assert_eq!(parts.len(), 2);
            assert!(!parts[0].is_empty());
            assert!(!parts[1].is_empty());

            // If we call it again with the same path, we should get the same result
            let mime2 = mime_type_for_path(path);
            assert_eq!(mime, mime2, "MIME type detection should be deterministic");
        }

        /// Test that sanitize_branch_name properly secures branch names
        #[test]
        fn sanitize_branch_name_security(
            branch_name in ".*"
        ) {
            let sanitized = sanitize_branch_name(&branch_name);

            // Should not contain dangerous Git characters
            assert!(!sanitized.contains(".."), "Sanitized branch name should not contain .. traversal");
            assert!(!sanitized.contains('~'), "Sanitized branch name should not contain ~");
            assert!(!sanitized.contains('^'), "Sanitized branch name should not contain ^");
            assert!(!sanitized.contains(':'), "Sanitized branch name should not contain :");
            assert!(!sanitized.contains('\\'), "Sanitized branch name should not contain backslash");
            assert!(!sanitized.contains('?'), "Sanitized branch name should not contain ?");
            assert!(!sanitized.contains('['), "Sanitized branch name should not contain [");
            assert!(!sanitized.contains(']'), "Sanitized branch name should not contain ]");
            assert!(!sanitized.contains('*'), "Sanitized branch name should not contain *");

            // Branch name should not end with .lock
            assert!(!sanitized.ends_with(".lock"),
                   "Sanitized branch name should not end with .lock");

            // Should not be .git
            assert!(sanitized != ".git", "Sanitized branch name should not be .git");
        }

        /// Test that get_file_extension returns consistent results
        #[test]
        fn file_extension_properties(
            filename in "[a-zA-Z0-9_\\-]+\\.[a-z0-9]{0,5}"
        ) {
            let path = Path::new(&filename);
            let extension = get_file_extension(path);

            // If filename contains a dot, extension should be Some
            if filename.contains('.') {
                assert!(extension.is_some(),
                       "Extension should be Some for filename with dot: {}", filename);

                // Extension should match everything after the last dot
                let parts: Vec<&str> = filename.split('.').collect();
                let expected_ext = parts.last().unwrap();
                assert_eq!(&extension.unwrap(), expected_ext,
                          "Extension should match text after last dot");
            }
        }

        /// Test that normalize_path removes double slashes and trailing slashes
        #[test]
        fn normalize_path_removes_redundant_slashes(
            // Generate paths with potentially redundant slashes
            segments in prop::collection::vec("\\w+", 1..5),
        ) {
            // Create a path with double slashes
            let mut path_with_doubles = String::new();
            for segment in &segments {
                path_with_doubles.push_str(segment);
                path_with_doubles.push_str("//");  // Double slash
            }

            // Normalize the path
            let normalized = normalize_path(&path_with_doubles);

            // Verify no double slashes in the result
            assert!(!normalized.contains("//"), "Normalized path should not contain double slashes");

            // The path should start with a slash
            assert!(normalized.starts_with('/'), "Normalized path should start with a slash");

            // The path should not end with a slash (unless it's just /)
            if normalized.len() > 1 {
                assert!(!normalized.ends_with('/'), "Normalized path should not end with a slash");
            }

            // All segments should still be present
            for segment in segments {
                assert!(normalized.contains(&segment), "Segment {} should be present in normalized path", segment);
            }
        }

        /// Test that parent_path correctly extracts the parent directory
        #[test]
        fn parent_path_properties(
            // Generate a path with 2-5 segments
            segments in prop::collection::vec("[a-zA-Z0-9_-]+", 2..5),
        ) {
            // Create a path from the segments
            let path = format!("/{}", segments.join("/"));

            // Get the parent path
            let parent = parent_path(&path);

            // The parent should be a prefix of the original path
            assert!(path.starts_with(&parent), "Parent path should be a prefix of the original path");

            // The parent should be shorter than the original path
            assert!(parent.len() < path.len(), "Parent path should be shorter than the original path");

            // The parent should contain one fewer segment than the original path
            let parent_segments = parent.split('/').filter(|s| !s.is_empty()).count();
            let original_segments = path.split('/').filter(|s| !s.is_empty()).count();
            assert_eq!(parent_segments, original_segments - 1, "Parent path should have one fewer segment");

            // The parent should include all segments except the last one
            for segment in &segments[..segments.len() - 1] {
                assert!(parent.contains(segment), "Parent path should contain segment {}", segment);
            }

            // Special case: root directory
            assert_eq!(parent_path("/"), "/", "Parent of root should be root");

            // Special case: directory in root
            let root_child = format!("/{}", segments[0]);
            assert_eq!(parent_path(&root_child), "/", "Parent of root child should be root");
        }

        /// Test that is_binary_content correctly identifies binary vs text content
        #[test]
        fn is_binary_content_properties(
            // Generate random content
            content in prop::collection::vec(0u8..=255, 1..1000),
        ) {
            let content_bytes = content.as_slice();

            // If content contains null bytes, it should be detected as binary
            let has_null = content.contains(&0);
            let has_high_bit = content.iter().any(|&b| b > 127);

            // Check binary detection
            let is_binary = is_binary_content(content_bytes);

            // Content with null bytes should always be detected as binary
            if has_null {
                assert!(is_binary, "Content with null bytes should be detected as binary");
            }

            // Pure ASCII text content should never be detected as binary
            if !has_null && !has_high_bit {
                // But only if it consists of printable characters and whitespace
                let all_printable_or_whitespace = content.iter().all(|&b|
                    (b >= 32 && b <= 126) || // printable ASCII
                    b == 9 || b == 10 || b == 13 // tab, LF, CR
                );

                if all_printable_or_whitespace && content.len() > 10 {
                    assert!(!is_binary, "Pure ASCII text should not be detected as binary");
                }
            }
        }

        /// Test that mime_type_for_path returns appropriate MIME types for different file extensions
        #[test]
        fn mime_type_for_path_extensions(
            // Generate random valid filenames with various extensions
            filename in "[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9]+)?",
            ext in prop::sample::select(&["txt", "md", "rs", "js", "css", "html", "json", "xml", "png", "jpg", "gif", "pdf"]),
        ) {
            // Create a path with the given extension
            let path_with_ext = format!("{}.{}", filename, ext);

            // Get the MIME type
            let mime = mime_type_for_path(&path_with_ext);

            // The MIME type should never be empty
            assert!(!mime.is_empty(), "MIME type should not be empty");

            // Check for expected MIME types based on extension
            match ext {
                "txt" => assert_eq!(mime, "text/plain", "Wrong MIME type for .txt"),
                "md" => assert_eq!(mime, "text/markdown", "Wrong MIME type for .md"),
                "rs" => assert_eq!(mime, "text/rust", "Wrong MIME type for .rs"),
                "js" => assert_eq!(mime, "application/javascript", "Wrong MIME type for .js"),
                "css" => assert_eq!(mime, "text/css", "Wrong MIME type for .css"),
                "html" => assert_eq!(mime, "text/html", "Wrong MIME type for .html"),
                "json" => assert_eq!(mime, "application/json", "Wrong MIME type for .json"),
                "xml" => assert_eq!(mime, "application/xml", "Wrong MIME type for .xml"),
                "png" => assert_eq!(mime, "image/png", "Wrong MIME type for .png"),
                "jpg" => assert_eq!(mime, "image/jpeg", "Wrong MIME type for .jpg"),
                "gif" => assert_eq!(mime, "image/gif", "Wrong MIME type for .gif"),
                "pdf" => assert_eq!(mime, "application/pdf", "Wrong MIME type for .pdf"),
                _ => {}  // Other extensions might have different MIME types
            }

            // For any extension, the MIME type should have a type and subtype separated by a slash
            let parts: Vec<&str> = mime.split('/').collect();
            assert_eq!(parts.len(), 2, "MIME type should have a type and subtype separated by a slash");
        }

        /// Test that get_file_extension correctly extracts file extensions
        #[test]
        fn get_file_extension_properties(
            // Generate random valid filenames with or without extensions
            base in "[a-zA-Z0-9_-]+",
            ext in prop::option::of("[a-zA-Z0-9]+"),
        ) {
            // Create a filename with or without an extension
            let filename = match ext {
                Some(ref extension) => format!("{}.{}", base, extension),
                None => base.clone(),
            };

            // Get the file extension
            let extracted_ext = get_file_extension(&filename);

            // Check that the extension matches what we expect
            match ext {
                Some(extension) => {
                    assert_eq!(extracted_ext, Some(extension.as_str()),
                               "Extracted extension should match the original extension");
                }
                None => {
                    assert_eq!(extracted_ext, None, "Files without extensions should return None");
                }
            }

            // Special cases
            assert_eq!(get_file_extension(""), None, "Empty filename should have no extension");
            assert_eq!(get_file_extension(".hidden"), None, "Hidden files should have no extension");
            assert_eq!(get_file_extension("file."), None, "Files ending with dot should have no extension");
        }

        /// Test that sanitize_branch_name correctly sanitizes branch names
        #[test]
        fn sanitize_branch_name_properties(
            // Generate random branch names with potentially unsafe characters
            branch_name in ".*",
        ) {
            // Sanitize the branch name
            let sanitized = sanitize_branch_name(&branch_name);

            // The sanitized name should not contain dangerous characters
            assert!(!sanitized.contains(".."), "Sanitized name should not contain '..'");
            assert!(!sanitized.contains('~'), "Sanitized name should not contain '~'");
            assert!(!sanitized.contains('^'), "Sanitized name should not contain '^'");
            assert!(!sanitized.contains(':'), "Sanitized name should not contain ':'");
            assert!(!sanitized.contains('?'), "Sanitized name should not contain '?'");
            assert!(!sanitized.contains('*'), "Sanitized name should not contain '*'");
            assert!(!sanitized.contains('['), "Sanitized name should not contain '['");
            assert!(!sanitized.contains('\\'), "Sanitized name should not contain '\\'");

            // If the input was already safe, it should remain unchanged
            let is_already_safe = !branch_name.contains("..") && !branch_name.contains('~') &&
                                  !branch_name.contains('^') && !branch_name.contains(':') &&
                                  !branch_name.contains('?') && !branch_name.contains('*') &&
                                  !branch_name.contains('[') && !branch_name.contains('\\');

            if is_already_safe && !branch_name.is_empty() {
                assert_eq!(sanitized, branch_name, "Safe branch names should remain unchanged");
            }
        }
    }
}
