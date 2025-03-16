//! Notification API endpoints for retrieving and managing notifications

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::{self, Result},
    http::ServerState,
    service::notification::{Notification, NotificationLevel},
};

/// Query parameters for retrieving notifications
#[derive(Debug, Deserialize)]
pub struct NotificationsQuery {
    /// Only include unread notifications
    #[serde(default)]
    pub unread_only: bool,
}

/// Query parameters for creating new notifications
#[derive(Debug, Deserialize)]
pub struct CreateNotificationParams {
    /// Notification title
    pub title: String,

    /// Notification message
    pub message: String,

    /// Notification level
    pub level: String,

    /// User ID to target (if none, creates a global notification)
    pub user_id: Option<String>,

    /// Whether the notification is dismissible
    #[serde(default = "default_true")]
    pub dismissible: bool,

    /// Target URL (optional)
    pub target_url: Option<String>,

    /// Expiration time in hours (optional)
    pub expires_in_hours: Option<u32>,
}

fn default_true() -> bool {
    true
}

/// Response for notification operations
#[derive(Debug, Serialize)]
pub struct NotificationResponse {
    /// Status message
    pub message: String,

    /// Status code
    pub status: String,

    /// Notification ID (if applicable)
    pub notification_id: Option<String>,
}

/// Get all notifications (global and user-specific if user is logged in)
pub async fn get_notifications(
    State(state): State<ServerState>,
    Query(query): Query<NotificationsQuery>,
) -> Result<impl IntoResponse> {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Get notifications
    let mut notifications = if let Some(user_id) = &user_id {
        notification_service.get_user_notifications(user_id).await
    } else {
        notification_service.get_global_notifications().await
    };

    // Filter by read status if requested
    if query.unread_only {
        notifications = notifications.into_iter().filter(|n| !n.read).collect();
    }

    Ok(Json(notifications))
}

/// Create a new notification
pub async fn create_notification(
    State(state): State<ServerState>,
    Json(params): Json<CreateNotificationParams>,
) -> Result<impl IntoResponse> {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Parse notification level
    let level = match params.level.to_lowercase().as_str() {
        "info" => NotificationLevel::Info,
        "warning" => NotificationLevel::Warning,
        "success" => NotificationLevel::Success,
        "error" => NotificationLevel::Error,
        _ => return Err(error::Error::InvalidRequest("Invalid notification level".to_string())),
    };

    // Create notification
    let mut notification = Notification::new(
        params.title,
        params.message,
        level,
        params.user_id.clone(),
    ).with_dismissible(params.dismissible);

    // Add target URL if specified
    if let Some(url) = params.target_url {
        notification = notification.with_target_url(url);
    }

    // Set expiration if specified
    if let Some(hours) = params.expires_in_hours {
        notification = notification.with_expiration(chrono::Duration::hours(hours as i64));
    }

    // Store notification
    let notification_id = notification.id.clone();

    if params.user_id.is_some() {
        notification_service.add_user_notification(notification).await?;
    } else {
        notification_service.add_global_notification(notification).await?;
    }

    Ok((
        StatusCode::CREATED,
        Json(NotificationResponse {
            message: "Notification created successfully".to_string(),
            status: "success".to_string(),
            notification_id: Some(notification_id),
        }),
    ))
}

/// Mark a notification as read
pub async fn mark_notification_as_read(
    State(state): State<ServerState>,
    Path(notification_id): Path<String>,
) -> Result<impl IntoResponse> {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Mark notification as read
    notification_service.mark_as_read(&notification_id, user_id.as_deref()).await?;

    Ok(Json(NotificationResponse {
        message: "Notification marked as read".to_string(),
        status: "success".to_string(),
        notification_id: Some(notification_id),
    }))
}

/// Dismiss a notification
pub async fn dismiss_notification(
    State(state): State<ServerState>,
    Path(notification_id): Path<String>,
) -> Result<impl IntoResponse> {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Dismiss notification
    notification_service.dismiss_notification(&notification_id, user_id.as_deref()).await?;

    Ok(Json(NotificationResponse {
        message: "Notification dismissed".to_string(),
        status: "success".to_string(),
        notification_id: Some(notification_id),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::{routing::get, Router};
    use hyper::Body;
    use std::sync::Arc;
    use tower::ServiceExt;

    use crate::service::notification::NotificationService;

    // Create a test app with notification service
    async fn create_test_app() -> Router {
        let notification_service = Arc::new(NotificationService::new_with_defaults());

        // Create a test global notification
        let test_notification = Notification::new(
            "Test Notification".to_string(),
            "This is a test notification".to_string(),
            NotificationLevel::Info,
            None, // Global notification
        );

        notification_service.add_global_notification(test_notification).await.unwrap();

        // Build the server state
        let app_state = ServerState {
            app: Arc::new(crate::App {
                notification_service,
                // Other required fields would be here in a real test
            }),
        };

        Router::new()
            .route("/notifications", get(get_notifications).post(create_notification))
            .route("/notifications/:id/read", post(mark_notification_as_read))
            .route("/notifications/:id/dismiss", post(dismiss_notification))
            .with_state(app_state)
    }

    #[tokio::test]
    async fn test_get_notifications() {
        let app = create_test_app().await;

        // Make a request to get all notifications
        let response = app
            .oneshot(Request::get("/notifications").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        // Parse the response body
        let body_bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let notifications: Vec<Notification> = serde_json::from_slice(&body_bytes).unwrap();

        // Should have at least one notification (the test one)
        assert!(!notifications.is_empty());
        assert_eq!(notifications[0].title, "Test Notification");
    }

    #[tokio::test]
    async fn test_create_notification() {
        let app = create_test_app().await;

        // Create a notification
        let create_params = CreateNotificationParams {
            title: "New Notification".to_string(),
            message: "This is a new notification".to_string(),
            level: "success".to_string(),
            user_id: None, // Global
            dismissible: true,
            target_url: None,
            expires_in_hours: Some(24),
        };

        let response = app
            .oneshot(
                Request::post("/notifications")
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_string(&create_params).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);

        // Get notifications after creating
        let response = app
            .oneshot(Request::get("/notifications").body(Body::empty()).unwrap())
            .await
            .unwrap();

        let body_bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let notifications: Vec<Notification> = serde_json::from_slice(&body_bytes).unwrap();

        // Should now have at least two notifications
        assert!(notifications.len() >= 2);

        // Find the newly created notification
        let new_notification = notifications
            .iter()
            .find(|n| n.title == "New Notification")
            .expect("New notification should exist");

        assert_eq!(new_notification.message, "This is a new notification");
        assert_eq!(new_notification.level, NotificationLevel::Success);
    }

    #[tokio::test]
    async fn test_mark_as_read() {
        let app = create_test_app().await;

        // Get notifications to find one to mark as read
        let response = app
            .oneshot(Request::get("/notifications").body(Body::empty()).unwrap())
            .await
            .unwrap();

        let body_bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let notifications: Vec<Notification> = serde_json::from_slice(&body_bytes).unwrap();

        let notification_id = &notifications[0].id;

        // Mark as read
        let response = app
            .oneshot(
                Request::post(&format!("/notifications/{}/read", notification_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        // Get notifications again
        let response = app
            .oneshot(Request::get("/notifications").body(Body::empty()).unwrap())
            .await
            .unwrap();

        let body_bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let notifications: Vec<Notification> = serde_json::from_slice(&body_bytes).unwrap();

        // Find the notification we marked as read
        let marked_notification = notifications
            .iter()
            .find(|n| n.id == *notification_id)
            .expect("Notification should still exist");

        assert!(marked_notification.read);
    }
}
