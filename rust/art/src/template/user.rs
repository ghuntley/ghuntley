//! User management templates

use crate::data::user::{User, UserRole};
use crate::template::BaseTemplate;
use askama::Template;
use std::sync::Arc;

/// User login template
#[derive(Template)]
#[template(path = "user/login.html")]
pub struct LoginTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// Error message if login failed
    pub error: Option<String>,
}

/// User registration template
#[derive(Template)]
#[template(path = "user/register.html")]
pub struct RegisterTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// Error message if registration failed
    pub error: Option<String>,
}

/// User profile template
#[derive(Template)]
#[template(path = "user/profile.html")]
pub struct UserProfileTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// User data
    pub user: User,

    /// Error message if update failed
    pub error: Option<String>,

    /// Success message if update succeeded
    pub success: Option<String>,
}

/// User management template (admin only)
#[derive(Template)]
#[template(path = "user/management.html")]
pub struct UserManagementTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// List of users
    pub users: Vec<User>,

    /// Error message
    pub error: Option<String>,

    /// Success message
    pub success: Option<String>,

    /// Current page number
    pub page: usize,

    /// Total number of pages
    pub total_pages: usize,

    /// Page size
    pub page_size: usize,
}

/// Create user template (admin only)
#[derive(Template)]
#[template(path = "user/create.html")]
pub struct CreateUserTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// Error message
    pub error: Option<String>,
}

/// Edit user template (admin only)
#[derive(Template)]
#[template(path = "user/edit.html")]
pub struct EditUserTemplate {
    /// Base template
    pub base: BaseTemplate,

    /// User data
    pub user: User,

    /// Error message
    pub error: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::template::TemplateRender;

    #[test]
    fn test_login_template() {
        let base = BaseTemplate {
            title: "Login".to_string(),
            description: "Login to Art".to_string(),
            base_url: "/".to_string(),
            current_path: "/login".to_string(),
            current_repo: None,
        };

        let template = LoginTemplate {
            base,
            error: Some("Invalid username or password".to_string()),
        };

        let result = template.render_to_string();
        assert!(result.is_ok());
    }

    // Additional tests can be added here
}
