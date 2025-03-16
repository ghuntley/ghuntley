// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! User management service
//!
//! This module provides a service implementation for user management
//! in the Art application.

use crate::error::{Error, Result};
use crate::data::user::{
    User, CreateUser, UpdateUser, Role, Permission, UserRepository, UserRole, UserSession
};
use sqlx::{Pool, Sqlite};
use std::sync::Arc;
use tracing::{debug, error, info, warn, instrument};
use uuid::Uuid;
use rand::{distributions::Alphanumeric, Rng};
use proptest::prelude::*;
use rand::seq::SliceRandom;
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use crate::data::user::{Theme, UserSettings, NotificationSettings, NotificationType};

/// User session data
#[derive(Debug, Clone)]
pub struct UserSession {
    /// User ID
    pub id: Uuid,

    /// Username
    pub username: String,

    /// Email
    pub email: String,

    /// Full name
    pub full_name: String,

    /// User roles
    pub roles: Vec<Role>,

    /// User permissions
    pub permissions: Vec<Permission>,

    /// Session token
    pub token: String,

    /// Session expiration time
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

/// User list options
#[derive(Debug, Clone)]
pub struct UserListOptions {
    /// Maximum number of users to return
    pub limit: usize,

    /// Number of users to skip
    pub offset: usize,

    /// Filter by role
    pub role: Option<Role>,

    /// Filter by active status
    pub is_active: Option<bool>,

    /// Filter by locked status
    pub is_locked: Option<bool>,
}

impl Default for UserListOptions {
    fn default() -> Self {
        Self {
            limit: 100,
            offset: 0,
            role: None,
            is_active: None,
            is_locked: None,
        }
    }
}

/// The user service provides business logic for user management
pub struct UserService {
    /// User repository for data access
    repository: Arc<UserRepository>,

    /// Session timeout in seconds
    session_timeout: i64,

    /// Maximum number of login attempts before locking the account
    max_login_attempts: u32,

    /// Time in seconds to lock the account after too many failed login attempts
    lockout_time: i64,
}

impl UserService {
    /// Create a new user service
    pub fn new(
        repository: Arc<UserRepository>,
        session_timeout: i64,
        max_login_attempts: u32,
        lockout_time: i64,
    ) -> Self {
        Self {
            repository,
            session_timeout,
            max_login_attempts,
            lockout_time,
        }
    }

    /// Initialize the user service, creating necessary database tables
    pub async fn initialize(&self) -> Result<()> {
        self.repository.initialize().await
    }

    /// Create a new user
    #[instrument(skip(self, password))]
    pub async fn create_user(
        &self,
        username: String,
        email: String,
        display_name: String,
        password: &str,
        role: UserRole,
    ) -> Result<User, Error> {
        // Validate inputs
        self.validate_username(&username)?;
        self.validate_email(&email)?;
        self.validate_password(password)?;

        // Create the user in the repository
        let user = self.repository.create_user(
            username,
            email,
            display_name,
            password,
            role,
        ).await?;

        info!("Created user: {}", user.username);
        Ok(user)
    }

    /// Create a default admin user if no users exist
    #[instrument(skip(self, password))]
    pub async fn create_default_admin(
        &self,
        username: String,
        email: String,
        display_name: String,
        password: &str,
    ) -> Result<Option<User>, Error> {
        // Check if any users exist
        let users = self.repository.list_users(Some(1), None).await?;
        if !users.is_empty() {
            debug!("Users already exist, not creating default admin");
            return Ok(None);
        }

        // Create admin user
        let user = self.create_user(
            username,
            email,
            display_name,
            password,
            UserRole::Admin,
        ).await?;

        info!("Created default admin user: {}", user.username);
        Ok(Some(user))
    }

    /// Get a user by ID
    #[instrument(skip(self))]
    pub async fn get_user(&self, id: i64) -> Result<User, Error> {
        match self.repository.get_user_by_id(id).await? {
            Some(user) => Ok(user),
            None => Err(Error::UserNotFound(id.to_string())),
        }
    }

    /// Get a user by username
    #[instrument(skip(self))]
    pub async fn get_user_by_username(&self, username: &str) -> Result<User, Error> {
        match self.repository.get_user_by_username(username).await? {
            Some(user) => Ok(user),
            None => Err(Error::UserNotFound(username.to_string())),
        }
    }

    /// List all users with pagination
    #[instrument(skip(self))]
    pub async fn list_users(
        &self,
        limit: Option<usize>,
        offset: Option<usize>,
    ) -> Result<Vec<User>, Error> {
        self.repository.list_users(limit, offset).await
    }

    /// Update an existing user
    #[instrument(skip(self, password))]
    pub async fn update_user(
        &self,
        id: i64,
        email: Option<String>,
        display_name: Option<String>,
        password: Option<&str>,
        role: Option<UserRole>,
        active: Option<bool>,
    ) -> Result<User, Error> {
        // Validate inputs
        if let Some(email) = &email {
            self.validate_email(email)?;
        }

        if let Some(password) = password {
            self.validate_password(password)?;
        }

        // Update the user in the repository
        let user = self.repository.update_user(
            id,
            email,
            display_name,
            password,
            role,
            active,
        ).await?;

        info!("Updated user: {}", user.username);
        Ok(user)
    }

    /// Delete a user
    #[instrument(skip(self))]
    pub async fn delete_user(&self, id: i64) -> Result<(), Error> {
        // Delete all sessions for the user
        self.repository.delete_user_sessions(id).await?;

        // Delete the user
        self.repository.delete_user(id).await?;

        info!("Deleted user ID: {}", id);
        Ok(())
    }

    /// Authenticate a user and create a session
    #[instrument(skip(self, password))]
    pub async fn login(
        &self,
        username_or_email: &str,
        password: &str,
        ip_address: String,
        user_agent: String,
    ) -> Result<(User, UserSession), Error> {
        // Authenticate the user
        let user = match self.repository.authenticate(username_or_email, password).await? {
            Some(user) => user,
            None => return Err(Error::Authentication("Invalid credentials".to_string())),
        };

        // Create a new session
        let session = self.repository.create_session(
            user.id,
            ip_address,
            user_agent,
            self.session_timeout,
        ).await?;

        info!("User logged in: {}", user.username);
        Ok((user, session))
    }

    /// Logout a user by deleting their session
    #[instrument(skip(self))]
    pub async fn logout(&self, session_id: &str) -> Result<(), Error> {
        self.repository.delete_session(session_id).await?;
        debug!("User logged out, session ID: {}", session_id);
        Ok(())
    }

    /// Get a session by ID
    #[instrument(skip(self))]
    pub async fn get_session(&self, session_id: &str) -> Result<Option<UserSession>> {
        let session = self.repository.get_session(session_id).await?;
        Ok(session)
    }

    /// Get the user associated with a session
    #[instrument(skip(self))]
    pub async fn get_session_user(&self, session_id: &str) -> Result<Option<User>, Error> {
        // Get the session
        let session = match self.get_session(session_id).await? {
            Some(session) => session,
            None => return Ok(None),
        };

        // Get the user
        match self.repository.get_user_by_id(session.id).await? {
            Some(user) => Ok(Some(user)),
            None => {
                // If the user doesn't exist, delete the session
                self.repository.delete_session(session_id).await?;
                Ok(None)
            }
        }
    }

    /// Clean up expired sessions, returning the number of sessions removed
    #[instrument(skip(self))]
    pub async fn cleanup_expired_sessions(&self) -> Result<usize> {
        self.repository.cleanup_expired_sessions().await
    }

    /// Generate a random password
    pub fn generate_password(length: usize) -> String {
        rand::thread_rng()
            .sample_iter(&Alphanumeric)
            .take(length)
            .map(char::from)
            .collect()
    }

    // Validation methods

    /// Validate a username
    fn validate_username(&self, username: &str) -> Result<(), Error> {
        if username.is_empty() {
            return Err(Error::InvalidRequest("Username cannot be empty".to_string()));
        }

        if username.len() < 3 {
            return Err(Error::InvalidRequest("Username must be at least 3 characters".to_string()));
        }

        if username.len() > 30 {
            return Err(Error::InvalidRequest("Username must be at most 30 characters".to_string()));
        }

        Ok(())
    }

    /// Validate an email address
    fn validate_email(&self, email: &str) -> Result<(), Error> {
        if email.is_empty() {
            return Err(Error::InvalidRequest("Email cannot be empty".to_string()));
        }

        if !email.contains('@') {
            return Err(Error::InvalidRequest("Invalid email format".to_string()));
        }

        Ok(())
    }

    /// Validate a password
    fn validate_password(&self, password: &str) -> Result<(), Error> {
        if password.is_empty() {
            return Err(Error::InvalidRequest("Password cannot be empty".to_string()));
        }

        if password.len() < 8 {
            return Err(Error::InvalidRequest("Password must be at least 8 characters".to_string()));
        }

        if password.len() > 100 {
            return Err(Error::InvalidRequest("Password must be at most 100 characters".to_string()));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use sqlx::sqlite::SqlitePoolOptions;
    use std::time::Duration;
    use crate::data::user::{Theme, UserSettings, NotificationSettings, NotificationType};

    // Generate a temporary SQLite database for testing
    async fn setup_test_db() -> Result<Pool<Sqlite>> {
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .acquire_timeout(Duration::from_secs(3))
            .connect("sqlite::memory:")
            .await
            .map_err(|e| Error::Database(format!("Failed to connect to database: {}", e)))?;

        Ok(pool)
    }

    // Generate valid usernames
    fn valid_username() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9_]{2,19}".prop_map(|s| s)
    }

    // Generate valid emails
    fn valid_email() -> impl Strategy<Value = String> {
        ("[a-z0-9_.-]{1,20}@[a-z0-9_.-]{1,20}\\.[a-z]{2,8}")
            .prop_map(|s| s)
    }

    // Generate valid passwords
    fn valid_password() -> impl Strategy<Value = String> {
        "[A-Za-z0-9!@#$%^&*]{8,30}".prop_map(|s| s)
    }

    // Generate valid full names
    fn valid_full_name() -> impl Strategy<Value = String> {
        "[A-Za-z ]{3,50}".prop_map(|s| s)
    }

    // Generate user roles
    fn user_role() -> impl Strategy<Value = UserRole> {
        prop_oneof![
            Just(UserRole::User),
            Just(UserRole::Maintainer),
            Just(UserRole::Admin)
        ]
    }

    // Generate user settings
    fn user_settings() -> impl Strategy<Value = UserSettings> {
        (
            prop_oneof![
                Just(Theme::Light),
                Just(Theme::Dark),
                Just(Theme::System)
            ],
            any::<bool>(),
            any::<bool>(),
            prop_oneof![
                Just(NotificationSettings::All),
                Just(NotificationSettings::Important),
                Just(NotificationSettings::None),
                prop::collection::vec(prop_oneof![
                    Just(NotificationType::RepositoryUpdate),
                    Just(NotificationType::SecurityAlert),
                    Just(NotificationType::SystemAnnouncement)
                ], 0..3).prop_map(|types| NotificationSettings::Custom(types.into_iter().collect()))
            ]
        )
            .prop_map(|(theme, show_avatars, use_monospace, notifications)| {
                UserSettings {
                    theme,
                    show_avatars,
                    use_monospace,
                    notifications,
                }
            })
    }

    // User operations
    #[derive(Debug, Clone)]
    enum UserOperation {
        Create {
            username: String,
            email: String,
            full_name: String,
            password: String,
            role: UserRole
        },
        Update {
            id: usize,
            email: Option<String>,
            full_name: Option<String>,
            password: Option<String>,
            role: Option<UserRole>,
            active: Option<bool>
        },
        Get { id: usize },
        GetByUsername { username: String },
        Delete { id: usize },
        Login { username: String, password: String },
        Logout { session_id: String },
    }

    // Strategy to generate user operations
    fn user_operations(max_users: usize) -> impl Strategy<Value = Vec<UserOperation>> {
        let create_op = (
            valid_username(),
            valid_email(),
            valid_full_name(),
            valid_password(),
            user_role()
        ).prop_map(|(username, email, full_name, password, role)| {
            UserOperation::Create {
                username,
                email,
                full_name,
                password,
                role,
            }
        });

        let update_op = (
            0..max_users,
            prop::option::of(valid_email()),
            prop::option::of(valid_full_name()),
            prop::option::of(valid_password()),
            prop::option::of(user_role()),
            prop::option::of(any::<bool>())
        ).prop_map(|(id, email, full_name, password, role, active)| {
            UserOperation::Update {
                id,
                email,
                full_name,
                password,
                role,
                active,
            }
        });

        let get_op = (0..max_users).prop_map(|id| UserOperation::Get { id });
        let get_by_username_op = valid_username().prop_map(|username| UserOperation::GetByUsername { username });
        let delete_op = (0..max_users).prop_map(|id| UserOperation::Delete { id });
        let login_op = (valid_username(), valid_password()).prop_map(|(username, password)| {
            UserOperation::Login { username, password }
        });
        let logout_op = any::<String>().prop_map(|session_id| UserOperation::Logout { session_id });

        // First, we need at least one create operation
        prop::collection::vec(create_op.clone(), 1..max_users)
            .prop_flat_map(move |creates| {
                let num_users = creates.len();
                let rest_ops = prop_oneof![
                    9 => create_op,
                    9 => update_op.clone().prop_filter(
                        "id within bounds",
                        move |op| if let UserOperation::Update { id, .. } = op { *id < num_users } else { true }
                    ),
                    9 => get_op.clone().prop_filter(
                        "id within bounds",
                        move |op| if let UserOperation::Get { id } = op { *id < num_users } else { true }
                    ),
                    9 => get_by_username_op,
                    9 => delete_op.clone().prop_filter(
                        "id within bounds",
                        move |op| if let UserOperation::Delete { id } = op { *id < num_users } else { true }
                    ),
                    9 => login_op,
                    9 => logout_op
                ];
                prop::collection::vec(rest_ops, 0..20).prop_map(move |rest| {
                    let mut all_ops = creates.clone();
                    all_ops.extend(rest);
                    all_ops
                })
            })
    }

    proptest! {
        #[test]
        fn test_user_service_create_and_get(
            username in valid_username(),
            email in valid_email(),
            full_name in valid_full_name(),
            password in valid_password()
        ) {
            // Run the async test
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Set up test database and service
                let pool = setup_test_db().await.unwrap();
                let service = UserService::new(Arc::new(UserRepository::new(pool)), 3600, 5, 300);
                service.initialize().await.unwrap();

                // Create user
                let user = service.create_user(
                    username.clone(),
                    email.clone(),
                    full_name.clone(),
                    &password,
                    UserRole::Admin
                ).await.unwrap();

                // Get user by ID
                let user_by_id = service.get_user(user.id).await.unwrap();
                prop_assert_eq!(user_by_id.username, username);

                // Get user by username
                let user_by_username = service.get_user_by_username(&username).await.unwrap();
                prop_assert_eq!(user_by_username.id, user.id);

                // Get user by email
                let user_by_email = service.get_user_by_email(&email).await.unwrap();
                prop_assert_eq!(user_by_email.id, user.id);

                // Authenticate user
                let (auth_user, session) = service.login(
                    &username,
                    &password,
                    "127.0.0.1".to_string(),
                    "test-agent".to_string()
                ).await.unwrap();
                prop_assert_eq!(auth_user.id, user.id);

                // Verify session
                let session_user = service.get_session_user(&session.token).await.unwrap().unwrap();
                prop_assert_eq!(session_user.id, user.id);

                // Failed authentication with wrong password
                let result = service.login(
                    &username,
                    "wrong_password",
                    "127.0.0.1".to_string(),
                    "test-agent".to_string()
                ).await;
                prop_assert!(result.is_err());

                // Logout
                service.logout(&session.token).await.unwrap();
                let session_check = service.get_session(&session.token).await.unwrap();
                prop_assert!(session_check.is_none());
            });
        }

        #[test]
        fn test_user_service_settings_management(
            username in valid_username(),
            email in valid_email(),
            full_name in valid_full_name(),
            password in valid_password(),
            settings in user_settings()
        ) {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Set up test database and service
                let pool = setup_test_db().await.unwrap();
                let service = UserService::new(Arc::new(UserRepository::new(pool)), 3600, 5, 300);
                service.initialize().await.unwrap();

                // Create user
                let user = service.create_user(
                    username.clone(),
                    email.clone(),
                    full_name.clone(),
                    &password,
                    UserRole::User
                ).await.unwrap();

                // Update user settings
                let updated_user = service.update_user_settings(
                    user.id,
                    settings.clone()
                ).await.unwrap();

                // Verify settings were updated
                prop_assert_eq!(updated_user.settings.theme, settings.theme);
                prop_assert_eq!(updated_user.settings.show_avatars, settings.show_avatars);
                prop_assert_eq!(updated_user.settings.use_monospace, settings.use_monospace);

                // Verify notification settings
                match (&updated_user.settings.notifications, &settings.notifications) {
                    (NotificationSettings::All, NotificationSettings::All) => {},
                    (NotificationSettings::Important, NotificationSettings::Important) => {},
                    (NotificationSettings::None, NotificationSettings::None) => {},
                    (NotificationSettings::Custom(a), NotificationSettings::Custom(b)) => {
                        prop_assert_eq!(a.len(), b.len());
                        for notification_type in a {
                            prop_assert!(b.contains(notification_type));
                        }
                    },
                    _ => prop_assert!(false, "Notification settings don't match: {:?} vs {:?}",
                                    updated_user.settings.notifications, settings.notifications),
                }

                // Get user and verify settings persisted
                let retrieved_user = service.get_user(user.id).await.unwrap();
                prop_assert_eq!(retrieved_user.settings.theme, settings.theme);
            });
        }

        #[test]
        fn test_user_service_role_permission_management(
            username in valid_username(),
            email in valid_email(),
            full_name in valid_full_name(),
            password in valid_password(),
            initial_role in user_role(),
            new_role in user_role()
        ) {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Set up test database and service
                let pool = setup_test_db().await.unwrap();
                let service = UserService::new(Arc::new(UserRepository::new(pool)), 3600, 5, 300);
                service.initialize().await.unwrap();

                // Create user with initial role
                let user = service.create_user(
                    username.clone(),
                    email.clone(),
                    full_name.clone(),
                    &password,
                    initial_role.clone()
                ).await.unwrap();

                // Verify initial permissions based on role
                prop_assert_eq!(user.role, initial_role);
                match initial_role {
                    UserRole::Admin => {
                        prop_assert!(user.has_permission(Permission::ManageUsers));
                        prop_assert!(user.has_permission(Permission::ManageRepositories));
                        prop_assert!(user.has_permission(Permission::ViewAllRepositories));
                    },
                    UserRole::Maintainer => {
                        prop_assert!(!user.has_permission(Permission::ManageUsers));
                        prop_assert!(user.has_permission(Permission::ManageRepositories));
                        prop_assert!(user.has_permission(Permission::ViewAllRepositories));
                    },
                    UserRole::User => {
                        prop_assert!(!user.has_permission(Permission::ManageUsers));
                        prop_assert!(!user.has_permission(Permission::ManageRepositories));
                        prop_assert!(!user.has_permission(Permission::ViewAllRepositories));
                    },
                }

                // Update user role
                let updated_user = service.update_user(
                    user.id,
                    None,
                    None,
                    None,
                    Some(new_role.clone()),
                    None
                ).await.unwrap();

                // Verify updated permissions based on new role
                prop_assert_eq!(updated_user.role, new_role);
                match new_role {
                    UserRole::Admin => {
                        prop_assert!(updated_user.has_permission(Permission::ManageUsers));
                    },
                    UserRole::Maintainer => {
                        prop_assert!(!updated_user.has_permission(Permission::ManageUsers));
                        prop_assert!(updated_user.has_permission(Permission::ManageRepositories));
                    },
                    UserRole::User => {
                        prop_assert!(!updated_user.has_permission(Permission::ManageUsers));
                        prop_assert!(!updated_user.has_permission(Permission::ManageRepositories));
                    },
                }

                // Add custom permission
                let user_with_custom_permission = service.add_user_permission(
                    updated_user.id,
                    Permission::ManageUsers
                ).await.unwrap();

                // Verify custom permission was added
                prop_assert!(user_with_custom_permission.has_permission(Permission::ManageUsers));

                // Remove custom permission
                let user_without_permission = service.remove_user_permission(
                    user_with_custom_permission.id,
                    Permission::ManageUsers
                ).await.unwrap();

                // Verify permission was removed if user's role doesn't inherently include it
                if new_role != UserRole::Admin {
                    prop_assert!(!user_without_permission.has_permission(Permission::ManageUsers));
                } else {
                    // Admin role always has ManageUsers permission regardless of removal attempt
                    prop_assert!(user_without_permission.has_permission(Permission::ManageUsers));
                }
            });
        }

        #[test]
        fn test_user_service_concurrent_operations(
            operations in user_operations(5)
        ) {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            rt.block_on(async {
                // Set up test database and service
                let pool = setup_test_db().await.unwrap();
                let repo = Arc::new(UserRepository::new(pool));
                let service = Arc::new(UserService::new(repo, 3600, 5, 300));
                service.initialize().await.unwrap();

                // Track created users for validation
                let users = Arc::new(Mutex::new(Vec::new()));
                let sessions = Arc::new(Mutex::new(Vec::new()));

                // Process operations in sequence to build expected state
                for op in operations {
                    match op {
                        UserOperation::Create { username, email, full_name, password, role } => {
                            // Skip if username or email already exists
                            let existing_usernames: HashSet<_> = users.lock().unwrap()
                                .iter()
                                .map(|u: &User| u.username.clone())
                                .collect();

                            let existing_emails: HashSet<_> = users.lock().unwrap()
                                .iter()
                                .map(|u: &User| u.email.clone())
                                .collect();

                            if !existing_usernames.contains(&username) && !existing_emails.contains(&email) {
                                match service.create_user(
                                    username,
                                    email,
                                    full_name,
                                    &password,
                                    role
                                ).await {
                                    Ok(user) => {
                                        users.lock().unwrap().push(user);
                                    },
                                    Err(_) => {
                                        // Ignore creation errors in this test
                                    }
                                }
                            }
                        },
                        UserOperation::Update { id, email, full_name, password, role, active } => {
                            let users_guard = users.lock().unwrap();
                            if id < users_guard.len() {
                                let user_id = users_guard[id].id;
                                drop(users_guard);

                                if let Ok(updated_user) = service.update_user(
                                    user_id,
                                    email,
                                    full_name,
                                    password.as_deref(),
                                    role,
                                    active
                                ).await {
                                    let mut users_guard = users.lock().unwrap();
                                    for i in 0..users_guard.len() {
                                        if users_guard[i].id == user_id {
                                            users_guard[i] = updated_user;
                                            break;
                                        }
                                    }
                                }
                            }
                        },
                        UserOperation::Get { id } => {
                            let users_guard = users.lock().unwrap();
                            if id < users_guard.len() {
                                let user_id = users_guard[id].id;
                                drop(users_guard);

                                let _ = service.get_user(user_id).await;
                            }
                        },
                        UserOperation::GetByUsername { username } => {
                            let _ = service.get_user_by_username(&username).await;
                        },
                        UserOperation::Delete { id } => {
                            let mut users_guard = users.lock().unwrap();
                            if id < users_guard.len() {
                                let user_id = users_guard[id].id;
                                let username = users_guard[id].username.clone();

                                // Remove from sessions first
                                let mut sessions_guard = sessions.lock().unwrap();
                                sessions_guard.retain(|(user, _)| user.username != username);
                                drop(sessions_guard);

                                drop(users_guard);

                                if service.delete_user(user_id).await.is_ok() {
                                    let mut users_guard = users.lock().unwrap();
                                    users_guard.retain(|u| u.id != user_id);
                                }
                            }
                        },
                        UserOperation::Login { username, password } => {
                            // Find the user
                            let users_guard = users.lock().unwrap();
                            let user_opt = users_guard.iter()
                                .find(|u| u.username == username);

                            if let Some(user) = user_opt {
                                let user_clone = user.clone();
                                drop(users_guard);

                                // Try to log in
                                match service.login(
                                    &username,
                                    &password,
                                    "127.0.0.1".to_string(),
                                    "test-agent".to_string()
                                ).await {
                                    Ok((user, session)) => {
                                        sessions.lock().unwrap().push((user, session));
                                    },
                                    Err(_) => {
                                        // Expected for wrong passwords
                                    }
                                }
                            }
                        },
                        UserOperation::Logout { session_id } => {
                            let mut sessions_guard = sessions.lock().unwrap();
                            if !sessions_guard.is_empty() {
                                let idx = session_id.as_bytes()[0] as usize % sessions_guard.len();
                                let session_token = sessions_guard[idx].1.token.clone();
                                drop(sessions_guard);

                                if service.logout(&session_token).await.is_ok() {
                                    let mut sessions_guard = sessions.lock().unwrap();
                                    sessions_guard.retain(|(_, s)| s.token != session_token);
                                }
                            }
                        }
                    }
                }

                // Verify the final state
                let users_guard = users.lock().unwrap();
                for user in users_guard.iter() {
                    // Get the user and verify it exists
                    let retrieved_user = service.get_user(user.id).await.unwrap();
                    prop_assert_eq!(retrieved_user.username, user.username);
                    prop_assert_eq!(retrieved_user.email, user.email);
                }

                // Verify sessions
                let sessions_guard = sessions.lock().unwrap();
                for (user, session) in sessions_guard.iter() {
                    // Get the session and verify if it exists
                    if let Ok(Some(active_session)) = service.get_session(&session.token).await {
                        prop_assert_eq!(active_session.id, user.id);
                    }
                }
            });
        }
    }
}
