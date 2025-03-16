//! Data access layer for the Art application

pub mod cache;
pub mod database;
pub mod git;
pub mod repository;
pub mod user;
pub mod sqlite;

// Re-export common data structures
pub use database::Sqlite;
pub use git::Git;
pub use repository::Repository;
pub use cache::Cache;
