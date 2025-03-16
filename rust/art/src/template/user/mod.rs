//! User templates
//!
//! This module provides templates for user-related pages.

mod login;
mod registration;
mod profile;
mod management;
mod email;

pub use login::LoginTemplate;
pub use registration::RegistrationTemplate;
pub use profile::ProfileTemplate;
pub use management::{UserManagementTemplate, UserEditTemplate};
pub use email::UserEmailSettingsTemplate;
