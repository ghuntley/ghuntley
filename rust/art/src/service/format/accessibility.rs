use crate::error::{Error, Result};
use prometheus::{IntCounter, IntGauge, Registry};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// Enhanced accessibility features for the Format Service
/// Provides tools for ensuring content is accessible to all users
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityFeatures {
    /// Minimum contrast ratio for text to background (WCAG 2.1 AA requires 4.5:1 for normal text)
    pub min_contrast_ratio: f64,

    /// Whether to add ARIA attributes to formatted output
    pub add_aria_attributes: bool,

    /// Whether to add tab index attributes for keyboard navigation
    pub add_tabindex: bool,

    /// Whether to add alt text for visual elements
    pub add_alt_text: bool,

    /// Whether to add role attributes for semantic markup
    pub add_role_attributes: bool,

    /// Whether to check heading hierarchy (h1, h2, etc.)
    pub check_heading_hierarchy: bool,

    /// Whether to add keyboard shortcuts
    pub add_keyboard_shortcuts: bool,

    /// Whether to optimize for screen readers
    pub optimize_for_screen_readers: bool,

    /// Custom translations for accessibility features
    pub translations: HashMap<String, String>,
}

impl Default for AccessibilityFeatures {
    fn default() -> Self {
        Self {
            min_contrast_ratio: 4.5, // WCAG 2.1 AA requirement
            add_aria_attributes: true,
            add_tabindex: true,
            add_alt_text: true,
            add_role_attributes: true,
            check_heading_hierarchy: true,
            add_keyboard_shortcuts: false, // Disabled by default as it may conflict with user preferences
            optimize_for_screen_readers: true,
            translations: HashMap::new(),
        }
    }
}

/// Accessibility violation levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ViolationLevel {
    /// Critical violations that must be fixed (e.g., zero contrast)
    Critical,

    /// Serious violations that should be fixed (e.g., very low contrast)
    Serious,

    /// Moderate violations that improve accessibility significantly if fixed
    Moderate,

    /// Minor violations that would be nice to fix
    Minor,
}

impl std::fmt::Display for ViolationLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ViolationLevel::Critical => write!(f, "Critical"),
            ViolationLevel::Serious => write!(f, "Serious"),
            ViolationLevel::Moderate => write!(f, "Moderate"),
            ViolationLevel::Minor => write!(f, "Minor"),
        }
    }
}

/// Describes an accessibility issue found during analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityViolation {
    /// Type of violation
    pub violation_type: String,

    /// Description of the violation
    pub description: String,

    /// Severity level
    pub level: ViolationLevel,

    /// Element selector or identifier where violation was found
    pub element: Option<String>,

    /// Suggested fix
    pub suggestion: Option<String>,

    /// WCAG 2.1 success criterion reference
    pub wcag_reference: Option<String>,
}

/// Report summarizing accessibility analysis results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityReport {
    /// Overall accessibility score (0-100)
    pub score: u8,

    /// List of violations found
    pub violations: Vec<AccessibilityViolation>,

    /// Number of critical violations
    pub critical_count: usize,

    /// Number of serious violations
    pub serious_count: usize,

    /// Number of moderate violations
    pub moderate_count: usize,

    /// Number of minor violations
    pub minor_count: usize,

    /// Whether the content passes minimum accessibility requirements
    pub passes_minimum_requirements: bool,

    /// Statistics about the content checked
    pub stats: HashMap<String, usize>,

    /// Timestamp of the analysis
    pub timestamp: String,
}

/// Manages accessibility features and analysis
pub struct AccessibilityManager {
    /// Configuration for accessibility features
    features: AccessibilityFeatures,

    /// Metrics for tracking accessibility issues
    metrics: AccessibilityMetrics,
}

/// Metrics related to accessibility
pub struct AccessibilityMetrics {
    /// Number of critical violations found
    pub critical_violations: IntCounter,

    /// Number of serious violations found
    pub serious_violations: IntCounter,

    /// Number of moderate violations found
    pub moderate_violations: IntCounter,

    /// Number of minor violations found
    pub minor_violations: IntCounter,

    /// Current accessibility score
    pub accessibility_score: IntGauge,

    /// Number of files checked
    pub files_checked: IntCounter,

    /// Number of elements checked
    pub elements_checked: IntCounter,
}

impl AccessibilityManager {
    /// Create a new accessibility manager
    pub fn new(features: AccessibilityFeatures, registry: &Registry) -> Result<Self> {
        // Create metrics
        let critical_violations = IntCounter::new(
            "accessibility_critical_violations_total",
            "Total number of critical accessibility violations",
        )?;

        let serious_violations = IntCounter::new(
            "accessibility_serious_violations_total",
            "Total number of serious accessibility violations",
        )?;

        let moderate_violations = IntCounter::new(
            "accessibility_moderate_violations_total",
            "Total number of moderate accessibility violations",
        )?;

        let minor_violations = IntCounter::new(
            "accessibility_minor_violations_total",
            "Total number of minor accessibility violations",
        )?;

        let accessibility_score = IntGauge::new(
            "accessibility_score",
            "Current accessibility score (0-100)",
        )?;

        let files_checked = IntCounter::new(
            "accessibility_files_checked_total",
            "Total number of files checked for accessibility",
        )?;

        let elements_checked = IntCounter::new(
            "accessibility_elements_checked_total",
            "Total number of elements checked for accessibility",
        )?;

        // Register metrics
        registry.register(Box::new(critical_violations.clone()))?;
        registry.register(Box::new(serious_violations.clone()))?;
        registry.register(Box::new(moderate_violations.clone()))?;
        registry.register(Box::new(minor_violations.clone()))?;
        registry.register(Box::new(accessibility_score.clone()))?;
        registry.register(Box::new(files_checked.clone()))?;
        registry.register(Box::new(elements_checked.clone()))?;

        let metrics = AccessibilityMetrics {
            critical_violations,
            serious_violations,
            moderate_violations,
            minor_violations,
            accessibility_score,
            files_checked,
            elements_checked,
        };

        Ok(Self { features, metrics })
    }

    /// Get the current accessibility features configuration
    pub fn get_features(&self) -> &AccessibilityFeatures {
        &self.features
    }

    /// Update accessibility features configuration
    pub fn update_features(&mut self, features: AccessibilityFeatures) {
        self.features = features;
    }

    /// Calculate the luminance value for a color (used for contrast calculations)
    pub fn calculate_luminance(&self, r: u8, g: u8, b: u8) -> f64 {
        // Convert RGB to sRGB
        let r_srgb = Self::to_srgb(r as f64 / 255.0);
        let g_srgb = Self::to_srgb(g as f64 / 255.0);
        let b_srgb = Self::to_srgb(b as f64 / 255.0);

        // Calculate luminance
        0.2126 * r_srgb + 0.7152 * g_srgb + 0.0722 * b_srgb
    }

    /// Convert a color component to sRGB
    fn to_srgb(component: f64) -> f64 {
        if component <= 0.03928 {
            component / 12.92
        } else {
            ((component + 0.055) / 1.055).powf(2.4)
        }
    }

    /// Parse a hex color into RGB components
    pub fn parse_hex_color(&self, hex: &str) -> Result<(u8, u8, u8)> {
        let hex = hex.trim_start_matches('#');

        if hex.len() != 6 {
            return Err(Error::InvalidInput(format!("Invalid hex color: {}", hex)));
        }

        let r = u8::from_str_radix(&hex[0..2], 16)
            .map_err(|_| Error::InvalidInput(format!("Invalid hex color: {}", hex)))?;

        let g = u8::from_str_radix(&hex[2..4], 16)
            .map_err(|_| Error::InvalidInput(format!("Invalid hex color: {}", hex)))?;

        let b = u8::from_str_radix(&hex[4..6], 16)
            .map_err(|_| Error::InvalidInput(format!("Invalid hex color: {}", hex)))?;

        Ok((r, g, b))
    }

    /// Calculate the contrast ratio between two colors
    pub fn calculate_contrast_ratio(&self, color1: &str, color2: &str) -> Result<f64> {
        let (r1, g1, b1) = self.parse_hex_color(color1)?;
        let (r2, g2, b2) = self.parse_hex_color(color2)?;

        let l1 = self.calculate_luminance(r1, g1, b1);
        let l2 = self.calculate_luminance(r2, g2, b2);

        // Ensure the lighter color is first
        let (lighter, darker) = if l1 > l2 { (l1, l2) } else { (l2, l1) };

        // Calculate contrast ratio
        let contrast_ratio = (lighter + 0.05) / (darker + 0.05);

        Ok(contrast_ratio)
    }

    /// Check if a color combination has sufficient contrast
    pub fn has_sufficient_contrast(&self, foreground: &str, background: &str) -> Result<bool> {
        let ratio = self.calculate_contrast_ratio(foreground, background)?;
        Ok(ratio >= self.features.min_contrast_ratio)
    }

    /// Suggest an alternative color with better contrast
    pub fn suggest_better_color(&self, color: &str, background: &str) -> Result<String> {
        let (r, g, b) = self.parse_hex_color(color)?;
        let (bg_r, bg_g, bg_b) = self.parse_hex_color(background)?;

        // Calculate initial contrast
        let initial_contrast = self.calculate_contrast_ratio(color, background)?;

        if initial_contrast >= self.features.min_contrast_ratio {
            // Already has sufficient contrast
            return Ok(color.to_string());
        }

        // Calculate luminance of background
        let bg_luminance = self.calculate_luminance(bg_r, bg_g, bg_b);

        // Determine if we should make the color lighter or darker for better contrast
        let (new_r, new_g, new_b) = if bg_luminance > 0.5 {
            // Dark background, make color darker
            (
                r.saturating_sub(30).max(0),
                g.saturating_sub(30).max(0),
                b.saturating_sub(30).max(0),
            )
        } else {
            // Light background, make color lighter
            (
                r.saturating_add(30).min(255),
                g.saturating_add(30).min(255),
                b.saturating_add(30).min(255),
            )
        };

        // Convert back to hex
        let new_color = format!("#{:02x}{:02x}{:02x}", new_r, new_g, new_b);

        // Check if the new color has sufficient contrast
        let new_contrast = self.calculate_contrast_ratio(&new_color, background)?;

        if new_contrast >= self.features.min_contrast_ratio {
            Ok(new_color)
        } else {
            // If still not enough contrast, go for maximum contrast
            if bg_luminance > 0.5 {
                Ok("#000000".to_string()) // Black for light backgrounds
            } else {
                Ok("#ffffff".to_string()) // White for dark backgrounds
            }
        }
    }

    /// Add ARIA attributes to HTML to improve screen reader compatibility
    pub fn add_aria_attributes(&self, html: &str) -> String {
        if !self.features.add_aria_attributes {
            return html.to_string();
        }

        // Simple implementation - in a real app this would use an HTML parser
        let mut result = html.to_string();

        // Add role="navigation" to nav elements
        result = result.replace("<nav", "<nav role=\"navigation\"");

        // Add role="main" to main content
        result = result.replace("<main", "<main role=\"main\"");

        // Add role="contentinfo" to footer
        result = result.replace("<footer", "<footer role=\"contentinfo\"");

        // Add aria-label to links without text
        result = result.replace("<a href=", "<a aria-label=\"Link\" href=");

        // Add aria-hidden to decorative elements
        result = result.replace("<span class=\"icon\">", "<span class=\"icon\" aria-hidden=\"true\">");

        result
    }

    /// Add tabindex attributes to elements to improve keyboard navigation
    pub fn add_tabindex(&self, html: &str) -> String {
        if !self.features.add_tabindex {
            return html.to_string();
        }

        // Simple implementation - in a real app this would use an HTML parser
        let mut result = html.to_string();

        // Add tabindex to code lines
        result = result.replace("<span class=\"line\">", "<span class=\"line\" tabindex=\"0\">");

        // Add tabindex to navigation links
        result = result.replace("<a href=", "<a tabindex=\"0\" href=");

        result
    }

    /// Add alt text to images and icons
    pub fn add_alt_text(&self, html: &str) -> String {
        if !self.features.add_alt_text {
            return html.to_string();
        }

        // Simple implementation - in a real app this would use an HTML parser
        let mut result = html.to_string();

        // Add alt text to images without it
        result = result.replace("<img src=", "<img alt=\"Code visualization\" src=");

        // Add aria-label to icon elements
        result = result.replace("<i class=\"icon-", "<i aria-label=\"Icon\" class=\"icon-");

        result
    }

    /// Enhance code snippets with accessibility features
    pub fn enhance_code_snippet(&self, html: &str) -> String {
        let mut result = html.to_string();

        if self.features.add_aria_attributes {
            result = self.add_aria_attributes(&result);
        }

        if self.features.add_tabindex {
            result = self.add_tabindex(&result);
        }

        if self.features.add_alt_text {
            result = self.add_alt_text(&result);
        }

        if self.features.optimize_for_screen_readers {
            // Add additional attributes for screen readers
            result = result.replace(
                "<pre>",
                "<pre aria-label=\"Code snippet\" role=\"code\" tabindex=\"0\">",
            );

            // Add line numbers as aria-label
            result = result.replace(
                "<span class=\"line-number\">",
                "<span class=\"line-number\" aria-hidden=\"true\">",
            );
        }

        result
    }

    /// Analyze HTML content for accessibility issues
    pub fn analyze_content(&self, html: &str) -> Result<AccessibilityReport> {
        // This is a simplified implementation
        // A real implementation would parse and analyze the HTML thoroughly

        let mut violations = Vec::new();
        let mut stats = HashMap::new();

        stats.insert("content_length".to_string(), html.len());
        stats.insert("elements_checked".to_string(), 0);

        // Check for missing alt attributes on images
        let img_count = html.matches("<img").count();
        let alt_count = html.matches("alt=").count();
        stats.insert("images".to_string(), img_count);

        if img_count > alt_count {
            violations.push(AccessibilityViolation {
                violation_type: "missing_alt".to_string(),
                description: "Images missing alt text".to_string(),
                level: ViolationLevel::Serious,
                element: None,
                suggestion: Some("Add alt attributes to all <img> elements".to_string()),
                wcag_reference: Some("1.1.1 Non-text Content".to_string()),
            });
        }

        // Check for low contrast text (simplified check)
        if html.contains("color:") && !html.contains("contrast-ratio") {
            violations.push(AccessibilityViolation {
                violation_type: "potential_low_contrast".to_string(),
                description: "Potential low contrast text detected".to_string(),
                level: ViolationLevel::Moderate,
                element: None,
                suggestion: Some("Ensure all text has a contrast ratio of at least 4.5:1".to_string()),
                wcag_reference: Some("1.4.3 Contrast (Minimum)".to_string()),
            });
        }

        // Check for missing form labels
        let input_count = html.matches("<input").count();
        let label_count = html.matches("<label").count();
        stats.insert("form_fields".to_string(), input_count);

        if input_count > label_count {
            violations.push(AccessibilityViolation {
                violation_type: "missing_labels".to_string(),
                description: "Form fields missing labels".to_string(),
                level: ViolationLevel::Serious,
                element: None,
                suggestion: Some("Add <label> elements or aria-label attributes to all form fields".to_string()),
                wcag_reference: Some("3.3.2 Labels or Instructions".to_string()),
            });
        }

        // Count violations by level
        let critical_count = violations.iter().filter(|v| v.level == ViolationLevel::Critical).count();
        let serious_count = violations.iter().filter(|v| v.level == ViolationLevel::Serious).count();
        let moderate_count = violations.iter().filter(|v| v.level == ViolationLevel::Moderate).count();
        let minor_count = violations.iter().filter(|v| v.level == ViolationLevel::Minor).count();

        // Update metrics
        self.metrics.critical_violations.inc_by(critical_count as u64);
        self.metrics.serious_violations.inc_by(serious_count as u64);
        self.metrics.moderate_violations.inc_by(moderate_count as u64);
        self.metrics.minor_violations.inc_by(minor_count as u64);
        self.metrics.files_checked.inc();
        self.metrics.elements_checked.inc_by(stats.get("elements_checked").cloned().unwrap_or(0) as u64);

        // Calculate score (simplified algorithm)
        let total_violation_points =
            (critical_count * 10) +
            (serious_count * 5) +
            (moderate_count * 2) +
            minor_count;

        let max_points = 100;
        let score = if total_violation_points >= max_points {
            0
        } else {
            max_points - total_violation_points
        };

        // Set metrics
        self.metrics.accessibility_score.set(score as i64);

        // Check if passes minimum requirements
        let passes_minimum_requirements = critical_count == 0 && serious_count <= 1;

        Ok(AccessibilityReport {
            score: score as u8,
            violations,
            critical_count,
            serious_count,
            moderate_count,
            minor_count,
            passes_minimum_requirements,
            stats,
            timestamp: chrono::Utc::now().to_rfc3339(),
        })
    }

    /// Generate an accessible version of content with improvements
    pub fn generate_accessible_version(&self, html: &str) -> Result<String> {
        let mut result = html.to_string();

        // Apply all accessibility enhancements
        result = self.add_aria_attributes(&result);
        result = self.add_tabindex(&result);
        result = self.add_alt_text(&result);

        // Add keyboard shortcut guidance if enabled
        if self.features.add_keyboard_shortcuts {
            let shortcuts_help = r#"
                <div class="keyboard-shortcuts" aria-label="Keyboard shortcuts" tabindex="0">
                    <button aria-expanded="false" class="shortcuts-toggle" tabindex="0">Keyboard Shortcuts</button>
                    <div class="shortcuts-panel" hidden>
                        <ul>
                            <li><kbd>n</kbd> Next line</li>
                            <li><kbd>p</kbd> Previous line</li>
                            <li><kbd>f</kbd> Find in code</li>
                            <li><kbd>h</kbd> Toggle help</li>
                        </ul>
                    </div>
                </div>
            "#;

            result = format!("{}{}", shortcuts_help, result);
        }

        // Add skip navigation link for keyboard users
        result = format!(
            r#"<a href="#main-content" class="skip-to-content" tabindex="0">Skip to main content</a>{}"#,
            result
        );

        // Add ARIA landmarks
        result = result.replace("<main", "<main id=\"main-content\" aria-label=\"Main content\"");

        Ok(result)
    }

    /// Get metrics for accessibility
    pub fn get_metrics(&self) -> &AccessibilityMetrics {
        &self.metrics
    }
}

/// Tests for the accessibility implementation
#[cfg(test)]
mod tests {
    use super::*;
    use prometheus::Registry;

    /// Create a test accessibility manager
    fn create_test_manager() -> AccessibilityManager {
        let features = AccessibilityFeatures::default();
        let registry = Registry::new();
        AccessibilityManager::new(features, &registry).expect("Failed to create test manager")
    }

    #[test]
    fn test_contrast_ratio_calculation() {
        let manager = create_test_manager();

        // Black on white should have maximum contrast
        let ratio = manager.calculate_contrast_ratio("#000000", "#ffffff").unwrap();
        assert!(ratio > 20.0); // Should be 21.0

        // White on black should have maximum contrast
        let ratio = manager.calculate_contrast_ratio("#ffffff", "#000000").unwrap();
        assert!(ratio > 20.0); // Should be 21.0

        // Similar colors should have low contrast
        let ratio = manager.calculate_contrast_ratio("#888888", "#999999").unwrap();
        assert!(ratio < 2.0);
    }

    #[test]
    fn test_has_sufficient_contrast() {
        let manager = create_test_manager();

        // Black on white has sufficient contrast
        assert!(manager.has_sufficient_contrast("#000000", "#ffffff").unwrap());

        // Similar colors don't have sufficient contrast
        assert!(!manager.has_sufficient_contrast("#888888", "#999999").unwrap());
    }

    #[test]
    fn test_suggest_better_color() {
        let manager = create_test_manager();

        // Already good contrast should return the same color
        let suggested = manager.suggest_better_color("#000000", "#ffffff").unwrap();
        assert_eq!(suggested, "#000000");

        // Low contrast should suggest a better color
        let suggested = manager.suggest_better_color("#888888", "#999999").unwrap();
        let new_contrast = manager.calculate_contrast_ratio(&suggested, "#999999").unwrap();
        assert!(new_contrast >= manager.features.min_contrast_ratio);
    }

    #[test]
    fn test_add_aria_attributes() {
        let manager = create_test_manager();

        let html = "<nav><a href=\"#\">Link</a></nav>";
        let enhanced = manager.add_aria_attributes(html);

        assert!(enhanced.contains("role=\"navigation\""));
        assert!(enhanced.contains("aria-label=\"Link\""));
    }

    #[test]
    fn test_content_analysis() {
        let manager = create_test_manager();

        // HTML with accessibility issues
        let html = r#"
            <div>
                <img src="image.png">
                <input type="text">
                <span style="color:#888">Low contrast text</span>
            </div>
        "#;

        let report = manager.analyze_content(html).unwrap();

        // Should detect missing alt text
        assert!(report.violations.iter().any(|v| v.violation_type == "missing_alt"));

        // Should detect missing form labels
        assert!(report.violations.iter().any(|v| v.violation_type == "missing_labels"));

        // Should have a score less than 100
        assert!(report.score < 100);
    }

    #[test]
    fn test_accessible_version_generation() {
        let manager = create_test_manager();

        let html = r#"
            <div>
                <img src="image.png">
                <a href="#">Link</a>
                <main>Content</main>
            </div>
        "#;

        let accessible = manager.generate_accessible_version(html).unwrap();

        // Should add alt text to images
        assert!(accessible.contains("alt=\"Code visualization\""));

        // Should add tabindex to links
        assert!(accessible.contains("tabindex=\"0\" href="));

        // Should add skip to content link
        assert!(accessible.contains("skip-to-content"));

        // Should add ARIA landmarks
        assert!(accessible.contains("id=\"main-content\""));
    }

    // Property-based tests using proptest
    use proptest::prelude::*;

    fn hex_color_strategy() -> impl Strategy<Value = String> {
        prop::collection::vec(prop::char::range('0', 'f'), 6)
            .prop_map(|chars| {
                let hex: String = chars.into_iter().collect();
                format!("#{}", hex)
            })
    }

    proptest! {
        #[test]
        fn prop_test_color_parsing(color in hex_color_strategy()) -> Result<()> {
            let manager = create_test_manager();
            let result = manager.parse_hex_color(&color);
            assert!(result.is_ok());

            let (r, g, b) = result.unwrap();
            assert!(r <= 255);
            assert!(g <= 255);
            assert!(b <= 255);

            Ok(())
        }

        #[test]
        fn prop_test_contrast_calculation(
            color1 in hex_color_strategy(),
            color2 in hex_color_strategy()
        ) -> Result<()> {
            let manager = create_test_manager();
            let result = manager.calculate_contrast_ratio(&color1, &color2);

            // If parsing succeeds, contrast ratio should be valid
            if let Ok(ratio) = result {
                // Contrast ratio should be between 1 and 21
                assert!(ratio >= 1.0);
                assert!(ratio <= 21.0);

                // Contrast ratio should be the same regardless of order
                let reverse_ratio = manager.calculate_contrast_ratio(&color2, &color1).unwrap();
                assert!((ratio - reverse_ratio).abs() < 0.001);
            }

            Ok(())
        }

        #[test]
        fn prop_test_color_suggestion_improves_contrast(
            background in hex_color_strategy(),
            foreground in hex_color_strategy()
        ) -> Result<()> {
            let manager = create_test_manager();

            // Skip if parsing fails
            if let (Ok(_), Ok(_)) = (
                manager.parse_hex_color(&background),
                manager.parse_hex_color(&foreground)
            ) {
                // Get initial contrast
                let initial_contrast = manager.calculate_contrast_ratio(&foreground, &background).unwrap_or(0.0);

                // Get suggested color
                let suggested = manager.suggest_better_color(&foreground, &background).unwrap_or_else(|_| foreground.clone());

                // Skip if suggestion fails
                if suggested != foreground {
                    // Get new contrast
                    let new_contrast = manager.calculate_contrast_ratio(&suggested, &background).unwrap_or(0.0);

                    // New contrast should be better or equal
                    assert!(new_contrast >= initial_contrast);
                }
            }

            Ok(())
        }

        #[test]
        fn prop_test_html_enhancement_preserves_content(
            html in "[a-zA-Z0-9<>/=\"'.\\s]{1,1000}"
        ) -> Result<()> {
            let manager = create_test_manager();

            // Skip completely invalid HTML
            if html.contains("<") && html.contains(">") {
                let enhanced = manager.add_aria_attributes(&html);

                // Original content should be preserved in the enhanced version
                for token in html.split_whitespace() {
                    if token.len() > 3 && !token.starts_with("<") {
                        assert!(enhanced.contains(token));
                    }
                }
            }

            Ok(())
        }
    }

    proptest! {
        // Test that accessibility analysis never panics
        #[test]
        fn prop_test_accessibility_analysis_doesnt_panic(
            html in "[a-zA-Z0-9<>/=\"'.\\s]{1,1000}"
        ) {
            let manager = create_test_manager();
            let _ = manager.analyze_content(&html);
            // Just making sure it doesn't panic
        }

        // Test that adding accessibility features always produces valid output
        #[test]
        fn prop_test_accessibility_features_produce_valid_output(
            add_aria in proptest::bool::ANY,
            add_tabindex in proptest::bool::ANY,
            add_alt_text in proptest::bool::ANY,
            html in "[a-zA-Z0-9<>/=\"'.\\s]{1,500}"
        ) {
            let registry = Registry::new();
            let features = AccessibilityFeatures {
                add_aria_attributes: add_aria,
                add_tabindex: add_tabindex,
                add_alt_text: add_alt_text,
                ..AccessibilityFeatures::default()
            };

            if let Ok(manager) = AccessibilityManager::new(features, &registry) {
                let _ = manager.enhance_code_snippet(&html);
                // Just ensuring it doesn't panic
            }
        }
    }

    // Property-based tests using proptest
    proptest! {
        #[test]
        fn proptest_accessible_version_generation(
            html in "[\\w\\s<>/=\"']+".prop_map(|s| format!("<div>{}</div>", s)),
            add_aria in proptest::bool::ANY,
            add_tabindex in proptest::bool::ANY,
            add_alt_text in proptest::bool::ANY,
        ) {
            let features = AccessibilityFeatures {
                add_aria_attributes: add_aria,
                add_tabindex: add_tabindex,
                add_alt_text: add_alt_text,
                ..AccessibilityFeatures::default()
            };

            let registry = Registry::new();
            let manager = AccessibilityManager::new(features, &registry).expect("Failed to create manager");

            // Generate accessible version
            let result = manager.generate_accessible_version(&html);

            // Test should not panic
            prop_assert!(result.is_ok(), "Failed to generate accessible version: {:?}", result.err());

            let accessible_html = result.unwrap();

            // The output should still be HTML
            prop_assert!(accessible_html.contains("<div"), "Output is not HTML: {}", accessible_html);

            // If ARIA attributes are enabled, check that they're added
            if add_aria {
                // Check for aria attributes only if there are elements that would need them
                if html.contains("<button") || html.contains("<a") || html.contains("<input") {
                    prop_assert!(
                        accessible_html.contains("aria-") || accessible_html.contains("role="),
                        "No ARIA attributes found in output: {}", accessible_html
                    );
                }
            }

            // If tabindex is enabled, check that it's added
            if add_tabindex {
                // Check for tabindex only if there are interactive elements
                if html.contains("<button") || html.contains("<a") || html.contains("<input") {
                    prop_assert!(
                        accessible_html.contains("tabindex="),
                        "No tabindex found in output: {}", accessible_html
                    );
                }
            }

            // If alt text is enabled, check that it's added
            if add_alt_text {
                // Check for alt text only if there are images
                if html.contains("<img") {
                    prop_assert!(
                        accessible_html.contains("alt="),
                        "No alt text found in output: {}", accessible_html
                    );
                }
            }
        }
    }

    proptest! {
        #[test]
        fn proptest_accessibility_analysis_consistent_results(
            html in "[\\w\\s<>/=\"']+".prop_map(|s| format!("<div>{}</div>", s)),
        ) {
            let features = AccessibilityFeatures::default();
            let registry = Registry::new();
            let manager = AccessibilityManager::new(features, &registry).expect("Failed to create manager");

            // Generate accessibility report
            let result = manager.analyze_content(&html);

            // Test should not panic
            prop_assert!(result.is_ok(), "Failed to analyze content: {:?}", result.err());

            let report = result.unwrap();

            // Validation of counts
            prop_assert_eq!(
                report.critical_count + report.serious_count + report.moderate_count + report.minor_count,
                report.violations.len(),
                "Violation counts don't match total violations"
            );

            // Validation of score (should be between 0-100)
            prop_assert!(report.score <= 100, "Score > 100: {}", report.score);

            // Second analysis with same input should yield same results
            let second_result = manager.analyze_content(&html);
            prop_assert!(second_result.is_ok(), "Failed on second analysis: {:?}", second_result.err());

            let second_report = second_result.unwrap();
            prop_assert_eq!(report.score, second_report.score, "Scores don't match between runs");
            prop_assert_eq!(report.violations.len(), second_report.violations.len(), "Violation counts don't match between runs");
        }
    }
}
