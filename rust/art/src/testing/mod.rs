// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Testing framework for Art
//!
//! This module provides testing utilities, helpers, and fixtures for Art's test suite.
//! It focuses heavily on property-based testing using the proptest crate.

pub mod assertions;
pub mod benchmark;
pub mod example_test;
pub mod fixtures;
pub mod fuzzing;
pub mod generators;
pub mod harness;
pub mod integration;
pub mod mutation;
pub mod properties;

use std::env;

/// Initialize the testing framework
///
/// This function should be called at the beginning of integration tests to
/// set up the environment, init logging, etc.
pub fn init() {
    // Only init once
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        // Set up test-specific environment variables
        env::set_var("RUST_LOG", "debug");

        // Initialize test logging
        let _ = tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .with_test_writer()
            .try_init();
    });
}

/// Test utility for creating a temporary directory with proper cleanup
pub fn temp_dir() -> tempfile::TempDir {
    tempfile::tempdir().expect("Failed to create temporary directory")
}

/// Common traits and types used in testing
pub mod prelude {
    pub use crate::error::{Error, Result};
    pub use anyhow::{anyhow, bail};
    pub use proptest::prelude::*;
    pub use proptest_derive::Arbitrary;
    pub use std::sync::Arc;
    pub use tracing::{debug, error, info, trace, warn};

    pub use super::fixtures::*;
    pub use super::generators::*;
    pub use super::properties::*;
    pub use super::assertions::*;
    pub use super::init;
    pub use super::temp_dir;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_init() {
        // Should initialize without errors
        init();
    }

    #[test]
    fn test_temp_dir() {
        let dir = temp_dir();
        assert!(dir.path().exists());
    }
}
