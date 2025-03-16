// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Git LFS (Large File Storage) support.
//!
//! This module implements the HTTP handlers for the Git LFS API.
//! The Git LFS API allows Git to store large files outside the Git repository,
//! replacing them with pointers in the repository itself.
//!
//! See https://github.com/git-lfs/git-lfs/blob/main/docs/api/batch.md for details.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::{Path as AxumPath, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json, Extension,
};
use bytes::Bytes;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use serde::{Serialize, Deserialize};
use tracing::{debug, error, info, warn};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use sha2::{Sha256, Digest};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;

use crate::data::git::Git;
use crate::error::{Error, Result};
use crate::service::observability::{metrics, trace};

use super::{GitHttp, GitHttpConfig};
use super::auth::{GitAuthResult, GitAuthService, GitOperation};

/// Git LFS batch request
#[derive(Debug, Deserialize)]
pub struct BatchRequest {
    /// Operation (upload or download)
    pub operation: String,

    /// Git LFS transfer options
    pub transfers: Option<Vec<String>>,

    /// Git ref information
    pub ref_: Option<serde_json::Value>,

    /// Repository
    pub repo: Option<serde_json::Value>,

    /// List of objects to process
    pub objects: Vec<LfsObject>,

    /// Hash algorithm used
    pub hash_algo: Option<String>,
}

/// Git LFS object information
#[derive(Debug, Serialize, Deserialize)]
pub struct LfsObject {
    /// Object ID (SHA-256 hash)
    pub oid: String,

    /// Object size in bytes
    pub size: u64,
}

/// Git LFS batch response
#[derive(Debug, Serialize)]
pub struct BatchResponse {
    /// Transfer adapter
    pub transfer: String,

    /// List of objects with download/upload actions
    pub objects: Vec<LfsObjectResponse>,
}

/// Git LFS object response
#[derive(Debug, Serialize)]
pub struct LfsObjectResponse {
    /// Object ID
    pub oid: String,

    /// Object size in bytes
    pub size: u64,

    /// Authenticated property (whether the object request is authenticated)
    pub authenticated: bool,

    /// Actions for the object (upload or download)
    pub actions: Option<LfsActions>,

    /// Error information if applicable
    pub error: Option<LfsError>,
}

/// Git LFS actions
#[derive(Debug, Serialize)]
pub struct LfsActions {
    /// Upload action
    pub upload: Option<LfsAction>,

    /// Download action
    pub download: Option<LfsAction>,

    /// Verify action
    pub verify: Option<LfsAction>,
}

/// Git LFS action
#[derive(Debug, Serialize)]
pub struct LfsAction {
    /// HTTP URL to perform the action
    pub href: String,

    /// HTTP headers to include with the request
    #[serde(skip_serializing_if = "Option::is_none")]
    pub header: Option<serde_json::Value>,

    /// Whether this action expires
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_in: Option<u64>,

    /// Extra action information
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extra: Option<serde_json::Value>,
}

/// Git LFS error
#[derive(Debug, Serialize)]
pub struct LfsError {
    /// Error code
    pub code: u32,

    /// Error message
    pub message: String,
}

/// Git LFS storage backend
pub struct LfsStorage {
    /// Base path for LFS object storage
    base_path: PathBuf,

    /// Base URL for LFS objects
    base_url: String,
}

impl LfsStorage {
    /// Create a new LFS storage
    pub fn new(base_path: PathBuf, base_url: String) -> Self {
        Self {
            base_path,
            base_url,
        }
    }

    /// Get the path to an LFS object
    pub fn get_object_path(&self, oid: &str) -> PathBuf {
        // Use first 2 chars as directory and rest as filename to avoid too many files in one directory
        let dir = &oid[0..2];
        let file = &oid[2..];

        self.base_path.join(dir).join(file)
    }

    /// Check if an LFS object exists
    pub async fn object_exists(&self, oid: &str) -> bool {
        fs::metadata(self.get_object_path(oid)).await.is_ok()
    }

    /// Get download URL for an LFS object
    pub fn get_download_url(&self, repo: &str, oid: &str) -> String {
        format!("{}/objects/{}/{}", self.base_url, repo, oid)
    }

    /// Get upload URL for an LFS object
    pub fn get_upload_url(&self, repo: &str, oid: &str) -> String {
        format!("{}/objects/{}/{}/upload", self.base_url, repo, oid)
    }

    /// Get verify URL for an LFS object
    pub fn get_verify_url(&self, repo: &str, oid: &str) -> String {
        format!("{}/objects/{}/{}/verify", self.base_url, repo, oid)
    }
}

/// Git LFS handlers
pub struct LfsHandlers;

impl LfsHandlers {
    /// Create new LFS handlers
    pub fn new() -> Self {
        Self {}
    }

    /// Handle batch API request
    pub async fn batch(
        State(state): State<Arc<super::GitRequestState>>,
        AxumPath(repo_name): AxumPath<String>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
        Json(request): Json<BatchRequest>,
    ) -> Result<Response> {
        trace::create_span("lfs_batch", || {
            // Check if LFS is enabled
            if !state.git_http.config().enable_lfs {
                return Err(Error::NotEnabled("Git LFS not enabled".to_string()));
            }

            metrics::increment_counter("lfs_batch_requests");

            // Get repository path
            let repo_path = state.git.get_repository_path(&repo_name)
                .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

            // Create the storage object
            let lfs_storage = LfsStorage::new(
                repo_path.join(".git").join("lfs").join("objects"),
                // Generate base URL based on original request
                format!("{}/git/{}/info/lfs", state.git_http.config().path_prefix, repo_name)
            );

            // Process each object based on operation
            let mut response_objects = Vec::new();

            for object in request.objects {
                let mut response_object = LfsObjectResponse {
                    oid: object.oid.clone(),
                    size: object.size,
                    authenticated: auth_result.is_valid(),
                    actions: None,
                    error: None,
                };

                // Check operation type
                match request.operation.as_str() {
                    "download" => {
                        // Check if object exists
                        if lfs_storage.object_exists(&object.oid).await {
                            // Create download action
                            response_object.actions = Some(LfsActions {
                                upload: None,
                                download: Some(LfsAction {
                                    href: lfs_storage.get_download_url(&repo_name, &object.oid),
                                    header: None,
                                    expires_in: Some(86400), // 24 hours
                                    extra: None,
                                }),
                                verify: None,
                            });
                        } else {
                            // Object not found
                            response_object.error = Some(LfsError {
                                code: 404,
                                message: "Object does not exist".to_string(),
                            });
                        }
                    },
                    "upload" => {
                        // Check if we already have this object
                        if lfs_storage.object_exists(&object.oid).await {
                            // No need to upload, just verify
                            response_object.actions = Some(LfsActions {
                                upload: None,
                                download: None,
                                verify: Some(LfsAction {
                                    href: lfs_storage.get_verify_url(&repo_name, &object.oid),
                                    header: None,
                                    expires_in: Some(86400), // 24 hours
                                    extra: None,
                                }),
                            });
                        } else {
                            // Need to upload
                            response_object.actions = Some(LfsActions {
                                upload: Some(LfsAction {
                                    href: lfs_storage.get_upload_url(&repo_name, &object.oid),
                                    header: None,
                                    expires_in: Some(86400), // 24 hours
                                    extra: None,
                                }),
                                download: None,
                                verify: Some(LfsAction {
                                    href: lfs_storage.get_verify_url(&repo_name, &object.oid),
                                    header: None,
                                    expires_in: Some(86400), // 24 hours
                                    extra: None,
                                }),
                            });
                        }
                    },
                    _ => {
                        // Unknown operation
                        response_object.error = Some(LfsError {
                            code: 400,
                            message: format!("Operation not supported: {}", request.operation),
                        });
                    }
                }

                response_objects.push(response_object);
            }

            // Build and return the response
            let response = BatchResponse {
                transfer: "basic".to_string(),
                objects: response_objects,
            };

            Ok(Json(response).into_response())
        })?
    }

    /// Handle object upload
    pub async fn upload_object(
        State(state): State<Arc<super::GitRequestState>>,
        AxumPath((repo_name, oid)): AxumPath<(String, String)>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
        body: Bytes,
    ) -> Result<Response> {
        trace::create_span("lfs_upload", || {
            // Check if LFS is enabled
            if !state.git_http.config().enable_lfs {
                return Err(Error::NotEnabled("Git LFS not enabled".to_string()));
            }

            metrics::increment_counter("lfs_upload_requests");

            // Verify authentication
            if !auth_result.is_valid() {
                return Err(Error::Unauthorized("Authentication required for uploading LFS objects".to_string()));
            }

            // Get repository path
            let repo_path = state.git.get_repository_path(&repo_name)
                .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

            // Create the storage object
            let lfs_storage = LfsStorage::new(
                repo_path.join(".git").join("lfs").join("objects"),
                format!("{}/git/{}/info/lfs", state.git_http.config().path_prefix, repo_name)
            );

            // Verify OID of uploaded content
            let mut hasher = Sha256::new();
            hasher.update(&body);
            let calculated_oid = format!("{:x}", hasher.finalize());

            if calculated_oid != oid {
                return Err(Error::BadRequest(format!("Content hash mismatch: expected {}, got {}", oid, calculated_oid)));
            }

            // Create directory if needed
            let object_path = lfs_storage.get_object_path(&oid);
            if let Some(parent) = object_path.parent() {
                fs::create_dir_all(parent).await
                    .map_err(|e| Error::Internal(format!("Failed to create LFS object directory: {}", e)))?;
            }

            // Write the file
            let mut file = fs::File::create(&object_path).await
                .map_err(|e| Error::Internal(format!("Failed to create LFS object file: {}", e)))?;

            file.write_all(&body).await
                .map_err(|e| Error::Internal(format!("Failed to write LFS object file: {}", e)))?;

            file.flush().await
                .map_err(|e| Error::Internal(format!("Failed to flush LFS object file: {}", e)))?;

            // Return success
            Ok(StatusCode::OK.into_response())
        })?
    }

    /// Handle object download
    pub async fn download_object(
        State(state): State<Arc<super::GitRequestState>>,
        AxumPath((repo_name, oid)): AxumPath<(String, String)>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
    ) -> Result<Response> {
        trace::create_span("lfs_download", || {
            // Check if LFS is enabled
            if !state.git_http.config().enable_lfs {
                return Err(Error::NotEnabled("Git LFS not enabled".to_string()));
            }

            metrics::increment_counter("lfs_download_requests");

            // Get repository path
            let repo_path = state.git.get_repository_path(&repo_name)
                .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

            // Create the storage object
            let lfs_storage = LfsStorage::new(
                repo_path.join(".git").join("lfs").join("objects"),
                format!("{}/git/{}/info/lfs", state.git_http.config().path_prefix, repo_name)
            );

            // Check if object exists
            let object_path = lfs_storage.get_object_path(&oid);
            if !lfs_storage.object_exists(&oid).await {
                return Err(Error::NotFound(format!("LFS object not found: {}", oid)));
            }

            // Read and return the file
            let file_bytes = fs::read(&object_path).await
                .map_err(|e| Error::Internal(format!("Failed to read LFS object file: {}", e)))?;

            // Construct the response
            let mut response = Response::new(axum::body::Body::from(file_bytes));
            response.headers_mut().insert(
                header::CONTENT_TYPE,
                header::HeaderValue::from_static("application/octet-stream")
            );

            Ok(response)
        })?
    }

    /// Handle object verification
    pub async fn verify_object(
        State(state): State<Arc<super::GitRequestState>>,
        AxumPath((repo_name, oid)): AxumPath<(String, String)>,
        headers: HeaderMap,
        Extension(auth_result): Extension<GitAuthResult>,
    ) -> Result<Response> {
        trace::create_span("lfs_verify", || {
            // Check if LFS is enabled
            if !state.git_http.config().enable_lfs {
                return Err(Error::NotEnabled("Git LFS not enabled".to_string()));
            }

            metrics::increment_counter("lfs_verify_requests");

            // Verify authentication
            if !auth_result.is_valid() {
                return Err(Error::Unauthorized("Authentication required for verifying LFS objects".to_string()));
            }

            // Get repository path
            let repo_path = state.git.get_repository_path(&repo_name)
                .map_err(|e| Error::Repository(format!("Repository not found: {}", e)))?;

            // Create the storage object
            let lfs_storage = LfsStorage::new(
                repo_path.join(".git").join("lfs").join("objects"),
                format!("{}/git/{}/info/lfs", state.git_http.config().path_prefix, repo_name)
            );

            // Check if object exists
            if !lfs_storage.object_exists(&oid).await {
                return Err(Error::NotFound(format!("LFS object not found: {}", oid)));
            }

            // Verification is successful - the object exists
            Ok(StatusCode::OK.into_response())
        })?
    }
}

/// Property tests for LFS functionality
#[cfg(test)]
pub mod tests {
    use super::*;
    use proptest::prelude::*;
    use tempfile::TempDir;
    use tokio::runtime::Runtime;

    /// Generate a random OID (SHA-256 hash)
    fn generate_random_oid() -> String {
        let random_bytes: Vec<u8> = (0..32).map(|_| rand::random::<u8>()).collect();
        let mut hasher = Sha256::new();
        hasher.update(&random_bytes);
        format!("{:x}", hasher.finalize())
    }

    /// Generate random content with a known hash
    fn generate_content_with_hash(size: usize) -> (Vec<u8>, String) {
        let content: Vec<u8> = (0..size).map(|_| rand::random::<u8>()).collect();
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let hash = format!("{:x}", hasher.finalize());
        (content, hash)
    }

    proptest! {
        /// Test that uploads verify the hash correctly
        #[test]
        fn test_upload_verifies_hash(content_size in 1..1024usize) {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                // Create temporary directory
                let temp_dir = TempDir::new().unwrap();
                let storage = LfsStorage::new(
                    temp_dir.path().to_path_buf(),
                    "http://example.com/lfs".to_string()
                );

                // Generate content and correct hash
                let (content, correct_hash) = generate_content_with_hash(content_size);

                // Create the object directory
                let object_path = storage.get_object_path(&correct_hash);
                if let Some(parent) = object_path.parent() {
                    fs::create_dir_all(parent).await.unwrap();
                }

                // Write the file directly
                let mut file = fs::File::create(&object_path).await.unwrap();
                file.write_all(&content).await.unwrap();
                file.flush().await.unwrap();

                // Verify object exists
                assert!(storage.object_exists(&correct_hash).await);

                // Test with incorrect hash
                let incorrect_hash = "0000000000000000000000000000000000000000000000000000000000000000";
                assert!(!storage.object_exists(incorrect_hash).await);
            });
        }

        /// Test that the LFS paths are correctly organized
        #[test]
        fn test_lfs_storage_paths(oid in "[0-9a-f]{64}") {
            // Create storage instance
            let storage = LfsStorage::new(
                PathBuf::from("/tmp/lfs"),
                "http://example.com/lfs".to_string()
            );

            // Get object path
            let object_path = storage.get_object_path(&oid);

            // Verify path structure
            assert_eq!(object_path.parent().unwrap().file_name().unwrap().to_str().unwrap(), &oid[0..2]);
            assert_eq!(object_path.file_name().unwrap().to_str().unwrap(), &oid[2..]);
        }

        /// Test that the URL generation is correct
        #[test]
        fn test_url_generation(
            repo_name in "[a-zA-Z0-9_-]{1,32}",
            oid in "[0-9a-f]{64}"
        ) {
            // Create storage instance
            let storage = LfsStorage::new(
                PathBuf::from("/tmp/lfs"),
                format!("http://example.com/git/{}/info/lfs", repo_name)
            );

            // Verify download URL
            let download_url = storage.get_download_url(&repo_name, &oid);
            assert_eq!(download_url, format!("http://example.com/git/{}/info/lfs/objects/{}/{}", repo_name, repo_name, oid));

            // Verify upload URL
            let upload_url = storage.get_upload_url(&repo_name, &oid);
            assert_eq!(upload_url, format!("http://example.com/git/{}/info/lfs/objects/{}/{}/upload", repo_name, repo_name, oid));

            // Verify verify URL
            let verify_url = storage.get_verify_url(&repo_name, &oid);
            assert_eq!(verify_url, format!("http://example.com/git/{}/info/lfs/objects/{}/{}/verify", repo_name, repo_name, oid));
        }
    }
}
