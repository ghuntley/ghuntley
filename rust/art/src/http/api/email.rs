//! Email API endpoints
//!
//! Provides API endpoints for sending emails through the application.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::{
    error::{self, Result},
    http::ServerState,
    service::notification::{Notification, NotificationEmailExt},
};

/// Parameters for sending an email notification
#[derive(Debug, Deserialize)]
pub struct SendEmailNotificationParams {
    /// Email recipient address
    pub email: String,

    /// Recipient's name
    pub name: String,
}

/// Response for email operations
#[derive(Debug, Serialize)]
pub struct EmailResponse {
    /// Status message
    pub message: String,

    /// Status code
    pub status: String,
}

/// Send a notification as an email
pub async fn send_notification_as_email(
    State(state): State<ServerState>,
    Path(notification_id): Path<String>,
    Json(params): Json<SendEmailNotificationParams>,
) -> Result<impl IntoResponse> {
    // Check if email service is enabled
    if !state.app.email_service.is_enabled() {
        return Err(error::Error::ConfigurationError("Email service is not enabled".to_string()));
    }

    // Get notification service
    let notification_service = state.app.notification_service.clone();
    let email_service = state.app.email_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Get the specific notification
    let notification = notification_service.get_notification(&notification_id, user_id.as_deref()).await?;

    // Send the notification as an email
    notification.send_as_email(
        &email_service,
        &params.email,
        &params.name,
    ).await?;

    Ok((
        StatusCode::OK,
        Json(EmailResponse {
            message: "Email sent successfully".to_string(),
            status: "success".to_string(),
        }),
    ))
}

/// Send a digest of all unread notifications as email
pub async fn send_notifications_digest_email(
    State(state): State<ServerState>,
    Json(params): Json<SendEmailNotificationParams>,
) -> Result<impl IntoResponse> {
    // Check if email service is enabled
    if !state.app.email_service.is_enabled() {
        return Err(error::Error::ConfigurationError("Email service is not enabled".to_string()));
    }

    // Get services
    let notification_service = state.app.notification_service.clone();
    let email_service = state.app.email_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Get all notifications for the user
    let notifications = if let Some(user_id) = &user_id {
        notification_service.get_user_notifications(user_id).await
    } else {
        notification_service.get_global_notifications().await
    };

    // Filter to only include unread notifications
    let unread_notifications: Vec<Notification> = notifications
        .into_iter()
        .filter(|n| !n.read)
        .collect();

    if unread_notifications.is_empty() {
        return Ok((
            StatusCode::OK,
            Json(EmailResponse {
                message: "No unread notifications to send".to_string(),
                status: "success".to_string(),
            }),
        ));
    }

    // Send the digest email
    crate::service::notification::email::send_notifications_as_email(
        &unread_notifications,
        &email_service,
        &params.email,
        &params.name,
    ).await?;

    Ok((
        StatusCode::OK,
        Json(EmailResponse {
            message: format!("Email digest with {} notifications sent successfully", unread_notifications.len()),
            status: "success".to_string(),
        }),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use hyper::Body;
    use std::sync::Arc;
    use tower::ServiceExt;

    use crate::service::email::EmailConfig;
    use crate::service::notification::{NotificationService, NotificationLevel};

    // Create a test app with required services
    async fn create_test_app() -> Router {
        let notification_service = Arc::new(NotificationService::new_with_defaults());
        let email_config = EmailConfig {
            enabled: true, // Enable for tests
            ..EmailConfig::default()
        };
        let email_service = Arc::new(crate::service::email::EmailService::new(email_config));

        // Add a template to the email service
        email_service.add_template(crate::service::email::EmailTemplate {
            name: "notification".to_string(),
            subject: "Test Subject".to_string(),
            text_content: "Test content".to_string(),
            html_content: None,
        }).await.unwrap();

        // Create a test notification
        let notification = Notification::new(
            "Test Notification".to_string(),
            "This is a test notification".to_string(),
            NotificationLevel::Info,
            None, // Global notification
        );

        notification_service.add_global_notification(notification).await.unwrap();

        // Get the notification ID for testing
        let notifications = notification_service.get_global_notifications().await;
        let notification_id = &notifications[0].id;

        // Build the server state
        let app_state = ServerState {
            app: Arc::new(crate::App {
                notification_service,
                email_service,
                // Other required fields would be here in a real test
            }),
        };

        Router::new()
            .route("/notifications/:id/email", post(send_notification_as_email))
            .route("/notifications/digest/email", post(send_notifications_digest_email))
            .with_state(app_state)
    }

    #[tokio::test]
    async fn test_send_notification_as_email() {
        let app = create_test_app().await;

        // Get the notification ID for testing
        let app_state = app.state().expect("App state should exist");
        let notifications = app_state.app.notification_service.get_global_notifications().await;
        let notification_id = &notifications[0].id;

        // Parameters for sending an email
        let params = SendEmailNotificationParams {
            email: "test@example.com".to_string(),
            name: "Test User".to_string(),
        };

        // Make the request
        let response = app
            .oneshot(
                Request::post(&format!("/notifications/{}/email", notification_id))
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&params).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check the response
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_send_notifications_digest_email() {
        let app = create_test_app().await;

        // Parameters for sending an email
        let params = SendEmailNotificationParams {
            email: "test@example.com".to_string(),
            name: "Test User".to_string(),
        };

        // Make the request
        let response = app
            .oneshot(
                Request::post("/notifications/digest/email")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&params).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Check the response
        assert_eq!(response.status(), StatusCode::OK);
    }
}
