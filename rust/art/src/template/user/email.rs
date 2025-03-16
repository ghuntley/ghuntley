//! User email settings template
//!
//! This module provides templates for user email settings.

use askama::Template;

use crate::service::user::User;
use crate::template::base::BasePage;

/// Template for user email settings
#[derive(Template)]
#[template(path = "user/email_settings.html")]
pub struct UserEmailSettingsTemplate {
    /// User
    pub user: User,

    /// Whether email service is enabled
    pub email_service_enabled: bool,

    /// Success message
    pub success_message: Option<String>,

    /// Error message
    pub error_message: Option<String>,
}

impl UserEmailSettingsTemplate {
    /// Create a new user email settings template
    pub fn new(user: User, email_service_enabled: bool) -> Self {
        Self {
            user,
            email_service_enabled,
            success_message: None,
            error_message: None,
        }
    }

    /// Create a new user email settings template with a success message
    pub fn new_with_message(user: User, email_service_enabled: bool, message: &str) -> Self {
        Self {
            user,
            email_service_enabled,
            success_message: Some(message.to_string()),
            error_message: None,
        }
    }

    /// Create a new user email settings template with an error message
    pub fn new_with_error(user: User, email_service_enabled: bool, error: &str) -> Self {
        Self {
            user,
            email_service_enabled,
            success_message: None,
            error_message: Some(error.to_string()),
        }
    }
}

impl BasePage for UserEmailSettingsTemplate {
    fn get_title(&self) -> &str {
        "Email Settings - Art"
    }

    fn get_content(&self) -> String {
        use askama::Template;
        self.render().unwrap_or_else(|_| String::from("Error rendering template"))
    }

    fn get_body_classes(&self) -> Option<&str> {
        Some("user-settings email-settings")
    }
}
