// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! User data structures for the Art application
//!
//! This module provides the core user data structures and related functionality
//! for user management in the Art application.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fmt;
use argon2::{
    password_hash::{
        rand_core::OsRng,
        PasswordHash, PasswordHasher, PasswordVerifier, SaltString
    },
    Argon2
};

pub mod repository;

/// User role with associated permissions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UserRole {
    /// Regular user with basic permissions
    User,

    /// Maintainer with repository management permissions
    Maintainer,

    /// Administrator with full permissions
    Admin,
}

impl UserRole {
    /// Returns true if the role is an admin role
    pub fn is_admin(&self) -> bool {
        matches!(self, UserRole::Admin)
    }

    /// Returns true if the role is a maintainer or higher
    pub fn is_maintainer_or_higher(&self) -> bool {
        matches!(self, UserRole::Admin | UserRole::Maintainer)
    }

    /// Returns the string representation of the role
    pub fn as_str(&self) -> &'static str {
        match self {
            UserRole::User => "user",
            UserRole::Maintainer => "maintainer",
            UserRole::Admin => "admin",
        }
    }

    /// Get a role from its string representation
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "user" => Some(UserRole::User),
            "maintainer" => Some(UserRole::Maintainer),
            "admin" => Some(UserRole::Admin),
            _ => None,
        }
    }
}

impl fmt::Display for UserRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// User account information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    /// Unique user ID
    pub id: i64,

    /// Username used for authentication
    pub username: String,

    /// Email address
    pub email: String,

    /// Display name
    pub display_name: String,

    /// Password hash
    #[serde(skip_serializing)]
    pub password_hash: String,

    /// User role
    pub role: UserRole,

    /// Account creation timestamp
    pub created_at: DateTime<Utc>,

    /// Last login timestamp
    pub last_login: Option<DateTime<Utc>>,

    /// Whether the account is currently active
    pub active: bool,
}

impl User {
    /// Create a new user
    pub fn new(
        id: i64,
        username: String,
        email: String,
        display_name: String,
        password_hash: String,
        role: UserRole,
    ) -> Self {
        Self {
            id,
            username,
            email,
            display_name,
            password_hash,
            role,
            created_at: Utc::now(),
            last_login: None,
            active: true,
        }
    }

    /// Create a new user with a plaintext password
    pub fn new_with_password(
        id: i64,
        username: String,
        email: String,
        display_name: String,
        password: &str,
        role: UserRole,
    ) -> Result<Self, crate::error::Error> {
        let password_hash = Self::hash_password(password)?;

        Ok(Self::new(
            id,
            username,
            email,
            display_name,
            password_hash,
            role,
        ))
    }

    /// Hash a password using Argon2
    pub fn hash_password(password: &str) -> Result<String, crate::error::Error> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| crate::error::Error::Internal(format!("Failed to hash password: {}", e)))?
            .to_string();

        Ok(password_hash)
    }

    /// Verify a password against the stored hash
    pub fn verify_password(&self, password: &str) -> Result<bool, crate::error::Error> {
        let parsed_hash = PasswordHash::new(&self.password_hash)
            .map_err(|e| crate::error::Error::Internal(format!("Failed to parse password hash: {}", e)))?;

        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }

    /// Update the last login timestamp
    pub fn update_last_login(&mut self) {
        self.last_login = Some(Utc::now());
    }

    /// Check if the user is an admin
    pub fn is_admin(&self) -> bool {
        self.role.is_admin()
    }

    /// Check if the user is a maintainer or higher
    pub fn is_maintainer_or_higher(&self) -> bool {
        self.role.is_maintainer_or_higher()
    }
}

/// Session information for a logged-in user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSession {
    /// Session ID
    pub id: String,

    /// User ID associated with this session
    pub user_id: i64,

    /// Session creation timestamp
    pub created_at: DateTime<Utc>,

    /// Session expiration timestamp
    pub expires_at: DateTime<Utc>,

    /// User's IP address
    pub ip_address: String,

    /// User agent string
    pub user_agent: String,
}

impl UserSession {
    /// Create a new user session
    pub fn new(
        id: String,
        user_id: i64,
        ip_address: String,
        user_agent: String,
        duration_seconds: i64,
    ) -> Self {
        let now = Utc::now();
        let expires_at = now + chrono::Duration::seconds(duration_seconds);

        Self {
            id,
            user_id,
            created_at: now,
            expires_at,
            ip_address,
            user_agent,
        }
    }

    /// Check if the session is expired
    pub fn is_expired(&self) -> bool {
        self.expires_at < Utc::now()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ops::Range;
    use proptest::prelude::*;
    use proptest::collection::vec;
    use proptest::option;
    use proptest::strategy::Strategy;

    fn arb_string_alphanumeric(length_range: Range<usize>) -> impl Strategy<Value = String> {
        vec(proptest::char::range('a', 'z'), length_range).prop_map(|chars| chars.into_iter().collect())
    }

    fn arb_username() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(3..30)
    }

    fn arb_email() -> impl Strategy<Value = String> {
        (arb_string_alphanumeric(3..20), arb_string_alphanumeric(3..10)).prop_map(|(name, domain)| {
            format!("{}@{}.com", name, domain)
        })
    }

    fn arb_display_name() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(1..50)
    }

    fn arb_password() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(8..50)
    }

    fn arb_user_role() -> impl Strategy<Value = UserRole> {
        prop_oneof![
            Just(UserRole::User),
            Just(UserRole::Maintainer),
            Just(UserRole::Admin)
        ]
    }

    fn arb_user_id() -> impl Strategy<Value = i64> {
        1..1000000
    }

    fn arb_datetime() -> impl Strategy<Value = DateTime<Utc>> {
        // Generate random timestamps between 2000 and 2050
        (2000..2050u32, 1..13u32, 1..29u32, 0..24u32, 0..60u32, 0..60u32)
            .prop_map(|(year, month, day, hour, min, sec)| {
                Utc.with_ymd_and_hms(year as i32, month, day, hour, min, sec)
                    .unwrap()
            })
    }

    fn arb_user() -> impl Strategy<Value = User> {
        (
            arb_user_id(),
            arb_username(),
            arb_email(),
            arb_display_name(),
            arb_password(),
            arb_user_role(),
            arb_datetime(),
            option::of(arb_datetime()),
            prop_oneof![Just(true), Just(false)]
        ).prop_map(|(id, username, email, display_name, password, role, created_at, last_login, active)| {
            // Hash the password for the user
            let password_hash = User::hash_password(&password).unwrap();

            User {
                id,
                username,
                email,
                display_name,
                password_hash,
                role,
                created_at,
                last_login,
                active,
            }
        })
    }

    fn arb_session() -> impl Strategy<Value = UserSession> {
        (
            arb_string_alphanumeric(32..64),
            arb_user_id(),
            arb_datetime(),
            arb_datetime(),
            arb_string_alphanumeric(7..15),
            arb_string_alphanumeric(10..100)
        ).prop_map(|(id, user_id, created_at, expires_at, ip_address, user_agent)| {
            UserSession {
                id,
                user_id,
                created_at,
                expires_at,
                ip_address,
                user_agent,
            }
        })
    }

    proptest! {
        #[test]
        fn test_role_is_admin(role: UserRole) {
            match role {
                UserRole::Admin => assert!(role.is_admin()),
                _ => assert!(!role.is_admin()),
            }
        }

        #[test]
        fn test_role_is_maintainer_or_higher(role: UserRole) {
            match role {
                UserRole::Admin | UserRole::Maintainer => assert!(role.is_maintainer_or_higher()),
                _ => assert!(!role.is_maintainer_or_higher()),
            }
        }

        #[test]
        fn test_role_as_str(role: UserRole) {
            let role_str = role.as_str();
            match role {
                UserRole::Admin => assert_eq!(role_str, "Admin"),
                UserRole::Maintainer => assert_eq!(role_str, "Maintainer"),
                UserRole::User => assert_eq!(role_str, "User"),
            }
        }

        #[test]
        fn test_role_display(role: UserRole) {
            let role_str = role.to_string();
            match role {
                UserRole::Admin => assert_eq!(role_str, "Admin"),
                UserRole::Maintainer => assert_eq!(role_str, "Maintainer"),
                UserRole::User => assert_eq!(role_str, "User"),
            }
        }

        #[test]
        fn test_role_from_str(
            role_str in prop_oneof![
                Just("Admin"), Just("admin"), Just("ADMIN"),
                Just("Maintainer"), Just("maintainer"), Just("MAINTAINER"),
                Just("User"), Just("user"), Just("USER"),
                Just("Unknown")
            ]
        ) {
            let role = UserRole::from_str(&role_str);
            match role_str.to_lowercase().as_str() {
                "admin" => assert_eq!(role, Some(UserRole::Admin)),
                "maintainer" => assert_eq!(role, Some(UserRole::Maintainer)),
                "user" => assert_eq!(role, Some(UserRole::User)),
                _ => assert_eq!(role, None),
            }
        }

        #[test]
        fn test_user_new(
            id in arb_user_id(),
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password_hash in arb_string_alphanumeric(32..100),
            role in arb_user_role()
        ) {
            let user = User::new(
                id,
                username.clone(),
                email.clone(),
                display_name.clone(),
                password_hash.clone(),
                role.clone()
            );

            assert_eq!(user.id, id);
            assert_eq!(user.username, username);
            assert_eq!(user.email, email);
            assert_eq!(user.display_name, display_name);
            assert_eq!(user.password_hash, password_hash);
            assert_eq!(user.role, role);
            assert!(user.created_at <= Utc::now());
            assert_eq!(user.last_login, None);
            assert!(user.active);
        }

        #[test]
        fn test_user_new_with_password(
            id in arb_user_id(),
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password in arb_password(),
            role in arb_user_role()
        ) {
            if let Ok(user) = User::new_with_password(
                id,
                username.clone(),
                email.clone(),
                display_name.clone(),
                &password,
                role.clone()
            ) {
                assert_eq!(user.id, id);
                assert_eq!(user.username, username);
                assert_eq!(user.email, email);
                assert_eq!(user.display_name, display_name);
                assert_eq!(user.role, role);
                assert!(user.created_at <= Utc::now());
                assert_eq!(user.last_login, None);
                assert!(user.active);

                // Verify password
                assert!(user.verify_password(&password).unwrap());

                // Wrong password shouldn't verify
                if !password.is_empty() {
                    let wrong_pass = format!("{}1", password);
                    assert!(!user.verify_password(&wrong_pass).unwrap());
                }
            }
        }

        #[test]
        fn test_user_update_last_login(mut user in arb_user()) {
            let before_update = Utc::now();
            std::thread::sleep(std::time::Duration::from_millis(5));

            user.update_last_login();

            assert!(user.last_login.is_some());
            let last_login = user.last_login.unwrap();
            assert!(last_login >= before_update);
            assert!(last_login <= Utc::now());
        }

        #[test]
        fn test_user_is_admin(user in arb_user()) {
            match user.role {
                UserRole::Admin => assert!(user.is_admin()),
                _ => assert!(!user.is_admin()),
            }
        }

        #[test]
        fn test_user_is_maintainer_or_higher(user in arb_user()) {
            match user.role {
                UserRole::Admin | UserRole::Maintainer => assert!(user.is_maintainer_or_higher()),
                _ => assert!(!user.is_maintainer_or_higher()),
            }
        }

        #[test]
        fn test_session_new(
            id in arb_string_alphanumeric(32..64),
            user_id in arb_user_id(),
            ip_address in arb_string_alphanumeric(7..15),
            user_agent in arb_string_alphanumeric(10..100),
            duration_seconds in 300..86400i64
        ) {
            let before_creation = Utc::now();
            std::thread::sleep(std::time::Duration::from_millis(5));

            let session = UserSession::new(
                id.clone(),
                user_id,
                ip_address.clone(),
                user_agent.clone(),
                duration_seconds
            );

            assert_eq!(session.id, id);
            assert_eq!(session.user_id, user_id);
            assert_eq!(session.ip_address, ip_address);
            assert_eq!(session.user_agent, user_agent);

            // Check creation time
            assert!(session.created_at >= before_creation);
            assert!(session.created_at <= Utc::now());

            // Check expiration time
            let expected_expiry = session.created_at + chrono::Duration::seconds(duration_seconds);
            assert_eq!(session.expires_at, expected_expiry);

            // Session should not be expired yet
            assert!(!session.is_expired());
        }

        #[test]
        fn test_session_expiry(session in arb_session()) {
            // Create a known expired and non-expired session for testing
            let now = Utc::now();

            // Past expiry
            let mut expired_session = session.clone();
            expired_session.expires_at = now - chrono::Duration::hours(1);
            assert!(expired_session.is_expired());

            // Future expiry
            let mut valid_session = session;
            valid_session.expires_at = now + chrono::Duration::hours(1);
            assert!(!valid_session.is_expired());
        }
    }
}
