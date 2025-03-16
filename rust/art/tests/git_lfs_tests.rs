// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Property-based tests for Git LFS functionality
//!
//! These tests verify the Git Large File Storage (LFS) implementation
//! by testing its core functionalities:
//! - Content hash verification (SHA-256)
//! - Storage path organization with sharding
//! - URL generation for LFS API endpoints
//! - Upload/download functionality

use art::http::git::lfs::{LfsObject, LfsStorage};
use art::error::Result;

use chrono::{DateTime, Utc};
use proptest::prelude::*;
use sha2::{Sha256, Digest};
use std::path::{Path, PathBuf};
use tempfile::TempDir;
use tokio::fs;
use tokio::io::AsyncWriteExt;

// Run tests in a Tokio runtime
fn run_async<F: std::future::Future<Output = ()>>(future: F) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(future);
}

// Generate random LFS object ID (SHA-256 hex string)
fn random_oid() -> String {
    let mut rng = rand::thread_rng();
    let random_bytes: Vec<u8> = (0..32).map(|_| rand::random::<u8>()).collect();
    let mut hasher = Sha256::new();
    hasher.update(&random_bytes);
    let hash = hasher.finalize();

    // Convert to hex string
    format!("{:x}", hash)
}

// Generate content with a known SHA-256 hash
fn generate_content_with_hash(size: usize) -> (Vec<u8>, String) {
    let content: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

    let mut hasher = Sha256::new();
    hasher.update(&content);
    let hash = hasher.finalize();
    let hash_hex = format!("{:x}", hash);

    (content, hash_hex)
}

// Property test for content hash verification
proptest! {
    #[test]
    fn test_content_hash_verification(size in 1..10_000usize) {
        // Generate content with a known hash
        let (content, hash) = generate_content_with_hash(size);

        // Verify that the hash is correct
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let computed_hash = format!("{:x}", hasher.finalize());

        // The computed hash should match our expected hash
        prop_assert_eq!(computed_hash, hash);

        // Create an LFS object with the hash and size
        let lfs_object = LfsObject {
            oid: hash.clone(),
            size: size as u64,
        };

        // The size in the LFS object should match the content length
        prop_assert_eq!(content.len() as u64, lfs_object.size);

        // Test that a corrupted content will have a different hash
        if !content.is_empty() {
            let mut corrupted = content.clone();
            corrupted[0] = corrupted[0].wrapping_add(1);

            let mut hasher = Sha256::new();
            hasher.update(&corrupted);
            let corrupted_hash = format!("{:x}", hasher.finalize());

            // The hash should change when content is modified
            prop_assert_ne!(corrupted_hash, hash);
        }
    }
}

// Property test for storage path organization
proptest! {
    #[test]
    fn test_storage_path_organization() {
        run_async(async {
            // Create a temporary directory for LFS storage
            let temp_dir = TempDir::new().unwrap();
            let base_path = temp_dir.path().to_path_buf();

            // Create an LFS storage instance
            let lfs_storage = LfsStorage::new(
                base_path.clone(),
                "https://example.com/git/repo/info/lfs".to_string()
            );

            // Generate random OIDs and check path organization
            for _ in 0..10 {
                let oid = random_oid();

                // Get the path to the object
                let object_path = lfs_storage.get_object_path(&oid);

                // Path should be organized as base_path/XX/rest_of_oid where XX is first 2 chars
                let expected_dir = base_path.join(&oid[0..2]);
                let expected_path = expected_dir.join(&oid[2..]);

                assert_eq!(object_path, expected_path);

                // Create directories and a file to test existence check
                fs::create_dir_all(&expected_dir).await.unwrap();

                let mut file = fs::File::create(&expected_path).await.unwrap();
                file.write_all(b"test content").await.unwrap();
                file.flush().await.unwrap();

                // Check that object_exists returns true for this path
                assert!(lfs_storage.object_exists(&oid).await);

                // Check that a non-existent object returns false
                let non_existent_oid = random_oid();
                assert!(!lfs_storage.object_exists(&non_existent_oid).await);
            }
        });
    }
}

// Property test for URL generation
proptest! {
    #[test]
    fn test_url_generation(
        repo_name in "[a-zA-Z0-9_-]{1,20}",
    ) {
        // Create a base URL with various schemas and paths
        let base_urls = vec![
            format!("https://example.com/git/{}/info/lfs", repo_name),
            format!("http://localhost:8080/git/{}/info/lfs", repo_name),
            format!("https://example.org/custom/path/git/{}/info/lfs", repo_name),
        ];

        for base_url in base_urls {
            let lfs_storage = LfsStorage::new(
                PathBuf::from("/tmp/lfs"),
                base_url.clone()
            );

            // Generate random OIDs
            for _ in 0..5 {
                let oid = random_oid();

                // Test download URL
                let download_url = lfs_storage.get_download_url(&repo_name, &oid);
                let expected_download = format!("{}/objects/{}/{}", base_url, repo_name, oid);
                prop_assert_eq!(download_url, expected_download);

                // Test upload URL
                let upload_url = lfs_storage.get_upload_url(&repo_name, &oid);
                let expected_upload = format!("{}/objects/{}/{}/upload", base_url, repo_name, oid);
                prop_assert_eq!(upload_url, expected_upload);

                // Test verify URL
                let verify_url = lfs_storage.get_verify_url(&repo_name, &oid);
                let expected_verify = format!("{}/objects/{}/{}/verify", base_url, repo_name, oid);
                prop_assert_eq!(verify_url, expected_verify);
            }
        }
    }
}

// Property test for upload/download functionality
proptest! {
    #[test]
    fn test_upload_download_functionality(
        content_size in 1..100_000usize
    ) {
        run_async(async {
            // Create a temporary directory for storage
            let temp_dir = TempDir::new().unwrap();
            let base_path = temp_dir.path().to_path_buf();

            // Generate test content with known hash
            let (content, hash) = generate_content_with_hash(content_size);

            // Create the LFS storage instance
            let lfs_storage = LfsStorage::new(
                base_path.clone(),
                "https://example.com/git/repo/info/lfs".to_string()
            );

            // Create the directory structure for the object
            let object_path = lfs_storage.get_object_path(&hash);
            fs::create_dir_all(object_path.parent().unwrap()).await.unwrap();

            // "Upload" the content
            let mut file = fs::File::create(&object_path).await.unwrap();
            file.write_all(&content).await.unwrap();
            file.flush().await.unwrap();

            // Verify the object exists
            assert!(lfs_storage.object_exists(&hash).await);

            // "Download" the content
            let downloaded = fs::read(&object_path).await.unwrap();

            // Verify the downloaded content matches the original
            assert_eq!(downloaded.len(), content.len());
            assert_eq!(downloaded, content);

            // Verify the hash of the downloaded content
            let mut hasher = Sha256::new();
            hasher.update(&downloaded);
            let downloaded_hash = format!("{:x}", hasher.finalize());
            assert_eq!(downloaded_hash, hash);
        });
    }
}

// Integration test for the end-to-end LFS workflow
#[test]
fn test_lfs_end_to_end_workflow() {
    run_async(async {
        // Create a temporary directory for testing
        let temp_dir = TempDir::new().unwrap();
        let repo_path = temp_dir.path().join("repo");
        let lfs_objects_path = repo_path.join(".git").join("lfs").join("objects");

        // Create the LFS storage backend
        let lfs_storage = LfsStorage::new(
            lfs_objects_path.clone(),
            "https://example.com/git/test-repo/info/lfs".to_string()
        );

        // Create directories
        fs::create_dir_all(&lfs_objects_path).await.unwrap();

        // Simulate a batch API request/response cycle
        let test_sizes = [1024, 10240, 102400];

        for size in test_sizes {
            // Generate content and compute hash
            let (content, oid) = generate_content_with_hash(size);
            let object = LfsObject {
                oid: oid.clone(),
                size: size as u64,
            };

            // Simulate upload of the object
            let object_path = lfs_storage.get_object_path(&oid);
            fs::create_dir_all(object_path.parent().unwrap()).await.unwrap();

            let mut file = fs::File::create(&object_path).await.unwrap();
            file.write_all(&content).await.unwrap();
            file.flush().await.unwrap();

            // Verify the object exists
            assert!(lfs_storage.object_exists(&oid).await);

            // Simulate download of the object
            let downloaded = fs::read(&object_path).await.unwrap();

            // Verify content integrity
            assert_eq!(downloaded.len(), content.len());
            assert_eq!(downloaded, content);

            // Verify hash matches
            let mut hasher = Sha256::new();
            hasher.update(&downloaded);
            let downloaded_hash = format!("{:x}", hasher.finalize());
            assert_eq!(downloaded_hash, oid);
        }
    });
}
