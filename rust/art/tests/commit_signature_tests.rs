// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Property-based tests for commit signature verification
//!
//! These tests verify the Git commit signature verification implementation
//! by testing its core functionalities:
//! - Signature status serialization/deserialization
//! - Signature verification parsing
//! - Signer information extraction
//! - Status display handling

use art::data::git::signature::{
    SignatureStatus, SignerInfo, SignatureVerification, SignatureVerifier
};
use art::service::commit::SignatureDetails;
use art::error::Result;

use chrono::{DateTime, Utc, TimeZone};
use proptest::prelude::*;
use serde_json;
use std::path::PathBuf;
use std::collections::HashMap;
use std::sync::Arc;
use tempfile::TempDir;

// Run tests in a Tokio runtime
fn run_async<F: std::future::Future<Output = ()>>(future: F) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(future);
}

// Strategies for generating test data

/// Generate a strategy for signature status
fn signature_status_strategy() -> impl Strategy<Value = SignatureStatus> {
    prop_oneof![
        Just(SignatureStatus::Valid),
        Just(SignatureStatus::ValidUntrusted),
        Just(SignatureStatus::Invalid),
        Just(SignatureStatus::Error),
        Just(SignatureStatus::None)
    ]
}

/// Generate optional text
fn optional_text_strategy() -> impl Strategy<Value = Option<String>> {
    prop_oneof![
        Just(None),
        "[a-zA-Z0-9_\\-\\s.@]{1,50}".prop_map(Some)
    ]
}

/// Generate a key ID (hex string)
fn key_id_strategy() -> impl Strategy<Value = String> {
    "[A-F0-9]{16}".prop_map(|id| id.to_string())
}

/// Generate a DateTime
fn datetime_strategy() -> impl Strategy<Value = Option<DateTime<Utc>>> {
    prop_oneof![
        Just(None),
        (1400000000i64..1700000000i64).prop_map(|ts| Some(Utc.timestamp_opt(ts, 0).unwrap()))
    ]
}

/// Generate a trust level
fn trust_level_strategy() -> impl Strategy<Value = Option<String>> {
    prop_oneof![
        Just(None),
        Just(Some("ultimate".to_string())),
        Just(Some("fully".to_string())),
        Just(Some("marginal".to_string())),
        Just(Some("never".to_string())),
        Just(Some("unknown".to_string()))
    ]
}

/// Generate a signer info
fn signer_info_strategy() -> impl Strategy<Value = SignerInfo> {
    (
        optional_text_strategy(), // name
        optional_text_strategy(), // email
        key_id_strategy(),        // key_id
        datetime_strategy(),      // created_at
        trust_level_strategy()    // trust_level
    ).prop_map(|(name, email, key_id, created_at, trust_level)| {
        SignerInfo {
            name,
            email,
            key_id,
            created_at,
            trust_level,
        }
    })
}

/// Generate signature verification
fn signature_verification_strategy() -> impl Strategy<Value = SignatureVerification> {
    (
        signature_status_strategy(),                  // status
        prop_oneof![Just(None), signer_info_strategy().prop_map(Some)], // signer
        optional_text_strategy()                      // message
    ).prop_map(|(status, signer, message)| {
        SignatureVerification {
            status,
            signer,
            message,
        }
    })
}

/// Generate signature details
fn signature_details_strategy() -> impl Strategy<Value = SignatureDetails> {
    (
        optional_text_strategy(), // signer_name
        optional_text_strategy(), // signer_email
        key_id_strategy(),        // key_id
        trust_level_strategy(),   // trust_level
        optional_text_strategy()  // message
    ).prop_map(|(signer_name, signer_email, key_id, trust_level, message)| {
        SignatureDetails {
            signer_name,
            signer_email,
            key_id,
            trust_level,
            message,
        }
    })
}

/// Generate GPG verification output
fn gpg_verification_output_strategy() -> impl Strategy<Value = String> {
    // These patterns are based on real gpg output patterns
    prop_oneof![
        // Valid signature
        "[A-F0-9]{16}".prop_map(|key_id| {
            format!(
                "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
                gpg:                using RSA key {}\n\
                gpg: Good signature from \"Test User <test@example.com>\" [ultimate]",
                key_id
            )
        }),
        // Valid but untrusted
        "[A-F0-9]{16}".prop_map(|key_id| {
            format!(
                "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
                gpg:                using RSA key {}\n\
                gpg: Good signature from \"Test User <test@example.com>\"\n\
                gpg: WARNING: This key is not certified with a trusted signature!\n\
                gpg:          There is no indication that the signature belongs to the owner.",
                key_id
            )
        }),
        // Invalid signature
        "[A-F0-9]{16}".prop_map(|key_id| {
            format!(
                "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
                gpg:                using RSA key {}\n\
                gpg: BAD signature from \"Test User <test@example.com>\" [ultimate]",
                key_id
            )
        }),
        // Error in signature
        Just(
            "gpg: Can't check signature: No public key\n\
            error: failed to verify signature".to_string()
        ),
        // No signature
        Just(
            "fatal: no signature found".to_string()
        )
    ]
}

/// Generate SSH verification output
fn ssh_verification_output_strategy() -> impl Strategy<Value = String> {
    // These patterns are based on real ssh-keygen -Y verify output patterns
    prop_oneof![
        // Valid signature
        "[A-Za-z0-9+/]{20,30}".prop_map(|key_id| {
            format!(
                "Good \"git\" signature for user@example.com with {}\n\
                Verified OK",
                key_id
            )
        }),
        // Invalid signature
        "[A-Za-z0-9+/]{20,30}".prop_map(|key_id| {
            format!(
                "Bad \"git\" signature for user@example.com with {}\n\
                Signature verification failed",
                key_id
            )
        }),
        // Error in signature
        Just(
            "error: ssh signature verification failed: invalid format".to_string()
        ),
        // No signature
        Just(
            "no ssh signature found".to_string()
        )
    ]
}

// Property tests

proptest! {
    /// Test signature status serialization and deserialization
    #[test]
    fn test_signature_status_serde(status in signature_status_strategy()) {
        // Convert to JSON
        let json = serde_json::to_string(&status).unwrap();

        // Parse back from JSON
        let parsed_status: SignatureStatus = serde_json::from_str(&json).unwrap();

        // Should be equal to original
        prop_assert_eq!(status, parsed_status);
    }

    /// Test signature status display
    #[test]
    fn test_signature_status_display(status in signature_status_strategy()) {
        // Get string representation
        let display = format!("{}", status);

        // Verify it's not empty
        prop_assert!(!display.is_empty());

        // Verify it matches expected pattern
        match status {
            SignatureStatus::Valid => prop_assert_eq!(display, "Valid"),
            SignatureStatus::ValidUntrusted => prop_assert_eq!(display, "Valid (untrusted)"),
            SignatureStatus::Invalid => prop_assert_eq!(display, "Invalid"),
            SignatureStatus::Error => prop_assert_eq!(display, "Error"),
            SignatureStatus::None => prop_assert_eq!(display, "None"),
        }
    }

    /// Test signer info serialization and deserialization
    #[test]
    fn test_signer_info_serde(signer in signer_info_strategy()) {
        // Convert to JSON
        let json = serde_json::to_string(&signer).unwrap();

        // Parse back from JSON
        let parsed_signer: SignerInfo = serde_json::from_str(&json).unwrap();

        // Should be equal to original
        prop_assert_eq!(signer.name, parsed_signer.name);
        prop_assert_eq!(signer.email, parsed_signer.email);
        prop_assert_eq!(signer.key_id, parsed_signer.key_id);

        // For DateTime, check both are Some or None, then compare the actual timestamps
        match (signer.created_at, parsed_signer.created_at) {
            (Some(t1), Some(t2)) => prop_assert_eq!(t1.timestamp(), t2.timestamp()),
            (None, None) => {},
            _ => prop_assert!(false, "DateTime serialization mismatch"),
        }

        prop_assert_eq!(signer.trust_level, parsed_signer.trust_level);
    }

    /// Test signature verification serialization and deserialization
    #[test]
    fn test_signature_verification_serde(verification in signature_verification_strategy()) {
        // Convert to JSON
        let json = serde_json::to_string(&verification).unwrap();

        // Parse back from JSON
        let parsed_verification: SignatureVerification = serde_json::from_str(&json).unwrap();

        // Should be equal to original
        prop_assert_eq!(verification.status, parsed_verification.status);
        prop_assert_eq!(verification.message, parsed_verification.message);

        // Compare signer info if present
        match (&verification.signer, &parsed_verification.signer) {
            (Some(s1), Some(s2)) => {
                prop_assert_eq!(s1.name, s2.name);
                prop_assert_eq!(s1.email, s2.email);
                prop_assert_eq!(s1.key_id, s2.key_id);
                prop_assert_eq!(s1.trust_level, s2.trust_level);

                // Compare created_at timestamps if present
                match (s1.created_at, s2.created_at) {
                    (Some(t1), Some(t2)) => prop_assert_eq!(t1.timestamp(), t2.timestamp()),
                    (None, None) => {},
                    _ => prop_assert!(false, "DateTime serialization mismatch"),
                }
            },
            (None, None) => {},
            _ => prop_assert!(false, "Signer info serialization mismatch"),
        }
    }

    /// Test signature details serialization and deserialization
    #[test]
    fn test_signature_details_serde(details in signature_details_strategy()) {
        // Convert to JSON
        let json = serde_json::to_string(&details).unwrap();

        // Parse back from JSON
        let parsed_details: SignatureDetails = serde_json::from_str(&json).unwrap();

        // Should be equal to original
        prop_assert_eq!(details.signer_name, parsed_details.signer_name);
        prop_assert_eq!(details.signer_email, parsed_details.signer_email);
        prop_assert_eq!(details.key_id, parsed_details.key_id);
        prop_assert_eq!(details.trust_level, parsed_details.trust_level);
        prop_assert_eq!(details.message, parsed_details.message);
    }

    /// Test mapping between SignerInfo and SignatureDetails
    #[test]
    fn test_signer_info_to_signature_details(signer in signer_info_strategy(), message in optional_text_strategy()) {
        // Create a SignatureVerification
        let verification = SignatureVerification {
            status: SignatureStatus::Valid,
            signer: Some(signer.clone()),
            message: message.clone(),
        };

        // Map to SignatureDetails (mimic the code in get_commit_with_signature_verification)
        let signature_details = verification.signer.map(|signer| SignatureDetails {
            signer_name: signer.name,
            signer_email: signer.email,
            key_id: signer.key_id,
            trust_level: signer.trust_level,
            message: verification.message,
        });

        // Verify the mapping
        if let Some(details) = signature_details {
            prop_assert_eq!(signer.name, details.signer_name);
            prop_assert_eq!(signer.email, details.signer_email);
            prop_assert_eq!(signer.key_id, details.key_id);
            prop_assert_eq!(signer.trust_level, details.trust_level);
            prop_assert_eq!(message, details.message);
        } else {
            prop_assert!(false, "SignerInfo to SignatureDetails mapping failed");
        }
    }
}

// Tests for GPG verification output parsing
#[test]
fn test_gpg_verification_parsing() {
    run_async(async {
        // Create a SignatureVerifier
        let verifier = SignatureVerifier::new(None, true);

        // Test valid signature parsing
        let valid_output = "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
            gpg:                using RSA key ABCD1234ABCD1234\n\
            gpg: Good signature from \"Test User <test@example.com>\" [ultimate]";

        let result = verifier.parse_gpg_verification_output(valid_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Valid);
        assert!(result.signer.is_some());
        if let Some(signer) = result.signer {
            assert_eq!(signer.name, Some("Test User".to_string()));
            assert_eq!(signer.email, Some("test@example.com".to_string()));
            assert_eq!(signer.key_id, "ABCD1234ABCD1234");
            assert_eq!(signer.trust_level, Some("ultimate".to_string()));
        }

        // Test valid but untrusted signature
        let untrusted_output = "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
            gpg:                using RSA key ABCD1234ABCD1234\n\
            gpg: Good signature from \"Test User <test@example.com>\"\n\
            gpg: WARNING: This key is not certified with a trusted signature!\n\
            gpg:          There is no indication that the signature belongs to the owner.";

        let result = verifier.parse_gpg_verification_output(untrusted_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::ValidUntrusted);

        // Test invalid signature
        let invalid_output = "gpg: Signature made Thu Apr 1 10:20:30 2022 UTC\n\
            gpg:                using RSA key ABCD1234ABCD1234\n\
            gpg: BAD signature from \"Test User <test@example.com>\" [ultimate]";

        let result = verifier.parse_gpg_verification_output(invalid_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Invalid);

        // Test error in verification
        let error_output = "gpg: Can't check signature: No public key\n\
            error: failed to verify signature";

        let result = verifier.parse_gpg_verification_output(error_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Error);

        // Test no signature
        let no_sig_output = "fatal: no signature found";

        let result = verifier.parse_gpg_verification_output(no_sig_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::None);
    });
}

// Tests for SSH verification output parsing
#[test]
fn test_ssh_verification_parsing() {
    run_async(async {
        // Create a SignatureVerifier
        let verifier = SignatureVerifier::new(None, true);

        // Test valid SSH signature parsing
        let valid_output = "Good \"git\" signature for user@example.com with SHA256:AAAAABBBBBCCCCCDDDDD\n\
            Verified OK";

        let result = verifier.parse_ssh_verification_output(valid_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Valid);
        assert!(result.signer.is_some());
        if let Some(signer) = result.signer {
            assert_eq!(signer.email, Some("user@example.com".to_string()));
            assert_eq!(signer.key_id, "SHA256:AAAAABBBBBCCCCCDDDDD");
        }

        // Test invalid SSH signature
        let invalid_output = "Bad \"git\" signature for user@example.com with SHA256:AAAAABBBBBCCCCCDDDDD\n\
            Signature verification failed";

        let result = verifier.parse_ssh_verification_output(invalid_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Invalid);

        // Test error in verification
        let error_output = "error: ssh signature verification failed: invalid format";

        let result = verifier.parse_ssh_verification_output(error_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::Error);

        // Test no signature
        let no_sig_output = "no ssh signature found";

        let result = verifier.parse_ssh_verification_output(no_sig_output).await.unwrap();
        assert_eq!(result.status, SignatureStatus::None);
    });
}

// Integration test for the signature verification workflow
#[test]
fn test_signature_verification_workflow() {
    run_async(async {
        // Create a SignatureVerifier with signature verification enabled
        let mut verifier = SignatureVerifier::new(None, true);

        // Test signature verification is enabled
        assert!(verifier.is_enabled());

        // Test setting verification disabled
        verifier.set_enabled(false);
        assert!(!verifier.is_enabled());

        // Test signature verification when disabled
        // This should return None status without any actual verification
        let repo = MockRepository::new("/path/to/repo");
        let result = verifier.verify_commit(&repo, "abcd1234").await.unwrap();
        assert_eq!(result.status, SignatureStatus::None);

        // Enable verification again and add trusted keys
        verifier.set_enabled(true);
        verifier.add_trusted_gpg_key("ABCD1234ABCD1234", "ultimate").await;
        verifier.add_trusted_ssh_key("SHA256:AAAAABBBBBCCCCC", "ultimate").await;
    });
}

// Mock Repository for testing
struct MockRepository {
    path: String,
}

impl MockRepository {
    fn new(path: &str) -> Self {
        Self { path: path.to_string() }
    }

    fn path(&self) -> &str {
        &self.path
    }
}

// Test that signature verify API correctly formats the signature information
#[test]
fn test_signature_api_formatting() {
    // Create a SignatureVerification
    let verification = SignatureVerification {
        status: SignatureStatus::Valid,
        signer: Some(SignerInfo {
            name: Some("Test User".to_string()),
            email: Some("test@example.com".to_string()),
            key_id: "ABCD1234ABCD1234".to_string(),
            created_at: Some(Utc.timestamp_opt(1617275430, 0).unwrap()),
            trust_level: Some("ultimate".to_string()),
        }),
        message: Some("Good signature".to_string()),
    };

    // Convert to SignatureDetails (mimicking the commit service)
    let signature_status = Some(verification.status.to_string());
    let signature_details = verification.signer.map(|signer| SignatureDetails {
        signer_name: signer.name,
        signer_email: signer.email,
        key_id: signer.key_id,
        trust_level: signer.trust_level,
        message: verification.message,
    });

    // Verify the conversion
    assert_eq!(signature_status, Some("Valid".to_string()));
    assert!(signature_details.is_some());
    if let Some(details) = signature_details {
        assert_eq!(details.signer_name, Some("Test User".to_string()));
        assert_eq!(details.signer_email, Some("test@example.com".to_string()));
        assert_eq!(details.key_id, "ABCD1234ABCD1234");
        assert_eq!(details.trust_level, Some("ultimate".to_string()));
        assert_eq!(details.message, Some("Good signature".to_string()));
    }

    // Verify JSON serialization formats correctly
    let json = serde_json::to_string(&signature_details).unwrap();
    assert!(json.contains("Test User"));
    assert!(json.contains("test@example.com"));
    assert!(json.contains("ABCD1234ABCD1234"));
    assert!(json.contains("ultimate"));
    assert!(json.contains("Good signature"));
}
