// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! User management web routes

use crate::http::ServerState;
use crate::data::user::{User, UserRole};
use crate::error::{Error, Result};
use crate::template::{
    BaseTemplate, LoginTemplate, RegisterTemplate, UserProfileTemplate,
    UserManagementTemplate, CreateUserTemplate, EditUserTemplate,
    TemplateRender,
};
use crate::service::user::UserService;

use axum::{
    extract::{Path, Query, State},
    response::{Html, Redirect, IntoResponse},
    routing::{get, post},
    Form, Router,
};
use serde::Deserialize;
use std::sync::Arc;
use tower_cookies::{Cookie, Cookies};
use validator::Validate;

/// Create user management web routes
pub fn user_routes(state: ServerState) -> Router {
    // Only create routes if user service is available
    if let Some(user_service) = state.user_service.clone() {
        Router::new()
            // Public routes
            .route("/login", get(login_page).post(login_handler))
            .route("/register", get(register_page).post(register_handler))
            .route("/logout", post(logout_handler))

            // User-only routes
            .route("/profile", get(profile_page).post(profile_update_handler))

            // Admin-only routes
            .route("/management", get(management_page))
            .route("/create", get(create_user_page).post(create_user_handler))
            .route("/edit/:id", get(edit_user_page).post(edit_user_handler))
            .route("/delete/:id", post(delete_user_handler))

            .with_state(state)
    } else {
        // Return empty router if user service is not available
        Router::new()
    }
}

/// Login page form data
#[derive(Deserialize, Validate)]
struct LoginForm {
    #[validate(length(min = 1, message = "Username is required"))]
    username: String,

    #[validate(length(min = 1, message = "Password is required"))]
    password: String,
}

/// Registration page form data
#[derive(Deserialize, Validate)]
struct RegisterForm {
    #[validate(length(min = 3, message = "Username must be at least 3 characters"))]
    #[validate(length(max = 30, message = "Username must be at most 30 characters"))]
    username: String,

    #[validate(email(message = "Invalid email format"))]
    email: String,

    #[validate(length(min = 1, message = "Display name is required"))]
    display_name: String,

    #[validate(length(min = 8, message = "Password must be at least 8 characters"))]
    password: String,

    password_confirm: String,
}

/// Profile update form data
#[derive(Deserialize, Validate)]
struct ProfileUpdateForm {
    #[validate(email(message = "Invalid email format"))]
    email: String,

    #[validate(length(min = 1, message = "Display name is required"))]
    display_name: String,

    current_password: Option<String>,
    new_password: Option<String>,
    new_password_confirm: Option<String>,
}

/// User creation form data
#[derive(Deserialize, Validate)]
struct CreateUserForm {
    #[validate(length(min = 3, message = "Username must be at least 3 characters"))]
    #[validate(length(max = 30, message = "Username must be at most 30 characters"))]
    username: String,

    #[validate(email(message = "Invalid email format"))]
    email: String,

    #[validate(length(min = 1, message = "Display name is required"))]
    display_name: String,

    #[validate(length(min = 8, message = "Password must be at least 8 characters"))]
    password: String,

    role: String,
}

/// User edit form data
#[derive(Deserialize, Validate)]
struct EditUserForm {
    id: i64,

    #[validate(email(message = "Invalid email format"))]
    email: String,

    #[validate(length(min = 1, message = "Display name is required"))]
    display_name: String,

    password: Option<String>,
    role: String,
    active: String,
}

/// User management query parameters
#[derive(Deserialize)]
struct UserManagementParams {
    page: Option<usize>,
    limit: Option<usize>,
}

/// Show login page
async fn login_page(
    State(state): State<ServerState>,
    cookies: Cookies,
) -> Result<impl IntoResponse> {
    // Check if already logged in
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(_)) = user_service.get_session_user(&session_id).await {
                // Already logged in, redirect to profile
                return Ok(Redirect::to("/user/profile").into_response());
            }
        }
    }

    // Render login page
    let base = BaseTemplate {
        title: "Login".to_string(),
        description: "Login to Art".to_string(),
        base_url: "/".to_string(),
        current_path: "/user/login".to_string(),
        current_repo: None,
    };

    let template = LoginTemplate {
        base,
        error: None,
    };

    Ok(Html(template.render_to_string()?).into_response())
}

/// Handle login form submission
async fn login_handler(
    State(state): State<ServerState>,
    mut cookies: Cookies,
    Form(form): Form<LoginForm>,
) -> Result<impl IntoResponse> {
    // Validate form
    if let Err(errors) = form.validate() {
        let error_message = errors.to_string();

        let base = BaseTemplate {
            title: "Login".to_string(),
            description: "Login to Art".to_string(),
            base_url: "/".to_string(),
            current_path: "/user/login".to_string(),
            current_repo: None,
        };

        let template = LoginTemplate {
            base,
            error: Some(error_message),
        };

        return Ok(Html(template.render_to_string()?).into_response());
    }

    // Attempt to login
    if let Some(user_service) = &state.user_service {
        match user_service.login(
            &form.username,
            &form.password,
            "127.0.0.1".to_string(), // Replace with actual IP address extraction
            "web-browser".to_string(), // Replace with actual user agent extraction
        ).await {
            Ok((_, session)) => {
                // Set session cookie
                let cookie = Cookie::build("art_session", session.id)
                    .path("/")
                    .secure(true)
                    .http_only(true)
                    .finish();

                cookies.add(cookie);

                // Redirect to profile
                return Ok(Redirect::to("/user/profile").into_response());
            },
            Err(err) => {
                let error_message = match err {
                    Error::Authentication(_) => "Invalid username or password".to_string(),
                    _ => "An error occurred during login".to_string(),
                };

                let base = BaseTemplate {
                    title: "Login".to_string(),
                    description: "Login to Art".to_string(),
                    base_url: "/".to_string(),
                    current_path: "/user/login".to_string(),
                    current_repo: None,
                };

                let template = LoginTemplate {
                    base,
                    error: Some(error_message),
                };

                return Ok(Html(template.render_to_string()?).into_response());
            }
        }
    }

    // User service not available
    let base = BaseTemplate {
        title: "Login".to_string(),
        description: "Login to Art".to_string(),
        base_url: "/".to_string(),
        current_path: "/user/login".to_string(),
        current_repo: None,
    };

    let template = LoginTemplate {
        base,
        error: Some("User authentication is not enabled".to_string()),
    };

    Ok(Html(template.render_to_string()?).into_response())
}

/// Show registration page
async fn register_page(
    State(state): State<ServerState>,
    cookies: Cookies,
) -> Result<impl IntoResponse> {
    // Check if already logged in
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(_)) = user_service.get_session_user(&session_id).await {
                // Already logged in, redirect to profile
                return Ok(Redirect::to("/user/profile").into_response());
            }
        }
    }

    // Render registration page
    let base = BaseTemplate {
        title: "Register".to_string(),
        description: "Create an account".to_string(),
        base_url: "/".to_string(),
        current_path: "/user/register".to_string(),
        current_repo: None,
    };

    let template = RegisterTemplate {
        base,
        error: None,
    };

    Ok(Html(template.render_to_string()?).into_response())
}

/// Handle registration form submission
async fn register_handler(
    State(state): State<ServerState>,
    mut cookies: Cookies,
    Form(form): Form<RegisterForm>,
) -> Result<impl IntoResponse> {
    // Validate form
    if let Err(errors) = form.validate() {
        let error_message = errors.to_string();

        let base = BaseTemplate {
            title: "Register".to_string(),
            description: "Create an account".to_string(),
            base_url: "/".to_string(),
            current_path: "/user/register".to_string(),
            current_repo: None,
        };

        let template = RegisterTemplate {
            base,
            error: Some(error_message),
        };

        return Ok(Html(template.render_to_string()?).into_response());
    }

    // Check if passwords match
    if form.password != form.password_confirm {
        let base = BaseTemplate {
            title: "Register".to_string(),
            description: "Create an account".to_string(),
            base_url: "/".to_string(),
            current_path: "/user/register".to_string(),
            current_repo: None,
        };

        let template = RegisterTemplate {
            base,
            error: Some("Passwords do not match".to_string()),
        };

        return Ok(Html(template.render_to_string()?).into_response());
    }

    // Attempt to create user
    if let Some(user_service) = &state.user_service {
        match user_service.create_user(
            form.username,
            form.email,
            form.display_name,
            &form.password,
            UserRole::User,
        ).await {
            Ok(user) => {
                // Login user
                match user_service.login(
                    &user.username,
                    &form.password,
                    "127.0.0.1".to_string(), // Replace with actual IP address extraction
                    "web-browser".to_string(), // Replace with actual user agent extraction
                ).await {
                    Ok((_, session)) => {
                        // Set session cookie
                        let cookie = Cookie::build("art_session", session.id)
                            .path("/")
                            .secure(true)
                            .http_only(true)
                            .finish();

                        cookies.add(cookie);

                        // Redirect to profile
                        return Ok(Redirect::to("/user/profile").into_response());
                    },
                    Err(_) => {
                        // User created but login failed, redirect to login page
                        return Ok(Redirect::to("/user/login").into_response());
                    }
                }
            },
            Err(err) => {
                let error_message = match err {
                    Error::UsernameTaken(_) => "Username is already taken".to_string(),
                    Error::EmailTaken(_) => "Email is already in use".to_string(),
                    _ => "An error occurred during registration".to_string(),
                };

                let base = BaseTemplate {
                    title: "Register".to_string(),
                    description: "Create an account".to_string(),
                    base_url: "/".to_string(),
                    current_path: "/user/register".to_string(),
                    current_repo: None,
                };

                let template = RegisterTemplate {
                    base,
                    error: Some(error_message),
                };

                return Ok(Html(template.render_to_string()?).into_response());
            }
        }
    }

    // User service not available
    let base = BaseTemplate {
        title: "Register".to_string(),
        description: "Create an account".to_string(),
        base_url: "/".to_string(),
        current_path: "/user/register".to_string(),
        current_repo: None,
    };

    let template = RegisterTemplate {
        base,
        error: Some("User registration is not enabled".to_string()),
    };

    Ok(Html(template.render_to_string()?).into_response())
}

/// Handle logout
async fn logout_handler(
    State(state): State<ServerState>,
    mut cookies: Cookies,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            // Attempt to logout
            let _ = user_service.logout(&session_id).await;
        }
    }

    // Remove session cookie
    cookies.remove(Cookie::new("art_session", ""));

    // Redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Show user profile page
async fn profile_page(
    State(state): State<ServerState>,
    cookies: Cookies,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(user)) = user_service.get_session_user(&session_id).await {
                // Render profile page
                let base = BaseTemplate {
                    title: "Profile".to_string(),
                    description: "Your profile".to_string(),
                    base_url: "/".to_string(),
                    current_path: "/user/profile".to_string(),
                    current_repo: None,
                };

                let template = UserProfileTemplate {
                    base,
                    user,
                    error: None,
                    success: None,
                };

                return Ok(Html(template.render_to_string()?).into_response());
            }
        }
    }

    // Not logged in, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Handle profile update
async fn profile_update_handler(
    State(state): State<ServerState>,
    cookies: Cookies,
    Form(form): Form<ProfileUpdateForm>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(mut user)) = user_service.get_session_user(&session_id).await {
                // Validate form
                if let Err(errors) = form.validate() {
                    let error_message = errors.to_string();

                    let base = BaseTemplate {
                        title: "Profile".to_string(),
                        description: "Your profile".to_string(),
                        base_url: "/".to_string(),
                        current_path: "/user/profile".to_string(),
                        current_repo: None,
                    };

                    let template = UserProfileTemplate {
                        base,
                        user,
                        error: Some(error_message),
                        success: None,
                    };

                    return Ok(Html(template.render_to_string()?).into_response());
                }

                // Check if password change was requested
                let password = if let (Some(current), Some(new), Some(confirm)) = (
                    &form.current_password,
                    &form.new_password,
                    &form.new_password_confirm
                ) {
                    if current.is_empty() || new.is_empty() || confirm.is_empty() {
                        None
                    } else if new != confirm {
                        let base = BaseTemplate {
                            title: "Profile".to_string(),
                            description: "Your profile".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/profile".to_string(),
                            current_repo: None,
                        };

                        let template = UserProfileTemplate {
                            base,
                            user,
                            error: Some("New passwords do not match".to_string()),
                            success: None,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    } else if new.len() < 8 {
                        let base = BaseTemplate {
                            title: "Profile".to_string(),
                            description: "Your profile".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/profile".to_string(),
                            current_repo: None,
                        };

                        let template = UserProfileTemplate {
                            base,
                            user,
                            error: Some("New password must be at least 8 characters".to_string()),
                            success: None,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    } else if !user.verify_password(current)? {
                        let base = BaseTemplate {
                            title: "Profile".to_string(),
                            description: "Your profile".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/profile".to_string(),
                            current_repo: None,
                        };

                        let template = UserProfileTemplate {
                            base,
                            user,
                            error: Some("Current password is incorrect".to_string()),
                            success: None,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    } else {
                        Some(new.as_str())
                    }
                } else {
                    None
                };

                // Update user
                match user_service.update_user(
                    user.id,
                    Some(form.email),
                    Some(form.display_name),
                    password,
                    None,  // Can't change own role
                    None,  // Can't change own active status
                ).await {
                    Ok(updated_user) => {
                        let base = BaseTemplate {
                            title: "Profile".to_string(),
                            description: "Your profile".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/profile".to_string(),
                            current_repo: None,
                        };

                        let template = UserProfileTemplate {
                            base,
                            user: updated_user,
                            error: None,
                            success: Some("Profile updated successfully".to_string()),
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    },
                    Err(err) => {
                        let error_message = match err {
                            Error::EmailTaken(_) => "Email is already in use".to_string(),
                            _ => "An error occurred while updating profile".to_string(),
                        };

                        let base = BaseTemplate {
                            title: "Profile".to_string(),
                            description: "Your profile".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/profile".to_string(),
                            current_repo: None,
                        };

                        let template = UserProfileTemplate {
                            base,
                            user,
                            error: Some(error_message),
                            success: None,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    }
                }
            }
        }
    }

    // Not logged in, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Show user management page (admin only)
async fn management_page(
    State(state): State<ServerState>,
    cookies: Cookies,
    Query(params): Query<UserManagementParams>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Get pagination parameters
                let limit = params.limit.unwrap_or(10);
                let page = params.page.unwrap_or(1);
                let offset = (page - 1) * limit;

                // Get user list
                match user_service.list_users(Some(limit), Some(offset)).await {
                    Ok(users) => {
                        // Get total user count for pagination
                        let total_users = match user_service.list_users(None, None).await {
                            Ok(all_users) => all_users.len(),
                            Err(_) => users.len(),
                        };

                        let total_pages = (total_users + limit - 1) / limit;

                        let base = BaseTemplate {
                            title: "User Management".to_string(),
                            description: "Manage users".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/management".to_string(),
                            current_repo: None,
                        };

                        let template = UserManagementTemplate {
                            base,
                            users,
                            error: None,
                            success: None,
                            page,
                            total_pages,
                            page_size: limit,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    },
                    Err(_) => {
                        // Error getting users
                        let base = BaseTemplate {
                            title: "User Management".to_string(),
                            description: "Manage users".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/management".to_string(),
                            current_repo: None,
                        };

                        let template = UserManagementTemplate {
                            base,
                            users: Vec::new(),
                            error: Some("Error fetching user list".to_string()),
                            success: None,
                            page: 1,
                            total_pages: 1,
                            page_size: limit,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    }
                }
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Show create user page (admin only)
async fn create_user_page(
    State(state): State<ServerState>,
    cookies: Cookies,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Render create user page
                let base = BaseTemplate {
                    title: "Create User".to_string(),
                    description: "Create a new user".to_string(),
                    base_url: "/".to_string(),
                    current_path: "/user/create".to_string(),
                    current_repo: None,
                };

                let template = CreateUserTemplate {
                    base,
                    error: None,
                };

                return Ok(Html(template.render_to_string()?).into_response());
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Handle create user form submission (admin only)
async fn create_user_handler(
    State(state): State<ServerState>,
    cookies: Cookies,
    Form(form): Form<CreateUserForm>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Validate form
                if let Err(errors) = form.validate() {
                    let error_message = errors.to_string();

                    let base = BaseTemplate {
                        title: "Create User".to_string(),
                        description: "Create a new user".to_string(),
                        base_url: "/".to_string(),
                        current_path: "/user/create".to_string(),
                        current_repo: None,
                    };

                    let template = CreateUserTemplate {
                        base,
                        error: Some(error_message),
                    };

                    return Ok(Html(template.render_to_string()?).into_response());
                }

                // Parse role
                let role = match form.role.as_str() {
                    "Admin" => UserRole::Admin,
                    "Maintainer" => UserRole::Maintainer,
                    _ => UserRole::User,
                };

                // Create user
                match user_service.create_user(
                    form.username,
                    form.email,
                    form.display_name,
                    &form.password,
                    role,
                ).await {
                    Ok(_) => {
                        // Redirect to user management with success message
                        // In a real application, we'd use flash messages here
                        return Ok(Redirect::to("/user/management").into_response());
                    },
                    Err(err) => {
                        let error_message = match err {
                            Error::UsernameTaken(_) => "Username is already taken".to_string(),
                            Error::EmailTaken(_) => "Email is already in use".to_string(),
                            _ => "An error occurred while creating user".to_string(),
                        };

                        let base = BaseTemplate {
                            title: "Create User".to_string(),
                            description: "Create a new user".to_string(),
                            base_url: "/".to_string(),
                            current_path: "/user/create".to_string(),
                            current_repo: None,
                        };

                        let template = CreateUserTemplate {
                            base,
                            error: Some(error_message),
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    }
                }
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Show edit user page (admin only)
async fn edit_user_page(
    State(state): State<ServerState>,
    cookies: Cookies,
    Path(id): Path<i64>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(current_user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !current_user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Get user to edit
                match user_service.get_user(id).await {
                    Ok(user) => {
                        let base = BaseTemplate {
                            title: "Edit User".to_string(),
                            description: "Edit user".to_string(),
                            base_url: "/".to_string(),
                            current_path: format!("/user/edit/{}", id),
                            current_repo: None,
                        };

                        let template = EditUserTemplate {
                            base,
                            user,
                            error: None,
                        };

                        return Ok(Html(template.render_to_string()?).into_response());
                    },
                    Err(_) => {
                        // User not found, redirect to management page
                        return Ok(Redirect::to("/user/management").into_response());
                    }
                }
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Handle edit user form submission (admin only)
async fn edit_user_handler(
    State(state): State<ServerState>,
    cookies: Cookies,
    Path(id): Path<i64>,
    Form(form): Form<EditUserForm>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(current_user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !current_user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Check if ID matches
                if id != form.id {
                    return Ok(Redirect::to("/user/management").into_response());
                }

                // Validate form
                if let Err(errors) = form.validate() {
                    let error_message = errors.to_string();

                    // Get user to re-render form
                    match user_service.get_user(id).await {
                        Ok(user) => {
                            let base = BaseTemplate {
                                title: "Edit User".to_string(),
                                description: "Edit user".to_string(),
                                base_url: "/".to_string(),
                                current_path: format!("/user/edit/{}", id),
                                current_repo: None,
                            };

                            let template = EditUserTemplate {
                                base,
                                user,
                                error: Some(error_message),
                            };

                            return Ok(Html(template.render_to_string()?).into_response());
                        },
                        Err(_) => {
                            // User not found, redirect to management page
                            return Ok(Redirect::to("/user/management").into_response());
                        }
                    }
                }

                // Parse role
                let role = match form.role.as_str() {
                    "Admin" => Some(UserRole::Admin),
                    "Maintainer" => Some(UserRole::Maintainer),
                    "User" => Some(UserRole::User),
                    _ => None,
                };

                // Parse active status
                let active = match form.active.as_str() {
                    "true" => Some(true),
                    "false" => Some(false),
                    _ => None,
                };

                // Get password (if provided)
                let password = match &form.password {
                    Some(pwd) if !pwd.is_empty() => Some(pwd.as_str()),
                    _ => None,
                };

                // Update user
                match user_service.update_user(
                    id,
                    Some(form.email),
                    Some(form.display_name),
                    password,
                    role,
                    active,
                ).await {
                    Ok(_) => {
                        // Redirect to user management with success message
                        // In a real application, we'd use flash messages here
                        return Ok(Redirect::to("/user/management").into_response());
                    },
                    Err(err) => {
                        let error_message = match err {
                            Error::EmailTaken(_) => "Email is already in use".to_string(),
                            Error::UserNotFound(_) => "User not found".to_string(),
                            _ => "An error occurred while updating user".to_string(),
                        };

                        // Get user to re-render form
                        match user_service.get_user(id).await {
                            Ok(user) => {
                                let base = BaseTemplate {
                                    title: "Edit User".to_string(),
                                    description: "Edit user".to_string(),
                                    base_url: "/".to_string(),
                                    current_path: format!("/user/edit/{}", id),
                                    current_repo: None,
                                };

                                let template = EditUserTemplate {
                                    base,
                                    user,
                                    error: Some(error_message),
                                };

                                return Ok(Html(template.render_to_string()?).into_response());
                            },
                            Err(_) => {
                                // User not found, redirect to management page
                                return Ok(Redirect::to("/user/management").into_response());
                            }
                        }
                    }
                }
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Handle delete user (admin only)
async fn delete_user_handler(
    State(state): State<ServerState>,
    cookies: Cookies,
    Path(id): Path<i64>,
) -> Result<impl IntoResponse> {
    if let Some(user_service) = &state.user_service {
        if let Some(session_id) = get_session_cookie(&cookies) {
            if let Ok(Some(current_user)) = user_service.get_session_user(&session_id).await {
                // Check if admin
                if !current_user.is_admin() {
                    return Ok(Redirect::to("/user/profile").into_response());
                }

                // Can't delete yourself
                if current_user.id == id {
                    return Ok(Redirect::to("/user/management").into_response());
                }

                // Delete user
                let _ = user_service.delete_user(id).await;

                // Redirect to user management
                return Ok(Redirect::to("/user/management").into_response());
            }
        }
    }

    // Not logged in or not admin, redirect to login page
    Ok(Redirect::to("/user/login").into_response())
}

/// Helper function to get session cookie
fn get_session_cookie(cookies: &Cookies) -> Option<String> {
    cookies.get("art_session").map(|cookie| cookie.value().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Helper function to create a test router
    async fn create_test_router() -> Router {
        // TODO: implement with mock user service
        Router::new()
    }

    // TODO: add tests for routes
}
