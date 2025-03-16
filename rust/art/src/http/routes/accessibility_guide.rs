use axum::{
    extract::Extension,
    response::Html,
    routing::get,
    Router,
};
use std::sync::Arc;

/// Endpoint to serve the accessibility best practices guide
#[get("/accessibility/guide")]
pub async fn accessibility_guide() -> Html<String> {
    Html(format!(
        r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Accessibility Best Practices - Art Git Browser</title>
            <link rel="stylesheet" href="/static/css/accessibility.css">
        </head>
        <body>
            <a href="#main-content" class="skip-to-content">Skip to main content</a>
            <header>
                <h1>Accessibility Best Practices for Art</h1>
            </header>
            <main id="main-content">
                <section>
                    <h2>Introduction</h2>
                    <p>
                        This guide provides best practices for ensuring your content is accessible to all users,
                        including those with disabilities. By following these guidelines, you can help make
                        the web a more inclusive place.
                    </p>
                </section>

                <section>
                    <h2>General Principles</h2>
                    <ul>
                        <li><strong>Perceivable</strong>: Information must be presentable to users in ways they can perceive.</li>
                        <li><strong>Operable</strong>: User interface components must be operable by all users.</li>
                        <li><strong>Understandable</strong>: Information and operation must be understandable.</li>
                        <li><strong>Robust</strong>: Content must be robust enough to be interpreted by a variety of user agents and assistive technologies.</li>
                    </ul>
                </section>

                <section>
                    <h2>Text Content</h2>
                    <h3>Headings</h3>
                    <p>Use headings (<code>&lt;h1&gt;</code> through <code>&lt;h6&gt;</code>) to provide structure to your content.</p>
                    <ul>
                        <li>Use only one <code>&lt;h1&gt;</code> per page, typically for the main page title.</li>
                        <li>Do not skip heading levels (e.g., don't go from <code>&lt;h2&gt;</code> to <code>&lt;h4&gt;</code>).</li>
                        <li>Use headings to create a logical document outline.</li>
                    </ul>

                    <h3>Text Alternatives</h3>
                    <p>Provide text alternatives for non-text content:</p>
                    <ul>
                        <li>Add <code>alt</code> attributes to images that describe their purpose or content.</li>
                        <li>For decorative images, use <code>alt=""</code> to indicate they should be ignored by screen readers.</li>
                        <li>Provide transcripts for audio content and captions for video content.</li>
                    </ul>

                    <h3>Color and Contrast</h3>
                    <p>Ensure sufficient color contrast for text readability:</p>
                    <ul>
                        <li>Text should have a contrast ratio of at least 4.5:1 against its background.</li>
                        <li>Large text (18pt or 14pt bold) should have a contrast ratio of at least 3:1.</li>
                        <li>Don't rely on color alone to convey information.</li>
                    </ul>
                </section>

                <section>
                    <h2>Interactive Elements</h2>
                    <h3>Keyboard Navigation</h3>
                    <p>Ensure all interactive elements are keyboard accessible:</p>
                    <ul>
                        <li>All functionality should be operable through a keyboard interface.</li>
                        <li>Maintain a logical tab order for interactive elements.</li>
                        <li>Ensure focus indicators are visible.</li>
                        <li>Avoid keyboard traps where focus gets stuck in an element.</li>
                    </ul>

                    <h3>Forms</h3>
                    <p>Make forms accessible to all users:</p>
                    <ul>
                        <li>Associate labels with form controls using the <code>&lt;label&gt;</code> element.</li>
                        <li>Group related form controls with <code>&lt;fieldset&gt;</code> and <code>&lt;legend&gt;</code>.</li>
                        <li>Provide clear error messages and instructions.</li>
                        <li>Use ARIA attributes when necessary to enhance accessibility.</li>
                    </ul>

                    <h3>Navigation</h3>
                    <p>Provide clear and consistent navigation:</p>
                    <ul>
                        <li>Include skip links to bypass repeated content.</li>
                        <li>Use descriptive link text that makes sense out of context.</li>
                        <li>Ensure navigation menus are accessible via keyboard.</li>
                    </ul>
                </section>

                <section>
                    <h2>Code and Repository Content</h2>
                    <h3>Code Snippets</h3>
                    <p>Make code snippets accessible:</p>
                    <ul>
                        <li>Use proper syntax highlighting for better readability.</li>
                        <li>Ensure code blocks have sufficient contrast.</li>
                        <li>Add line numbers for reference.</li>
                        <li>Wrap long lines of code to prevent horizontal scrolling when possible.</li>
                    </ul>

                    <h3>Repository Documentation</h3>
                    <p>Create accessible documentation:</p>
                    <ul>
                        <li>Structure README files with proper headings.</li>
                        <li>Add alt text to diagrams and screenshots.</li>
                        <li>Use descriptive link text in documentation.</li>
                        <li>Ensure tables have proper headers and structure.</li>
                    </ul>
                </section>

                <section>
                    <h2>Using Art's Accessibility Features</h2>
                    <h3>AccessibilityManager</h3>
                    <p>
                        Art includes an <code>AccessibilityManager</code> that provides tools for analyzing and improving
                        content accessibility. You can use this to:
                    </p>
                    <ul>
                        <li>Check color contrast ratios and get suggestions for improvement.</li>
                        <li>Analyze HTML content for accessibility issues.</li>
                        <li>Generate accessible versions of content with added ARIA attributes and keyboard navigation support.</li>
                        <li>Get detailed accessibility reports with WCAG reference information.</li>
                    </ul>

                    <h3>API Endpoints</h3>
                    <p>Art provides the following API endpoints for accessibility features:</p>
                    <ul>
                        <li><code>POST /format/accessible</code> - Format code with accessibility enhancements</li>
                        <li><code>POST /format/accessibility/analyze</code> - Analyze HTML for accessibility issues</li>
                        <li><code>POST /format/accessibility/enhance</code> - Generate an accessible version of HTML</li>
                        <li><code>POST /format/accessibility/contrast</code> - Check and improve color contrast</li>
                        <li><code>POST /format/accessibility/config</code> - Update accessibility features</li>
                        <li><code>GET /format/accessibility/config</code> - Get current accessibility features</li>
                    </ul>
                </section>

                <section>
                    <h2>Resources</h2>
                    <ul>
                        <li><a href="https://www.w3.org/WAI/standards-guidelines/wcag/">Web Content Accessibility Guidelines (WCAG)</a></li>
                        <li><a href="https://www.w3.org/WAI/ARIA/apg/">ARIA Authoring Practices Guide</a></li>
                        <li><a href="https://webaim.org/">WebAIM: Web Accessibility In Mind</a></li>
                        <li><a href="https://developer.mozilla.org/en-US/docs/Web/Accessibility">MDN Web Docs: Accessibility</a></li>
                    </ul>
                </section>
            </main>
            <footer>
                <p>&copy; Art Git Browser</p>
            </footer>
        </body>
        </html>
        "#
    ))
}

/// Update the router function to include the accessibility guide route
pub fn add_to_router(router: &mut Router) {
    router.route("/accessibility/guide", get(accessibility_guide));
}
