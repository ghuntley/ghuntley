// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::path::Path;
use std::process::Command;
use tracing::{error, info};

#[derive(Parser)]
#[command(name = "deploy")]
#[command(about = "Deploy tool for managing depot sync and deployments")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Sync the depot repository
    Sync,
    /// Deploy NixOS machine configuration
    Machine {
        /// Deploy from local directory instead of syncing from depot
        #[arg(long)]
        local: bool,
    },
    /// Deploy Home Manager configuration
    Home {
        /// Deploy from local directory instead of syncing from depot
        #[arg(long)]
        local: bool,
    },
}

const DEPOT_DIR: &str = "/var/lib/depot";
const REPO_URL: &str = "https://github.com/ghuntley/ghuntley";

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Sync => sync_depot().await,
        Commands::Machine { local } => deploy_machine(local).await,
        Commands::Home { local } => deploy_home(local).await,
    }
}

async fn sync_depot() -> Result<()> {
    info!("Starting depot sync");

    let depot_path = Path::new(DEPOT_DIR);
    let git_dir = depot_path.join(".git");

    if !git_dir.exists() {
        info!("Cloning depot repository from {}", REPO_URL);
        let output = Command::new("git")
            .args(&[
                "clone",
                "--depth",
                "1",
                "--filter=blob:none",
                REPO_URL,
                DEPOT_DIR,
            ])
            .output()
            .context("Failed to execute git clone")?;

        if !output.status.success() {
            error!(
                "Git clone failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            anyhow::bail!("Git clone failed");
        }
    } else {
        info!("Pulling depot repository updates");
        let output = Command::new("git")
            .args(&["-C", DEPOT_DIR, "pull", "--ff-only", "--prune"])
            .output()
            .context("Failed to execute git pull")?;

        if !output.status.success() {
            error!(
                "Git pull failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            anyhow::bail!("Git pull failed");
        }
    }

    info!("Depot sync completed successfully");
    Ok(())
}

async fn deploy_machine(local: bool) -> Result<()> {
    info!("Starting NixOS machine deployment");

    let depot_dir = if local {
        std::env::current_dir()
            .context("Failed to get current directory")?
            .to_string_lossy()
            .to_string()
    } else {
        // Sync depot first
        sync_depot()
            .await
            .context("Failed to sync depot before machine deployment")?;
        DEPOT_DIR.to_string()
    };

    // Get hostname
    let hostname_output = Command::new("hostname")
        .output()
        .context("Failed to get hostname")?;

    if !hostname_output.status.success() {
        error!("Failed to get hostname");
        anyhow::bail!("Failed to get hostname");
    }

    let hostname = String::from_utf8(hostname_output.stdout)
        .context("Invalid hostname output")?
        .trim()
        .to_string();

    let flake_target = format!("infra:desktop:{}", hostname);
    info!(
        "Deploying NixOS configuration for {} using flake target {}",
        hostname, flake_target
    );

    // Check if the flake target exists
    let check_output = Command::new("nix")
        .args(&["flake", "show", "--json"])
        .current_dir(&depot_dir)
        .output()
        .context("Failed to check flake targets")?;

    if !check_output.status.success() {
        error!(
            "Failed to check flake targets: {}",
            String::from_utf8_lossy(&check_output.stderr)
        );
        anyhow::bail!("Failed to check flake targets");
    }

    let flake_info: serde_json::Value =
        serde_json::from_slice(&check_output.stdout).context("Failed to parse flake info JSON")?;

    if flake_info
        .get("nixosConfigurations")
        .and_then(|configs| configs.get(&flake_target))
        .is_none()
    {
        error!("Flake target {} not found", flake_target);
        anyhow::bail!("Flake target not found");
    }

    // Deploy the configuration
    let deploy_result = Command::new("nixos-rebuild")
        .args(&[
            "switch",
            "--flake",
            &format!("{}#{}", depot_dir, flake_target),
            "--sudo",
            "--verbose",
        ])
        .status()
        .context("Failed to execute nixos-rebuild")?;

    if !deploy_result.success() {
        error!("Deploy machine failed");
        anyhow::bail!("Deploy failed");
    }

    info!("NixOS machine deployment completed successfully");
    Ok(())
}

async fn deploy_home(local: bool) -> Result<()> {
    info!("Starting Home Manager deployment");

    let depot_dir = if local {
        std::env::current_dir()
            .context("Failed to get current directory")?
            .to_string_lossy()
            .to_string()
    } else {
        // Sync depot first
        sync_depot()
            .await
            .context("Failed to sync depot before home deployment")?;
        DEPOT_DIR.to_string()
    };

    let flake_target = "users:ghuntley:home";
    info!(
        "Deploying Home Manager configuration using flake target {}",
        flake_target
    );

    // Check if the flake target exists
    let check_output = Command::new("nix")
        .args(&["flake", "show", "--json"])
        .current_dir(&depot_dir)
        .output()
        .context("Failed to check flake targets")?;

    if !check_output.status.success() {
        error!(
            "Failed to check flake targets: {}",
            String::from_utf8_lossy(&check_output.stderr)
        );
        anyhow::bail!("Failed to check flake targets");
    }

    let flake_info: serde_json::Value =
        serde_json::from_slice(&check_output.stdout).context("Failed to parse flake info JSON")?;

    if flake_info
        .get("homeConfigurations")
        .and_then(|configs| configs.get(flake_target))
        .is_none()
    {
        error!("Flake target {} not found", flake_target);
        anyhow::bail!("Flake target not found");
    }

    // Deploy the home configuration
    let deploy_result = Command::new("home-manager")
        .args(&[
            "switch",
            "--flake",
            &format!("{}#{}", depot_dir, flake_target),
            "--impure",
        ])
        .status()
        .context("Failed to execute home-manager")?;

    if !deploy_result.success() {
        error!("Home Manager deployment failed");
        anyhow::bail!("Home Manager deployment failed");
    }

    info!("Home Manager deployment completed successfully");
    Ok(())
}
