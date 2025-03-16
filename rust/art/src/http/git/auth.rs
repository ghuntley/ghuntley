//! Git HTTP authentication module
//!
//! This module provides authentication services for Git HTTP operations.
//! It supports basic authentication, token-based authentication, and
//! the ability to implement custom authentication providers.

use async_trait::async_trait;
use std::sync::Arc;
use std::collections::HashMap;
use crate::error::{Error, Result};
use axum::http::HeaderMap;

/// Git authentication configuration
#[derive(Debug, Clone)]
pub struct GitAuthConfig {
    /// Whether authentication is required for read operations
    pub require_auth_for_read: bool,

    /// Whether authentication is required for write operations
    pub require_auth_for_write: bool,

    /// Authentication realm name
    pub realm: String,

    /// HTTP header to use for authentication (if not standard)
    pub auth_header: Option<String>,

    /// Whether to use bearer token authentication
    pub use_bearer_auth: bool,
}

impl Default for GitAuthConfig {
    fn default() -> Self {
        Self {
            require_auth_for_read: false,
            require_auth_for_write: true,
            realm: "Git".to_string(),
            auth_header: None,
            use_bearer_auth: false,
        }
    }
}

/// Git operation type for permission checks
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitOperation {
    /// Read-only operations (fetch, clone)
    Read,

    /// Write operations (push)
    Write,
}

/// Git authentication credentials
#[derive(Debug, Clone)]
pub enum GitCredentials {
    /// Basic authentication with username and password
    Basic {
        username: String,
        password: String,
    },

    /// Token-based authentication
    Token(String),

    /// No credentials provided
    None,
}

/// Git authentication result
#[derive(Debug, Clone)]
pub struct GitAuthResult {
    /// Whether authentication was successful
    pub authenticated: bool,

    /// User identity if authenticated
    pub user: Option<String>,

    /// User roles/permissions if authenticated
    pub roles: Vec<String>,

    /// Additional metadata about the authentication
    pub metadata: HashMap<String, String>,
}

impl GitAuthResult {
    /// Create a new successful authentication result
    pub fn success(user: String) -> Self {
        Self {
            authenticated: true,
            user: Some(user),
            roles: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    /// Create a new successful authentication result with roles
    pub fn with_roles(user: String, roles: Vec<String>) -> Self {
        Self {
            authenticated: true,
            user: Some(user),
            roles,
            metadata: HashMap::new(),
        }
    }

    /// Create a new failed authentication result
    pub fn failure() -> Self {
        Self {
            authenticated: false,
            user: None,
            roles: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    /// Add metadata to the authentication result
    pub fn with_metadata(mut self, key: &str, value: &str) -> Self {
        self.metadata.insert(key.to_string(), value.to_string());
        self
    }

    /// Add a role to the authentication result
    pub fn add_role(&mut self, role: &str) {
        self.roles.push(role.to_string());
    }
}

/// Git authentication service trait
///
/// This trait defines the interface for authentication services.
/// Implement this trait to create custom authentication providers.
#[async_trait]
pub trait GitAuthService: Send + Sync {
    /// Authenticate a user based on HTTP headers
    async fn authenticate(&self, headers: &HeaderMap) -> Result<GitAuthResult>;

    /// Check if a user has permission for a given repository and operation
    async fn check_permission(
        &self,
        auth_result: &GitAuthResult,
        repo_name: &str,
        operation: GitOperation,
    ) -> Result<bool>;

    /// Get the authentication configuration
    fn config(&self) -> &GitAuthConfig;

    /// Extract credentials from HTTP headers
    fn extract_credentials(&self, headers: &HeaderMap) -> GitCredentials {
        // Get the header name to use for authentication
        let auth_header_name = self.config().auth_header
            .as_deref()
            .unwrap_or("authorization");

        // Get the authorization header
        let auth_header = match headers.get(auth_header_name) {
            Some(value) => value,
            None => return GitCredentials::None,
        };

        // Convert header value to string
        let auth_value = match auth_header.to_str() {
            Ok(value) => value,
            Err(_) => return GitCredentials::None,
        };

        // Check if using bearer token authentication
        if self.config().use_bearer_auth {
            if let Some(token) = auth_value.strip_prefix("Bearer ") {
                return GitCredentials::Token(token.to_string());
            }
            return GitCredentials::None;
        }

        // Check for basic authentication
        if let Some(base64) = auth_value.strip_prefix("Basic ") {
            // Decode Base64
            let decoded = match base64::decode(base64) {
                Ok(bytes) => bytes,
                Err(_) => return GitCredentials::None,
            };

            // Convert to string
            let credentials = match String::from_utf8(decoded) {
                Ok(s) => s,
                Err(_) => return GitCredentials::None,
            };

            // Split username and password
            let parts: Vec<&str> = credentials.split(':').collect();
            if parts.len() == 2 {
                return GitCredentials::Basic {
                    username: parts[0].to_string(),
                    password: parts[1].to_string(),
                };
            }
        }

        GitCredentials::None
    }
}

/// Basic authentication service using a username/password map
pub struct BasicAuthService {
    /// Authentication configuration
    config: GitAuthConfig,

    /// Username/password map
    credentials: HashMap<String, String>,

    /// User roles map
    roles: HashMap<String, Vec<String>>,

    /// Repository permissions (repo_name -> [(user, operation_type)])
    repo_permissions: HashMap<String, Vec<(String, GitOperation)>>,
}

impl BasicAuthService {
    /// Create a new basic authentication service
    pub fn new(config: GitAuthConfig) -> Self {
        Self {
            config,
            credentials: HashMap::new(),
            roles: HashMap::new(),
            repo_permissions: HashMap::new(),
        }
    }

    /// Add a user with password
    pub fn add_user(mut self, username: &str, password: &str) -> Self {
        self.credentials.insert(username.to_string(), password.to_string());
        self
    }

    /// Add a role to a user
    pub fn add_role(mut self, username: &str, role: &str) -> Self {
        let roles = self.roles.entry(username.to_string()).or_insert_with(Vec::new);
        roles.push(role.to_string());
        self
    }

    /// Add a repository permission for a user
    pub fn add_permission(
        mut self,
        username: &str,
        repo_name: &str,
        operation: GitOperation,
    ) -> Self {
        let permissions = self.repo_permissions
            .entry(repo_name.to_string())
            .or_insert_with(Vec::new);

        permissions.push((username.to_string(), operation));
        self
    }

    /// Check if a password is valid for a user
    fn check_password(&self, username: &str, password: &str) -> bool {
        match self.credentials.get(username) {
            Some(stored_password) => stored_password == password,
            None => false,
        }
    }

    /// Get roles for a user
    fn get_user_roles(&self, username: &str) -> Vec<String> {
        match self.roles.get(username) {
            Some(roles) => roles.clone(),
            None => Vec::new(),
        }
    }
}

#[async_trait]
impl GitAuthService for BasicAuthService {
    async fn authenticate(&self, headers: &HeaderMap) -> Result<GitAuthResult> {
        // Extract credentials from headers
        let credentials = self.extract_credentials(headers);

        match credentials {
            GitCredentials::Basic { username, password } => {
                // Check if password is valid
                if self.check_password(&username, &password) {
                    // Get user roles
                    let roles = self.get_user_roles(&username);

                    // Return successful authentication result
                    Ok(GitAuthResult::with_roles(username, roles))
                } else {
                    // Return failed authentication result
                    Ok(GitAuthResult::failure())
                }
            },
            GitCredentials::Token(_) => {
                // Token authentication not supported by BasicAuthService
                Ok(GitAuthResult::failure())
            },
            GitCredentials::None => {
                // No credentials provided
                Ok(GitAuthResult::failure())
            },
        }
    }

    async fn check_permission(
        &self,
        auth_result: &GitAuthResult,
        repo_name: &str,
        operation: GitOperation,
    ) -> Result<bool> {
        // If not authenticated, deny access
        if !auth_result.authenticated {
            return Ok(false);
        }

        // Get the authenticated username
        let username = match &auth_result.user {
            Some(username) => username,
            None => return Ok(false),
        };

        // If repository is not in permissions map, allow access (for backward compatibility)
        if !self.repo_permissions.contains_key(repo_name) {
            return Ok(true);
        }

        // Check if user has permission for this repository and operation
        match self.repo_permissions.get(repo_name) {
            Some(permissions) => {
                // Check if user has permission for this operation
                for (user, op) in permissions {
                    if user == username && (op == &operation || op == &GitOperation::Read) {
                        return Ok(true);
                    }
                }

                // No matching permission found
                Ok(false)
            },
            None => {
                // Repository not found in permissions map
                Ok(false)
            },
        }
    }

    fn config(&self) -> &GitAuthConfig {
        &self.config
    }
}

/// User-based authentication service using the UserService
pub struct UserAuthService {
    /// Authentication configuration
    config: GitAuthConfig,

    /// User service instance
    user_service: Arc<crate::service::user::UserService>,

    /// Repository permissions (repo_name -> [(role, operation_type)])
    repo_permissions: HashMap<String, Vec<(String, GitOperation)>>,
}

impl UserAuthService {
    /// Create a new user-based authentication service
    pub fn new(config: GitAuthConfig, user_service: Arc<crate::service::user::UserService>) -> Self {
        Self {
            config,
            user_service,
            repo_permissions: HashMap::new(),
        }
    }

    /// Add a repository permission for a role
    ///
    /// This associates a repository with a role and operation type.
    /// Users with the specified role will be granted permission to
    /// perform the operation on the repository.
    pub fn add_role_permission(
        mut self,
        role: &str,
        repo_name: &str,
        operation: GitOperation,
    ) -> Self {
        let permissions = self.repo_permissions
            .entry(repo_name.to_string())
            .or_insert_with(Vec::new);

        permissions.push((role.to_string(), operation));
        self
    }

    /// Set default permissions for all repositories
    ///
    /// This adds default permissions for common roles:
    /// - Admin: Read and Write to all repositories
    /// - Maintainer: Read and Write to all repositories
    /// - User: Read to all repositories (if configured to allow reads)
    pub fn with_default_permissions(mut self) -> Self {
        // Define a special "all" repository for default permissions
        let all_repos = "*";

        // Admins can do everything
        let admin_permissions = self.repo_permissions
            .entry(all_repos.to_string())
            .or_insert_with(Vec::new);

        admin_permissions.push(("admin".to_string(), GitOperation::Read));
        admin_permissions.push(("admin".to_string(), GitOperation::Write));

        // Maintainers can do everything
        admin_permissions.push(("maintainer".to_string(), GitOperation::Read));
        admin_permissions.push(("maintainer".to_string(), GitOperation::Write));

        // Users can read if configured
        if !self.config.require_auth_for_read {
            admin_permissions.push(("user".to_string(), GitOperation::Read));
        }

        self
    }
}

#[async_trait]
impl GitAuthService for UserAuthService {
    async fn authenticate(&self, headers: &HeaderMap) -> Result<GitAuthResult> {
        // Extract credentials from headers
        let credentials = self.extract_credentials(headers);

        match credentials {
            GitCredentials::Basic { username, password } => {
                // Get IP address and user agent for session tracking
                let ip_address = headers
                    .get("x-forwarded-for")
                    .and_then(|h| h.to_str().ok())
                    .unwrap_or("unknown")
                    .to_string();

                let user_agent = headers
                    .get("user-agent")
                    .and_then(|h| h.to_str().ok())
                    .unwrap_or("unknown")
                    .to_string();

                // Authenticate user
                match self.user_service.login(&username, &password, ip_address, user_agent).await {
                    Ok((user, session)) => {
                        // Create successful auth result
                        let mut result = GitAuthResult::success(user.username.clone());

                        // Add role
                        let role = user.role.as_str().to_lowercase();
                        result.add_role(&role);

                        // Add metadata
                        result = result
                            .with_metadata("user_id", &user.id.to_string())
                            .with_metadata("email", &user.email)
                            .with_metadata("display_name", &user.display_name)
                            .with_metadata("session_id", &session.id);

                        Ok(result)
                    },
                    Err(_) => {
                        // Authentication failed
                        Ok(GitAuthResult::failure())
                    }
                }
            },
            GitCredentials::Token(token) => {
                // Treat token as session ID
                match self.user_service.get_session_user(&token).await {
                    Ok(Some(user)) => {
                        // Create successful auth result
                        let mut result = GitAuthResult::success(user.username.clone());

                        // Add role
                        let role = user.role.as_str().to_lowercase();
                        result.add_role(&role);

                        // Add metadata
                        result = result
                            .with_metadata("user_id", &user.id.to_string())
                            .with_metadata("email", &user.email)
                            .with_metadata("display_name", &user.display_name)
                            .with_metadata("session_id", &token);

                        Ok(result)
                    },
                    _ => {
                        // Invalid token or session expired
                        Ok(GitAuthResult::failure())
                    }
                }
            },
            GitCredentials::None => {
                // No credentials provided
                Ok(GitAuthResult::failure())
            }
        }
    }

    async fn check_permission(
        &self,
        auth_result: &GitAuthResult,
        repo_name: &str,
        operation: GitOperation,
    ) -> Result<bool> {
        // If not authenticated, deny access
        if !auth_result.authenticated {
            return Ok(false);
        }

        // If read operations don't require auth and this is a read operation, allow
        if !self.config.require_auth_for_read && operation == GitOperation::Read {
            return Ok(true);
        }

        // Get user roles
        let roles = &auth_result.roles;
        if roles.is_empty() {
            return Ok(false);
        }

        // Check repository-specific permissions
        if let Some(permissions) = self.repo_permissions.get(repo_name) {
            for (role, op) in permissions {
                if roles.contains(role) && op == &operation {
                    return Ok(true);
                }
            }
        }

        // Check global permissions (for "*" wildcard repository)
        if let Some(permissions) = self.repo_permissions.get("*") {
            for (role, op) in permissions {
                if roles.contains(role) && op == &operation {
                    return Ok(true);
                }
            }
        }

        // No matching permission found
        Ok(false)
    }

    fn config(&self) -> &GitAuthConfig {
        &self.config
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn create_auth_header(username: &str, password: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();

        // Create basic auth header
        let credentials = format!("{}:{}", username, password);
        let encoded = base64::encode(credentials);
        let auth_value = format!("Basic {}", encoded);

        // Add to headers
        headers.insert("authorization", HeaderValue::from_str(&auth_value).unwrap());

        headers
    }

    #[tokio::test]
    async fn test_basic_auth_service() -> Result<()> {
        // Create authentication service
        let auth_service = BasicAuthService::new(GitAuthConfig::default())
            .add_user("user1", "password1")
            .add_user("user2", "password2")
            .add_role("user1", "admin")
            .add_role("user2", "developer")
            .add_permission("user1", "repo1", GitOperation::Write)
            .add_permission("user2", "repo1", GitOperation::Read)
            .add_permission("user2", "repo2", GitOperation::Write);

        // Test valid authentication
        let headers = create_auth_header("user1", "password1");
        let auth_result = auth_service.authenticate(&headers).await?;

        assert!(auth_result.authenticated);
        assert_eq!(auth_result.user, Some("user1".to_string()));
        assert_eq!(auth_result.roles, vec!["admin".to_string()]);

        // Test invalid password
        let headers = create_auth_header("user1", "wrong-password");
        let auth_result = auth_service.authenticate(&headers).await?;

        assert!(!auth_result.authenticated);
        assert_eq!(auth_result.user, None);

        // Test non-existent user
        let headers = create_auth_header("non-existent", "password");
        let auth_result = auth_service.authenticate(&headers).await?;

        assert!(!auth_result.authenticated);
        assert_eq!(auth_result.user, None);

        // Test permission checks
        let headers = create_auth_header("user1", "password1");
        let auth_result = auth_service.authenticate(&headers).await?;

        // user1 should have write access to repo1
        assert!(auth_service.check_permission(&auth_result, "repo1", GitOperation::Write).await?);
        // user1 should also have read access to repo1 (implied by write access)
        assert!(auth_service.check_permission(&auth_result, "repo1", GitOperation::Read).await?);
        // user1 should not have write access to repo2
        assert!(!auth_service.check_permission(&auth_result, "repo2", GitOperation::Write).await?);

        // Test user2 permissions
        let headers = create_auth_header("user2", "password2");
        let auth_result = auth_service.authenticate(&headers).await?;

        // user2 should have read access to repo1
        assert!(auth_service.check_permission(&auth_result, "repo1", GitOperation::Read).await?);
        // user2 should not have write access to repo1
        assert!(!auth_service.check_permission(&auth_result, "repo1", GitOperation::Write).await?);
        // user2 should have write access to repo2
        assert!(auth_service.check_permission(&auth_result, "repo2", GitOperation::Write).await?);

        Ok(())
    }

    #[test]
    fn test_extract_credentials() {
        // Create authentication service
        let auth_service = BasicAuthService::new(GitAuthConfig::default());

        // Test basic auth
        let headers = create_auth_header("user", "password");
        let credentials = auth_service.extract_credentials(&headers);

        match credentials {
            GitCredentials::Basic { username, password } => {
                assert_eq!(username, "user");
                assert_eq!(password, "password");
            },
            _ => panic!("Expected basic credentials"),
        }

        // Test bearer token
        let mut headers = HeaderMap::new();
        headers.insert(
            "authorization",
            HeaderValue::from_str("Bearer token123").unwrap()
        );

        let auth_service = BasicAuthService::new(GitAuthConfig {
            use_bearer_auth: true,
            ..GitAuthConfig::default()
        });

        let credentials = auth_service.extract_credentials(&headers);

        match credentials {
            GitCredentials::Token(token) => {
                assert_eq!(token, "token123");
            },
            _ => panic!("Expected token credentials"),
        }

        // Test no credentials
        let headers = HeaderMap::new();
        let credentials = auth_service.extract_credentials(&headers);

        match credentials {
            GitCredentials::None => {},
            _ => panic!("Expected no credentials"),
        }
    }

    #[test]
    fn test_auth_config_default() {
        let config = GitAuthConfig::default();

        assert!(!config.require_auth_for_read);
        assert!(config.require_auth_for_write);
        assert_eq!(config.realm, "Git");
        assert_eq!(config.auth_header, None);
        assert!(!config.use_bearer_auth);
    }
}

#[cfg(test)]
mod user_auth_tests {
    use super::*;
    use crate::data::user::{User, UserRole};
    use crate::service::user::UserService;
    use crate::data::user::repository::UserRepository;
    use r2d2_sqlite::SqliteConnectionManager;
    use r2d2::Pool;
    use std::sync::Arc;

    async fn create_test_user_service() -> Arc<UserService> {
        // Create an in-memory SQLite database for testing
        let manager = SqliteConnectionManager::memory();
        let pool = Pool::new(manager).unwrap();
        let pool = Arc::new(pool);

        // Create and initialize the user repository
        let user_repo = UserRepository::new(pool);
        user_repo.initialize().await.unwrap();
        let user_repo = Arc::new(user_repo);

        // Create the user service
        let user_service = UserService::new(
            user_repo,
            3600, // 1 hour session timeout
            5,    // 5 max login attempts
            300,  // 5 minute lockout time
        );

        // Create test users
        user_service.create_user(
            "admin".to_string(),
            "admin@example.com".to_string(),
            "Admin User".to_string(),
            "admin123",
            UserRole::Admin,
        ).await.unwrap();

        user_service.create_user(
            "user".to_string(),
            "user@example.com".to_string(),
            "Regular User".to_string(),
            "user123",
            UserRole::User,
        ).await.unwrap();

        Arc::new(user_service)
    }

    #[tokio::test]
    async fn test_user_auth_service() -> Result<()> {
        // Create test user service
        let user_service = create_test_user_service().await;

        // Create authentication configuration
        let config = GitAuthConfig {
            require_auth_for_read: false,
            require_auth_for_write: true,
            ..Default::default()
        };

        // Create user authentication service
        let auth_service = UserAuthService::new(config, user_service.clone())
            .with_default_permissions()
            .add_role_permission("user", "public-repo", GitOperation::Write);

        // Create basic auth headers for admin
        let admin_headers = create_auth_header("admin", "admin123");

        // Authenticate admin user
        let admin_result = auth_service.authenticate(&admin_headers).await?;
        assert!(admin_result.authenticated);
        assert_eq!(admin_result.user, Some("admin".to_string()));
        assert!(admin_result.roles.contains(&"admin".to_string()));

        // Check permissions for admin
        assert!(auth_service.check_permission(&admin_result, "any-repo", GitOperation::Read).await?);
        assert!(auth_service.check_permission(&admin_result, "any-repo", GitOperation::Write).await?);

        // Create basic auth headers for regular user
        let user_headers = create_auth_header("user", "user123");

        // Authenticate regular user
        let user_result = auth_service.authenticate(&user_headers).await?;
        assert!(user_result.authenticated);
        assert_eq!(user_result.user, Some("user".to_string()));
        assert!(user_result.roles.contains(&"user".to_string()));

        // Check permissions for regular user
        assert!(auth_service.check_permission(&user_result, "any-repo", GitOperation::Read).await?);
        assert!(!auth_service.check_permission(&user_result, "any-repo", GitOperation::Write).await?);
        assert!(auth_service.check_permission(&user_result, "public-repo", GitOperation::Write).await?);

        // Create invalid auth headers
        let invalid_headers = create_auth_header("user", "wrongpass");

        // Authenticate with invalid credentials
        let invalid_result = auth_service.authenticate(&invalid_headers).await?;
        assert!(!invalid_result.authenticated);
        assert_eq!(invalid_result.user, None);

        Ok(())
    }
}
