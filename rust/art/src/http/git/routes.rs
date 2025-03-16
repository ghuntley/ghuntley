//! Git HTTP protocol routes

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Router,
};

use crate::http::ServerState;
use crate::error::Result;

/// Create Git HTTP protocol routes
pub fn git_routes() -> Router<ServerState> {
    Router::new()
        .route("/:repo/info/refs", get(info_refs))
        .route("/:repo/git-upload-pack", post(upload_pack))
        .route("/:repo/git-receive-pack", post(receive_pack))
}

/// Handler for info/refs endpoint
async fn info_refs(
    State(_state): State<ServerState>,
    Path(_repo): Path<String>,
) -> Result<String> {
    // This is a placeholder implementation
    // The real implementation would handle Git HTTP protocol
    Ok("Git info/refs endpoint".to_string())
}

/// Handler for git-upload-pack endpoint
async fn upload_pack(
    State(_state): State<ServerState>,
    Path(_repo): Path<String>,
) -> Result<String> {
    // This is a placeholder implementation
    // The real implementation would handle Git HTTP protocol
    Ok("Git upload-pack endpoint".to_string())
}

/// Handler for git-receive-pack endpoint
async fn receive_pack(
    State(_state): State<ServerState>,
    Path(_repo): Path<String>,
) -> Result<String> {
    // This is a placeholder implementation
    // The real implementation would handle Git HTTP protocol
    Ok("Git receive-pack endpoint".to_string())
}
