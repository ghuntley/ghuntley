//! Template rendering module

use crate::error::{Error, Result};
use askama::Template;

mod base;
mod repo;
mod commit;
mod file;
mod filters;
mod search;
mod user;
mod maintenance;

pub use base::*;
pub use repo::*;
pub use commit::*;
pub use file::*;
pub use filters::*;
pub use search::*;
pub use user::*;
pub use maintenance::*;

/// Helper trait for rendering templates
pub trait TemplateRender {
    /// Render the template to a string
    fn render_to_string(&self) -> Result<String>;
}

impl<T: Template> TemplateRender for T {
    fn render_to_string(&self) -> Result<String> {
        self.render().map_err(Error::Template)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use askama::Template;

    #[derive(Template)]
    #[template(path = "test.html", escape = "none")]
    struct TestTemplate {
        title: String,
        content: String,
    }

    impl Template for TestTemplate {
        fn render(&self) -> askama::Result<String> {
            Ok(format!("<h1>{}</h1><div>{}</div>", self.title, self.content))
        }
    }

    #[test]
    fn test_template_render() {
        let template = TestTemplate {
            title: "Test Title".to_string(),
            content: "Test Content".to_string(),
        };

        let result = template.render_to_string();
        assert!(result.is_ok());

        let html = result.unwrap();
        assert!(html.contains("Test Title"));
        assert!(html.contains("Test Content"));
    }

    #[test]
    fn test_template_error_handling() {
        struct ErrorTemplate;

        impl Template for ErrorTemplate {
            fn render(&self) -> askama::Result<String> {
                Err(askama::Error::Custom("Test error".to_string()))
            }
        }

        let template = ErrorTemplate;
        let result = template.render_to_string();
        assert!(result.is_err());
    }
}
