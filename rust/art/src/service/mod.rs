//! Service layer for the Art application
//!
//! The service layer provides higher-level operations on top of the data layer.
//! It implements business logic, validation, and coordinates operations across
//! multiple data sources.

pub mod commit;
pub mod file;
pub mod format;
pub mod health;
pub mod index;
pub mod observability;
pub mod repository;
pub mod search;
pub mod status;
pub mod testing;
pub mod user;
pub mod git;
pub mod metrics;
pub mod notification;
pub mod email;

// Re-export the services
pub use search::SearchService;
pub use status::StatusService;
pub use observability::ObservabilityService;
pub use email::EmailService;
pub use testing::TestingService;

pub use self::git::GitService;
pub use self::observability::ObservabilityService;
pub use self::repository::statistics::RepositoryStatisticsService;
pub use self::repository::RepositoryService;
pub use self::repository::maintenance::MaintenanceScheduler;
pub use self::user::UserService;
