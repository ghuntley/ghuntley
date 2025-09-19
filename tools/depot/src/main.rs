// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

use anyhow::Result;
use clap::{Parser, Subcommand};
use tracing::{error, info, warn};

#[derive(Parser)]
#[command(name = "depot")]
#[command(about = "A build system for nix flake expressions")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Build the specified nix flake expression
    Build {
        /// Nix flake expression to build
        expression: String,
    },
    /// Test the specified nix flake expression
    Test {
        /// Nix flake expression to test
        expression: String,
    },
    /// License management commands
    License {
        #[command(subcommand)]
        action: LicenseAction,
    },
    /// Format code
    Fmt {
        /// Optional target expression to format
        expression: Option<String>,
    },
    /// Lint code
    Lint {
        /// Optional target expression to lint
        expression: Option<String>,
    },
    /// Check code (typecheck, etc.)
    Check {
        /// Optional target expression to check
        expression: Option<String>,
    },
}

#[derive(Subcommand)]
enum LicenseAction {
    /// Check license headers
    Check,
    /// Add license headers
    Add,
}

fn init_tracing() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let cli = Cli::parse();

    match cli.command {
        Commands::Build { expression } => build_expression(&expression).await,
        Commands::Test { expression } => test_expression(&expression).await,
        Commands::License { action } => handle_license(action).await,
        Commands::Fmt { expression } => format_code(expression.as_deref()).await,
        Commands::Lint { expression } => lint_code(expression.as_deref()).await,
        Commands::Check { expression } => check_code(expression.as_deref()).await,
    }
}

async fn build_expression(expression: &str) -> Result<()> {
    info!("Building nix flake expression: {}", expression);

    // Execute nix build command
    let output = tokio::process::Command::new("nix")
        .args(&["build", expression])
        .output()
        .await?;

    if output.status.success() {
        info!("Build succeeded for: {}", expression);
        println!("{}", String::from_utf8_lossy(&output.stdout));
    } else {
        error!("Build failed for: {}", expression);
        eprintln!("{}", String::from_utf8_lossy(&output.stderr));
        std::process::exit(1);
    }

    Ok(())
}

async fn test_expression(expression: &str) -> Result<()> {
    info!("Testing nix flake expression: {}", expression);

    // Execute nix build with check flag for testing
    let output = tokio::process::Command::new("nix")
        .args(&["build", "--check", expression])
        .output()
        .await?;

    if output.status.success() {
        info!("Tests passed for: {}", expression);
        println!("{}", String::from_utf8_lossy(&output.stdout));
    } else {
        error!("Tests failed for: {}", expression);
        eprintln!("{}", String::from_utf8_lossy(&output.stderr));
        std::process::exit(1);
    }

    Ok(())
}

async fn handle_license(action: LicenseAction) -> Result<()> {
    let action_str = match action {
        LicenseAction::Check => "check",
        LicenseAction::Add => "add",
    };

    info!("Running license {}", action_str);

    // Execute the license tool from tools/license
    let output = tokio::process::Command::new("cargo")
        .args(&[
            "run",
            "--manifest-path",
            "tools/license/Cargo.toml",
            "--",
            action_str,
        ])
        .output()
        .await?;

    if output.status.success() {
        info!("License {} completed successfully", action_str);
        println!("{}", String::from_utf8_lossy(&output.stdout));
    } else {
        error!("License {} failed", action_str);
        eprintln!("{}", String::from_utf8_lossy(&output.stderr));
        std::process::exit(1);
    }

    Ok(())
}

async fn format_code(expression: Option<&str>) -> Result<()> {
    if let Some(expr) = expression {
        info!("Formatting code for expression: {}", expr);
        // TODO: treefmt doesn't support specific expressions, format all for now
        warn!("treefmt doesn't support specific expressions, formatting all files");

        let output = tokio::process::Command::new("treefmt").output().await?;

        if output.status.success() {
            info!("Format completed");
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Format failed");
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    } else {
        info!("Formatting all code");
        // Run treefmt for entire project
        let output = tokio::process::Command::new("treefmt").output().await?;

        if output.status.success() {
            info!("Format completed");
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Format failed");
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    }

    Ok(())
}

async fn lint_code(expression: Option<&str>) -> Result<()> {
    if let Some(expr) = expression {
        info!("Linting code for expression: {}", expr);
        // Run nix flake check for specific expression
        let output = tokio::process::Command::new("nix")
            .args(&["flake", "check", expr])
            .output()
            .await?;

        if output.status.success() {
            info!("Lint completed for: {}", expr);
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Lint failed for: {}", expr);
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    } else {
        info!("Linting all code");
        // Run nix flake check for entire flake
        let output = tokio::process::Command::new("nix")
            .args(&["flake", "check"])
            .output()
            .await?;

        if output.status.success() {
            info!("Lint completed");
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Lint failed");
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    }

    Ok(())
}

async fn check_code(expression: Option<&str>) -> Result<()> {
    if let Some(expr) = expression {
        info!("Checking code for expression: {}", expr);
        // Run nix build with dry-run for checking
        let output = tokio::process::Command::new("nix")
            .args(&["build", "--dry-run", expr])
            .output()
            .await?;

        if output.status.success() {
            info!("Check completed for: {}", expr);
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Check failed for: {}", expr);
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    } else {
        info!("Checking all code");
        // Run nix flake check
        let output = tokio::process::Command::new("nix")
            .args(&["flake", "check"])
            .output()
            .await?;

        if output.status.success() {
            info!("Check completed");
            println!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            error!("Check failed");
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            std::process::exit(1);
        }
    }

    Ok(())
}
