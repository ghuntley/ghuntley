//! Command-line interface for the Art application

mod commands;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

/// Art - Git repository browser
#[derive(Parser, Debug)]
#[clap(version, about, long_about = None)]
pub struct Cli {
    /// Path to configuration file
    #[clap(short, long, value_name = "FILE")]
    pub config: Option<PathBuf>,

    /// Enable verbose logging
    #[clap(short, long)]
    pub verbose: bool,

    /// Subcommand to execute
    #[clap(subcommand)]
    pub command: Commands,
}

/// Art subcommands
#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Start the web server
    Serve {
        /// Server port
        #[clap(short, long, default_value_t = 3000)]
        port: u16,

        /// Bind address
        #[clap(short, long, default_value = "127.0.0.1")]
        bind: String,

        /// Git repositories directory
        #[clap(long, value_name = "DIRECTORY")]
        repo_dir: Option<PathBuf>,

        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Maximum cache size in MB
        #[clap(long, default_value_t = 100)]
        cache_size: usize,

        /// Number of worker threads (0 = automatic)
        #[clap(long, default_value_t = 0)]
        threads: usize,
    },

    /// Repository management commands
    Repo {
        #[clap(subcommand)]
        command: RepoCommands,
    },

    /// Run maintenance tasks
    Maintenance {
        /// Git repositories directory
        #[clap(long, value_name = "DIRECTORY")]
        repo_dir: Option<PathBuf>,
    },

    /// Check system status
    Status {
        /// Git repositories directory
        #[clap(long, value_name = "DIRECTORY")]
        repo_dir: Option<PathBuf>,

        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,
    },

    /// User management commands
    User {
        #[clap(subcommand)]
        command: UserCommands,
    },

    /// Database backup commands
    Db {
        #[clap(subcommand)]
        command: DbCommands,
    },
}

/// Repository management subcommands
#[derive(Subcommand, Debug)]
pub enum RepoCommands {
    /// List repositories
    List {
        /// Git repositories directory
        #[clap(long, value_name = "DIRECTORY")]
        repo_dir: Option<PathBuf>,
    },

    /// Add a repository
    Add {
        /// Repository path
        #[clap(value_name = "PATH")]
        path: PathBuf,
    },

    /// Reindex repositories
    Reindex {
        /// Git repositories directory
        #[clap(long, value_name = "DIRECTORY")]
        repo_dir: Option<PathBuf>,

        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,
    },
}

/// User management subcommands
#[derive(Subcommand, Debug)]
pub enum UserCommands {
    /// List all users
    List {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Maximum number of users to display
        #[clap(long, default_value_t = 100)]
        limit: usize,

        /// Number of users to skip (for pagination)
        #[clap(long, default_value_t = 0)]
        offset: usize,

        /// Filter by role (user, maintainer, admin)
        #[clap(long)]
        role: Option<String>,

        /// Only show active users
        #[clap(long)]
        active_only: bool,
    },

    /// Add a new user
    Add {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Username
        #[clap(long)]
        username: String,

        /// Email address
        #[clap(long)]
        email: String,

        /// Display name
        #[clap(long)]
        display_name: String,

        /// Password (if not provided, will be prompted)
        #[clap(long)]
        password: Option<String>,

        /// User role (user, maintainer, admin)
        #[clap(long, default_value = "user")]
        role: String,
    },

    /// Update an existing user
    Update {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// User ID or username to update
        #[clap(long)]
        user: String,

        /// New email address
        #[clap(long)]
        email: Option<String>,

        /// New display name
        #[clap(long)]
        display_name: Option<String>,

        /// New password (if not provided, will not be changed)
        #[clap(long)]
        password: Option<String>,

        /// New role (user, maintainer, admin)
        #[clap(long)]
        role: Option<String>,

        /// Set account status to active
        #[clap(long, conflicts_with = "inactive")]
        active: bool,

        /// Set account status to inactive
        #[clap(long, conflicts_with = "active")]
        inactive: bool,
    },

    /// Delete a user
    Delete {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// User ID or username to delete
        user: String,

        /// Confirm deletion without prompting
        #[clap(long)]
        force: bool,
    },

    /// Create default admin user
    CreateAdmin {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Admin username
        #[clap(long, default_value = "admin")]
        username: String,

        /// Admin email
        #[clap(long, default_value = "admin@example.com")]
        email: String,

        /// Admin display name
        #[clap(long, default_value = "Administrator")]
        display_name: String,

        /// Admin password (if not provided, will be prompted)
        #[clap(long)]
        password: Option<String>,
    },

    /// Validate user credentials (check if username/password is valid)
    Validate {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Username to validate
        #[clap(long)]
        username: String,

        /// Password (if not provided, will prompt)
        #[clap(long)]
        password: Option<String>,
    },
}

/// Database management subcommands
#[derive(Subcommand, Debug)]
pub enum DbCommands {
    /// Create a database backup
    Backup {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Backup directory (overrides config)
        #[clap(long, value_name = "DIRECTORY")]
        backup_dir: Option<PathBuf>,

        /// Compression level (0-9, 0 means no compression)
        #[clap(long, default_value = "6")]
        compression: u32,
    },

    /// List available database backups
    List {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Backup directory (overrides config)
        #[clap(long, value_name = "DIRECTORY")]
        backup_dir: Option<PathBuf>,

        /// Show detailed information for each backup
        #[clap(long)]
        detailed: bool,
    },

    /// Restore database from backup
    Restore {
        /// SQLite database path
        #[clap(long, value_name = "FILE")]
        db_path: Option<PathBuf>,

        /// Path to the backup file
        #[clap(value_name = "BACKUP_FILE")]
        backup_file: PathBuf,

        /// Force restore without confirmation
        #[clap(long)]
        force: bool,
    },

    /// Verify backup integrity
    Verify {
        /// Path to the backup file
        #[clap(value_name = "BACKUP_FILE")]
        backup_file: PathBuf,
    },
}

/// Parse command-line arguments
pub fn parse_args() -> Cli {
    Cli::parse()
}
