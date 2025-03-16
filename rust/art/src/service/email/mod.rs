//! Email service for sending emails from the Art application
//!
//! This module provides functionality for sending emails using SMTP,
//! including templated emails for common scenarios like account verification,
//! password reset, and notifications.

use lettre::{
    message::{header, MultiPart, SinglePart},
    transport::smtp::{authentication::Credentials, client::TlsParameters},
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
};
use lettre::transport::smtp::Error as SmtpError;
use lettre::message::header::ContentType;

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc};

use crate::error::{Error, Result};

/// Configuration for the email service
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EmailConfig {
    /// Whether email sending is enabled
    pub enabled: bool,

    /// SMTP server hostname
    pub smtp_server: String,

    /// SMTP server port
    pub smtp_port: u16,

    /// SMTP username
    pub smtp_username: String,

    /// SMTP password
    pub smtp_password: String,

    /// Whether to use TLS
    pub use_tls: bool,

    /// From email address
    pub from_address: String,

    /// From name
    pub from_name: String,

    /// Reply-to email address (optional)
    pub reply_to: Option<String>,

    /// Maximum retries for sending an email
    pub max_retries: u32,

    /// Retry delay in seconds
    pub retry_delay_seconds: u64,
}

impl Default for EmailConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            smtp_server: "smtp.example.com".to_string(),
            smtp_port: 587,
            smtp_username: "username".to_string(),
            smtp_password: "password".to_string(),
            use_tls: true,
            from_address: "noreply@example.com".to_string(),
            from_name: "Art Git Browser".to_string(),
            reply_to: None,
            max_retries: 3,
            retry_delay_seconds: 60,
        }
    }
}

/// Represents an email template with variables
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailTemplate {
    /// Name of the template
    pub name: String,

    /// Subject of the email
    pub subject: String,

    /// Plain text content
    pub text_content: String,

    /// HTML content (optional)
    pub html_content: Option<String>,
}

/// Email priority level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EmailPriority {
    /// High priority email
    High,

    /// Normal priority email
    Normal,

    /// Low priority email
    Low,
}

/// Email delivery status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EmailDeliveryStatus {
    /// Email is queued for delivery
    Queued,

    /// Email is being sent
    Sending,

    /// Email was delivered successfully
    Delivered,

    /// Email delivery failed
    Failed,
}

/// Email details
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Email {
    /// Unique ID for the email
    pub id: String,

    /// Email recipient
    pub to: String,

    /// Email subject
    pub subject: String,

    /// Text content
    pub text_content: String,

    /// HTML content (optional)
    pub html_content: Option<String>,

    /// CC recipients (optional)
    pub cc: Option<Vec<String>>,

    /// BCC recipients (optional)
    pub bcc: Option<Vec<String>>,

    /// Reply-to address (optional)
    pub reply_to: Option<String>,

    /// Email priority
    pub priority: EmailPriority,

    /// Attachments (file paths)
    pub attachments: Vec<String>,

    /// When the email was created
    pub created_at: DateTime<Utc>,

    /// When the email was last updated
    pub updated_at: DateTime<Utc>,

    /// Current delivery status
    pub status: EmailDeliveryStatus,

    /// Number of delivery attempts
    pub delivery_attempts: u32,

    /// Error message if delivery failed
    pub error_message: Option<String>,
}

impl Email {
    /// Create a new email
    pub fn new(
        to: String,
        subject: String,
        text_content: String,
        html_content: Option<String>,
    ) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            to,
            subject,
            text_content,
            html_content,
            cc: None,
            bcc: None,
            reply_to: None,
            priority: EmailPriority::Normal,
            attachments: Vec::new(),
            created_at: now,
            updated_at: now,
            status: EmailDeliveryStatus::Queued,
            delivery_attempts: 0,
            error_message: None,
        }
    }

    /// Set CC recipients
    pub fn with_cc(mut self, cc: Vec<String>) -> Self {
        self.cc = Some(cc);
        self
    }

    /// Set BCC recipients
    pub fn with_bcc(mut self, bcc: Vec<String>) -> Self {
        self.bcc = Some(bcc);
        self
    }

    /// Set reply-to address
    pub fn with_reply_to(mut self, reply_to: String) -> Self {
        self.reply_to = Some(reply_to);
        self
    }

    /// Set email priority
    pub fn with_priority(mut self, priority: EmailPriority) -> Self {
        self.priority = priority;
        self
    }

    /// Add an attachment
    pub fn with_attachment(mut self, attachment: String) -> Self {
        self.attachments.push(attachment);
        self
    }
}

/// Service for sending emails
pub struct EmailService {
    /// Configuration for the email service
    config: EmailConfig,

    /// SMTP transport
    mailer: Option<AsyncSmtpTransport<Tokio1Executor>>,

    /// Email queue for retrying failed emails
    email_queue: RwLock<Vec<Email>>,

    /// Email templates
    templates: RwLock<Vec<EmailTemplate>>,
}

impl EmailService {
    /// Create a new email service with the given configuration
    pub fn new(config: EmailConfig) -> Self {
        let mailer = if config.enabled {
            let creds = Credentials::new(
                config.smtp_username.clone(),
                config.smtp_password.clone(),
            );

            let mailer_builder = if config.use_tls {
                AsyncSmtpTransport::<Tokio1Executor>::relay(&config.smtp_server)
                    .unwrap()
                    .credentials(creds)
                    .port(config.smtp_port)
            } else {
                AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&config.smtp_server)
                    .credentials(creds)
                    .port(config.smtp_port)
            };

            Some(mailer_builder.build())
        } else {
            None
        };

        Self {
            config,
            mailer,
            email_queue: RwLock::new(Vec::new()),
            templates: RwLock::new(Vec::new()),
        }
    }

    /// Send an email
    pub async fn send_email(&self, email: Email) -> Result<()> {
        if !self.config.enabled {
            return Err(Error::ConfigurationError("Email service is disabled".to_string()));
        }

        let mut email_message_builder = Message::builder()
            .from(format!("{} <{}>", self.config.from_name, self.config.from_address).parse().map_err(|e| Error::EmailError(format!("Invalid from address: {}", e)))?)
            .to(email.to.parse().map_err(|e| Error::EmailError(format!("Invalid to address: {}", e)))?)
            .subject(email.subject.clone());

        // Add CC recipients if specified
        if let Some(cc) = &email.cc {
            for cc_addr in cc {
                email_message_builder = email_message_builder.cc(cc_addr.parse().map_err(|e| Error::EmailError(format!("Invalid CC address: {}", e)))?);
            }
        }

        // Add BCC recipients if specified
        if let Some(bcc) = &email.bcc {
            for bcc_addr in bcc {
                email_message_builder = email_message_builder.bcc(bcc_addr.parse().map_err(|e| Error::EmailError(format!("Invalid BCC address: {}", e)))?);
            }
        }

        // Add reply-to if specified
        let reply_to = email.reply_to.clone().or_else(|| self.config.reply_to.clone());
        if let Some(reply_to) = reply_to {
            email_message_builder = email_message_builder.reply_to(reply_to.parse().map_err(|e| Error::EmailError(format!("Invalid reply-to address: {}", e)))?);
        }

        // Set priority header if specified
        match email.priority {
            EmailPriority::High => {
                email_message_builder = email_message_builder.header(header::Priority::Urgent);
            }
            EmailPriority::Normal => {
                email_message_builder = email_message_builder.header(header::Priority::Normal);
            }
            EmailPriority::Low => {
                email_message_builder = email_message_builder.header(header::Priority::NonUrgent);
            }
        }

        // Build the email body
        let email_message = if let Some(html_content) = email.html_content {
            // Create a multipart email with both text and HTML content
            email_message_builder
                .multipart(
                    MultiPart::alternative()
                        .singlepart(
                            SinglePart::builder()
                                .header(ContentType::TEXT_PLAIN)
                                .body(email.text_content.clone())
                        )
                        .singlepart(
                            SinglePart::builder()
                                .header(ContentType::TEXT_HTML)
                                .body(html_content)
                        )
                )
                .map_err(|e| Error::EmailError(format!("Failed to build email: {}", e)))?
        } else {
            // Create a simple text-only email
            email_message_builder
                .header(ContentType::TEXT_PLAIN)
                .body(email.text_content.clone())
                .map_err(|e| Error::EmailError(format!("Failed to build email: {}", e)))?
        };

        // Send the email
        match &self.mailer {
            Some(mailer) => {
                match mailer.send(email_message).await {
                    Ok(_) => Ok(()),
                    Err(e) => {
                        // Add to retry queue if delivery failed
                        let mut email_clone = email.clone();
                        email_clone.delivery_attempts += 1;
                        email_clone.status = EmailDeliveryStatus::Failed;
                        email_clone.error_message = Some(format!("{}", e));
                        email_clone.updated_at = Utc::now();

                        if email_clone.delivery_attempts < self.config.max_retries {
                            let mut queue = self.email_queue.write().await;
                            queue.push(email_clone);
                        }

                        Err(Error::EmailError(format!("Failed to send email: {}", e)))
                    }
                }
            }
            None => Err(Error::ConfigurationError("Email transport not initialized".to_string())),
        }
    }

    /// Check enabled status
    pub fn is_enabled(&self) -> bool {
        self.config.enabled
    }

    /// Add a template to the email service
    pub async fn add_template(&self, template: EmailTemplate) -> Result<()> {
        let mut templates = self.templates.write().await;

        // Check if template with the same name already exists
        if templates.iter().any(|t| t.name == template.name) {
            return Err(Error::DuplicateResource(format!("Email template with name '{}' already exists", template.name)));
        }

        templates.push(template);
        Ok(())
    }

    /// Get a template by name
    pub async fn get_template(&self, name: &str) -> Result<EmailTemplate> {
        let templates = self.templates.read().await;

        templates
            .iter()
            .find(|t| t.name == name)
            .cloned()
            .ok_or_else(|| Error::NotFound(format!("Email template '{}' not found", name)))
    }

    /// Render a template with variables and send it as an email
    pub async fn send_template_email(
        &self,
        template_name: &str,
        to: String,
        variables: &serde_json::Value,
    ) -> Result<()> {
        if !self.is_enabled() {
            return Err(Error::ConfigurationError("Email service is disabled".to_string()));
        }

        // Get the template
        let template = self.get_template(template_name).await?;

        // Render the template
        let rendered_subject = self.render_template_string(&template.subject, variables)?;
        let rendered_text = self.render_template_string(&template.text_content, variables)?;
        let rendered_html = match &template.html_content {
            Some(html) => Some(self.render_template_string(html, variables)?),
            None => None,
        };

        // Create and send the email
        let email = Email::new(
            to,
            rendered_subject,
            rendered_text,
            rendered_html,
        );

        self.send_email(email).await
    }

    /// Render a template string with variables
    fn render_template_string(&self, template: &str, variables: &serde_json::Value) -> Result<String> {
        let mut handlebars = handlebars::Handlebars::new();
        handlebars.register_template_string("temp", template).map_err(|e| {
            Error::TemplateError(format!("Failed to register template: {}", e))
        })?;

        handlebars.render("temp", variables).map_err(|e| {
            Error::TemplateError(format!("Failed to render template: {}", e))
        })
    }

    /// Process the email queue, retrying failed emails
    pub async fn process_queue(&self) -> Result<()> {
        if !self.is_enabled() {
            return Ok(());
        }

        let mut queue = self.email_queue.write().await;
        let mut remaining_emails = Vec::new();

        for mut email in queue.drain(..) {
            // Skip emails that have reached the max retry count
            if email.delivery_attempts >= self.config.max_retries {
                continue;
            }

            // Try to send the email
            let email_clone = email.clone();
            match self.send_email(email_clone).await {
                Ok(_) => {
                    // Email sent successfully, update status
                    email.status = EmailDeliveryStatus::Delivered;
                    email.updated_at = Utc::now();
                }
                Err(e) => {
                    // Email delivery failed again, increment attempt count and keep in queue
                    email.delivery_attempts += 1;
                    email.error_message = Some(format!("{}", e));
                    email.updated_at = Utc::now();

                    if email.delivery_attempts < self.config.max_retries {
                        remaining_emails.push(email);
                    }
                }
            }
        }

        // Update queue with remaining emails
        *queue = remaining_emails;

        Ok(())
    }

    /// Get the number of emails in the queue
    pub async fn queue_size(&self) -> usize {
        let queue = self.email_queue.read().await;
        queue.len()
    }

    /// Add common templates
    pub async fn add_common_templates(&self) -> Result<()> {
        // Welcome email template
        self.add_template(EmailTemplate {
            name: "welcome".to_string(),
            subject: "Welcome to Art Git Browser".to_string(),
            text_content: "Hello {{name}},\n\nWelcome to Art Git Browser! Your account has been created successfully.\n\nUsername: {{username}}\n\nYou can now log in and start exploring repositories.\n\nBest regards,\nThe Art Team".to_string(),
            html_content: Some("<h1>Welcome to Art Git Browser</h1><p>Hello {{name}},</p><p>Welcome to Art Git Browser! Your account has been created successfully.</p><p><strong>Username:</strong> {{username}}</p><p>You can now log in and start exploring repositories.</p><p>Best regards,<br>The Art Team</p>".to_string()),
        }).await?;

        // Password reset template
        self.add_template(EmailTemplate {
            name: "password_reset".to_string(),
            subject: "Password Reset Request".to_string(),
            text_content: "Hello {{name}},\n\nWe received a request to reset your password. Please use the following link to reset your password:\n\n{{reset_link}}\n\nThis link will expire in 24 hours. If you did not request a password reset, please ignore this email.\n\nBest regards,\nThe Art Team".to_string(),
            html_content: Some("<h1>Password Reset Request</h1><p>Hello {{name}},</p><p>We received a request to reset your password. Please use the following link to reset your password:</p><p><a href=\"{{reset_link}}\">Reset Password</a></p><p>This link will expire in 24 hours. If you did not request a password reset, please ignore this email.</p><p>Best regards,<br>The Art Team</p>".to_string()),
        }).await?;

        // Account verification template
        self.add_template(EmailTemplate {
            name: "account_verification".to_string(),
            subject: "Verify Your Account".to_string(),
            text_content: "Hello {{name}},\n\nThank you for registering with Art Git Browser. Please verify your account by clicking the following link:\n\n{{verification_link}}\n\nThis link will expire in 24 hours.\n\nBest regards,\nThe Art Team".to_string(),
            html_content: Some("<h1>Verify Your Account</h1><p>Hello {{name}},</p><p>Thank you for registering with Art Git Browser. Please verify your account by clicking the following link:</p><p><a href=\"{{verification_link}}\">Verify Account</a></p><p>This link will expire in 24 hours.</p><p>Best regards,<br>The Art Team</p>".to_string()),
        }).await?;

        // Notification email template
        self.add_template(EmailTemplate {
            name: "notification".to_string(),
            subject: "{{notification_title}}".to_string(),
            text_content: "Hello {{name}},\n\n{{notification_message}}\n\nYou can view all your notifications by logging into your account.\n\nBest regards,\nThe Art Team".to_string(),
            html_content: Some("<h1>{{notification_title}}</h1><p>Hello {{name}},</p><p>{{notification_message}}</p><p>You can view all your notifications by logging into your account.</p><p>Best regards,<br>The Art Team</p>".to_string()),
        }).await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::sleep;
    use std::time::Duration;

    fn get_test_config() -> EmailConfig {
        EmailConfig {
            enabled: false, // Disable for tests
            smtp_server: "localhost".to_string(),
            smtp_port: 25,
            smtp_username: "test".to_string(),
            smtp_password: "test".to_string(),
            use_tls: false,
            from_address: "test@example.com".to_string(),
            from_name: "Test User".to_string(),
            reply_to: Some("reply@example.com".to_string()),
            max_retries: 3,
            retry_delay_seconds: 1,
        }
    }

    #[tokio::test]
    async fn test_email_template_crud() {
        let config = get_test_config();
        let service = EmailService::new(config);

        // Test adding a template
        let template = EmailTemplate {
            name: "test_template".to_string(),
            subject: "Test Subject".to_string(),
            text_content: "Test content {{var}}".to_string(),
            html_content: Some("<p>Test HTML {{var}}</p>".to_string()),
        };

        assert!(service.add_template(template.clone()).await.is_ok());

        // Test getting a template
        let retrieved = service.get_template("test_template").await.unwrap();
        assert_eq!(retrieved.name, "test_template");
        assert_eq!(retrieved.subject, "Test Subject");

        // Test getting a non-existent template
        assert!(service.get_template("nonexistent").await.is_err());

        // Test adding a duplicate template
        assert!(service.add_template(template).await.is_err());
    }

    #[tokio::test]
    async fn test_template_rendering() {
        let config = get_test_config();
        let service = EmailService::new(config);

        let template = "Hello {{name}}, your code is {{code}}!";
        let vars = serde_json::json!({
            "name": "John",
            "code": "12345"
        });

        let result = service.render_template_string(template, &vars).unwrap();
        assert_eq!(result, "Hello John, your code is 12345!");
    }

    #[tokio::test]
    async fn test_email_queue_processing() {
        let mut config = get_test_config();
        config.enabled = true; // Enable to test queue processing
        let service = EmailService::new(config);

        // Add some emails to the queue manually
        {
            let mut queue = service.email_queue.write().await;
            for i in 0..3 {
                let mut email = Email::new(
                    format!("test{}@example.com", i),
                    format!("Test Subject {}", i),
                    format!("Test content {}", i),
                    None,
                );
                email.status = EmailDeliveryStatus::Failed;
                email.delivery_attempts = 1;
                queue.push(email);
            }
        }

        // Verify queue size
        assert_eq!(service.queue_size().await, 3);

        // Process queue (this will try to send emails but fail since SMTP is not set up)
        let _ = service.process_queue().await;

        // Verify emails are still in queue (retries < max_retries)
        assert!(service.queue_size().await > 0);

        // Manually update all emails to reach max retries
        {
            let mut queue = service.email_queue.write().await;
            for email in queue.iter_mut() {
                email.delivery_attempts = 3; // Max retries
            }
        }

        // Process queue again
        let _ = service.process_queue().await;

        // Verify queue is now empty (all emails have reached max retries)
        assert_eq!(service.queue_size().await, 0);
    }

    #[tokio::test]
    async fn test_common_templates() {
        let config = get_test_config();
        let service = EmailService::new(config);

        // Add common templates
        assert!(service.add_common_templates().await.is_ok());

        // Verify templates were added
        assert!(service.get_template("welcome").await.is_ok());
        assert!(service.get_template("password_reset").await.is_ok());
        assert!(service.get_template("account_verification").await.is_ok());
        assert!(service.get_template("notification").await.is_ok());
    }
}
