//! Email settings web UI
//!
//! This module provides web UI components for configuring email settings.

use axum::{
    extract::{Path, State},
    response::IntoResponse,
    Form,
};
use serde::Deserialize;

use crate::{
    error::Result,
    http::ServerState,
    service::email::EmailConfig,
    template::user::UserEmailSettingsTemplate,
};

/// Form data for updating email settings
#[derive(Debug, Deserialize)]
pub struct UpdateEmailSettingsForm {
    /// Whether to enable email notifications
    pub email_notifications_enabled: Option<String>,

    /// Email address for notifications
    pub email_address: String,
}

/// Handler for email settings page
pub async fn email_settings_handler(
    State(state): State<ServerState>,
) -> Result<impl IntoResponse> {
    // Get current user
    let user = match state.get_current_user().await {
        Some(user) => user,
        None => return Err(crate::error::Error::Unauthorized("You must be logged in to access this page".to_string())),
    };

    // Get email configuration
    let email_config = state.app.email_service.clone();

    // Render the email settings template
    let template = UserEmailSettingsTemplate::new(
        user,
        email_config.is_enabled(),
    );

    Ok(template)
}

/// Handler for updating email settings
pub async fn update_email_settings_handler(
    State(state): State<ServerState>,
    Form(form): Form<UpdateEmailSettingsForm>,
) -> Result<impl IntoResponse> {
    // Get current user
    let user = match state.get_current_user().await {
        Some(user) => user.clone(),
        None => return Err(crate::error::Error::Unauthorized("You must be logged in to access this page".to_string())),
    };

    // Get user service
    let user_service = state.app.user_service.clone();

    // Update user's email preferences
    let email_notifications_enabled = form.email_notifications_enabled.is_some();

    // Update user settings
    let mut updated_user = user.clone();
    updated_user.email = Some(form.email_address);
    updated_user.email_notifications_enabled = Some(email_notifications_enabled);

    user_service.update_user(&updated_user).await?;

    // Redirect back to settings page with success message
    let template = UserEmailSettingsTemplate::new_with_message(
        updated_user,
        state.app.email_service.is_enabled(),
        "Email settings updated successfully",
    );

    Ok(template)
}

/// Handler for sending a test email
pub async fn send_test_email_handler(
    State(state): State<ServerState>,
) -> Result<impl IntoResponse> {
    // Get current user
    let user = match state.get_current_user().await {
        Some(user) => user.clone(),
        None => return Err(crate::error::Error::Unauthorized("You must be logged in to access this page".to_string())),
    };

    // Get email service
    let email_service = state.app.email_service.clone();

    // Check if email service is enabled
    if !email_service.is_enabled() {
        return Err(crate::error::Error::ConfigurationError("Email service is not enabled".to_string()));
    }

    // Check if user has an email address
    let email_address = match &user.email {
        Some(email) => email.clone(),
        None => return Err(crate::error::Error::InvalidRequest("No email address configured for user".to_string())),
    };

    // Prepare variables for template
    let variables = serde_json::json!({
        "name": user.username,
        "username": user.username,
        "email": email_address,
    });

    // Send test email
    email_service.send_template_email(
        "welcome",
        email_address,
        &variables,
    ).await?;

    // Render the email settings template with success message
    let template = UserEmailSettingsTemplate::new_with_message(
        user,
        email_service.is_enabled(),
        "Test email sent successfully",
    );

    Ok(template)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use hyper::Body;
    use std::sync::Arc;
    use tower::ServiceExt;

    use crate::service::email::EmailConfig;
    use crate::service::user::{User, UserService};

    // Create a test user
    fn create_test_user() -> User {
        User {
            id: "test-user-id".to_string(),
            username: "testuser".to_string(),
            email: Some("test@example.com".to_string()),
            email_notifications_enabled: Some(true),
            is_admin: true,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
            last_login: None,
            // Other required fields would be here
            ..Default::default()
        }
    }

    // Create a test app
    async fn create_test_app() -> Router {
        let email_config = EmailConfig {
            enabled: true,
            ..EmailConfig::default()
        };
        let email_service = Arc::new(crate::service::email::EmailService::new(email_config));

        // Add a template for testing
        email_service.add_template(crate::service::email::EmailTemplate {
            name: "welcome".to_string(),
            subject: "Welcome".to_string(),
            text_content: "Welcome, {{name}}!".to_string(),
            html_content: None,
        }).await.unwrap();

        let user_service = Arc::new(UserService::new_in_memory());

        // Add test user
        let test_user = create_test_user();
        user_service.create_user(&test_user).await.unwrap();

        // Build the server state
        let app_state = ServerState {
            app: Arc::new(crate::App {
                email_service,
                user_service,
                // Other required fields would be here
            }),
            // Mock get_current_user to always return our test user
            get_current_user: Box::new(|| Box::pin(async {
                Some(create_test_user())
            })),
        };

        Router::new()
            .route("/user/settings/email", get(email_settings_handler).post(update_email_settings_handler))
            .route("/user/settings/email/test", post(send_test_email_handler))
            .with_state(app_state)
    }

    #[tokio::test]
    async fn test_email_settings_page() {
        let app = create_test_app().await;

        // Request the email settings page
        let response = app
            .oneshot(Request::get("/user/settings/email").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_update_email_settings() {
        let app = create_test_app().await;

        // Form data for updating email settings
        let form_data = "email_notifications_enabled=on&email_address=newemail@example.com";

        // Submit the form
        let response = app
            .oneshot(
                Request::post("/user/settings/email")
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .body(Body::from(form_data))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_send_test_email() {
        let app = create_test_app().await;

        // Request to send a test email
        let response = app
            .oneshot(Request::post("/user/settings/email/test").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }
}
