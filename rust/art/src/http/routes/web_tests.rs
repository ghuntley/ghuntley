#[cfg(test)]
mod accessibility_guide_tests {
    use super::*;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;

    #[tokio::test]
    async fn test_accessibility_guide_route() {
        // Create a router with our route
        let app = Router::new().route("/accessibility/guide", get(accessibility_guide));

        // Create a request
        let request = Request::builder()
            .uri("/accessibility/guide")
            .method("GET")
            .body(Body::empty())
            .unwrap();

        // Process the request
        let response = app.oneshot(request).await.unwrap();

        // Check status code
        assert_eq!(response.status(), StatusCode::OK);

        // Check response body
        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap();

        // Verify content
        assert!(body_str.contains("Accessibility Best Practices"));
        assert!(body_str.contains("Skip to main content"));
        assert!(body_str.contains("WCAG"));
        assert!(body_str.contains("Using Art's Accessibility Features"));
        assert!(body_str.contains("General Principles"));
        assert!(body_str.contains("Perceivable"));
        assert!(body_str.contains("Operable"));
        assert!(body_str.contains("Understandable"));
        assert!(body_str.contains("Robust"));
    }

    // Property-based test for the accessibility guide
    #[cfg(feature = "proptest")]
    mod prop_tests {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            #[test]
            fn accessibility_guide_contains_required_a11y_elements(
                // Generate random request data that shouldn't affect the guide content
                user_agent in "[a-zA-Z0-9\\-_.]+",
                accept_language in "[a-z\\-,;=]+",
            ) {
                tokio_test::block_on(async {
                    // Create a router with our route
                    let app = Router::new().route("/accessibility/guide", get(accessibility_guide));

                    // Create a request with the generated headers
                    let request = Request::builder()
                        .uri("/accessibility/guide")
                        .method("GET")
                        .header("User-Agent", user_agent)
                        .header("Accept-Language", accept_language)
                        .body(Body::empty())
                        .unwrap();

                    // Process the request
                    let response = app.oneshot(request).await.unwrap();

                    // Check status code
                    assert_eq!(response.status(), StatusCode::OK);

                    // Check response body
                    let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
                    let body_str = String::from_utf8(body.to_vec()).unwrap();

                    // Verify essential accessibility elements are always present
                    let required_a11y_elements = [
                        "lang=\"en\"",                      // Language attribute
                        "meta name=\"viewport\"",           // Responsive viewport
                        "skip-to-content",                  // Skip link
                        "main id=\"main-content\"",         // Main content area
                        "aria-current=\"page\"",            // Current page indicator
                        "h1",                               // Top-level heading
                        "h2",                               // Section headings
                        "ul",                               // Lists for content structure
                        "Accessibility Best Practices",     // Title text
                    ];

                    for element in required_a11y_elements {
                        assert!(
                            body_str.contains(element),
                            "Guide is missing required accessibility element: {}",
                            element
                        );
                    }

                    // Check for proper HTML structure
                    assert!(body_str.contains("<!DOCTYPE html>"));
                    assert!(body_str.contains("<html"));
                    assert!(body_str.contains("<head>"));
                    assert!(body_str.contains("<body>"));
                    assert!(body_str.contains("</html>"));
                });
            }
        }
    }
}
