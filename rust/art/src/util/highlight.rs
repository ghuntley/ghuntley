//! Syntax highlighting utilities

use crate::error::{Error, Result};
use once_cell::sync::Lazy;
use syntect::highlighting::{Theme, ThemeSet};
use syntect::html::{ClassedHTMLGenerator, ClassStyle};
use syntect::parsing::{SyntaxReference, SyntaxSet};
use std::path::Path;

/// Global syntax set instance
static SYNTAX_SET: Lazy<SyntaxSet> = Lazy::new(|| SyntaxSet::load_defaults_newlines());

/// Global theme set instance
static THEME_SET: Lazy<ThemeSet> = Lazy::new(|| ThemeSet::load_defaults());

/// Default theme name
const DEFAULT_THEME: &str = "base16-ocean.dark";

/// Detect syntax for a file based on extension and content
pub fn detect_syntax(path: &Path, content: &str) -> Option<&'static SyntaxReference> {
    let file_name = path.file_name()?.to_str()?;

    // Try to detect by extension first
    if let Some(syntax) = SYNTAX_SET.find_syntax_by_extension(
        path.extension()?.to_str()?
    ) {
        return Some(syntax);
    }

    // Try by filename
    if let Some(syntax) = SYNTAX_SET.find_syntax_by_filename(file_name)? {
        return Some(syntax);
    }

    // Try by first line
    let first_line = content.lines().next()?;
    SYNTAX_SET.find_syntax_by_first_line(first_line)
}

/// Highlight syntax for a file
pub fn highlight_syntax(path: &Path, content: &str) -> Result<String> {
    // Detect syntax for the file
    let syntax = detect_syntax(path, content)
        .unwrap_or_else(|| SYNTAX_SET.find_syntax_plain_text());

    // Get the theme
    let theme = &THEME_SET.themes[DEFAULT_THEME];

    // Generate HTML
    let html = highlight_content(content, syntax, theme)?;

    Ok(html)
}

/// Highlight content with the given syntax and theme
fn highlight_content(content: &str, syntax: &SyntaxReference, theme: &Theme) -> Result<String> {
    let mut html_generator = ClassedHTMLGenerator::new_with_class_style(
        syntax,
        &SYNTAX_SET,
        ClassStyle::SpanInline,
    );

    for line in content.lines() {
        html_generator.parse_html_for_line(line)
            .map_err(|e| Error::Internal(format!("Failed to highlight syntax: {}", e)))?;
    }

    let html = html_generator.finalize();
    Ok(html)
}

/// Get a list of available themes
pub fn available_themes() -> Vec<String> {
    THEME_SET.themes.keys().cloned().collect()
}

/// Get a list of supported file extensions
pub fn supported_extensions() -> Vec<String> {
    SYNTAX_SET.syntaxes()
        .iter()
        .flat_map(|s| s.file_extensions.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn test_highlight_syntax() {
        // Test a simple rust file
        let content = r#"fn main() {
    println!("Hello, world!");
}"#;
        let result = highlight_syntax(Path::new("test.rs"), content);
        assert!(result.is_ok(), "Highlighting failed");

        let html = result.unwrap();
        assert!(html.contains("<span"), "HTML should contain span tags");
        assert!(html.contains("println"), "HTML should contain the code");
    }

    #[test]
    fn test_detect_language() {
        // Test cases
        let cases = [
            ("file.rs", Some("rust")),
            ("file.py", Some("python")),
            ("file.js", Some("javascript")),
            ("file.html", Some("html")),
            ("file.css", Some("css")),
            ("file.md", Some("markdown")),
            ("file.txt", None),
            ("file", None),
        ];

        for (input, expected) in cases {
            let result = detect_language(Path::new(input));
            assert_eq!(result, expected, "Failed for input: {}", input);
        }
    }

    /// Helper function to get language name from syntax reference
    fn get_language_name(syntax: &SyntaxReference) -> String {
        syntax.name.to_lowercase()
    }

    /// Helper function to detect language from a file path
    fn detect_language(path: &Path) -> Option<&'static str> {
        detect_syntax(path, "").map(|syntax| syntax.name.to_lowercase().as_str())
    }

    #[test]
    fn test_detect_syntax_by_extension() {
        // Test file extensions
        let extensions = [
            ("test.rs", "rust"),
            ("test.py", "python"),
            ("test.js", "javascript"),
            ("test.go", "go"),
            ("test.c", "c"),
            ("test.cpp", "c++"),
            ("test.h", "c"),
            ("test.hpp", "c++"),
            ("test.java", "java"),
            ("test.kt", "kotlin"),
            ("test.md", "markdown"),
            ("test.json", "json"),
            ("test.yaml", "yaml"),
            ("test.yml", "yaml"),
            ("test.toml", "toml"),
            ("test.sh", "bash"),
            ("test.bat", "batch file"),
        ];

        for (file, expected_lang) in extensions {
            let syntax = detect_syntax(Path::new(file), "");
            assert!(syntax.is_some(), "Syntax detection failed for {}", file);
            let lang = get_language_name(syntax.unwrap()).to_lowercase();
            assert!(
                lang.contains(&expected_lang.to_lowercase()),
                "Expected language {} for {}, got {}",
                expected_lang, file, lang
            );
        }
    }

    #[test]
    fn test_detect_syntax_by_first_line() {
        // Test shebang detection
        let cases = [
            ("#!/bin/bash", "bash"),
            ("#!/usr/bin/env python", "python"),
            ("#!/usr/bin/env node", "javascript"),
            ("#!/usr/bin/perl", "perl"),
            ("<?php", "php"),
        ];

        for (first_line, expected_lang) in cases {
            let syntax = detect_syntax(Path::new("file"), first_line);
            assert!(syntax.is_some(), "Syntax detection failed for {}", first_line);
            let lang = get_language_name(syntax.unwrap()).to_lowercase();
            assert!(
                lang.contains(&expected_lang.to_lowercase()),
                "Expected language {} for {}, got {}",
                expected_lang, first_line, lang
            );
        }
    }

    #[test]
    fn test_available_themes() {
        let themes = available_themes();
        assert!(!themes.is_empty(), "No themes available");
        assert!(themes.contains(&DEFAULT_THEME.to_string()), "Default theme not found");
    }

    #[test]
    fn test_supported_extensions() {
        let extensions = supported_extensions();
        assert!(!extensions.is_empty(), "No extensions available");

        // Check for common extensions
        let common_extensions = ["rs", "py", "js", "html", "css", "md", "json"];
        for ext in common_extensions {
            assert!(
                extensions.contains(&ext.to_string()),
                "Common extension {} not found",
                ext
            );
        }
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Test that highlight_syntax produces valid HTML output
        #[test]
        fn highlight_syntax_produces_valid_html(
            // Generate random code snippets for various languages
            code in "[ -~\\n\\t]{1,500}",  // Printable ASCII + newlines and tabs
            extension in prop::sample::select(&["rs", "js", "py", "go", "c", "cpp", "h", "hpp", "html", "css", "txt"]),
        ) {
            // Skip empty code or very short snippets
            if code.trim().len() < 2 {
                return Ok(());
            }

            // Highlight the code for the given language
            let highlighted = highlight_syntax(&code, Some(extension));

            // The result should not be empty
            assert!(!highlighted.is_empty(), "Highlighted code should not be empty");

            // The result should be valid HTML
            assert!(highlighted.contains('<'), "Highlighted code should contain HTML tags");
            assert!(highlighted.contains('>'), "Highlighted code should contain HTML tags");

            // The result should be longer than the input (due to added HTML tags)
            assert!(highlighted.len() > code.len(), "Highlighted code should be longer than the input");

            // The original code content should be preserved (ignoring HTML tags and whitespace differences)
            let just_text = extract_text_from_html(&highlighted);
            let normalized_code = normalize_whitespace(&code);
            let normalized_text = normalize_whitespace(&just_text);

            // The normalized content should be similar to the original code
            assert!(content_similarity(&normalized_code, &normalized_text) > 0.7,
                   "Highlighted content should preserve the original text");
        }

        /// Test that detect_language selects appropriate languages based on file extensions
        #[test]
        fn detect_language_from_extension(
            filename in "[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9]+)?",
            ext in prop::sample::select(&["rs", "js", "py", "go", "c", "cpp", "h", "hpp", "html", "css", "sh", "md", "txt"]),
        ) {
            // Create a path with the given extension
            let path_with_ext = format!("{}.{}", filename, ext);

            // Detect the language
            let language = detect_language(&path_with_ext);

            // Check that common extensions map to expected languages
            match ext {
                "rs" => assert_eq!(language, Some("rust"), "Wrong language for .rs file"),
                "js" => assert_eq!(language, Some("javascript"), "Wrong language for .js file"),
                "py" => assert_eq!(language, Some("python"), "Wrong language for .py file"),
                "go" => assert_eq!(language, Some("go"), "Wrong language for .go file"),
                "c" | "h" => assert_eq!(language, Some("c"), "Wrong language for .c/.h file"),
                "cpp" | "hpp" => assert_eq!(language, Some("cpp"), "Wrong language for .cpp/.hpp file"),
                "html" => assert_eq!(language, Some("html"), "Wrong language for .html file"),
                "css" => assert_eq!(language, Some("css"), "Wrong language for .css file"),
                "sh" => assert_eq!(language, Some("bash"), "Wrong language for .sh file"),
                "md" => assert_eq!(language, Some("markdown"), "Wrong language for .md file"),
                "txt" => assert_eq!(language, None, "Should not detect a language for .txt file"),
                _ => {}  // Other extensions might map to different languages
            }

            // Unknown extensions should return None
            let unknown_ext = format!("{}.unknown_extension", filename);
            assert_eq!(detect_language(&unknown_ext), None, "Unknown extension should not be detected as any language");
        }
    }

    // Helper functions for testing

    /// Extract text content from HTML by removing all HTML tags
    fn extract_text_from_html(html: &str) -> String {
        let mut result = String::new();
        let mut in_tag = false;

        for c in html.chars() {
            match c {
                '<' => in_tag = true,
                '>' => in_tag = false,
                _ if !in_tag => result.push(c),
                _ => {}
            }
        }

        result
    }

    /// Normalize whitespace by converting all whitespace sequences to a single space
    fn normalize_whitespace(text: &str) -> String {
        let mut result = String::new();
        let mut prev_was_whitespace = false;

        for c in text.chars() {
            if c.is_whitespace() {
                if !prev_was_whitespace {
                    result.push(' ');
                    prev_was_whitespace = true;
                }
            } else {
                result.push(c);
                prev_was_whitespace = false;
            }
        }

        result.trim().to_string()
    }

    /// Calculate a simple similarity score between two strings (0.0 to 1.0)
    fn content_similarity(s1: &str, s2: &str) -> f64 {
        // For this simple test, we'll just compare character by character
        let s1_chars: Vec<char> = s1.chars().collect();
        let s2_chars: Vec<char> = s2.chars().collect();

        let max_len = s1_chars.len().max(s2_chars.len());
        if max_len == 0 {
            return 1.0;  // Both strings are empty, so they're identical
        }

        let min_len = s1_chars.len().min(s2_chars.len());
        let mut matching = 0;

        for i in 0..min_len {
            if s1_chars[i] == s2_chars[i] {
                matching += 1;
            }
        }

        matching as f64 / max_len as f64
    }
}
