//! Property-based tests for responsive UI functionality
//!
//! These tests verify that the responsive UI components render correctly
//! at different viewport sizes and with different content.

use proptest::prelude::*;
use scraper::{Html, Selector};

// Since we're using server-side rendering, we'll simulate rendering HTML
// at different viewport sizes and verify the correct classes and structures are applied

/// Simulates the rendering of HTML with responsive classes
fn simulate_render_at_viewport(html_template: &str, viewport_width: u32) -> String {
    // In a real implementation, this would use the actual template renderer
    // For our tests, we'll just simulate by adding viewport-specific classes

    let viewport_class = if viewport_width <= 576 {
        "mobile-viewport"
    } else if viewport_width <= 768 {
        "tablet-viewport"
    } else if viewport_width <= 992 {
        "desktop-viewport"
    } else {
        "large-desktop-viewport"
    };

    // Add the viewport class to the body
    let with_viewport = html_template.replace("<body", &format!("<body class=\"{}\"", viewport_class));

    // If mobile, add the mobile navigation toggle
    if viewport_width <= 576 {
        with_viewport.replace(
            "</header>",
            r#"</header><button class="mobile-nav-toggle" aria-label="Toggle navigation">☰</button>"#
        )
    } else {
        with_viewport
    }
}

/// Tests that the layout grid changes based on viewport size
fn verify_layout_grid(html: &str, viewport_width: u32) -> bool {
    let document = Html::parse_document(html);
    let layout_selector = Selector::parse(".repo-layout").unwrap();

    if let Some(layout) = document.select(&layout_selector).next() {
        let style = layout.value().attr("style").unwrap_or("");

        // Check for appropriate grid template columns based on viewport
        if viewport_width <= 576 {
            // Mobile should have a single column
            style.contains("grid-template-columns: 1fr")
        } else if viewport_width <= 768 {
            // Tablet should have narrower sidebar
            style.contains("grid-template-columns: 180px 1fr")
        } else if viewport_width <= 992 {
            // Small desktop
            style.contains("grid-template-columns: 220px 1fr")
        } else {
            // Large desktop
            style.contains("grid-template-columns: 250px 1fr")
        }
    } else {
        false
    }
}

/// Tests that the sidebar is displayed correctly based on viewport
fn verify_sidebar_display(html: &str, viewport_width: u32) -> bool {
    let document = Html::parse_document(html);
    let sidebar_selector = Selector::parse(".sidebar").unwrap();

    if let Some(sidebar) = document.select(&sidebar_selector).next() {
        if viewport_width <= 576 {
            // On mobile, sidebar should be initially hidden
            !sidebar.value().has_class("active", scraper::CaseSensitivity::CaseSensitive)
        } else {
            // On larger screens, sidebar should be visible
            true
        }
    } else {
        false
    }
}

/// Tests that the mobile navigation toggle is only present on mobile viewports
fn verify_mobile_nav_toggle(html: &str, viewport_width: u32) -> bool {
    let document = Html::parse_document(html);
    let toggle_selector = Selector::parse(".mobile-nav-toggle").unwrap();

    let has_toggle = document.select(&toggle_selector).next().is_some();

    if viewport_width <= 576 {
        has_toggle // Should have toggle on mobile
    } else {
        !has_toggle // Should not have toggle on larger screens
    }
}

/// Tests that line numbers in code views are hidden on mobile
fn verify_line_numbers(html: &str, viewport_width: u32) -> bool {
    let document = Html::parse_document(html);
    let line_numbers_selector = Selector::parse(".line-numbers").unwrap();

    if let Some(line_numbers) = document.select(&line_numbers_selector).next() {
        let style = line_numbers.value().attr("style").unwrap_or("");

        if viewport_width <= 576 {
            // Should be hidden on mobile
            style.contains("display: none")
        } else {
            // Should be visible on larger screens
            !style.contains("display: none")
        }
    } else {
        false
    }
}

// Generate random HTML for testing
fn generate_test_html(
    repo_name: &str,
    has_sidebar: bool,
    has_code: bool,
    has_table: bool,
) -> String {
    let sidebar = if has_sidebar {
        format!(r#"
        <div class="sidebar">
            <h3>Repository</h3>
            <p>{}</p>
            <ul>
                <li><a href="#">Branches</a></li>
                <li><a href="#">Tags</a></li>
                <li><a href="#">Commits</a></li>
            </ul>
        </div>
        "#, repo_name)
    } else {
        String::new()
    };

    let code = if has_code {
        r#"
        <div class="code-view">
            <table>
                <tr>
                    <td class="line-numbers">1</td>
                    <td class="code">fn main() {</td>
                </tr>
                <tr>
                    <td class="line-numbers">2</td>
                    <td class="code">    println!("Hello, world!");</td>
                </tr>
                <tr>
                    <td class="line-numbers">3</td>
                    <td class="code">}</td>
                </tr>
            </table>
        </div>
        "#
    } else {
        String::new()
    };

    let table = if has_table {
        r#"
        <div class="file-browser">
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Last modified</th>
                        <th>Size</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td data-label="Name">file1.rs</td>
                        <td data-label="Last modified">2023-01-01</td>
                        <td data-label="Size">1.2KB</td>
                    </tr>
                    <tr>
                        <td data-label="Name">file2.rs</td>
                        <td data-label="Last modified">2023-01-02</td>
                        <td data-label="Size">2.3KB</td>
                    </tr>
                </tbody>
            </table>
        </div>
        "#
    } else {
        String::new()
    };

    format!(r#"
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>{} - Art</title>
        <link rel="stylesheet" href="/assets/css/main.css">
    </head>
    <body>
        <div class="repo-layout">
            <header class="header">
                <div class="container">
                    <h1>{}</h1>
                    <form class="search-form">
                        <input type="text" class="search-input" placeholder="Search...">
                        <button type="submit" class="search-button">Search</button>
                    </form>
                </div>
            </header>
            {}
            <main class="content">
                <div class="container">
                    {}
                    {}
                </div>
            </main>
            <footer class="footer">
                <div class="container">
                    <p>Art - Git Repository Browser</p>
                </div>
            </footer>
        </div>
    </body>
    </html>
    "#, repo_name, repo_name, sidebar, code, table)
}

proptest! {
    /// Test that responsive layout adjusts based on viewport width
    #[test]
    fn test_responsive_layout_adjusts_to_viewport(
        repo_name in "[a-zA-Z0-9_-]{3,20}",
        viewport_width in 320u32..1440u32,
        has_sidebar in proptest::bool::ANY,
        has_code in proptest::bool::ANY,
        has_table in proptest::bool::ANY,
    ) {
        let base_html = generate_test_html(&repo_name, has_sidebar, has_code, has_table);
        let responsive_html = simulate_render_at_viewport(&base_html, viewport_width);

        // Verify layout grid matches viewport
        prop_assert!(verify_layout_grid(&responsive_html, viewport_width));

        // Verify sidebar display based on viewport
        if has_sidebar {
            prop_assert!(verify_sidebar_display(&responsive_html, viewport_width));
        }

        // Verify mobile nav toggle
        prop_assert!(verify_mobile_nav_toggle(&responsive_html, viewport_width));

        // Verify line numbers visibility if code is present
        if has_code {
            prop_assert!(verify_line_numbers(&responsive_html, viewport_width));
        }
    }

    /// Test that breadcrumbs truncate on mobile but not on desktop
    #[test]
    fn test_breadcrumb_truncation(
        path_segments in proptest::collection::vec("[a-zA-Z0-9_-]{3,20}", 1..10),
        viewport_width in 320u32..1440u32,
    ) {
        // Create breadcrumb HTML
        let mut breadcrumb_html = String::from("<ul class=\"breadcrumb\">");
        for segment in &path_segments {
            breadcrumb_html.push_str(&format!(
                "<li class=\"breadcrumb-item\"><a href=\"#\">{}</a></li>",
                segment
            ));
        }
        breadcrumb_html.push_str("</ul>");

        let full_html = format!(r#"
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body>
            {}
        </body>
        </html>
        "#, breadcrumb_html);

        let responsive_html = simulate_render_at_viewport(&full_html, viewport_width);
        let document = Html::parse_document(&responsive_html);
        let item_selector = Selector::parse(".breadcrumb-item").unwrap();

        for item in document.select(&item_selector) {
            let style = item.value().attr("style").unwrap_or("");

            if viewport_width <= 576 {
                // On mobile, should have text truncation
                prop_assert!(
                    style.contains("max-width") &&
                    style.contains("text-overflow: ellipsis") &&
                    style.contains("overflow: hidden")
                );
            } else {
                // On desktop, should not truncate
                prop_assert!(!style.contains("max-width: 12ch"));
            }
        }
    }

    /// Test that tables stack on mobile but display normally on desktop
    #[test]
    fn test_table_stacking(
        rows in 1..10usize,
        columns in 2..5usize,
        viewport_width in 320u32..1440u32,
    ) {
        // Generate a table with random data
        let mut table_html = String::from("<table><thead><tr>");

        // Add headers
        for i in 0..columns {
            table_html.push_str(&format!("<th>Column {}</th>", i));
        }
        table_html.push_str("</tr></thead><tbody>");

        // Add rows
        for row in 0..rows {
            table_html.push_str("<tr>");
            for col in 0..columns {
                table_html.push_str(&format!(
                    "<td data-label=\"Column {}\">Data {}-{}</td>",
                    col, row, col
                ));
            }
            table_html.push_str("</tr>");
        }
        table_html.push_str("</tbody></table>");

        let full_html = format!(r#"
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body>
            <div class="file-browser">
                {}
            </div>
        </body>
        </html>
        "#, table_html);

        let responsive_html = simulate_render_at_viewport(&full_html, viewport_width);
        let document = Html::parse_document(&responsive_html);

        // Select table rows
        let row_selector = Selector::parse("tr").unwrap();
        let rows = document.select(&row_selector);

        for row in rows {
            let style = row.value().attr("style").unwrap_or("");

            if viewport_width <= 576 {
                // On mobile, rows should stack (display: block)
                prop_assert!(style.contains("display: block") ||
                          document.root_element().inner_html().contains("td { display: block"));
            } else {
                // On desktop, rows should display normally
                prop_assert!(!style.contains("display: block") ||
                          !document.root_element().inner_html().contains("td { display: block"));
            }
        }
    }

    /// Test that search box is responsive
    #[test]
    fn test_search_box_responsiveness(
        viewport_width in 320u32..1440u32,
    ) {
        let search_html = r#"
        <form class="search-form">
            <input type="text" class="search-input" placeholder="Search...">
            <button type="submit" class="search-button">Search</button>
        </form>
        "#;

        let full_html = format!(r#"
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body>
            {}
        </body>
        </html>
        "#, search_html);

        let responsive_html = simulate_render_at_viewport(&full_html, viewport_width);
        let document = Html::parse_document(&responsive_html);

        let form_selector = Selector::parse(".search-form").unwrap();
        if let Some(form) = document.select(&form_selector).next() {
            let style = form.value().attr("style").unwrap_or("");

            // Search form should always be flex, with wrap allowed on smaller screens
            prop_assert!(style.contains("display: flex") ||
                      document.root_element().inner_html().contains("display: flex"));
            prop_assert!(style.contains("flex-wrap: wrap") ||
                      document.root_element().inner_html().contains("flex-wrap: wrap"));
        }
    }
}
