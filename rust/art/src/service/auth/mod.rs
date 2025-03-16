//! Authentication and authorization service for Art.
//!
//! This module provides authentication and authorization functionalities
//! for the Art application, allowing control over repository access.

use crate::data::Sqlite;
use crate::error::{Error, Result};
use crate::data::cache::Cache;
use crate::service::repository::RepositoryService;

use std::sync::Arc;
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime};
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use tracing::{debug, error, info, trace, warn};
use sha2::{Sha256, Digest};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use rand::{thread_rng, Rng, distributions::Alphanumeric};

/// Authentication and authorization service
pub struct AuthService {
    /// Database access
    db: Arc<Sqlite>,

    /// Cache
    cache: Arc<Cache>,

    /// Repository service
    repository_service: Arc<RepositoryService>,
}

/// User information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    /// User ID
    pub id: String,

    /// Username
    pub username: String,

    /// Email
    pub email: Option<String>,

    /// Display name
    pub display_name: Option<String>,

    /// Roles
    pub roles: Vec<String>,

    /// Is admin user
    pub is_admin: bool,

    /// Created timestamp
    pub created_at: DateTime<Utc>,

    /// Last login timestamp
    pub last_login: Option<DateTime<Utc>>,
}

/// Authentication token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthToken {
    /// Token value
    pub token: String,

    /// User ID
    pub user_id: String,

    /// Token creation time
    pub created_at: DateTime<Utc>,

    /// Token expiration time
    pub expires_at: DateTime<Utc>,

    /// Token scope
    pub scope: Vec<String>,
}

/// Permission type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PermissionType {
    /// Read permission
    Read,

    /// Write permission
    Write,

    /// Admin permission
    Admin,
}

/// Repository permission
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryPermission {
    /// Repository name
    pub repository: String,

    /// User ID
    pub user_id: String,

    /// Permission type
    pub permission: PermissionType,

    /// Created timestamp
    pub created_at: DateTime<Utc>,

    /// Last updated timestamp
    pub updated_at: DateTime<Utc>,
}

impl AuthService {
    /// Create a new authentication service
    pub fn new(db: Arc<Sqlite>, cache: Arc<Cache>, repository_service: Arc<RepositoryService>) -> Self {
        Self {
            db,
            cache,
            repository_service,
        }
    }

    /// Authenticate a user with username and password
    pub async fn authenticate(&self, username: &str, password: &str) -> Result<Option<User>> {
        // Try cache first
        let cache_key = format!("auth:user:{}", username);
        if let Some(user_data) = self.cache.get::<String>(&cache_key).await {
            // Check if stored password hash matches
            let stored_hash = user_data;
            let salt = username; // Use username as a simple salt
            let calculated_hash = self.hash_password(password, salt);

            if stored_hash == calculated_hash {
                // Get user from cache
                let user_cache_key = format!("user:{}", username);
                if let Some(user) = self.cache.get::<User>(&user_cache_key).await {
                    return Ok(Some(user));
                }
            }
        }

        // Check database
        match self.get_user_by_username(username).await? {
            Some(user) => {
                // Verify password
                let salt = username; // Use username as a simple salt
                let calculated_hash = self.hash_password(password, salt);

                // TODO: Properly retrieve stored hash from database
                let stored_hash = "mock_hash"; // Replace with actual database lookup

                if calculated_hash == stored_hash {
                    // Update last login
                    self.update_last_login(&user.id).await?;

                    // Cache authentication
                    self.cache.set(&cache_key, &calculated_hash).await;

                    // Cache user
                    let user_cache_key = format!("user:{}", username);
                    self.cache.set(&user_cache_key, &user).await;

                    Ok(Some(user))
                } else {
                    Ok(None)
                }
            },
            None => Ok(None),
        }
    }

    /// Authenticate a user with API token
    pub async fn authenticate_token(&self, token: &str) -> Result<Option<User>> {
        // Check if token is valid
        let token_cache_key = format!("auth:token:{}", token);
        if let Some(token_data) = self.cache.get::<AuthToken>(&token_cache_key).await {
            if token_data.expires_at > Utc::now() {
                // Token is valid, get user
                return self.get_user_by_id(&token_data.user_id).await;
            }
        }

        // TODO: Check database for token
        let auth_token = None; // Replace with database lookup

        match auth_token {
            Some(token_data) => {
                // Check if token has expired
                if token_data.expires_at <= Utc::now() {
                    return Ok(None);
                }

                // Get user
                let user = self.get_user_by_id(&token_data.user_id).await?;

                // Cache token
                self.cache.set(&token_cache_key, &token_data).await;

                Ok(user)
            },
            None => Ok(None),
        }
    }

    /// Create a new authentication token for a user
    pub async fn create_token(&self, user_id: &str, expires_in: Duration, scope: Vec<String>) -> Result<AuthToken> {
        // Generate random token
        let token = self.generate_token(32);

        // Create token with expiry
        let created_at = Utc::now();
        let expires_at = created_at + chrono::Duration::from_std(expires_in).unwrap_or_default();

        let auth_token = AuthToken {
            token: token.clone(),
            user_id: user_id.to_string(),
            created_at,
            expires_at,
            scope,
        };

        // TODO: Store token in database

        // Cache token
        let token_cache_key = format!("auth:token:{}", token);
        self.cache.set(&token_cache_key, &auth_token).await;

        Ok(auth_token)
    }

    /// Check if a user has permission for a repository
    pub async fn check_permission(&self,
        user_id: &str,
        repository: &str,
        required_permission: PermissionType
    ) -> Result<bool> {
        // Validate repository name
        let repo_name = self.repository_service.sanitize_repository_name(repository)?;

        // Check if user is admin
        let user = self.get_user_by_id(user_id).await?;
        if let Some(user) = user {
            if user.is_admin {
                return Ok(true);
            }
        } else {
            return Ok(false);
        }

        // Check cache for permission
        let perm_cache_key = format!("perm:{}:{}", user_id, repo_name);
        if let Some(perm) = self.cache.get::<PermissionType>(&perm_cache_key).await {
            // Check if the cached permission is sufficient
            return Ok(self.is_permission_sufficient(perm, required_permission));
        }

        // Check database for permission
        let permission = self.get_repository_permission(user_id, &repo_name).await?;

        match permission {
            Some(perm) => {
                // Cache permission
                self.cache.set(&perm_cache_key, &perm.permission).await;

                Ok(self.is_permission_sufficient(perm.permission, required_permission))
            },
            None => Ok(false),
        }
    }

    /// Grant permission to a user for a repository
    pub async fn grant_permission(&self,
        user_id: &str,
        repository: &str,
        permission: PermissionType
    ) -> Result<RepositoryPermission> {
        // Validate repository name
        let repo_name = self.repository_service.sanitize_repository_name(repository)?;

        // Check if user exists
        if self.get_user_by_id(user_id).await?.is_none() {
            return Err(Error::NotFound(format!("User {} not found", user_id)));
        }

        // Create or update permission
        let now = Utc::now();
        let repo_permission = RepositoryPermission {
            repository: repo_name.clone(),
            user_id: user_id.to_string(),
            permission,
            created_at: now,
            updated_at: now,
        };

        // TODO: Store in database

        // Invalidate cache
        let perm_cache_key = format!("perm:{}:{}", user_id, repo_name);
        self.cache.invalidate(&perm_cache_key).await;

        Ok(repo_permission)
    }

    /// Revoke permission from a user for a repository
    pub async fn revoke_permission(&self, user_id: &str, repository: &str) -> Result<()> {
        // Validate repository name
        let repo_name = self.repository_service.sanitize_repository_name(repository)?;

        // TODO: Remove from database

        // Invalidate cache
        let perm_cache_key = format!("perm:{}:{}", user_id, repo_name);
        self.cache.invalidate(&perm_cache_key).await;

        Ok(())
    }

    /// Get user by username
    async fn get_user_by_username(&self, username: &str) -> Result<Option<User>> {
        // TODO: Get from database
        // For now, return a mock user for testing
        if username == "admin" {
            Ok(Some(User {
                id: "1".to_string(),
                username: username.to_string(),
                email: Some("admin@example.com".to_string()),
                display_name: Some("Administrator".to_string()),
                roles: vec!["admin".to_string()],
                is_admin: true,
                created_at: Utc::now(),
                last_login: Some(Utc::now()),
            }))
        } else if username == "user" {
            Ok(Some(User {
                id: "2".to_string(),
                username: username.to_string(),
                email: Some("user@example.com".to_string()),
                display_name: Some("Test User".to_string()),
                roles: vec!["user".to_string()],
                is_admin: false,
                created_at: Utc::now(),
                last_login: Some(Utc::now()),
            }))
        } else {
            Ok(None)
        }
    }

    /// Get user by ID
    async fn get_user_by_id(&self, user_id: &str) -> Result<Option<User>> {
        // TODO: Get from database
        // For now, return a mock user for testing
        if user_id == "1" {
            Ok(Some(User {
                id: user_id.to_string(),
                username: "admin".to_string(),
                email: Some("admin@example.com".to_string()),
                display_name: Some("Administrator".to_string()),
                roles: vec!["admin".to_string()],
                is_admin: true,
                created_at: Utc::now(),
                last_login: Some(Utc::now()),
            }))
        } else if user_id == "2" {
            Ok(Some(User {
                id: user_id.to_string(),
                username: "user".to_string(),
                email: Some("user@example.com".to_string()),
                display_name: Some("Test User".to_string()),
                roles: vec!["user".to_string()],
                is_admin: false,
                created_at: Utc::now(),
                last_login: Some(Utc::now()),
            }))
        } else {
            Ok(None)
        }
    }

    /// Update user's last login time
    async fn update_last_login(&self, user_id: &str) -> Result<()> {
        // TODO: Update in database
        Ok(())
    }

    /// Get repository permission
    async fn get_repository_permission(&self, user_id: &str, repository: &str) -> Result<Option<RepositoryPermission>> {
        // TODO: Get from database
        // For now, return a mock permission for testing
        if user_id == "2" && repository == "test-repo" {
            Ok(Some(RepositoryPermission {
                repository: repository.to_string(),
                user_id: user_id.to_string(),
                permission: PermissionType::Read,
                created_at: Utc::now(),
                updated_at: Utc::now(),
            }))
        } else {
            Ok(None)
        }
    }

    /// Check if a permission is sufficient for a required permission
    fn is_permission_sufficient(&self, granted: PermissionType, required: PermissionType) -> bool {
        match (granted, required) {
            (PermissionType::Admin, _) => true,
            (PermissionType::Write, PermissionType::Read) => true,
            (PermissionType::Write, PermissionType::Write) => true,
            (PermissionType::Read, PermissionType::Read) => true,
            _ => false,
        }
    }

    /// Hash a password
    fn hash_password(&self, password: &str, salt: &str) -> String {
        // Simple password hashing for demonstration
        // In production, use a proper password hashing algorithm like bcrypt, argon2, etc.
        // TODO - use argon2
        let mut hasher = Sha256::new();
        hasher.update(password);
        hasher.update(salt);
        let result = hasher.finalize();
        BASE64.encode(result)
    }

    /// Generate a random token
    fn generate_token(&self, length: usize) -> String {
        thread_rng()
            .sample_iter(&Alphanumeric)
            .take(length)
            .map(char::from)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::data::Git;
    use tempfile::TempDir;

    /// Create a test authentication service
    async fn create_test_service() -> (AuthService, TempDir) {
        // Create a temporary directory
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let temp_path = temp_dir.path().to_string_lossy().to_string();

        // Create SQLite database
        let db_path = temp_dir.path().join("test.db");
        let db = Arc::new(Sqlite::open(&db_path.to_string_lossy().to_string()).expect("Failed to create database"));

        // Create cache
        let cache = Arc::new(Cache::new().await);

        // Create Git data access
        let git = Arc::new(Git::new(&temp_dir.path().to_string_lossy().to_string()).expect("Failed to create Git manager"));

        // Create repository service
        let repo_service = Arc::new(RepositoryService::new(git, db.clone(), cache.clone()));

        // Create authentication service
        let auth_service = AuthService::new(db, cache, repo_service);

        (auth_service, temp_dir)
    }

    #[tokio::test]
    async fn test_user_authentication() {
        let (service, _temp_dir) = create_test_service().await;

        // Test admin authentication
        let admin = service.authenticate("admin", "password").await.expect("Authentication should succeed");
        assert!(admin.is_some());
        assert_eq!(admin.unwrap().username, "admin");

        // Test user authentication
        let user = service.authenticate("user", "password").await.expect("Authentication should succeed");
        assert!(user.is_some());
        assert_eq!(user.unwrap().username, "user");

        // Test invalid authentication
        let invalid = service.authenticate("invalid", "password").await.expect("Authentication should succeed");
        assert!(invalid.is_none());
    }

    #[tokio::test]
    async fn test_token_creation() {
        let (service, _temp_dir) = create_test_service().await;

        // Create token
        let token = service.create_token("1", Duration::from_secs(3600), vec!["read".to_string()]).await.expect("Token creation should succeed");

        assert!(!token.token.is_empty());
        assert_eq!(token.user_id, "1");
        assert!(token.expires_at > token.created_at);
        assert_eq!(token.scope, vec!["read"]);
    }

    #[tokio::test]
    async fn test_permission_checking() {
        let (service, _temp_dir) = create_test_service().await;

        // Test admin permission (always granted)
        let admin_perm = service.check_permission("1", "test-repo", PermissionType::Write).await.expect("Permission check should succeed");
        assert!(admin_perm);

        // Test user with read permission
        let user_read_perm = service.check_permission("2", "test-repo", PermissionType::Read).await.expect("Permission check should succeed");
        assert!(user_read_perm);

        // Test user without write permission
        let user_write_perm = service.check_permission("2", "test-repo", PermissionType::Write).await.expect("Permission check should succeed");
        assert!(!user_write_perm);
    }
}

#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use std::time::Duration;

    // Strategy for generating valid user IDs
    fn user_id_strategy() -> impl Strategy<Value = String> {
        "[1-9][0-9]{0,5}"
    }

    // Strategy for generating valid usernames
    fn username_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z][a-zA-Z0-9_-]{3,20}"
    }

    // Strategy for generating valid email addresses
    fn email_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
    }

    // Strategy for generating valid repository names
    fn repository_name_strategy() -> impl Strategy<Value = String> {
        "[a-zA-Z][a-zA-Z0-9_-]{1,20}"
    }

    // Strategy for generating permission types
    fn permission_type_strategy() -> impl Strategy<Value = PermissionType> {
        prop_oneof![
            Just(PermissionType::Read),
            Just(PermissionType::Write),
            Just(PermissionType::Admin)
        ]
    }

    proptest! {
        /// Test that password hashing produces consistent results
        #[test]
        fn password_hashing_is_consistent(
            password in "[a-zA-Z0-9!@#$%^&*()]{6,20}",
            salt in "[a-zA-Z0-9]{1,10}"
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (service, _temp_dir) = create_test_service().await;

                // Hash the password twice with the same salt
                let hash1 = service.hash_password(&password, &salt);
                let hash2 = service.hash_password(&password, &salt);

                // The hashes should be identical
                assert_eq!(hash1, hash2, "Password hashing should be consistent");

                // Different password should produce different hash
                if !password.is_empty() {
                    let modified_password = format!("{}X", &password[0..password.len()-1]);
                    let hash3 = service.hash_password(&modified_password, &salt);
                    assert_ne!(hash1, hash3, "Different passwords should produce different hashes");
                }

                // Different salt should produce different hash
                if !salt.is_empty() {
                    let modified_salt = format!("{}X", &salt[0..salt.len()-1]);
                    let hash4 = service.hash_password(&password, &modified_salt);
                    assert_ne!(hash1, hash4, "Different salts should produce different hashes");
                }
            });
        }

        /// Test that permission checking follows the defined rules
        #[test]
        fn permission_checking_follows_rules(
            granted in permission_type_strategy(),
            required in permission_type_strategy()
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (service, _temp_dir) = create_test_service().await;

                // Check permission according to the rules
                let result = service.is_permission_sufficient(granted, required);

                // Verify the result matches the expected rules
                match (granted, required) {
                    (PermissionType::Admin, _) => assert!(result, "Admin should have access to everything"),
                    (PermissionType::Write, PermissionType::Read) => assert!(result, "Write permission should grant Read access"),
                    (PermissionType::Write, PermissionType::Write) => assert!(result, "Write permission should grant Write access"),
                    (PermissionType::Read, PermissionType::Read) => assert!(result, "Read permission should grant Read access"),
                    (PermissionType::Read, PermissionType::Write) => assert!(!result, "Read permission should not grant Write access"),
                    (PermissionType::Read, PermissionType::Admin) => assert!(!result, "Read permission should not grant Admin access"),
                    (PermissionType::Write, PermissionType::Admin) => assert!(!result, "Write permission should not grant Admin access"),
                }
            });
        }

        /// Test that token generation produces valid tokens
        #[test]
        fn token_generation_produces_valid_tokens(
            length in 16usize..100usize
        ) {
            // Create a test service
            let rt = tokio::runtime::Runtime::new().unwrap();

            rt.block_on(async {
                let (service, _temp_dir) = create_test_service().await;

                // Generate a token
                let token = service.generate_token(length);

                // Verify the token length
                assert_eq!(token.len(), length, "Token length should match requested length");

                // Verify the token contains only valid characters
                assert!(token.chars().all(|c| c.is_ascii_alphanumeric()), "Token should contain only alphanumeric characters");

                // Generate another token - they should be different
                let token2 = service.generate_token(length);
                assert_ne!(token, token2, "Two generated tokens should be different");
            });
        }

        /// Test user serialization and deserialization
        #[test]
        fn user_serializes_and_deserializes_correctly(
            id in user_id_strategy(),
            username in username_strategy(),
            has_email in proptest::bool::ANY,
            has_display_name in proptest::bool::ANY,
            is_admin in proptest::bool::ANY
        ) {
            // Create test role
            let roles = vec![
                if is_admin { "admin".to_string() } else { "user".to_string() }
            ];

            // Create email and display name if requested
            let email = if has_email {
                Some(format!("{}@example.com", username))
            } else {
                None
            };

            let display_name = if has_display_name {
                Some(format!("Test {}", username))
            } else {
                None
            };

            // Current time
            let now = Utc::now();

            // Create user
            let user = User {
                id: id.clone(),
                username: username.clone(),
                email: email.clone(),
                display_name: display_name.clone(),
                roles: roles.clone(),
                is_admin,
                created_at: now,
                last_login: Some(now),
            };

            // Serialize to JSON
            let json = serde_json::to_string(&user).expect("Serialization should succeed");

            // Deserialize from JSON
            let deserialized: User = serde_json::from_str(&json).expect("Deserialization should succeed");

            // Verify fields match
            assert_eq!(deserialized.id, id);
            assert_eq!(deserialized.username, username);
            assert_eq!(deserialized.email, email);
            assert_eq!(deserialized.display_name, display_name);
            assert_eq!(deserialized.roles, roles);
            assert_eq!(deserialized.is_admin, is_admin);

            // The serialized JSON should include all relevant fields
            assert!(json.contains(&id));
            assert!(json.contains(&username));

            if let Some(email_str) = &email {
                assert!(json.contains(email_str));
            }

            if let Some(display_name_str) = &display_name {
                assert!(json.contains(display_name_str));
            }

            assert!(json.contains(&is_admin.to_string()));
        }
    }
}
