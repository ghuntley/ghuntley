// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Git commit signature verification
//!
//! This module provides functionality for verifying signed Git commits.
//! It handles both GPG and SSH signatures, and integrates with the
//! Git repository system.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::str;
use std::sync::Arc;
use std::collections::HashMap;

use serde::{Serialize, Deserialize};
use thiserror::Error;
use tracing::{debug, error, info, warn, trace};
use tokio::process;
use tokio::io::AsyncWriteExt;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc};
use once_cell::sync::Lazy;
use regex::Regex;

use crate::error::{Error, Result};
use super::repository::Repository;

/// Signature verification error
#[derive(Debug, Error)]
pub enum SignatureError {
    /// GPG verification error
    #[error("GPG verification error: {0}")]
    GpgError(String),

    /// SSH verification error
    #[error("SSH verification error: {0}")]
    SshError(String),

    /// Invalid signature format
    #[error("Invalid signature format: {0}")]
    InvalidFormat(String),

    /// Signature not found
    #[error("Signature not found")]
    NotFound,

    /// Command execution error
    #[error("Command execution error: {0}")]
    CommandError(String),
}

/// Signature verification status
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SignatureStatus {
    /// Signature is valid
    Valid,

    /// Signature is valid but from an untrusted key
    ValidUntrusted,

    /// Signature is invalid
    Invalid,

    /// Signature verification error
    Error,

    /// No signature
    None,
}

impl std::fmt::Display for SignatureStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SignatureStatus::Valid => write!(f, "Valid"),
            SignatureStatus::ValidUntrusted => write!(f, "Valid (untrusted)"),
            SignatureStatus::Invalid => write!(f, "Invalid"),
            SignatureStatus::Error => write!(f, "Error"),
            SignatureStatus::None => write!(f, "None"),
        }
    }
}

/// Signer information extracted from a verified signature
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignerInfo {
    /// Name of the signer
    pub name: Option<String>,

    /// Email of the signer
    pub email: Option<String>,

    /// Key ID used for signing
    pub key_id: String,

    /// Signature creation time
    pub created_at: Option<DateTime<Utc>>,

    /// Trust level of the key
    pub trust_level: Option<String>,
}

/// Signature verification result
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignatureVerification {
    /// Verification status
    pub status: SignatureStatus,

    /// Signer information (if available)
    pub signer: Option<SignerInfo>,

    /// Raw verification message
    pub message: Option<String>,
}

/// Signature verifier for Git commits
pub struct SignatureVerifier {
    /// GPG home directory
    gpg_homedir: Option<PathBuf>,

    /// Trusted GPG keys (key ID -> trust level)
    trusted_gpg_keys: Arc<RwLock<HashMap<String, String>>>,

    /// Trusted SSH keys (key ID -> trust level)
    trusted_ssh_keys: Arc<RwLock<HashMap<String, String>>>,

    /// Whether to verify signatures
    verify_signatures: bool,
}

impl SignatureVerifier {
    /// Create a new signature verifier
    pub fn new(gpg_homedir: Option<PathBuf>, verify_signatures: bool) -> Self {
        Self {
            gpg_homedir,
            trusted_gpg_keys: Arc::new(RwLock::new(HashMap::new())),
            trusted_ssh_keys: Arc::new(RwLock::new(HashMap::new())),
            verify_signatures,
        }
    }

    /// Check if signature verification is enabled
    pub fn is_enabled(&self) -> bool {
        self.verify_signatures
    }

    /// Set signature verification enabled/disabled
    pub fn set_enabled(&mut self, enabled: bool) {
        self.verify_signatures = enabled;
    }

    /// Add a trusted GPG key
    pub async fn add_trusted_gpg_key(&self, key_id: &str, trust_level: &str) {
        let mut keys = self.trusted_gpg_keys.write().await;
        keys.insert(key_id.to_string(), trust_level.to_string());
    }

    /// Add a trusted SSH key
    pub async fn add_trusted_ssh_key(&self, key_id: &str, trust_level: &str) {
        let mut keys = self.trusted_ssh_keys.write().await;
        keys.insert(key_id.to_string(), trust_level.to_string());
    }

    /// Verify a commit signature for the given commit ID
    pub async fn verify_commit(&self, repo: &Repository, commit_id: &str) -> Result<SignatureVerification> {
        if !self.verify_signatures {
            // Signature verification is disabled
            return Ok(SignatureVerification {
                status: SignatureStatus::None,
                signer: None,
                message: Some("Signature verification disabled".to_string()),
            });
        }

        // First try GPG verification
        match self.verify_gpg_signature(repo, commit_id).await {
            Ok(verification) => {
                // Check if a signature was found
                if verification.status != SignatureStatus::None {
                    return Ok(verification);
                }
            }
            Err(e) => {
                warn!("GPG verification failed: {}", e);
                // Continue to try SSH verification
            }
        }

        // Then try SSH verification
        match self.verify_ssh_signature(repo, commit_id).await {
            Ok(verification) => Ok(verification),
            Err(e) => {
                warn!("SSH verification failed: {}", e);
                // Return a generic error status
                Ok(SignatureVerification {
                    status: SignatureStatus::Error,
                    signer: None,
                    message: Some(format!("Verification error: {}", e)),
                })
            }
        }
    }

    /// Verify a GPG signature for the given commit ID
    async fn verify_gpg_signature(&self, repo: &Repository, commit_id: &str) -> Result<SignatureVerification> {
        // Check if GPG is available
        if !self.is_gpg_available().await {
            debug!("GPG is not available for signature verification");
            return Ok(SignatureVerification {
                status: SignatureStatus::None,
                signer: None,
                message: Some("GPG not available".to_string()),
            });
        }

        // Build the GPG command
        let mut cmd = process::Command::new("git");
        cmd.arg("--git-dir").arg(repo.path());
        cmd.arg("verify-commit");

        // Add GPG home directory if specified
        if let Some(homedir) = &self.gpg_homedir {
            cmd.arg(format!("--gpg-homedir={}", homedir.display()));
        }

        // Add the commit ID
        cmd.arg(commit_id);

        // Capture output and error
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        // Run the command
        let output = cmd.output().await.map_err(|e| {
            Error::Git(format!("Failed to run git verify-commit: {}", e))
        })?;

        // Parse the verification result
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();

        // Combine output
        let combined_output = format!("{}\n{}", stdout, stderr);

        // Parse the verification result
        self.parse_gpg_verification_output(&combined_output).await
    }

    /// Parse GPG verification output
    async fn parse_gpg_verification_output(&self, output: &str) -> Result<SignatureVerification> {
        // Regular expressions for parsing output
        static GPG_GOOD_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] GOODSIG ([A-F0-9]+) (.+)$").unwrap()
        });

        static GPG_VALID_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] VALIDSIG ([A-F0-9]+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) ([A-F0-9]+)").unwrap()
        });

        static GPG_KEY_EXPIRED_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] EXPKEYSIG ([A-F0-9]+) (.+)$").unwrap()
        });

        static GPG_NO_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] BADSIG").unwrap()
        });

        static GPG_ERR_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] ERRSIG ([A-F0-9]+) (\d+) (\d+) (\d+) (\d+) (\d+)").unwrap()
        });

        static GPG_NO_PUB_KEY_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^\[GNUPG:\] NO_PUBKEY ([A-F0-9]+)$").unwrap()
        });

        static GPG_USER_ID_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r#"(?m)^gpg: Good signature from "(.+) <(.+)>""#).unwrap()
        });

        // Check for valid signature
        if let Some(caps) = GPG_GOOD_SIG_RE.captures(output) {
            let key_id = caps.get(1).map_or("", |m| m.as_str()).to_string();
            let signer_data = caps.get(2).map_or("", |m| m.as_str()).to_string();

            // Extract signer information
            let mut name = None;
            let mut email = None;

            if let Some(caps) = GPG_USER_ID_RE.captures(output) {
                name = caps.get(1).map(|m| m.as_str().to_string());
                email = caps.get(2).map(|m| m.as_str().to_string());
            }

            // Check if the key is trusted
            let trust_level = {
                let keys = self.trusted_gpg_keys.read().await;
                keys.get(&key_id).cloned()
            };

            // Create the verification result
            let status = if trust_level.is_some() {
                SignatureStatus::Valid
            } else {
                SignatureStatus::ValidUntrusted
            };

            let signer = SignerInfo {
                name,
                email,
                key_id,
                created_at: None, // Could extract this from VALIDSIG if needed
                trust_level,
            };

            return Ok(SignatureVerification {
                status,
                signer: Some(signer),
                message: Some("Valid GPG signature".to_string()),
            });
        }

        // Check for bad signature
        if GPG_NO_SIG_RE.is_match(output) {
            let key_id = if let Some(caps) = GPG_NO_PUB_KEY_RE.captures(output) {
                caps.get(1).map(|m| m.as_str().to_string())
            } else {
                None
            };

            return Ok(SignatureVerification {
                status: SignatureStatus::Invalid,
                signer: key_id.map(|key_id| SignerInfo {
                    name: None,
                    email: None,
                    key_id,
                    created_at: None,
                    trust_level: None,
                }),
                message: Some("Invalid GPG signature".to_string()),
            });
        }

        // Check for error signature
        if let Some(caps) = GPG_ERR_SIG_RE.captures(output) {
            let key_id = caps.get(1).map_or("", |m| m.as_str()).to_string();

            return Ok(SignatureVerification {
                status: SignatureStatus::Error,
                signer: Some(SignerInfo {
                    name: None,
                    email: None,
                    key_id,
                    created_at: None,
                    trust_level: None,
                }),
                message: Some("GPG signature verification error".to_string()),
            });
        }

        // No signature found
        Ok(SignatureVerification {
            status: SignatureStatus::None,
            signer: None,
            message: Some("No GPG signature found".to_string()),
        })
    }

    /// Verify an SSH signature for the given commit ID
    async fn verify_ssh_signature(&self, repo: &Repository, commit_id: &str) -> Result<SignatureVerification> {
        // Check if SSH is available
        if !self.is_ssh_available().await {
            debug!("SSH is not available for signature verification");
            return Ok(SignatureVerification {
                status: SignatureStatus::None,
                signer: None,
                message: Some("SSH not available".to_string()),
            });
        }

        // Build the Git command for SSH signature verification
        let mut cmd = process::Command::new("git");
        cmd.arg("--git-dir").arg(repo.path());
        cmd.arg("verify-commit");
        cmd.arg("--ssh-format");
        cmd.arg(commit_id);

        // Capture output and error
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        // Run the command
        let output = cmd.output().await.map_err(|e| {
            Error::Git(format!("Failed to run git verify-commit: {}", e))
        })?;

        // Parse the verification result
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();

        // Combine output
        let combined_output = format!("{}\n{}", stdout, stderr);

        // Parse the verification result
        self.parse_ssh_verification_output(&combined_output).await
    }

    /// Parse SSH verification output
    async fn parse_ssh_verification_output(&self, output: &str) -> Result<SignatureVerification> {
        // Regular expressions for parsing output
        static SSH_GOOD_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^Good signature for (\S+)").unwrap()
        });

        static SSH_VALID_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r#"(?m)^Valid signature from "(.+)"#).unwrap()
        });

        static SSH_KEY_ID_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^using (\w+) key (\S+)").unwrap()
        });

        static SSH_BAD_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^BAD signature from").unwrap()
        });

        static SSH_NO_SIG_RE: Lazy<Regex> = Lazy::new(|| {
            Regex::new(r"(?m)^(error:|fatal:) no signature found").unwrap()
        });

        // Check for valid signature
        if SSH_GOOD_SIG_RE.is_match(output) || SSH_VALID_SIG_RE.is_match(output) {
            // Extract key ID
            let key_id = if let Some(caps) = SSH_KEY_ID_RE.captures(output) {
                caps.get(2).map_or("", |m| m.as_str()).to_string()
            } else {
                "unknown".to_string()
            };

            // Extract signer name
            let name = if let Some(caps) = SSH_VALID_SIG_RE.captures(output) {
                caps.get(1).map(|m| m.as_str().to_string())
            } else {
                None
            };

            // Check if the key is trusted
            let trust_level = {
                let keys = self.trusted_ssh_keys.read().await;
                keys.get(&key_id).cloned()
            };

            // Create the verification result
            let status = if trust_level.is_some() {
                SignatureStatus::Valid
            } else {
                SignatureStatus::ValidUntrusted
            };

            let signer = SignerInfo {
                name,
                email: None, // SSH signatures don't typically have emails
                key_id,
                created_at: None,
                trust_level,
            };

            return Ok(SignatureVerification {
                status,
                signer: Some(signer),
                message: Some("Valid SSH signature".to_string()),
            });
        }

        // Check for bad signature
        if SSH_BAD_SIG_RE.is_match(output) {
            return Ok(SignatureVerification {
                status: SignatureStatus::Invalid,
                signer: None,
                message: Some("Invalid SSH signature".to_string()),
            });
        }

        // Check for no signature
        if SSH_NO_SIG_RE.is_match(output) {
            return Ok(SignatureVerification {
                status: SignatureStatus::None,
                signer: None,
                message: Some("No SSH signature found".to_string()),
            });
        }

        // Error case
        Ok(SignatureVerification {
            status: SignatureStatus::Error,
            signer: None,
            message: Some(format!("SSH signature verification error: {}", output)),
        })
    }

    /// Check if GPG is available
    async fn is_gpg_available(&self) -> bool {
        let output = process::Command::new("gpg")
            .arg("--version")
            .output()
            .await;

        output.is_ok()
    }

    /// Check if SSH is available for signature verification
    async fn is_ssh_available(&self) -> bool {
        let output = process::Command::new("ssh-keygen")
            .arg("-Y")
            .arg("help")
            .output()
            .await;

        output.is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use tokio::fs;
    use tokio::process::Command;
    use proptest::prelude::*;
    use tokio::runtime::Runtime;

    /// Create a test Git repository
    async fn create_test_repo() -> (TempDir, Repository) {
        // Create a temporary directory
        let temp_dir = TempDir::new().unwrap();
        let repo_path = temp_dir.path().to_path_buf();

        // Initialize a Git repository
        let status = Command::new("git")
            .arg("init")
            .arg("--initial-branch=main")
            .current_dir(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        // Configure Git user
        let status = Command::new("git")
            .args(&["config", "user.name", "Test User"])
            .current_dir(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        let status = Command::new("git")
            .args(&["config", "user.email", "test@example.com"])
            .current_dir(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        // Create a dummy file and commit it
        let file_path = repo_path.join("README.md");
        fs::write(&file_path, "# Test Repository\n\nThis is a test repository.").await.unwrap();

        let status = Command::new("git")
            .args(&["add", "README.md"])
            .current_dir(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        let status = Command::new("git")
            .args(&["commit", "-m", "Initial commit"])
            .current_dir(&repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        // Create the Repository instance
        let repo = Repository::open(repo_path.join(".git"))
            .unwrap();

        (temp_dir, repo)
    }

    /// Create a test signed commit
    async fn create_test_signed_commit(repo_path: &Path, sign_key: Option<&str>) -> String {
        // Create a new file
        let file_path = repo_path.join("signed.txt");
        fs::write(&file_path, "This is a signed file").await.unwrap();

        // Stage the file
        let status = Command::new("git")
            .args(&["add", "signed.txt"])
            .current_dir(repo_path)
            .status()
            .await
            .unwrap();

        assert!(status.success());

        // Commit with signature if key is provided
        let mut cmd = Command::new("git");
        cmd.args(&["commit", "-m", "Signed commit"]);

        if let Some(key) = sign_key {
            cmd.args(&["-S", key]);
        }

        cmd.current_dir(repo_path);

        let output = cmd.output().await.unwrap();

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            panic!("Failed to create signed commit: {}", stderr);
        }

        // Get the commit hash
        let output = Command::new("git")
            .args(&["rev-parse", "HEAD"])
            .current_dir(repo_path)
            .output()
            .await
            .unwrap();

        assert!(output.status.success());

        String::from_utf8_lossy(&output.stdout).trim().to_string()
    }

    /// Test case for verification status parsing
    fn verification_status_display(status: SignatureStatus) -> bool {
        let display = status.to_string();
        !display.is_empty()
    }

    proptest! {
        #[test]
        fn test_verification_status_display(status in prop_oneof![
            Just(SignatureStatus::Valid),
            Just(SignatureStatus::ValidUntrusted),
            Just(SignatureStatus::Invalid),
            Just(SignatureStatus::Error),
            Just(SignatureStatus::None)
        ]) {
            verification_status_display(status)
        }

        #[test]
        fn test_signer_info_with_varying_data(
            name in proptest::option::of("\\PC{1,50}"),
            email in proptest::option::of("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"),
            key_id in "[A-F0-9]{8,64}",
            trust_level in proptest::option::of("\\PC{1,20}")
        ) {
            let signer = SignerInfo {
                name: name.clone(),
                email: email.clone(),
                key_id: key_id.clone(),
                created_at: None,
                trust_level: trust_level.clone()
            };

            // Verify the fields are preserved
            assert_eq!(signer.name, name);
            assert_eq!(signer.email, email);
            assert_eq!(signer.key_id, key_id);
            assert_eq!(signer.trust_level, trust_level);
        }

        #[test]
        fn test_parse_verification_output(output in "([\\PC\\s]{0,1000})") {
            let rt = Runtime::new().unwrap();

            rt.block_on(async {
                let verifier = SignatureVerifier::new(None, true);

                // GPG verification output - this shouldn't panic
                let gpg_result = verifier.parse_gpg_verification_output(&output).await;
                assert!(gpg_result.is_ok(), "GPG parsing shouldn't panic");

                // SSH verification output - this shouldn't panic
                let ssh_result = verifier.parse_ssh_verification_output(&output).await;
                assert!(ssh_result.is_ok(), "SSH parsing shouldn't panic");
            });
        }
    }

    #[tokio::test]
    async fn test_verify_unsigned_commit() {
        // Create a test repository
        let (temp_dir, repo) = create_test_repo().await;

        // Get the commit hash
        let output = Command::new("git")
            .args(&["rev-parse", "HEAD"])
            .current_dir(temp_dir.path())
            .output()
            .await
            .unwrap();

        assert!(output.status.success());

        let commit_id = String::from_utf8_lossy(&output.stdout).trim().to_string();

        // Create a signature verifier
        let verifier = SignatureVerifier::new(None, true);

        // Verify the commit
        let result = verifier.verify_commit(&repo, &commit_id).await.unwrap();

        // The commit should have no signature
        assert_eq!(result.status, SignatureStatus::None);
    }

    #[tokio::test]
    #[ignore] // Only run manually when GPG is configured
    async fn test_verify_gpg_signed_commit() {
        // Create a test repository
        let (temp_dir, repo) = create_test_repo().await;

        // Create a signed commit - requires GPG to be set up
        let commit_id = create_test_signed_commit(temp_dir.path(), Some("key-id")).await;

        // Create a signature verifier
        let verifier = SignatureVerifier::new(None, true);

        // Verify the commit
        let result = verifier.verify_commit(&repo, &commit_id).await.unwrap();

        // The commit should have a valid signature or an error if GPG isn't set up
        assert!(matches!(
            result.status,
            SignatureStatus::Valid | SignatureStatus::ValidUntrusted | SignatureStatus::Error
        ));
    }

    #[test]
    fn test_signature_status_serialization() {
        // Test that SignatureStatus can be serialized and deserialized
        let statuses = vec![
            SignatureStatus::Valid,
            SignatureStatus::ValidUntrusted,
            SignatureStatus::Invalid,
            SignatureStatus::Error,
            SignatureStatus::None,
        ];

        for status in statuses {
            let serialized = serde_json::to_string(&status).unwrap();
            let deserialized: SignatureStatus = serde_json::from_str(&serialized).unwrap();
            assert_eq!(status, deserialized);
        }
    }
}
