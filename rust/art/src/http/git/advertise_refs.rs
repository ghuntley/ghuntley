//! Git HTTP protocol advertise refs

use std::process::Command;
use crate::error::{Error, Result};

/// Advertise Git references
pub async fn advertise_refs(
    repo_path: &str,
    service: &str,
) -> Result<Vec<u8>> {
    // Determine the git command to use
    let git_cmd = match service {
        "git-upload-pack" => "upload-pack",
        "git-receive-pack" => "receive-pack",
        _ => return Err(Error::InvalidInput(format!("Invalid Git service: {}", service))),
    };

    // Execute git command with --advertise-refs
    let output = Command::new("git")
        .arg(git_cmd)
        .arg("--advertise-refs")
        .arg("--stateless-rpc")
        .arg(repo_path)
        .output()
        .map_err(|e| Error::Git(format!("Failed to execute git {}: {}", git_cmd, e)))?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        return Err(Error::Git(format!("Git {} failed: {}", git_cmd, error)));
    }

    Ok(output.stdout)
}
