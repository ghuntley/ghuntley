// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! User repository for database operations
//!
//! This module provides the repository implementation for user-related
//! database operations in the Art application.

use super::{User, UserRole, UserSession};
use crate::error::Error;
use chrono::{DateTime, Utc};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, OptionalExtension, Row};
use uuid::Uuid;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// Repository for user-related database operations
pub struct UserRepository {
    /// SQLite connection pool
    pool: Arc<Pool<SqliteConnectionManager>>,
}

impl UserRepository {
    /// Create a new user repository
    pub fn new(pool: Arc<Pool<SqliteConnectionManager>>) -> Self {
        Self { pool }
    }

    /// Initialize the user repository, creating tables if they don't exist
    pub async fn initialize(&self) -> Result<(), Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        // Create users table
        conn.execute(
            "CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                username TEXT NOT NULL UNIQUE,
                email TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL,
                created_at TEXT NOT NULL,
                last_login TEXT,
                active INTEGER NOT NULL
            )",
            [],
        )
        .map_err(|e| Error::Database(e.to_string()))?;

        // Create sessions table
        conn.execute(
            "CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                ip_address TEXT NOT NULL,
                user_agent TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )",
            [],
        )
        .map_err(|e| Error::Database(e.to_string()))?;

        debug!("User repository initialized successfully");
        Ok(())
    }

    /// Get a user by ID
    pub async fn get_user_by_id(&self, id: i64) -> Result<Option<User>, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.query_row(
            "SELECT id, username, email, display_name, password_hash, role, created_at, last_login, active
             FROM users WHERE id = ?1",
            [id],
            |row| self.map_user_row(row),
        )
        .optional()
        .map_err(|e| Error::Database(e.to_string()))
    }

    /// Get a user by username
    pub async fn get_user_by_username(&self, username: &str) -> Result<Option<User>, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.query_row(
            "SELECT id, username, email, display_name, password_hash, role, created_at, last_login, active
             FROM users WHERE username = ?1",
            [username],
            |row| self.map_user_row(row),
        )
        .optional()
        .map_err(|e| Error::Database(e.to_string()))
    }

    /// Get a user by email
    pub async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.query_row(
            "SELECT id, username, email, display_name, password_hash, role, created_at, last_login, active
             FROM users WHERE email = ?1",
            [email],
            |row| self.map_user_row(row),
        )
        .optional()
        .map_err(|e| Error::Database(e.to_string()))
    }

    /// List all users with optional pagination
    pub async fn list_users(
        &self,
        limit: Option<usize>,
        offset: Option<usize>,
    ) -> Result<Vec<User>, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        let limit = limit.unwrap_or(100);
        let offset = offset.unwrap_or(0);

        let mut stmt = conn
            .prepare(
                "SELECT id, username, email, display_name, password_hash, role, created_at, last_login, active
                 FROM users ORDER BY id LIMIT ?1 OFFSET ?2",
            )
            .map_err(|e| Error::Database(e.to_string()))?;

        let users = stmt
            .query_map([limit as i64, offset as i64], |row| self.map_user_row(row))
            .map_err(|e| Error::Database(e.to_string()))?
            .map(|u| u.map_err(|e| Error::Database(e.to_string())))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(users)
    }

    /// Create a new user
    pub async fn create_user(
        &self,
        username: String,
        email: String,
        display_name: String,
        password: &str,
        role: UserRole,
    ) -> Result<User, Error> {
        // Check if username is already taken
        if let Ok(Some(_)) = self.get_user_by_username(&username).await {
            return Err(Error::UsernameTaken(username));
        }

        // Check if email is already taken
        if let Ok(Some(_)) = self.get_user_by_email(&email).await {
            return Err(Error::EmailTaken(email));
        }

        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        // Hash the password
        let password_hash = User::hash_password(password)?;

        // Current time
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        // Insert the user
        conn.execute(
            "INSERT INTO users (username, email, display_name, password_hash, role, created_at, active)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                username,
                email,
                display_name,
                password_hash,
                role.as_str(),
                now_str,
                true,
            ],
        )
        .map_err(|e| Error::Database(e.to_string()))?;

        // Get the inserted user ID
        let id = conn.last_insert_rowid();

        // Return the new user
        Ok(User::new(
            id,
            username,
            email,
            display_name,
            password_hash,
            role,
        ))
    }

    /// Update an existing user
    pub async fn update_user(
        &self,
        id: i64,
        email: Option<String>,
        display_name: Option<String>,
        password: Option<&str>,
        role: Option<UserRole>,
        active: Option<bool>,
    ) -> Result<User, Error> {
        // Check if user exists
        let mut user = match self.get_user_by_id(id).await? {
            Some(user) => user,
            None => return Err(Error::UserNotFound(id.to_string())),
        };

        // Check if email is unique if we're changing it
        if let Some(email) = &email {
            if email != &user.email {
                if let Ok(Some(_)) = self.get_user_by_email(email).await {
                    return Err(Error::EmailTaken(email.clone()));
                }
            }
        }

        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;
        let mut updates = Vec::new();
        let mut params = Vec::new();

        // Update email if provided
        if let Some(email) = email {
            updates.push("email = ?");
            params.push(email.clone());
            user.email = email;
        }

        // Update display name if provided
        if let Some(display_name) = display_name {
            updates.push("display_name = ?");
            params.push(display_name.clone());
            user.display_name = display_name;
        }

        // Update password if provided
        if let Some(password) = password {
            let password_hash = User::hash_password(password)?;
            updates.push("password_hash = ?");
            params.push(password_hash.clone());
            user.password_hash = password_hash;
        }

        // Update role if provided
        if let Some(role) = role {
            updates.push("role = ?");
            params.push(role.as_str().to_string());
            user.role = role;
        }

        // Update active status if provided
        if let Some(active) = active {
            updates.push("active = ?");
            params.push(if active { "1" } else { "0" }.to_string());
            user.active = active;
        }

        // If there are updates, execute the query
        if !updates.is_empty() {
            let query = format!(
                "UPDATE users SET {} WHERE id = ?",
                updates.join(", ")
            );

            // Add the ID parameter
            params.push(id.to_string());

            // Execute the update
            conn.execute(
                &query,
                rusqlite::params_from_iter(params.iter()),
            )
            .map_err(|e| Error::Database(e.to_string()))?;
        }

        Ok(user)
    }

    /// Delete a user by ID
    pub async fn delete_user(&self, id: i64) -> Result<(), Error> {
        // Check if user exists
        match self.get_user_by_id(id).await? {
            Some(_) => (),
            None => return Err(Error::UserNotFound(id.to_string())),
        }

        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        // Delete the user
        conn.execute("DELETE FROM users WHERE id = ?1", [id])
            .map_err(|e| Error::Database(e.to_string()))?;

        Ok(())
    }

    /// Update the last login time for a user
    pub async fn update_last_login(&self, id: i64) -> Result<(), Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        conn.execute(
            "UPDATE users SET last_login = ?1 WHERE id = ?2",
            params![now_str, id],
        )
        .map_err(|e| Error::Database(e.to_string()))?;

        Ok(())
    }

    /// Authenticate a user with username/email and password
    pub async fn authenticate(
        &self,
        username_or_email: &str,
        password: &str,
    ) -> Result<Option<User>, Error> {
        // Try to get the user by username or email
        let user = if username_or_email.contains('@') {
            self.get_user_by_email(username_or_email).await?
        } else {
            self.get_user_by_username(username_or_email).await?
        };

        // If user not found, return None
        let user = match user {
            Some(user) => user,
            None => return Ok(None),
        };

        // Check if account is active
        if !user.active {
            return Err(Error::Authentication("Account is inactive".to_string()));
        }

        // Verify password
        if user.verify_password(password)? {
            // Update last login time
            self.update_last_login(user.id).await?;

            // Return authenticated user
            Ok(Some(user))
        } else {
            // Invalid password
            Ok(None)
        }
    }

    /// Create a new session for a user
    pub async fn create_session(
        &self,
        user_id: i64,
        ip_address: String,
        user_agent: String,
        duration_seconds: i64,
    ) -> Result<UserSession, Error> {
        // Check if user exists
        match self.get_user_by_id(user_id).await? {
            Some(_) => (),
            None => return Err(Error::UserNotFound(user_id.to_string())),
        }

        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        // Generate session ID
        let id = Uuid::new_v4().to_string();

        // Create session
        let session = UserSession::new(
            id,
            user_id,
            ip_address,
            user_agent,
            duration_seconds,
        );

        // Store session in database
        conn.execute(
            "INSERT INTO sessions (id, user_id, created_at, expires_at, ip_address, user_agent)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                session.id,
                session.user_id,
                session.created_at.to_rfc3339(),
                session.expires_at.to_rfc3339(),
                session.ip_address,
                session.user_agent,
            ],
        )
        .map_err(|e| Error::Database(e.to_string()))?;

        Ok(session)
    }

    /// Get a session by ID
    pub async fn get_session(&self, id: &str) -> Result<Option<UserSession>, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.query_row(
            "SELECT id, user_id, created_at, expires_at, ip_address, user_agent
             FROM sessions WHERE id = ?1",
            [id],
            |row| {
                let id: String = row.get(0)?;
                let user_id: i64 = row.get(1)?;
                let created_at: String = row.get(2)?;
                let expires_at: String = row.get(3)?;
                let ip_address: String = row.get(4)?;
                let user_agent: String = row.get(5)?;

                let created_at = DateTime::parse_from_rfc3339(&created_at)
                    .map_err(|e| rusqlite::Error::FromSqlConversionFailure(
                        0, rusqlite::types::Type::Text, Box::new(e)
                    ))?
                    .with_timezone(&Utc);

                let expires_at = DateTime::parse_from_rfc3339(&expires_at)
                    .map_err(|e| rusqlite::Error::FromSqlConversionFailure(
                        0, rusqlite::types::Type::Text, Box::new(e)
                    ))?
                    .with_timezone(&Utc);

                Ok(UserSession {
                    id,
                    user_id,
                    created_at,
                    expires_at,
                    ip_address,
                    user_agent,
                })
            },
        )
        .optional()
        .map_err(|e| Error::Database(e.to_string()))
    }

    /// Delete a session by ID
    pub async fn delete_session(&self, id: &str) -> Result<(), Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.execute("DELETE FROM sessions WHERE id = ?1", [id])
            .map_err(|e| Error::Database(e.to_string()))?;

        Ok(())
    }

    /// Delete all sessions for a user
    pub async fn delete_user_sessions(&self, user_id: i64) -> Result<(), Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;

        conn.execute("DELETE FROM sessions WHERE user_id = ?1", [user_id])
            .map_err(|e| Error::Database(e.to_string()))?;

        Ok(())
    }

    /// Delete expired sessions
    pub async fn delete_expired_sessions(&self) -> Result<usize, Error> {
        let conn = self.pool.get().map_err(|e| Error::Database(e.to_string()))?;
        let now = Utc::now().to_rfc3339();

        let result = conn
            .execute("DELETE FROM sessions WHERE expires_at < ?1", [now])
            .map_err(|e| Error::Database(e.to_string()))?;

        Ok(result)
    }

    // Helper method to map a database row to a User
    fn map_user_row(&self, row: &Row) -> rusqlite::Result<User> {
        let id: i64 = row.get(0)?;
        let username: String = row.get(1)?;
        let email: String = row.get(2)?;
        let display_name: String = row.get(3)?;
        let password_hash: String = row.get(4)?;
        let role_str: String = row.get(5)?;
        let created_at_str: String = row.get(6)?;
        let last_login_str: Option<String> = row.get(7)?;
        let active: bool = row.get::<_, i64>(8)? != 0;

        // Parse role
        let role = UserRole::from_str(&role_str).unwrap_or(UserRole::User);

        // Parse timestamps
        let created_at = DateTime::parse_from_rfc3339(&created_at_str)
            .map_err(|e| rusqlite::Error::FromSqlConversionFailure(
                0, rusqlite::types::Type::Text, Box::new(e)
            ))?
            .with_timezone(&Utc);

        let last_login = if let Some(last_login_str) = last_login_str {
            Some(
                DateTime::parse_from_rfc3339(&last_login_str)
                    .map_err(|e| rusqlite::Error::FromSqlConversionFailure(
                        0, rusqlite::types::Type::Text, Box::new(e)
                    ))?
                    .with_timezone(&Utc),
            )
        } else {
            None
        };

        Ok(User {
            id,
            username,
            email,
            display_name,
            password_hash,
            role,
            created_at,
            last_login,
            active,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use r2d2_sqlite::SqliteConnectionManager;
    use std::sync::Arc;
    use tempfile::NamedTempFile;

    // Setup a temporary database for testing
    async fn setup_test_db() -> (Arc<Pool<SqliteConnectionManager>>, UserRepository) {
        let temp_file = NamedTempFile::new().unwrap();
        let manager = SqliteConnectionManager::file(temp_file.path());
        let pool = Arc::new(Pool::new(manager).unwrap());

        let repo = UserRepository::new(pool.clone());
        repo.initialize().await.unwrap();

        (pool, repo)
    }

    // Helper to generate test data using proptest strategies from the main module
    fn arb_string_alphanumeric(length_range: std::ops::Range<usize>) -> impl Strategy<Value = String> {
        super::super::tests::arb_string_alphanumeric(length_range)
    }

    fn arb_username() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(3..30)
    }

    fn arb_email() -> impl Strategy<Value = String> {
        // Simplified for tests
        (
            arb_string_alphanumeric(3..20),
            arb_string_alphanumeric(2..10),
            prop::sample::select(vec![
                "com", "org", "net", "io", "dev"
            ]),
        )
            .prop_map(|(name, domain, tld)| format!("{}@{}.{}", name, domain, tld))
    }

    fn arb_display_name() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(3..50)
    }

    fn arb_password() -> impl Strategy<Value = String> {
        arb_string_alphanumeric(8..30)
    }

    fn arb_user_role() -> impl Strategy<Value = UserRole> {
        prop::sample::select(vec![
            UserRole::User,
            UserRole::Maintainer,
            UserRole::Admin,
        ])
    }

    fn arb_duration_seconds() -> impl Strategy<Value = i64> {
        (60..86400i64)
    }

    proptest! {
        #[test]
        fn test_create_and_get_user(
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password in arb_password(),
            role in arb_user_role()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Create user
                let user = repo.create_user(
                    username.clone(),
                    email.clone(),
                    display_name.clone(),
                    &password,
                    role,
                ).await.unwrap();

                // Verify user properties
                prop_assert_eq!(user.username, username);
                prop_assert_eq!(user.email, email);
                prop_assert_eq!(user.display_name, display_name);
                prop_assert_eq!(user.role, role);
                prop_assert_eq!(user.active, true);
                prop_assert_eq!(user.last_login, None);

                // Get user by ID
                let retrieved_user = repo.get_user_by_id(user.id).await.unwrap().unwrap();
                prop_assert_eq!(retrieved_user.id, user.id);
                prop_assert_eq!(retrieved_user.username, username);
                prop_assert_eq!(retrieved_user.email, email);

                // Get user by username
                let by_username = repo.get_user_by_username(&username).await.unwrap().unwrap();
                prop_assert_eq!(by_username.id, user.id);

                // Get user by email
                let by_email = repo.get_user_by_email(&email).await.unwrap().unwrap();
                prop_assert_eq!(by_email.id, user.id);

                // Verify password authentication
                let auth_result = repo.authenticate(&username, &password).await.unwrap();
                prop_assert!(auth_result.is_some());
                prop_assert_eq!(auth_result.unwrap().id, user.id);

                // Check invalid password
                let bad_auth = repo.authenticate(&username, "wrong_password").await.unwrap();
                prop_assert!(bad_auth.is_none());
            });
        }

        #[test]
        fn test_update_user(
            username in arb_username(),
            email in arb_email(),
            new_email in arb_email(),
            display_name in arb_display_name(),
            new_display_name in arb_display_name(),
            password in arb_password(),
            new_password in arb_password(),
            role in arb_user_role(),
            new_role in arb_user_role()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Create user
                let user = repo.create_user(
                    username.clone(),
                    email.clone(),
                    display_name.clone(),
                    &password,
                    role,
                ).await.unwrap();

                // Skip test if email is same as new_email (would cause unique constraint error)
                if email != new_email {
                    // Update user
                    let updated_user = repo.update_user(
                        user.id,
                        Some(new_email.clone()),
                        Some(new_display_name.clone()),
                        Some(&new_password),
                        Some(new_role),
                        Some(false),
                    ).await.unwrap();

                    // Verify updated properties
                    prop_assert_eq!(updated_user.email, new_email);
                    prop_assert_eq!(updated_user.display_name, new_display_name);
                    prop_assert_eq!(updated_user.role, new_role);
                    prop_assert_eq!(updated_user.active, false);

                    // Retrieve user again to verify database update
                    let retrieved = repo.get_user_by_id(user.id).await.unwrap().unwrap();
                    prop_assert_eq!(retrieved.email, new_email);
                    prop_assert_eq!(retrieved.display_name, new_display_name);
                    prop_assert_eq!(retrieved.role, new_role);
                    prop_assert_eq!(retrieved.active, false);

                    // Verify new password works
                    let auth_result = repo.authenticate(&username, &new_password).await.unwrap();
                    prop_assert!(auth_result.is_some());
                }
            });
        }

        #[test]
        fn test_delete_user(
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password in arb_password(),
            role in arb_user_role()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Create user
                let user = repo.create_user(
                    username,
                    email,
                    display_name,
                    &password,
                    role,
                ).await.unwrap();

                // Verify user exists
                let exists = repo.get_user_by_id(user.id).await.unwrap();
                prop_assert!(exists.is_some());

                // Delete user
                repo.delete_user(user.id).await.unwrap();

                // Verify user no longer exists
                let not_exists = repo.get_user_by_id(user.id).await.unwrap();
                prop_assert!(not_exists.is_none());
            });
        }

        #[test]
        fn test_user_sessions(
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password in arb_password(),
            role in arb_user_role(),
            ip_address in arb_string_alphanumeric(7..15),
            user_agent in arb_string_alphanumeric(10..100),
            duration_seconds in arb_duration_seconds()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Create user
                let user = repo.create_user(
                    username,
                    email,
                    display_name,
                    &password,
                    role,
                ).await.unwrap();

                // Create session
                let session = repo.create_session(
                    user.id,
                    ip_address.clone(),
                    user_agent.clone(),
                    duration_seconds,
                ).await.unwrap();

                // Verify session properties
                prop_assert_eq!(session.user_id, user.id);
                prop_assert_eq!(session.ip_address, ip_address);
                prop_assert_eq!(session.user_agent, user_agent);

                // Retrieve session
                let retrieved = repo.get_session(&session.id).await.unwrap().unwrap();
                prop_assert_eq!(retrieved.id, session.id);
                prop_assert_eq!(retrieved.user_id, user.id);

                // Delete session
                repo.delete_session(&session.id).await.unwrap();

                // Verify session is gone
                let not_exists = repo.get_session(&session.id).await.unwrap();
                prop_assert!(not_exists.is_none());

                // Create multiple sessions
                let session1 = repo.create_session(
                    user.id,
                    ip_address.clone(),
                    user_agent.clone(),
                    duration_seconds,
                ).await.unwrap();

                let session2 = repo.create_session(
                    user.id,
                    ip_address.clone(),
                    user_agent.clone(),
                    duration_seconds,
                ).await.unwrap();

                // Verify both sessions exist
                prop_assert!(repo.get_session(&session1.id).await.unwrap().is_some());
                prop_assert!(repo.get_session(&session2.id).await.unwrap().is_some());

                // Delete all user sessions
                repo.delete_user_sessions(user.id).await.unwrap();

                // Verify both sessions are gone
                prop_assert!(repo.get_session(&session1.id).await.unwrap().is_none());
                prop_assert!(repo.get_session(&session2.id).await.unwrap().is_none());
            });
        }

        #[test]
        fn test_unique_constraints(
            username in arb_username(),
            email in arb_email(),
            display_name in arb_display_name(),
            password in arb_password(),
            role in arb_user_role()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Create first user
                repo.create_user(
                    username.clone(),
                    email.clone(),
                    display_name.clone(),
                    &password,
                    role,
                ).await.unwrap();

                // Try to create user with same username
                let result = repo.create_user(
                    username.clone(),
                    format!("other_{}", email),
                    display_name.clone(),
                    &password,
                    role,
                ).await;

                prop_assert!(result.is_err());
                if let Err(err) = result {
                    match err {
                        Error::UsernameTaken(_) => {},
                        _ => prop_assert!(false, "Expected UsernameTaken error, got {:?}", err),
                    }
                }

                // Try to create user with same email
                let result = repo.create_user(
                    format!("other_{}", username),
                    email.clone(),
                    display_name.clone(),
                    &password,
                    role,
                ).await;

                prop_assert!(result.is_err());
                if let Err(err) = result {
                    match err {
                        Error::EmailTaken(_) => {},
                        _ => prop_assert!(false, "Expected EmailTaken error, got {:?}", err),
                    }
                }
            });
        }

        #[test]
        fn test_list_users(
            username1 in arb_username(),
            email1 in arb_email(),
            display_name1 in arb_display_name(),
            username2 in arb_username(),
            email2 in arb_email(),
            display_name2 in arb_display_name(),
            password in arb_password(),
            role in arb_user_role()
        ) {
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (_, repo) = setup_test_db().await;

                // Skip test if usernames or emails are the same (would cause unique constraint errors)
                if username1 == username2 || email1 == email2 {
                    return Ok(());
                }

                // Create multiple users
                repo.create_user(
                    username1.clone(),
                    email1.clone(),
                    display_name1.clone(),
                    &password,
                    role,
                ).await.unwrap();

                repo.create_user(
                    username2.clone(),
                    email2.clone(),
                    display_name2.clone(),
                    &password,
                    role,
                ).await.unwrap();

                // List all users
                let users = repo.list_users(None, None).await.unwrap();
                prop_assert_eq!(users.len(), 2);

                // Test pagination - first page
                let first_page = repo.list_users(Some(1), Some(0)).await.unwrap();
                prop_assert_eq!(first_page.len(), 1);

                // Test pagination - second page
                let second_page = repo.list_users(Some(1), Some(1)).await.unwrap();
                prop_assert_eq!(second_page.len(), 1);

                // Verify different users on each page
                prop_assert_ne!(first_page[0].id, second_page[0].id);
            });
        }
    }
}
