use crate::service::notification::{NotificationConfig, NotificationService, Notification, NotificationLevel};
use crate::service::email::{EmailService, EmailConfig};
use std::sync::Arc;
use chrono::Duration;
use crate::config::Config;
use crate::error::Result;

/// The main application container
pub struct App {
    // ... existing fields ...

    /// Notification service
    pub notification_service: Arc<NotificationService>,

    /// Email service
    pub email_service: Arc<EmailService>,

    // ... existing fields ...
}

impl App {
    /// Create a new application instance with the given configuration
    pub async fn new_with_config(config: Config) -> Result<Self> {
        // ... existing code ...

        // Create notification service
        let notification_service = Arc::new(NotificationService::new_with_defaults());

        // Create email service
        let email_service = Arc::new(EmailService::new(config.email.clone()));

        // Initialize email templates if email service is enabled
        if email_service.is_enabled() {
            email_service.add_common_templates().await?;
        }

        // Create some test notifications
        Self::create_test_notifications(&notification_service).await?;

        // ... existing code ...

        Ok(Self {
            // ... existing fields ...
            notification_service,
            email_service,
            // ... existing fields ...
        })
    }

    /// Create test notifications for demonstration purposes
    async fn create_test_notifications(notification_service: &Arc<NotificationService>) -> Result<()> {
        // Welcome notification (global)
        let welcome = Notification::new(
            "Welcome to Art".to_string(),
            "Welcome to the Art Git Repository Browser. This notification system allows administrators to communicate important information to users.".to_string(),
            NotificationLevel::Info,
            None, // Global notification
        ).with_expiration(Duration::days(7));

        notification_service.add_global_notification(welcome).await?;

        // Maintenance notification (global)
        let maintenance = Notification::new(
            "Scheduled Maintenance".to_string(),
            "The system will be undergoing scheduled maintenance this weekend. Expect brief periods of downtime.".to_string(),
            NotificationLevel::Warning,
            None, // Global notification
        ).with_expiration(Duration::days(3));

        notification_service.add_global_notification(maintenance).await?;

        // New feature notification (global)
        let new_feature = Notification::new(
            "New Feature: Notification System".to_string(),
            "We've added a new notification system to help keep you informed about important updates and events.".to_string(),
            NotificationLevel::Success,
            None, // Global notification
        ).with_expiration(Duration::days(5));

        notification_service.add_global_notification(new_feature).await?;

        Ok(())
    }

    // ... existing code ...
}
