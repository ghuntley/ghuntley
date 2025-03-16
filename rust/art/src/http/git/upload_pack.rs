//! Git HTTP protocol upload-pack handler

use std::process::{Command, Stdio};
use std::io::Write;
use crate::error::{Error, Result};

/// Handle Git upload-pack request
pub async fn handle_upload_pack(
    repo_path: &str,
    body: &[u8],
) -> Result<Vec<u8>> {
    // Execute git upload-pack command
    let mut child = Command::new("git")
        .arg("upload-pack")
        .arg("--stateless-rpc")
        .arg(repo_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Error::Git(format!("Failed to execute git upload-pack: {}", e)))?;

    // Write request body to git command stdin
    if let Some(stdin) = child.stdin.as_mut() {
        stdin.write_all(body)
            .map_err(|e| Error::Git(format!("Failed to write to git upload-pack stdin: {}", e)))?;
    }

    // Wait for command to complete
    let output = child.wait_with_output()
        .map_err(|e| Error::Git(format!("Failed to get git upload-pack output: {}", e)))?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        return Err(Error::Git(format!("Git upload-pack failed: {}", error)));
    }

    Ok(output.stdout)
}
