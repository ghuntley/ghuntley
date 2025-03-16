//! Email integration for the notification system
//!
//! This module provides functionality for sending email notifications.

use std::sync::Arc;
use serde_json::json;

use crate::error::Result;
use crate::service::email::{EmailService, EmailPriority};
use crate::service::notification::{Notification, NotificationLevel};

/// Extension trait for sending notifications via email
pub trait NotificationEmailExt {
    /// Send this notification as an email
    async fn send_as_email(&self, email_service: &Arc<EmailService>, recipient_email: &str, recipient_name: &str) -> Result<()>;
}

impl NotificationEmailExt for Notification {
    async fn send_as_email(&self, email_service: &Arc<EmailService>, recipient_email: &str, recipient_name: &str) -> Result<()> {
        if !email_service.is_enabled() {
            return Ok(());
        }

        // Map notification level to email priority
        let priority = match self.level {
            NotificationLevel::Info => EmailPriority::Normal,
            NotificationLevel::Success => EmailPriority::Normal,
            NotificationLevel::Warning => EmailPriority::High,
            NotificationLevel::Error => EmailPriority::High,
        };

        // Prepare variables for template
        let variables = json!({
            "name": recipient_name,
            "notification_title": self.title,
            "notification_message": self.message,
            "notification_id": self.id,
            "notification_level": self.level.as_str(),
            "created_at": self.created_at.to_rfc3339(),
            "target_url": self.target_url
        });

        // Send the notification email using the notification template
        email_service.send_template_email(
            "notification",
            recipient_email.to_string(),
            &variables
        ).await
    }
}

/// Helper for sending multiple notifications via email
pub async fn send_notifications_as_email(
    notifications: &[Notification],
    email_service: &Arc<EmailService>,
    recipient_email: &str,
    recipient_name: &str,
) -> Result<()> {
    if !email_service.is_enabled() {
        return Ok(());
    }

    // Convert notifications to a format suitable for email template
    let notification_items: Vec<serde_json::Value> = notifications
        .iter()
        .map(|n| {
            json!({
                "id": n.id,
                "title": n.title,
                "message": n.message,
                "level": n.level.as_str(),
                "created_at": n.created_at.to_rfc3339(),
                "target_url": n.target_url
            })
        })
        .collect();

    // Prepare variables for digest template
    let variables = json!({
        "name": recipient_name,
        "notifications": notification_items,
        "count": notifications.len()
    });

    // Send the notification digest email
    email_service.send_template_email(
        "notification_digest",
        recipient_email.to_string(),
        &variables
    ).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::email::EmailConfig;
    use chrono::Utc;

    #[tokio::test]
    async fn test_send_notification_as_email() {
        // Create a test email service (disabled for tests)
        let config = EmailConfig::default();
        let email_service = Arc::new(EmailService::new(config));

        // Create a test notification
        let notification = Notification::new(
            "Test Notification".to_string(),
            "This is a test notification".to_string(),
            NotificationLevel::Info,
            None, // Global notification
        );

        // Test sending the notification as an email (should succeed even though service is disabled)
        let result = notification.send_as_email(&email_service, "test@example.com", "Test User").await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_send_notifications_as_email() {
        // Create a test email service (disabled for tests)
        let config = EmailConfig::default();
        let email_service = Arc::new(EmailService::new(config));

        // Create test notifications
        let notifications = vec![
            Notification::new(
                "Test Notification 1".to_string(),
                "This is test notification 1".to_string(),
                NotificationLevel::Info,
                None,
            ),
            Notification::new(
                "Test Notification 2".to_string(),
                "This is test notification 2".to_string(),
                NotificationLevel::Warning,
                None,
            ),
        ];

        // Test sending the notifications as a digest email
        let result = send_notifications_as_email(
            &notifications,
            &email_service,
            "test@example.com",
            "Test User",
        ).await;

        assert!(result.is_ok());
    }
}
