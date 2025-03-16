//! Base template for all pages

use askama::Template;

/// Base template context for all pages
#[derive(Template)]
#[template(path = "base.html")]
pub struct BaseTemplate {
    /// Page title
    pub title: String,

    /// Page description
    pub description: String,

    /// Base URL for the application
    pub base_url: String,

    /// Current active path for navigation highlighting
    pub current_path: String,

    /// Current repository (if any)
    pub current_repo: Option<String>,

    /// Notification banner HTML (if any)
    pub notification_banner: Option<String>,
}

/// Base page for any content page
pub trait BasePage {
    /// Get the page title
    fn get_title(&self) -> &str;

    /// Get the page content
    fn get_content(&self) -> String;

    /// Get the body classes
    fn get_body_classes(&self) -> Option<&str> {
        None
    }

    /// Get additional head content
    fn get_head(&self) -> Option<String> {
        None
    }

    /// Render the page as a base template
    fn as_base_template(&self) -> BaseTemplate {
        BaseTemplate {
            title: self.get_title().to_string(),
            description: String::new(),
            base_url: String::new(),
            current_path: String::new(),
            current_repo: None,
            notification_banner: None,
        }
    }
}
