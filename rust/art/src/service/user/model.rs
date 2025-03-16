#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    /// Email address
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,

    /// Whether email notifications are enabled for this user
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email_notifications_enabled: Option<bool>,

    /// Email notification preferences for security events
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notify_security: Option<bool>,

    /// Email notification preferences for system announcements
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notify_system: Option<bool>,

    /// Email notification preferences for repository events
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notify_repository: Option<bool>,

    /// Email digest frequency (immediate, daily, weekly)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub digest_frequency: Option<String>,
}

impl Default for User {
    fn default() -> Self {
        Self {
            email: None,
            email_notifications_enabled: Some(false),
            notify_security: Some(true),
            notify_system: Some(true),
            notify_repository: Some(true),
            digest_frequency: Some("immediate".to_string()),
        }
    }
}
