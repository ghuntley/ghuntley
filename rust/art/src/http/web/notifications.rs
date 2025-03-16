//! Notifications UI handlers and components for displaying notifications to users

use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
};
use serde::Deserialize;

use crate::{
    error::Result,
    http::ServerState,
    service::notification::{Notification, NotificationLevel},
};

/// Handler for the notification center page
pub async fn notification_center_handler(
    State(state): State<ServerState>,
) -> Result<impl IntoResponse> {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Get notifications
    let notifications = if let Some(user_id) = &user_id {
        notification_service.get_user_notifications(user_id).await
    } else {
        notification_service.get_global_notifications().await
    };

    // Render the notification center
    let html = render_notification_center(&notifications);

    Ok(html)
}

/// Render the notification center page
fn render_notification_center(notifications: &[Notification]) -> String {
    let mut html = String::from(r#"
        <div class="notification-center">
            <h1>Notification Center</h1>
            <div class="notification-filters">
                <button class="filter active" data-filter="all">All</button>
                <button class="filter" data-filter="unread">Unread</button>
                <button class="filter" data-filter="info">Info</button>
                <button class="filter" data-filter="warning">Warning</button>
                <button class="filter" data-filter="success">Success</button>
                <button class="filter" data-filter="error">Error</button>
            </div>
            <div class="notification-list">
    "#);

    if notifications.is_empty() {
        html.push_str(r#"
            <div class="no-notifications">
                <p>No notifications to display</p>
            </div>
        "#);
    } else {
        for notification in notifications {
            html.push_str(&render_notification_item(notification));
        }
    }

    html.push_str(r#"
            </div>
            <div class="notification-actions">
                <button id="mark-all-read" class="btn">Mark All as Read</button>
                <button id="dismiss-all" class="btn">Dismiss All</button>
            </div>
        </div>
        <script>
            // Filter notifications
            document.querySelectorAll('.filter').forEach(button => {
                button.addEventListener('click', function() {
                    // Update active filter
                    document.querySelectorAll('.filter').forEach(b => b.classList.remove('active'));
                    this.classList.add('active');

                    const filter = this.dataset.filter;
                    const items = document.querySelectorAll('.notification-item');

                    items.forEach(item => {
                        if (filter === 'all') {
                            item.style.display = 'flex';
                        } else if (filter === 'unread') {
                            item.style.display = item.classList.contains('unread') ? 'flex' : 'none';
                        } else {
                            item.style.display = item.classList.contains(filter) ? 'flex' : 'none';
                        }
                    });
                });
            });

            // Mark notification as read
            document.querySelectorAll('.mark-read').forEach(button => {
                button.addEventListener('click', async function(e) {
                    e.stopPropagation();
                    const id = this.closest('.notification-item').dataset.id;

                    try {
                        const response = await fetch(`/api/notifications/${id}/read`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        });

                        if (response.ok) {
                            this.closest('.notification-item').classList.remove('unread');
                            this.textContent = 'Read';
                        }
                    } catch (error) {
                        console.error('Error marking notification as read:', error);
                    }
                });
            });

            // Dismiss notification
            document.querySelectorAll('.dismiss').forEach(button => {
                button.addEventListener('click', async function(e) {
                    e.stopPropagation();
                    const item = this.closest('.notification-item');
                    const id = item.dataset.id;

                    try {
                        const response = await fetch(`/api/notifications/${id}/dismiss`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        });

                        if (response.ok) {
                            item.remove();
                        }
                    } catch (error) {
                        console.error('Error dismissing notification:', error);
                    }
                });
            });

            // Mark all as read
            document.getElementById('mark-all-read').addEventListener('click', async function() {
                const unreadItems = document.querySelectorAll('.notification-item.unread');

                for (const item of unreadItems) {
                    const id = item.dataset.id;

                    try {
                        const response = await fetch(`/api/notifications/${id}/read`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        });

                        if (response.ok) {
                            item.classList.remove('unread');
                            item.querySelector('.mark-read').textContent = 'Read';
                        }
                    } catch (error) {
                        console.error('Error marking notification as read:', error);
                    }
                }
            });

            // Dismiss all
            document.getElementById('dismiss-all').addEventListener('click', async function() {
                const items = document.querySelectorAll('.notification-item');

                for (const item of items) {
                    if (!item.querySelector('.dismiss')) continue; // Skip non-dismissible

                    const id = item.dataset.id;

                    try {
                        const response = await fetch(`/api/notifications/${id}/dismiss`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        });

                        if (response.ok) {
                            item.remove();
                        }
                    } catch (error) {
                        console.error('Error dismissing notification:', error);
                    }
                }
            });

            // Handle notification click (for notifications with target URL)
            document.querySelectorAll('.notification-item').forEach(item => {
                if (item.dataset.url) {
                    item.addEventListener('click', function() {
                        window.location.href = this.dataset.url;
                    });
                }
            });
        </script>
    "#);

    html
}

/// Render a single notification item
fn render_notification_item(notification: &Notification) -> String {
    let level_class = notification.level.as_css_class();
    let read_class = if notification.read { "" } else { "unread" };
    let dismissible = notification.dismissible;
    let target_url = notification.target_url.as_deref().unwrap_or("");

    let created_at = notification.created_at.format("%Y-%m-%d %H:%M:%S").to_string();

    let expires_text = if let Some(expires_at) = notification.expires_at {
        let now = chrono::Utc::now();
        if expires_at > now {
            let duration = expires_at - now;
            let hours = duration.num_hours();
            let minutes = duration.num_minutes() % 60;

            if hours > 0 {
                format!("Expires in {} hour{} {} minute{}",
                    hours,
                    if hours == 1 { "" } else { "s" },
                    minutes,
                    if minutes == 1 { "" } else { "s" }
                )
            } else {
                format!("Expires in {} minute{}",
                    minutes,
                    if minutes == 1 { "" } else { "s" }
                )
            }
        } else {
            "Expired".to_string()
        }
    } else {
        "Never expires".to_string()
    };

    let read_button_text = if notification.read { "Read" } else { "Mark as read" };

    format!(r#"
        <div class="notification-item {level_class} {read_class}" data-id="{id}" data-url="{target_url}">
            <div class="notification-icon">
                <i class="icon-{level_class}"></i>
            </div>
            <div class="notification-content">
                <div class="notification-header">
                    <h3 class="notification-title">{title}</h3>
                    <span class="notification-time">{created_at}</span>
                </div>
                <div class="notification-message">{message}</div>
                <div class="notification-footer">
                    <span class="notification-expiry">{expires_text}</span>
                    <div class="notification-actions">
                        <button class="mark-read">{read_button_text}</button>
                        {dismiss_button}
                    </div>
                </div>
            </div>
        </div>
    "#,
    level_class = level_class,
    read_class = read_class,
    id = notification.id,
    target_url = target_url,
    title = notification.title,
    message = notification.message,
    created_at = created_at,
    expires_text = expires_text,
    read_button_text = read_button_text,
    dismiss_button = if dismissible {
        r#"<button class="dismiss">Dismiss</button>"#
    } else {
        ""
    })
}

/// Render a notification banner for inclusion in page layouts
pub async fn render_notification_banner(state: &ServerState) -> String {
    // Get notification service
    let notification_service = state.app.notification_service.clone();

    // Get user ID from session (if available)
    let user_id = match state.get_current_user().await {
        Some(user) => Some(user.id.to_string()),
        None => None,
    };

    // Get notifications
    let notifications = if let Some(user_id) = &user_id {
        notification_service.get_user_notifications(user_id).await
    } else {
        notification_service.get_global_notifications().await
    };

    // Only include unread notifications
    let unread_notifications: Vec<_> = notifications.iter().filter(|n| !n.read).collect();
    let unread_count = unread_notifications.len();

    if unread_count == 0 {
        // No unread notifications, return empty string
        return String::new();
    }

    // Render the notification banner with the most recent unread notification
    let notification = unread_notifications[0];
    let level_class = notification.level.as_css_class();

    format!(r#"
        <div class="notification-banner {level_class}">
            <div class="notification-banner-content">
                <div class="notification-banner-icon">
                    <i class="icon-{level_class}"></i>
                </div>
                <div class="notification-banner-text">
                    <strong>{title}</strong> {message}
                </div>
                <div class="notification-banner-actions">
                    <a href="/notifications" class="btn">View {unread_count} notification{s}</a>
                    <button class="dismiss-banner">×</button>
                </div>
            </div>
        </div>
        <script>
            // Dismiss notification banner
            document.querySelector('.dismiss-banner').addEventListener('click', function() {
                document.querySelector('.notification-banner').style.display = 'none';
            });
        </script>
    "#,
    level_class = level_class,
    title = notification.title,
    message = notification.message,
    unread_count = unread_count,
    s = if unread_count == 1 { "" } else { "s" }
    )
}

/// CSS styles for notifications
pub fn notification_styles() -> &'static str {
    r#"
    /* Notification Banner */
    .notification-banner {
        position: sticky;
        top: 0;
        left: 0;
        width: 100%;
        padding: 10px 20px;
        z-index: 100;
        font-size: 14px;
        border-bottom: 1px solid rgba(0, 0, 0, 0.1);
    }

    .notification-banner.info {
        background-color: #e3f2fd;
        color: #0288d1;
    }

    .notification-banner.success {
        background-color: #e8f5e9;
        color: #2e7d32;
    }

    .notification-banner.warning {
        background-color: #fff8e1;
        color: #ff8f00;
    }

    .notification-banner.error {
        background-color: #ffebee;
        color: #c62828;
    }

    .notification-banner-content {
        display: flex;
        align-items: center;
        max-width: 1200px;
        margin: 0 auto;
    }

    .notification-banner-icon {
        margin-right: 15px;
    }

    .notification-banner-text {
        flex: 1;
    }

    .notification-banner-actions {
        display: flex;
        align-items: center;
    }

    .notification-banner-actions .btn {
        margin-right: 10px;
        padding: 5px 10px;
        border-radius: 4px;
        background-color: rgba(0, 0, 0, 0.1);
        color: inherit;
        text-decoration: none;
        font-size: 12px;
    }

    .dismiss-banner {
        background: none;
        border: none;
        font-size: 20px;
        cursor: pointer;
        color: inherit;
        opacity: 0.7;
    }

    .dismiss-banner:hover {
        opacity: 1;
    }

    /* Notification Center */
    .notification-center {
        max-width: 800px;
        margin: 20px auto;
        padding: 20px;
        background-color: #fff;
        border-radius: 8px;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
    }

    .notification-center h1 {
        margin-top: 0;
        margin-bottom: 20px;
        font-size: 24px;
        color: #333;
    }

    .notification-filters {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-bottom: 20px;
    }

    .notification-filters .filter {
        background: none;
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 8px 12px;
        cursor: pointer;
        font-size: 14px;
        transition: all 0.2s;
    }

    .notification-filters .filter:hover {
        background-color: #f5f5f5;
    }

    .notification-filters .filter.active {
        background-color: #2196f3;
        color: white;
        border-color: #2196f3;
    }

    .notification-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-bottom: 20px;
    }

    .no-notifications {
        padding: 40px;
        text-align: center;
        color: #666;
        font-style: italic;
    }

    .notification-item {
        display: flex;
        border-radius: 6px;
        overflow: hidden;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
        transition: all 0.2s;
    }

    .notification-item.unread {
        border-left: 3px solid #2196f3;
    }

    .notification-item[data-url] {
        cursor: pointer;
    }

    .notification-item[data-url]:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.15);
    }

    .notification-item.info {
        background-color: #f1f8fe;
    }

    .notification-item.success {
        background-color: #f1fbf1;
    }

    .notification-item.warning {
        background-color: #fffcf1;
    }

    .notification-item.error {
        background-color: #fef1f1;
    }

    .notification-icon {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 50px;
        background-color: rgba(0, 0, 0, 0.03);
    }

    .notification-icon .icon-info {
        color: #2196f3;
    }

    .notification-icon .icon-success {
        color: #4caf50;
    }

    .notification-icon .icon-warning {
        color: #ff9800;
    }

    .notification-icon .icon-error {
        color: #f44336;
    }

    .notification-content {
        flex: 1;
        padding: 15px;
    }

    .notification-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 5px;
    }

    .notification-title {
        margin: 0;
        font-size: 16px;
        font-weight: 600;
        color: #333;
    }

    .notification-time {
        font-size: 12px;
        color: #666;
    }

    .notification-message {
        margin-bottom: 10px;
        color: #555;
    }

    .notification-footer {
        display: flex;
        justify-content: space-between;
        align-items: center;
    }

    .notification-expiry {
        font-size: 12px;
        color: #999;
    }

    .notification-footer .notification-actions {
        display: flex;
        gap: 8px;
    }

    .notification-footer button {
        background: none;
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 4px 8px;
        font-size: 12px;
        cursor: pointer;
    }

    .notification-footer .mark-read:hover {
        background-color: #e3f2fd;
    }

    .notification-footer .dismiss:hover {
        background-color: #ffebee;
    }

    .notification-actions .btn {
        padding: 8px 16px;
        border: none;
        border-radius: 4px;
        background-color: #2196f3;
        color: white;
        cursor: pointer;
        font-size: 14px;
        margin-right: 10px;
    }

    .notification-actions .btn:hover {
        background-color: #1976d2;
    }

    /* Mobile responsiveness */
    @media (max-width: 600px) {
        .notification-banner-content {
            flex-direction: column;
            align-items: flex-start;
        }

        .notification-banner-icon {
            margin-bottom: 5px;
        }

        .notification-banner-text {
            margin-bottom: 10px;
        }

        .notification-item {
            flex-direction: column;
        }

        .notification-icon {
            width: 100%;
            height: 30px;
        }

        .notification-header {
            flex-direction: column;
        }

        .notification-footer {
            flex-direction: column;
            align-items: flex-start;
        }

        .notification-expiry {
            margin-bottom: 5px;
        }
    }

    /* Dark mode */
    .dark-mode .notification-center {
        background-color: #2d2d2d;
    }

    .dark-mode .notification-center h1 {
        color: #e0e0e0;
    }

    .dark-mode .notification-filters .filter {
        border-color: #444;
        color: #e0e0e0;
    }

    .dark-mode .notification-filters .filter:hover {
        background-color: #444;
    }

    .dark-mode .notification-filters .filter.active {
        background-color: #2196f3;
    }

    .dark-mode .notification-item {
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
    }

    .dark-mode .notification-item.info {
        background-color: #1a2737;
    }

    .dark-mode .notification-item.success {
        background-color: #1a2e1d;
    }

    .dark-mode .notification-item.warning {
        background-color: #332a1a;
    }

    .dark-mode .notification-item.error {
        background-color: #331a1a;
    }

    .dark-mode .notification-title {
        color: #e0e0e0;
    }

    .dark-mode .notification-message {
        color: #bbb;
    }

    .dark-mode .notification-time,
    .dark-mode .notification-expiry {
        color: #888;
    }

    .dark-mode .notification-footer button {
        border-color: #444;
        color: #e0e0e0;
    }
    "#
}
