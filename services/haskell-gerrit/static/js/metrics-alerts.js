/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Alert notification system
class AlertNotification {
    constructor() {
        this.container = this.createContainer();
        this.alerts = new Map();
    }

    createContainer() {
        const container = document.createElement('div');
        container.className = 'alert-notification-container';
        document.body.appendChild(container);
        return container;
    }

    show(alert) {
        const { id, severity, title, message, timestamp } = alert;

        // Create notification element
        const notification = document.createElement('div');
        notification.className = `alert-notification ${severity}`;
        notification.innerHTML = `
            <div class="alert-header">
                <span class="alert-title">${title}</span>
                <button class="close-btn">&times;</button>
            </div>
            <div class="alert-message">${message}</div>
            <div class="alert-timestamp">${formatTimestamp(timestamp)}</div>
            <div class="alert-progress"></div>
        `;

        // Add close button handler
        const closeBtn = notification.querySelector('.close-btn');
        closeBtn.addEventListener('click', () => this.dismiss(id));

        // Add to container
        this.container.appendChild(notification);
        this.alerts.set(id, notification);

        // Add progress bar animation
        const progress = notification.querySelector('.alert-progress');
        progress.style.animation = 'alert-progress 5s linear';

        // Auto dismiss after 5 seconds
        setTimeout(() => this.dismiss(id), 5000);

        // Add fade in animation
        notification.style.animation = 'alert-slide-in 0.3s ease-out';
    }

    dismiss(id) {
        const notification = this.alerts.get(id);
        if (notification) {
            notification.style.animation = 'alert-slide-out 0.3s ease-out';
            setTimeout(() => {
                notification.remove();
                this.alerts.delete(id);
            }, 300);
        }
    }

    dismissAll() {
        this.alerts.forEach((_, id) => this.dismiss(id));
    }

    updateAlerts(alerts) {
        // Remove old alerts that are no longer active
        const activeIds = new Set(alerts.map(a => a.id));
        this.alerts.forEach((_, id) => {
            if (!activeIds.has(id)) {
                this.dismiss(id);
            }
        });

        // Add or update current alerts
        alerts.forEach(alert => {
            if (!this.alerts.has(alert.id)) {
                this.show(alert);
            }
        });
    }
}

// Alert severity styles
const severityStyles = {
    critical: {
        background: '#dc3545',
        color: '#fff'
    },
    warning: {
        background: '#ffc107',
        color: '#000'
    },
    info: {
        background: '#17a2b8',
        color: '#fff'
    }
};

// Initialize alert notification system
let alertSystem;
document.addEventListener('DOMContentLoaded', () => {
    alertSystem = new AlertNotification();
});

// Update alert notifications
function updateAlertNotifications(alerts) {
    if (alertSystem) {
        alertSystem.updateAlerts(alerts);
    }
}

// Format alert timestamp
function formatAlertTimestamp(timestamp) {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now - date;

    if (diff < 60000) { // Less than 1 minute
        return 'Just now';
    } else if (diff < 3600000) { // Less than 1 hour
        const minutes = Math.floor(diff / 60000);
        return `${minutes} minute${minutes > 1 ? 's' : ''} ago`;
    } else if (diff < 86400000) { // Less than 1 day
        const hours = Math.floor(diff / 3600000);
        return `${hours} hour${hours > 1 ? 's' : ''} ago`;
    } else {
        return date.toLocaleString();
    }
}

// Export functions
window.MetricsAlerts = {
    updateAlertNotifications,
    formatAlertTimestamp
};
