//! Notification service for managing and displaying user notifications
//!
//! This module provides functionality for creating, storing, and retrieving
//! notifications to be displayed to users in the Art application.

use crate::error::{Error, Result};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

pub mod email;

/// Notification level/severity
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NotificationLevel {
    /// Informational message
    Info,
    /// Warning message
    Warning,
    /// Success message
    Success,
    /// Error message
    Error,
}

impl NotificationLevel {
    /// Get the CSS class for this notification level
    pub fn as_css_class(&self) -> &'static str {
        match self {
            NotificationLevel::Info => "info",
            NotificationLevel::Warning => "warning",
            NotificationLevel::Success => "success",
            NotificationLevel::Error => "error",
        }
    }
}

/// A notification to be displayed to a user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    /// Unique ID for the notification
    pub id: String,

    /// The notification's title/summary
    pub title: String,

    /// Detailed message content
    pub message: String,

    /// The notification's severity level
    pub level: NotificationLevel,

    /// When the notification was created
    pub created_at: DateTime<Utc>,

    /// When the notification expires (if any)
    pub expires_at: Option<DateTime<Utc>>,

    /// Whether the notification has been read/seen
    pub read: bool,

    /// Whether the notification is dismissible by the user
    pub dismissible: bool,

    /// Associated user ID (if any)
    pub user_id: Option<String>,

    /// Target URL (if any)
    pub target_url: Option<String>,

    /// Additional data for the notification
    pub metadata: HashMap<String, String>,
}

impl Notification {
    /// Create a new notification
    pub fn new(
        title: String,
        message: String,
        level: NotificationLevel,
        user_id: Option<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            title,
            message,
            level,
            created_at: Utc::now(),
            expires_at: None,
            read: false,
            dismissible: true,
            user_id,
            target_url: None,
            metadata: HashMap::new(),
        }
    }

    /// Set expiration time for the notification
    pub fn with_expiration(mut self, duration: Duration) -> Self {
        self.expires_at = Some(self.created_at + duration);
        self
    }

    /// Set whether the notification is dismissible
    pub fn with_dismissible(mut self, dismissible: bool) -> Self {
        self.dismissible = dismissible;
        self
    }

    /// Set target URL for the notification
    pub fn with_target_url(mut self, url: String) -> Self {
        self.target_url = Some(url);
        self
    }

    /// Add metadata to the notification
    pub fn with_metadata(mut self, key: String, value: String) -> Self {
        self.metadata.insert(key, value);
        self
    }

    /// Check if the notification has expired
    pub fn is_expired(&self) -> bool {
        if let Some(expires_at) = self.expires_at {
            expires_at < Utc::now()
        } else {
            false
        }
    }
}

/// Configuration for the notification service
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationConfig {
    /// Maximum number of notifications to store per user
    pub max_notifications_per_user: usize,

    /// Default expiration time for notifications (in hours)
    pub default_expiration_hours: u32,

    /// How often to clean up expired notifications (in minutes)
    pub cleanup_interval_minutes: u64,
}

impl Default for NotificationConfig {
    fn default() -> Self {
        Self {
            max_notifications_per_user: 100,
            default_expiration_hours: 24,
            cleanup_interval_minutes: 60,
        }
    }
}

/// Service for managing notifications
pub struct NotificationService {
    /// Global notifications (not user-specific)
    global_notifications: RwLock<Vec<Notification>>,

    /// User-specific notifications
    user_notifications: RwLock<HashMap<String, Vec<Notification>>>,

    /// Configuration for the notification service
    config: NotificationConfig,

    /// Last cleanup time
    last_cleanup: RwLock<DateTime<Utc>>,
}

impl NotificationService {
    /// Create a new notification service
    pub fn new(config: NotificationConfig) -> Self {
        Self {
            global_notifications: RwLock::new(Vec::new()),
            user_notifications: RwLock::new(HashMap::new()),
            config,
            last_cleanup: RwLock::new(Utc::now()),
        }
    }

    /// Create a new notification service with default config
    pub fn new_with_defaults() -> Self {
        Self::new(NotificationConfig::default())
    }

    /// Add a global notification visible to all users
    pub async fn add_global_notification(&self, notification: Notification) -> Result<()> {
        let mut notifications = self.global_notifications.write().await;
        notifications.push(notification);

        // Try cleanup if needed
        self.try_cleanup().await;

        Ok(())
    }

    /// Add a user-specific notification
    pub async fn add_user_notification(&self, notification: Notification) -> Result<()> {
        if let Some(user_id) = &notification.user_id {
            let mut user_notifications = self.user_notifications.write().await;

            let notifications = user_notifications
                .entry(user_id.clone())
                .or_insert_with(Vec::new);

            // Ensure we don't exceed max notifications per user
            if notifications.len() >= self.config.max_notifications_per_user {
                // Remove oldest notification
                notifications.sort_by(|a, b| a.created_at.cmp(&b.created_at));
                notifications.remove(0);
            }

            notifications.push(notification);
        } else {
            return Err(Error::InvalidInput(
                "User-specific notification must have a user ID".to_string(),
            ));
        }

        // Try cleanup if needed
        self.try_cleanup().await;

        Ok(())
    }

    /// Get all global notifications
    pub async fn get_global_notifications(&self) -> Vec<Notification> {
        let notifications = self.global_notifications.read().await;
        notifications
            .iter()
            .filter(|n| !n.is_expired())
            .cloned()
            .collect()
    }

    /// Get notifications for a specific user
    pub async fn get_user_notifications(&self, user_id: &str) -> Vec<Notification> {
        let user_notifications = self.user_notifications.read().await;

        let mut result = Vec::new();

        // Add global notifications
        let global = self.global_notifications.read().await;
        for notification in global.iter() {
            if !notification.is_expired() {
                result.push(notification.clone());
            }
        }

        // Add user-specific notifications
        if let Some(user_notifs) = user_notifications.get(user_id) {
            for notification in user_notifs.iter() {
                if !notification.is_expired() {
                    result.push(notification.clone());
                }
            }
        }

        // Sort by creation time (newest first)
        result.sort_by(|a, b| b.created_at.cmp(&a.created_at));

        result
    }

    /// Mark a notification as read
    pub async fn mark_as_read(&self, notification_id: &str, user_id: Option<&str>) -> Result<()> {
        // Try to mark in global notifications
        {
            let mut global = self.global_notifications.write().await;
            if let Some(notification) = global.iter_mut().find(|n| n.id == notification_id) {
                notification.read = true;
                return Ok(());
            }
        }

        // If user ID is provided, try to mark in user notifications
        if let Some(user_id) = user_id {
            let mut user_notifications = self.user_notifications.write().await;
            if let Some(notifications) = user_notifications.get_mut(user_id) {
                if let Some(notification) = notifications.iter_mut().find(|n| n.id == notification_id) {
                    notification.read = true;
                    return Ok(());
                }
            }
        }

        Err(Error::NotFound(format!("Notification with ID {} not found", notification_id)))
    }

    /// Dismiss (delete) a notification
    pub async fn dismiss_notification(&self, notification_id: &str, user_id: Option<&str>) -> Result<()> {
        // Try to dismiss from global notifications
        {
            let mut global = self.global_notifications.write().await;
            if let Some(index) = global.iter().position(|n| n.id == notification_id) {
                let notification = &global[index];
                if !notification.dismissible {
                    return Err(Error::InvalidOperation(
                        "This notification cannot be dismissed".to_string(),
                    ));
                }
                global.remove(index);
                return Ok(());
            }
        }

        // If user ID is provided, try to dismiss from user notifications
        if let Some(user_id) = user_id {
            let mut user_notifications = self.user_notifications.write().await;
            if let Some(notifications) = user_notifications.get_mut(user_id) {
                if let Some(index) = notifications.iter().position(|n| n.id == notification_id) {
                    let notification = &notifications[index];
                    if !notification.dismissible {
                        return Err(Error::InvalidOperation(
                            "This notification cannot be dismissed".to_string(),
                        ));
                    }
                    notifications.remove(index);
                    return Ok(());
                }
            }
        }

        Err(Error::NotFound(format!("Notification with ID {} not found", notification_id)))
    }

    /// Create a convenience notification with info level
    pub async fn info(&self, title: impl Into<String>, message: impl Into<String>, user_id: Option<String>) -> Result<()> {
        let notification = Notification::new(
            title.into(),
            message.into(),
            NotificationLevel::Info,
            user_id.clone(),
        ).with_expiration(Duration::hours(self.config.default_expiration_hours as i64));

        if user_id.is_some() {
            self.add_user_notification(notification).await
        } else {
            self.add_global_notification(notification).await
        }
    }

    /// Create a convenience notification with warning level
    pub async fn warning(&self, title: impl Into<String>, message: impl Into<String>, user_id: Option<String>) -> Result<()> {
        let notification = Notification::new(
            title.into(),
            message.into(),
            NotificationLevel::Warning,
            user_id.clone(),
        ).with_expiration(Duration::hours(self.config.default_expiration_hours as i64));

        if user_id.is_some() {
            self.add_user_notification(notification).await
        } else {
            self.add_global_notification(notification).await
        }
    }

    /// Create a convenience notification with success level
    pub async fn success(&self, title: impl Into<String>, message: impl Into<String>, user_id: Option<String>) -> Result<()> {
        let notification = Notification::new(
            title.into(),
            message.into(),
            NotificationLevel::Success,
            user_id.clone(),
        ).with_expiration(Duration::hours(self.config.default_expiration_hours as i64));

        if user_id.is_some() {
            self.add_user_notification(notification).await
        } else {
            self.add_global_notification(notification).await
        }
    }

    /// Create a convenience notification with error level
    pub async fn error(&self, title: impl Into<String>, message: impl Into<String>, user_id: Option<String>) -> Result<()> {
        let notification = Notification::new(
            title.into(),
            message.into(),
            NotificationLevel::Error,
            user_id.clone(),
        ).with_expiration(Duration::hours(self.config.default_expiration_hours as i64));

        if user_id.is_some() {
            self.add_user_notification(notification).await
        } else {
            self.add_global_notification(notification).await
        }
    }

    /// Try to clean up expired notifications if enough time has passed
    async fn try_cleanup(&self) {
        let now = Utc::now();
        let mut last_cleanup = self.last_cleanup.write().await;

        // Only clean up if the interval has passed
        if (now - *last_cleanup).num_minutes() >= self.config.cleanup_interval_minutes as i64 {
            // Clean up global notifications
            {
                let mut global = self.global_notifications.write().await;
                global.retain(|n| !n.is_expired());
            }

            // Clean up user notifications
            {
                let mut user_notifications = self.user_notifications.write().await;
                for notifications in user_notifications.values_mut() {
                    notifications.retain(|n| !n.is_expired());
                }

                // Remove empty user entries
                user_notifications.retain(|_, notifications| !notifications.is_empty());
            }

            // Update last cleanup time
            *last_cleanup = now;
        }
    }

    /// Manually trigger cleanup of expired notifications
    pub async fn cleanup(&self) {
        // Clean up global notifications
        {
            let mut global = self.global_notifications.write().await;
            global.retain(|n| !n.is_expired());
        }

        // Clean up user notifications
        {
            let mut user_notifications = self.user_notifications.write().await;
            for notifications in user_notifications.values_mut() {
                notifications.retain(|n| !n.is_expired());
            }

            // Remove empty user entries
            user_notifications.retain(|_, notifications| !notifications.is_empty());
        }

        // Update last cleanup time
        let mut last_cleanup = self.last_cleanup.write().await;
        *last_cleanup = Utc::now();
    }
}

// Re-export email integration
pub use email::NotificationEmailExt;

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use proptest_derive::Arbitrary;
    use std::collections::HashSet;
    use tokio::runtime::Runtime;

    /// Execute async tests
    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        let rt = Runtime::new().unwrap();
        rt.block_on(future)
    }

    /// Generate a valid notification title
    fn title_strategy() -> impl Strategy<Value = String> {
        prop::string::string_regex("[A-Za-z0-9 ]{3,50}").unwrap()
    }

    /// Generate a valid notification message
    fn message_strategy() -> impl Strategy<Value = String> {
        prop::string::string_regex("[A-Za-z0-9 .,!?]{10,200}").unwrap()
    }

    /// Generate a valid user ID
    fn user_id_strategy() -> impl Strategy<Value = Option<String>> {
        prop_oneof![
            Just(None),
            uuid::Uuid::new_v4().to_string().prop_map(Some),
        ]
    }

    /// Generate notification level
    fn level_strategy() -> impl Strategy<Value = NotificationLevel> {
        prop_oneof![
            Just(NotificationLevel::Info),
            Just(NotificationLevel::Warning),
            Just(NotificationLevel::Success),
            Just(NotificationLevel::Error),
        ]
    }

    /// Generate a vector of random notifications
    fn notifications_strategy() -> impl Strategy<Value = Vec<Notification>> {
        prop::collection::vec(
            (
                title_strategy(),
                message_strategy(),
                level_strategy(),
                user_id_strategy(),
            )
                .prop_map(|(title, message, level, user_id)| {
                    Notification::new(title, message, level, user_id)
                }),
            1..10,
        )
    }

    /// Generate expiration duration
    fn expiration_strategy() -> impl Strategy<Value = Option<Duration>> {
        prop_oneof![
            Just(None),
            (1i64..100).prop_map(|hours| Some(Duration::hours(hours))),
        ]
    }

    proptest! {
        /// Test creating and retrieving global notifications
        #[test]
        fn test_global_notifications(
            notifications in notifications_strategy()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Add all notifications as global
                let mut global_notification_ids = HashSet::new();
                for mut notification in notifications.clone() {
                    notification.user_id = None; // Ensure these are global
                    service.add_global_notification(notification.clone()).await.unwrap();
                    global_notification_ids.insert(notification.id.clone());
                }

                // Retrieve global notifications
                let retrieved = service.get_global_notifications().await;

                // Verify all notifications were retrieved
                let retrieved_ids: HashSet<String> = retrieved.iter().map(|n| n.id.clone()).collect();
                prop_assert_eq!(global_notification_ids, retrieved_ids);
            });
        }

        /// Test creating and retrieving user-specific notifications
        #[test]
        fn test_user_notifications(
            notifications in notifications_strategy(),
            user_id in uuid::Uuid::new_v4().to_string()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Add all notifications as user-specific
                let mut user_notification_ids = HashSet::new();
                for mut notification in notifications.clone() {
                    notification.user_id = Some(user_id.clone());
                    service.add_user_notification(notification.clone()).await.unwrap();
                    user_notification_ids.insert(notification.id.clone());
                }

                // Retrieve user notifications
                let retrieved = service.get_user_notifications(&user_id).await;

                // Verify all notifications were retrieved
                let retrieved_ids: HashSet<String> = retrieved.iter().map(|n| n.id.clone()).collect();
                prop_assert_eq!(user_notification_ids, retrieved_ids);
            });
        }

        /// Test that notifications are properly marked as read
        #[test]
        fn test_mark_as_read(
            notifications in notifications_strategy()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Split notifications into global and user-specific
                let mut global_notifications = Vec::new();
                let mut user_notifications: HashMap<String, Vec<Notification>> = HashMap::new();

                for mut notification in notifications {
                    if notification.user_id.is_none() {
                        global_notifications.push(notification);
                    } else {
                        let user_id = notification.user_id.clone().unwrap();
                        user_notifications.entry(user_id).or_insert_with(Vec::new).push(notification);
                    }
                }

                // Add global notifications
                for notification in global_notifications.iter() {
                    service.add_global_notification(notification.clone()).await.unwrap();
                }

                // Add user notifications
                for (user_id, notifications) in user_notifications.iter() {
                    for notification in notifications {
                        service.add_user_notification(notification.clone()).await.unwrap();
                    }
                }

                // Mark global notifications as read
                if !global_notifications.is_empty() {
                    let notification = &global_notifications[0];
                    service.mark_as_read(&notification.id, None).await.unwrap();

                    // Verify it was marked as read
                    let retrieved = service.get_global_notifications().await;
                    let marked = retrieved.iter().find(|n| n.id == notification.id).unwrap();
                    prop_assert!(marked.read);
                }

                // Mark user notifications as read
                for (user_id, notifications) in user_notifications.iter() {
                    if !notifications.is_empty() {
                        let notification = &notifications[0];
                        service.mark_as_read(&notification.id, Some(user_id)).await.unwrap();

                        // Verify it was marked as read
                        let retrieved = service.get_user_notifications(user_id).await;
                        let marked = retrieved.iter().find(|n| n.id == notification.id).unwrap();
                        prop_assert!(marked.read);
                    }
                }
            });
        }

        /// Test dismissing notifications
        #[test]
        fn test_dismiss_notification(
            notifications in notifications_strategy()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Split notifications into global and user-specific
                let mut global_notifications = Vec::new();
                let mut user_notifications: HashMap<String, Vec<Notification>> = HashMap::new();

                for mut notification in notifications {
                    notification.dismissible = true; // Ensure all are dismissible

                    if notification.user_id.is_none() {
                        global_notifications.push(notification);
                    } else {
                        let user_id = notification.user_id.clone().unwrap();
                        user_notifications.entry(user_id).or_insert_with(Vec::new).push(notification);
                    }
                }

                // Add global notifications
                for notification in global_notifications.iter() {
                    service.add_global_notification(notification.clone()).await.unwrap();
                }

                // Add user notifications
                for (user_id, notifications) in user_notifications.iter() {
                    for notification in notifications {
                        service.add_user_notification(notification.clone()).await.unwrap();
                    }
                }

                // Dismiss a global notification
                if !global_notifications.is_empty() {
                    let notification = &global_notifications[0];
                    service.dismiss_notification(&notification.id, None).await.unwrap();

                    // Verify it was dismissed
                    let retrieved = service.get_global_notifications().await;
                    prop_assert!(!retrieved.iter().any(|n| n.id == notification.id));
                }

                // Dismiss user notifications
                for (user_id, notifications) in user_notifications.iter() {
                    if !notifications.is_empty() {
                        let notification = &notifications[0];
                        service.dismiss_notification(&notification.id, Some(user_id)).await.unwrap();

                        // Verify it was dismissed
                        let retrieved = service.get_user_notifications(user_id).await;
                        prop_assert!(!retrieved.iter().any(|n| n.id == notification.id));
                    }
                }
            });
        }

        /// Test that notifications expire correctly
        #[test]
        fn test_notification_expiration(
            title in title_strategy(),
            message in message_strategy(),
            level in level_strategy(),
            user_id in user_id_strategy()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Create a notification that's already expired
                let mut notification = Notification::new(
                    title,
                    message,
                    level,
                    user_id.clone(),
                );

                // Set expiration to the past
                notification.expires_at = Some(Utc::now() - Duration::hours(1));

                // Add notification
                if user_id.is_some() {
                    service.add_user_notification(notification.clone()).await.unwrap();

                    // Manually trigger cleanup
                    service.cleanup().await;

                    // Verify the notification doesn't appear in results
                    let retrieved = service.get_user_notifications(&user_id.unwrap()).await;
                    prop_assert!(!retrieved.iter().any(|n| n.id == notification.id));
                } else {
                    service.add_global_notification(notification.clone()).await.unwrap();

                    // Manually trigger cleanup
                    service.cleanup().await;

                    // Verify the notification doesn't appear in results
                    let retrieved = service.get_global_notifications().await;
                    prop_assert!(!retrieved.iter().any(|n| n.id == notification.id));
                }
            });
        }

        /// Test convenience methods for creating notifications
        #[test]
        fn test_convenience_methods(
            title in title_strategy(),
            message in message_strategy(),
            user_id in user_id_strategy()
        ) {
            block_on(async {
                let service = NotificationService::new_with_defaults();

                // Test info method
                service.info(&title, &message, user_id.clone()).await.unwrap();

                // Test warning method
                service.warning(&title, &message, user_id.clone()).await.unwrap();

                // Test success method
                service.success(&title, &message, user_id.clone()).await.unwrap();

                // Test error method
                service.error(&title, &message, user_id.clone()).await.unwrap();

                // Verify notifications were created with correct levels
                let notifications = if let Some(user_id) = &user_id {
                    service.get_user_notifications(user_id).await
                } else {
                    service.get_global_notifications().await
                };

                // There should be 4 notifications, one for each level
                prop_assert_eq!(notifications.len(), 4);

                // Verify one notification of each level exists
                let levels: HashSet<NotificationLevel> = notifications.iter().map(|n| n.level).collect();
                prop_assert!(levels.contains(&NotificationLevel::Info));
                prop_assert!(levels.contains(&NotificationLevel::Warning));
                prop_assert!(levels.contains(&NotificationLevel::Success));
                prop_assert!(levels.contains(&NotificationLevel::Error));
            });
        }

        /// Test max notifications per user limit
        #[test]
        fn test_max_notifications_limit(user_id in uuid::Uuid::new_v4().to_string()) {
            block_on(async {
                let config = NotificationConfig {
                    max_notifications_per_user: 5,
                    default_expiration_hours: 24,
                    cleanup_interval_minutes: 60,
                };

                let service = NotificationService::new(config);

                // Add more notifications than the limit
                for i in 0..10 {
                    let notification = Notification::new(
                        format!("Title {}", i),
                        format!("Message {}", i),
                        NotificationLevel::Info,
                        Some(user_id.clone()),
                    );

                    service.add_user_notification(notification).await.unwrap();
                }

                // Verify only max_notifications_per_user notifications were kept
                let notifications = service.get_user_notifications(&user_id).await;
                prop_assert_eq!(notifications.len(), 5);

                // Verify the oldest notifications were removed (notifications should be sorted by creation time, newest first)
                // The IDs of the notifications should be from the higher i values (5-9)
                for notification in notifications {
                    let title = notification.title;
                    let i = title.split_whitespace().last().unwrap().parse::<i32>().unwrap();
                    prop_assert!(i >= 5);
                }
            });
        }
    }

    #[test]
    fn test_notification_level_css_class() {
        assert_eq!(NotificationLevel::Info.as_css_class(), "info");
        assert_eq!(NotificationLevel::Warning.as_css_class(), "warning");
        assert_eq!(NotificationLevel::Success.as_css_class(), "success");
        assert_eq!(NotificationLevel::Error.as_css_class(), "error");
    }

    #[test]
    fn test_non_dismissible_notifications() {
        block_on(async {
            let service = NotificationService::new_with_defaults();

            // Create a non-dismissible notification
            let notification = Notification::new(
                "Title".to_string(),
                "Message".to_string(),
                NotificationLevel::Info,
                None,
            ).with_dismissible(false);

            service.add_global_notification(notification.clone()).await.unwrap();

            // Attempt to dismiss should fail
            let result = service.dismiss_notification(&notification.id, None).await;
            assert!(result.is_err());
        });
    }
}
