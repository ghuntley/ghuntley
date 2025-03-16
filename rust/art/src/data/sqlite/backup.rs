// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! SQLite database backup and recovery operations
//!
//! This module provides functionality for backing up SQLite databases and
//! restoring from backups if the database becomes corrupted.

use crate::error::{Error, Result};
use chrono::{DateTime, Utc};
use log::{debug, error, info, warn};
use rusqlite::backup::{Backup, BackupStep};
use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Configuration for the database backup system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupConfig {
    /// Directory where backups are stored
    pub backup_dir: PathBuf,

    /// Whether automatic backups are enabled
    pub enabled: bool,

    /// Maximum number of backups to keep
    pub max_backups: usize,

    /// Interval between backups in hours
    pub interval_hours: u32,

    /// Compression level (0-9, 0 means no compression)
    pub compression_level: u32,
}

impl Default for BackupConfig {
    fn default() -> Self {
        Self {
            backup_dir: PathBuf::from("./backups"),
            enabled: true,
            max_backups: 7,
            interval_hours: 24,
            compression_level: 6,
        }
    }
}

/// Metadata about a database backup
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupMetadata {
    /// When the backup was created
    pub created_at: DateTime<Utc>,

    /// Size of the backup in bytes
    pub size_bytes: u64,

    /// Database version/schema version when backup was created
    pub db_version: String,

    /// Original source path
    pub source_path: PathBuf,

    /// Whether the backup is compressed
    pub compressed: bool,

    /// Checksum of the backup file (SHA-256)
    pub checksum: String,
}

/// Interface for database backup operations
pub struct DatabaseBackup {
    /// Configuration for backup operations
    config: BackupConfig,
}

impl DatabaseBackup {
    /// Create a new database backup manager
    pub fn new(config: BackupConfig) -> Self {
        // Create backup directory if it doesn't exist
        if !config.backup_dir.exists() {
            if let Err(e) = fs::create_dir_all(&config.backup_dir) {
                error!("Failed to create backup directory: {}", e);
            }
        }

        Self { config }
    }

    /// Get the list of available backups
    pub fn list_backups(&self) -> Result<Vec<(PathBuf, BackupMetadata)>> {
        let mut backups = Vec::new();

        if !self.config.backup_dir.exists() {
            return Ok(backups);
        }

        for entry in fs::read_dir(&self.config.backup_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().map_or(false, |ext| ext == "backup" || ext == "backup.gz") {
                let metadata_path = path.with_extension("metadata.json");

                if metadata_path.exists() {
                    match fs::read_to_string(&metadata_path) {
                        Ok(content) => {
                            match serde_json::from_str::<BackupMetadata>(&content) {
                                Ok(metadata) => {
                                    backups.push((path.clone(), metadata));
                                }
                                Err(e) => {
                                    warn!("Failed to parse backup metadata for {:?}: {}", path, e);
                                }
                            }
                        }
                        Err(e) => {
                            warn!("Failed to read backup metadata for {:?}: {}", path, e);
                        }
                    }
                } else {
                    warn!("Backup {:?} has no metadata file", path);
                }
            }
        }

        // Sort by creation date, newest first
        backups.sort_by(|(_, a), (_, b)| b.created_at.cmp(&a.created_at));

        Ok(backups)
    }

    /// Create a new backup of the database
    pub fn create_backup(&self, db_path: &Path) -> Result<PathBuf> {
        info!("Creating backup of database at {}", db_path.display());

        // Generate backup filename with timestamp
        let now = Utc::now();
        let timestamp = now.format("%Y%m%d_%H%M%S");
        let db_filename = db_path.file_name()
            .ok_or_else(|| Error::Internal("Invalid database path".to_string()))?
            .to_string_lossy();

        let backup_filename = format!("{}_{}.backup", db_filename, timestamp);
        let backup_path = self.config.backup_dir.join(&backup_filename);

        // Ensure parent directory exists
        if let Some(parent) = backup_path.parent() {
            fs::create_dir_all(parent)?;
        }

        // Open source database in read-only mode
        let source = Connection::open_with_flags(
            db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI,
        )?;

        // Create destination database
        let dest = Connection::open(&backup_path)?;

        // Create backup
        let backup = Backup::new(&source, &dest)?;

        // Perform backup in chunks
        let mut remaining = backup.step(100)?;
        while remaining > 0 {
            remaining = backup.step(100)?;
        }

        // Get database version
        let version: String = source.query_row("SELECT sqlite_version()", [], |row| row.get(0))?;

        // Calculate checksum
        let checksum = calculate_file_checksum(&backup_path)?;

        // Compress the backup if compression is enabled
        let final_backup_path = if self.config.compression_level > 0 {
            let compressed_path = backup_path.with_extension("backup.gz");
            compress_file(&backup_path, &compressed_path, self.config.compression_level)?;

            // Remove the uncompressed backup
            fs::remove_file(&backup_path)?;

            compressed_path
        } else {
            backup_path.clone()
        };

        // Store metadata
        let metadata = BackupMetadata {
            created_at: now,
            size_bytes: fs::metadata(&final_backup_path)?.len(),
            db_version: version,
            source_path: db_path.to_path_buf(),
            compressed: self.config.compression_level > 0,
            checksum,
        };

        let metadata_path = final_backup_path.with_extension("metadata.json");
        let metadata_json = serde_json::to_string_pretty(&metadata)?;
        fs::write(&metadata_path, metadata_json)?;

        // Remove old backups if we have too many
        self.cleanup_old_backups()?;

        info!("Database backup created at {}", final_backup_path.display());
        Ok(final_backup_path)
    }

    /// Restore database from a backup
    pub fn restore_backup(&self, backup_path: &Path, target_path: &Path) -> Result<()> {
        info!("Restoring database from backup {} to {}",
              backup_path.display(), target_path.display());

        // Check if the backup file exists
        if !backup_path.exists() {
            return Err(Error::NotFound(format!("Backup file not found: {}", backup_path.display())));
        }

        // If target exists, create a temporary backup of the current database
        if target_path.exists() {
            let tmp_backup_path = target_path.with_extension("bak");
            info!("Creating temporary backup of current database at {}", tmp_backup_path.display());
            fs::copy(target_path, &tmp_backup_path)?;
        }

        // If the backup is compressed, uncompress it first
        let decompressed_path = if backup_path.extension().map_or(false, |ext| ext == "gz") {
            let temp_path = self.config.backup_dir.join("temp_restore.db");
            decompress_file(backup_path, &temp_path)?;
            Some(temp_path)
        } else {
            None
        };

        let source_path = decompressed_path.as_ref().unwrap_or(backup_path);

        // Open source (backup) database
        let source = Connection::open(source_path)?;

        // Create or open destination database
        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let dest = Connection::open(target_path)?;

        // Create backup
        let backup = Backup::new(&source, &dest)?;

        // Perform backup in chunks
        let mut remaining = backup.step(100)?;
        while remaining > 0 {
            remaining = backup.step(100)?;
        }

        // Clean up temporary decompressed file if we created one
        if let Some(path) = decompressed_path {
            if path.exists() {
                let _ = fs::remove_file(path);
            }
        }

        info!("Database restored successfully from backup");
        Ok(())
    }

    /// Cleanup old backups to maintain the maximum number of backups
    fn cleanup_old_backups(&self) -> Result<()> {
        let backups = self.list_backups()?;

        if backups.len() <= self.config.max_backups {
            return Ok(());
        }

        // Keep the newest max_backups and remove the rest
        let to_remove = &backups[self.config.max_backups..];

        for (path, metadata) in to_remove {
            info!("Removing old backup {} from {}",
                  path.display(), metadata.created_at);

            // Remove the backup file
            if let Err(e) = fs::remove_file(path) {
                warn!("Failed to remove old backup {}: {}", path.display(), e);
            }

            // Remove the metadata file
            let metadata_path = path.with_extension("metadata.json");
            if metadata_path.exists() {
                if let Err(e) = fs::remove_file(&metadata_path) {
                    warn!("Failed to remove backup metadata {}: {}", metadata_path.display(), e);
                }
            }
        }

        Ok(())
    }

    /// Check if automatic backup is due
    pub fn is_backup_due(&self, db_path: &Path) -> Result<bool> {
        if !self.config.enabled {
            return Ok(false);
        }

        let backups = self.list_backups()?;

        // If no backups exist, a backup is due
        if backups.is_empty() {
            return Ok(true);
        }

        // Find the most recent backup for this database
        let mut latest_backup = None;

        for (_, metadata) in backups {
            if metadata.source_path == db_path {
                match latest_backup {
                    None => latest_backup = Some(metadata),
                    Some(ref existing) if metadata.created_at > existing.created_at => {
                        latest_backup = Some(metadata);
                    },
                    _ => {}
                }
            }
        }

        // If no backup exists for this specific database, a backup is due
        let latest = match latest_backup {
            Some(b) => b,
            None => return Ok(true),
        };

        // Check if the time since the last backup exceeds the interval
        let now = Utc::now();
        let duration = now.signed_duration_since(latest.created_at);
        let hours = duration.num_hours();

        Ok(hours >= i64::from(self.config.interval_hours))
    }

    /// Verify a database backup
    pub fn verify_backup(&self, backup_path: &Path) -> Result<bool> {
        info!("Verifying backup integrity: {}", backup_path.display());

        // Check if backup file exists
        if !backup_path.exists() {
            return Err(Error::NotFound(format!("Backup file not found: {}", backup_path.display())));
        }

        // Get metadata
        let metadata_path = backup_path.with_extension("metadata.json");
        if !metadata_path.exists() {
            return Err(Error::NotFound(format!("Backup metadata not found: {}", metadata_path.display())));
        }

        let metadata_content = fs::read_to_string(&metadata_path)?;
        let metadata: BackupMetadata = serde_json::from_str(&metadata_content)?;

        // If compressed, verify by decompression test
        if metadata.compressed {
            let temp_path = self.config.backup_dir.join("temp_verify.db");

            // Clean up any existing temp file
            if temp_path.exists() {
                let _ = fs::remove_file(&temp_path);
            }

            // Attempt decompression
            match decompress_file(backup_path, &temp_path) {
                Ok(_) => {
                    // Calculate checksum of the decompressed file
                    let checksum = calculate_file_checksum(&temp_path)?;

                    // Clean up temp file
                    let _ = fs::remove_file(temp_path);

                    Ok(checksum == metadata.checksum)
                },
                Err(e) => {
                    error!("Failed to decompress backup for verification: {}", e);
                    Ok(false)
                }
            }
        } else {
            // For uncompressed backups, just verify the checksum
            let checksum = calculate_file_checksum(backup_path)?;
            Ok(checksum == metadata.checksum)
        }
    }
}

/// Calculate a SHA-256 checksum of a file
fn calculate_file_checksum(path: &Path) -> Result<String> {
    use sha2::{Sha256, Digest};

    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();

    let mut buffer = [0; 1024 * 1024]; // 1MB buffer
    loop {
        let bytes_read = std::io::Read::read(&mut file, &mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    let result = hasher.finalize();
    Ok(format!("{:x}", result))
}

/// Compress a file using gzip
fn compress_file(source: &Path, dest: &Path, level: u32) -> Result<()> {
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::copy;

    let mut input = std::fs::File::open(source)?;
    let output = std::fs::File::create(dest)?;

    let compression_level = match level {
        0 => Compression::none(),
        1 => Compression::best_speed(),
        2..=8 => Compression::new(level),
        _ => Compression::best_compression(),
    };

    let mut encoder = GzEncoder::new(output, compression_level);
    copy(&mut input, &mut encoder)?;
    encoder.finish()?;

    Ok(())
}

/// Decompress a gzip file
fn decompress_file(source: &Path, dest: &Path) -> Result<()> {
    use flate2::read::GzDecoder;
    use std::io::copy;

    let input = std::fs::File::open(source)?;
    let mut output = std::fs::File::create(dest)?;

    let mut decoder = GzDecoder::new(input);
    copy(&mut decoder, &mut output)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::HashMap;
    use rusqlite::Connection;
    use tempfile::tempdir;

    /// Property tests for the database backup functionality
    proptest! {
        #[test]
        fn test_backup_and_restore(
            db_size in 1..100usize,
            backup_count in 1..10usize,
            max_backups in 5..15usize,
            compression in 0..=9u32
        ) {
            // Create a temp directory for testing
            let temp = tempdir().unwrap();
            let db_path = temp.path().join("test.db");
            let backup_dir = temp.path().join("backups");

            // Create a test database with random data
            let conn = Connection::open(&db_path).unwrap();
            conn.execute(
                "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
                [],
            ).unwrap();

            // Transaction for faster inserts
            let tx = conn.transaction().unwrap();

            // Insert random data
            let mut entries = HashMap::new();
            for i in 0..db_size {
                let value = format!("value_{}", i);
                tx.execute(
                    "INSERT INTO test (id, value) VALUES (?, ?)",
                    [i as i64, &value],
                ).unwrap();
                entries.insert(i as i64, value);
            }

            tx.commit().unwrap();
            conn.close().unwrap();

            // Create backup config
            let config = BackupConfig {
                backup_dir,
                enabled: true,
                max_backups,
                interval_hours: 24,
                compression_level: compression,
            };

            let backup_manager = DatabaseBackup::new(config.clone());

            // Create multiple backups
            let mut backup_paths = Vec::new();
            for _ in 0..backup_count {
                let backup_path = backup_manager.create_backup(&db_path).unwrap();
                backup_paths.push(backup_path);

                // Small delay to ensure unique timestamps
                std::thread::sleep(Duration::from_millis(10));
            }

            // Check that we don't have more backups than max_backups
            let backups = backup_manager.list_backups().unwrap();
            assert!(backups.len() <= max_backups);

            // Restore from the latest backup to a new location
            let restored_path = temp.path().join("restored.db");
            backup_manager.restore_backup(&backup_paths.last().unwrap(), &restored_path).unwrap();

            // Verify the restored data matches the original
            let conn = Connection::open(&restored_path).unwrap();
            let mut stmt = conn.prepare("SELECT id, value FROM test").unwrap();
            let rows = stmt.query_map([], |row| {
                let id: i64 = row.get(0)?;
                let value: String = row.get(1)?;
                Ok((id, value))
            }).unwrap();

            let mut restored_entries = HashMap::new();
            for row in rows {
                let (id, value) = row.unwrap();
                restored_entries.insert(id, value);
            }

            // Verify all original entries exist in the restored database
            assert_eq!(entries.len(), restored_entries.len());
            for (id, value) in &entries {
                assert_eq!(Some(value), restored_entries.get(id));
            }

            // Verify backup integrity
            for path in &backup_paths {
                if path.exists() {
                    assert!(backup_manager.verify_backup(path).unwrap());
                }
            }
        }
    }

    /// Test that is_backup_due works correctly
    #[test]
    fn test_backup_due() {
        // Create a temp directory
        let temp = tempdir().unwrap();
        let db_path = temp.path().join("test.db");
        let backup_dir = temp.path().join("backups");

        // Create empty database
        let conn = Connection::open(&db_path).unwrap();
        conn.close().unwrap();

        // Create backup config with long interval
        let config = BackupConfig {
            backup_dir: backup_dir.clone(),
            enabled: true,
            max_backups: 5,
            interval_hours: 24,
            compression_level: 0,
        };

        let backup_manager = DatabaseBackup::new(config.clone());

        // No backups exist, so backup should be due
        assert!(backup_manager.is_backup_due(&db_path).unwrap());

        // Create a backup
        backup_manager.create_backup(&db_path).unwrap();

        // A backup was just created, so another backup shouldn't be due
        assert!(!backup_manager.is_backup_due(&db_path).unwrap());

        // Change the interval to 0 hours
        let config = BackupConfig {
            interval_hours: 0,
            ..config
        };

        let backup_manager = DatabaseBackup::new(config);

        // With 0 hour interval, backup should be due again
        assert!(backup_manager.is_backup_due(&db_path).unwrap());
    }

    /// Test backup verification
    #[test]
    fn test_backup_verification() {
        // Create a temp directory
        let temp = tempdir().unwrap();
        let db_path = temp.path().join("test.db");
        let backup_dir = temp.path().join("backups");

        // Create test database
        let conn = Connection::open(&db_path).unwrap();
        conn.execute(
            "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
            [],
        ).unwrap();

        conn.execute(
            "INSERT INTO test (id, value) VALUES (1, 'test value')",
            [],
        ).unwrap();

        conn.close().unwrap();

        // Create backup config
        let config = BackupConfig {
            backup_dir,
            enabled: true,
            max_backups: 5,
            interval_hours: 24,
            compression_level: 6, // Enable compression for this test
        };

        let backup_manager = DatabaseBackup::new(config);

        // Create a backup
        let backup_path = backup_manager.create_backup(&db_path).unwrap();

        // Verify the backup
        assert!(backup_manager.verify_backup(&backup_path).unwrap());

        // Corrupt the backup by writing garbage to it
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .open(&backup_path)
            .unwrap();
        use std::io::{Seek, SeekFrom, Write};
        file.seek(SeekFrom::Start(100)).unwrap();
        file.write_all(b"CORRUPTED").unwrap();

        // Verification should now fail
        assert!(!backup_manager.verify_backup(&backup_path).unwrap());
    }

    /// Test different compression levels
    #[test]
    fn test_compression_levels() {
        // Create a temp directory
        let temp = tempdir().unwrap();
        let db_path = temp.path().join("test.db");

        // Create test database with some repeated data (compressible)
        let conn = Connection::open(&db_path).unwrap();
        conn.execute(
            "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
            [],
        ).unwrap();

        // Add some highly compressible data
        let tx = conn.transaction().unwrap();
        for i in 0..1000 {
            tx.execute(
                "INSERT INTO test (id, value) VALUES (?, ?)",
                [i, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"],
            ).unwrap();
        }
        tx.commit().unwrap();
        conn.close().unwrap();

        // Get size of uncompressed database
        let uncompressed_size = fs::metadata(&db_path).unwrap().len();

        // Test different compression levels
        let compression_levels = [0, 1, 6, 9];
        let mut sizes = Vec::new();

        for level in compression_levels {
            let backup_dir = temp.path().join(format!("backups_{}", level));

            let config = BackupConfig {
                backup_dir,
                enabled: true,
                max_backups: 5,
                interval_hours: 24,
                compression_level: level,
            };

            let backup_manager = DatabaseBackup::new(config);
            let backup_path = backup_manager.create_backup(&db_path).unwrap();

            // Get size of compressed backup
            let backup_size = fs::metadata(&backup_path).unwrap().len();
            sizes.push((level, backup_size));

            // Verify the backup
            assert!(backup_manager.verify_backup(&backup_path).unwrap());
        }

        // Level 0 should be uncompressed and similar in size to the original
        let level0 = sizes.iter().find(|(l, _)| *l == 0).unwrap().1;
        // Allow for small differences due to SQLite page size and format differences
        assert!(level0 > uncompressed_size / 2 && level0 < uncompressed_size * 2);

        // Higher compression levels should produce smaller files
        if sizes.len() > 1 {
            let mut sorted_sizes = sizes.clone();
            sorted_sizes.sort_by_key(|(_, size)| *size);

            // Exclude level 0 (uncompressed) from comparison
            let compressed_sizes: Vec<_> = sorted_sizes
                .iter()
                .filter(|(level, _)| *level > 0)
                .collect();

            if compressed_sizes.len() > 1 {
                // Higher levels (generally) produce better compression
                let (_, highest_level_size) = compressed_sizes.last().unwrap();
                let (_, lowest_level_size) = compressed_sizes.first().unwrap();

                // Highest compression level should be smaller than lowest level
                // (or at least not significantly larger)
                assert!(*highest_level_size <= *lowest_level_size * 11 / 10);
            }
        }
    }
}
