use crate::service::format::accessibility::AccessibilityFeatures;

/// Endpoint to format code with accessibility enhancements
#[post("/format/accessible")]
pub async fn format_accessible_code(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
    Json(params): Json<FormatRequestParams>,
) -> Result<Json<FormattedCode>> {
    let mut service = format_service.write().await;

    let formatted = service.format_accessible_code(
        &params.content,
        &params.path,
        &params.options.unwrap_or_default(),
    )?;

    Ok(Json(formatted))
}

/// Request to analyze content for accessibility issues
#[derive(Debug, Deserialize)]
pub struct AccessibilityAnalysisRequest {
    /// HTML content to analyze
    pub html: String,
}

/// Endpoint to analyze HTML for accessibility issues
#[post("/format/accessibility/analyze")]
pub async fn analyze_accessibility(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
    Json(params): Json<AccessibilityAnalysisRequest>,
) -> Result<Json<crate::service::format::accessibility::AccessibilityReport>> {
    let service = format_service.read().await;

    let report = service.analyze_accessibility(&params.html)?;

    Ok(Json(report))
}

/// Request to generate an accessible version of HTML
#[derive(Debug, Deserialize)]
pub struct AccessibleVersionRequest {
    /// HTML content to enhance
    pub html: String,
}

/// Response with enhanced HTML
#[derive(Debug, Serialize)]
pub struct AccessibleVersionResponse {
    /// Enhanced HTML with accessibility features
    pub html: String,
}

/// Endpoint to generate an accessible version of HTML
#[post("/format/accessibility/enhance")]
pub async fn generate_accessible_version(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
    Json(params): Json<AccessibleVersionRequest>,
) -> Result<Json<AccessibleVersionResponse>> {
    let service = format_service.read().await;

    let html = service.generate_accessible_version(&params.html)?;

    Ok(Json(AccessibleVersionResponse { html }))
}

/// Request to check and improve color contrast
#[derive(Debug, Deserialize)]
pub struct ContrastCheckRequest {
    /// Foreground color in hex format (#RRGGBB)
    pub foreground: String,

    /// Background color in hex format (#RRGGBB)
    pub background: String,
}

/// Response with contrast check results
#[derive(Debug, Serialize)]
pub struct ContrastCheckResponse {
    /// Whether the contrast ratio meets WCAG AA standards
    pub has_sufficient_contrast: bool,

    /// The calculated contrast ratio
    pub contrast_ratio: f64,

    /// A suggested color with better contrast (if needed)
    pub suggested_color: Option<String>,
}

/// Endpoint to check and improve color contrast
#[post("/format/accessibility/contrast")]
pub async fn check_color_contrast(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
    Json(params): Json<ContrastCheckRequest>,
) -> Result<Json<ContrastCheckResponse>> {
    let service = format_service.read().await;

    // Check if the contrast is sufficient
    let (has_contrast, suggestion) = service.check_color_contrast_and_suggest(
        &params.foreground,
        &params.background,
    )?;

    // Calculate the contrast ratio
    let contrast_ratio = if let Some(manager) = service.accessibility_manager() {
        manager.calculate_contrast_ratio(&params.foreground, &params.background)?
    } else {
        0.0
    };

    Ok(Json(ContrastCheckResponse {
        has_sufficient_contrast: has_contrast,
        contrast_ratio,
        suggested_color: suggestion,
    }))
}

/// Request to update accessibility features
#[derive(Debug, Deserialize)]
pub struct UpdateAccessibilityFeaturesRequest {
    /// New accessibility features to set
    pub features: AccessibilityFeatures,
}

/// Endpoint to update accessibility features
#[post("/format/accessibility/config")]
pub async fn update_accessibility_features(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
    Json(params): Json<UpdateAccessibilityFeaturesRequest>,
) -> Result<StatusCode> {
    let mut service = format_service.write().await;

    service.update_accessibility_features(params.features)?;

    Ok(StatusCode::OK)
}

/// Endpoint to get current accessibility features
#[get("/format/accessibility/config")]
pub async fn get_accessibility_features(
    Extension(format_service): Extension<Arc<RwLock<FormatService>>>,
) -> Result<Json<AccessibilityFeatures>> {
    let service = format_service.read().await;

    if let Some(manager) = service.accessibility_manager() {
        Ok(Json(manager.get_features().clone()))
    } else {
        Err(Error::Internal("Accessibility manager not initialized".to_string()).into())
    }
}

// Update the router function to include the new endpoints
pub fn router() -> Router {
    Router::new()
        .route("/format", post(format_code))
        .route("/format/diff", post(format_diff))
        .route("/format/blame", post(format_blame))
        .route("/format/markdown", post(format_markdown))
        .route("/format/themes", get(get_themes))
        .route("/format/languages", get(get_languages))
        // Add new accessibility routes
        .route("/format/accessible", post(format_accessible_code))
        .route("/format/accessibility/analyze", post(analyze_accessibility))
        .route("/format/accessibility/enhance", post(generate_accessible_version))
        .route("/format/accessibility/contrast", post(check_color_contrast))
        .route("/format/accessibility/config", post(update_accessibility_features))
        .route("/format/accessibility/config", get(get_accessibility_features))
}

// ... existing code ...

// Add tests for the new endpoints
#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::format::FormatService;
    use axum::http::StatusCode;
    use prometheus::Registry;

    // ... existing tests ...

    #[tokio::test]
    async fn test_accessibility_endpoints() {
        // Create a test service with accessibility features
        let registry = Registry::new();
        let service = FormatService::with_accessibility("github", &registry).unwrap();
        let service = Arc::new(RwLock::new(service));

        // Create a test router
        let app = Router::new()
            .route("/format/accessible", post(format_accessible_code))
            .route("/format/accessibility/analyze", post(analyze_accessibility))
            .route("/format/accessibility/enhance", post(generate_accessible_version))
            .route("/format/accessibility/contrast", post(check_color_contrast))
            .route("/format/accessibility/config", post(update_accessibility_features))
            .route("/format/accessibility/config", get(get_accessibility_features))
            .layer(Extension(service));

        // Test format accessible code endpoint
        let body = FormatRequestParams {
            content: "function test() { return 42; }".to_string(),
            path: "test.js".to_string(),
            options: None,
        };

        let response =
            request()
                .method("POST")
                .uri("/format/accessible")
                .json(&body)
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Test accessibility analysis endpoint
        let body = AccessibilityAnalysisRequest {
            html: "<div><img src='test.png'></div>".to_string(),
        };

        let response =
            request()
                .method("POST")
                .uri("/format/accessibility/analyze")
                .json(&body)
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Test generate accessible version endpoint
        let body = AccessibleVersionRequest {
            html: "<div><a href='#'>Link</a></div>".to_string(),
        };

        let response =
            request()
                .method("POST")
                .uri("/format/accessibility/enhance")
                .json(&body)
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Test color contrast check endpoint
        let body = ContrastCheckRequest {
            foreground: "#000000".to_string(),
            background: "#ffffff".to_string(),
        };

        let response =
            request()
                .method("POST")
                .uri("/format/accessibility/contrast")
                .json(&body)
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Extract the response
        let contrast_response: ContrastCheckResponse = serde_json::from_slice(response.body()).unwrap();

        // Black on white should have sufficient contrast
        assert!(contrast_response.has_sufficient_contrast);
        assert!(contrast_response.contrast_ratio > 20.0); // Should be 21.0

        // Test get accessibility features endpoint
        let response =
            request()
                .method("GET")
                .uri("/format/accessibility/config")
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Test update accessibility features endpoint
        let features = AccessibilityFeatures {
            min_contrast_ratio: 7.0, // Higher than default
            add_keyboard_shortcuts: true,
            ..AccessibilityFeatures::default()
        };

        let body = UpdateAccessibilityFeaturesRequest { features };

        let response =
            request()
                .method("POST")
                .uri("/format/accessibility/config")
                .json(&body)
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        // Verify that features were updated
        let response =
            request()
                .method("GET")
                .uri("/format/accessibility/config")
                .reply(&app)
                .await;

        assert_eq!(response.status(), StatusCode::OK);

        let updated_features: AccessibilityFeatures = serde_json::from_slice(response.body()).unwrap();
        assert_eq!(updated_features.min_contrast_ratio, 7.0);
        assert!(updated_features.add_keyboard_shortcuts);
    }
}
