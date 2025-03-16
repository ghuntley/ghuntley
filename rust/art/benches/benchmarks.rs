#![feature(test)]

extern crate test;
extern crate art;

use art::config::{Config, RepositoryConfig, DatabaseConfig};
use art::data::git::{Git, Repository};
use art::data::database::Database;
use art::data::cache::Cache;
use art::util::highlight;
use art::error::Result;

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use tempfile::TempDir;
use test::Bencher;

// Helper function to create a benchmark repository
fn create_benchmark_repo(dir: &TempDir) -> Result<PathBuf> {
    let repo_path = dir.path().join("bench-repo");

    // Create a directory for the repository
    fs::create_dir_all(&repo_path)?;

    // Initialize the repository
    let _ = Command::new("git")
        .args(&["init"])
        .current_dir(&repo_path)
        .output()?;

    // Configure user information
    Command::new("git")
        .args(&["config", "user.name", "Bench User"])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["config", "user.email", "bench@example.com"])
        .current_dir(&repo_path)
        .output()?;

    // Create README file
    fs::write(repo_path.join("README.md"), "# Benchmark Repository\n\nThis repository is used for benchmarking.")?;

    // Add and commit README
    Command::new("git")
        .args(&["add", "README.md"])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Initial commit"])
        .current_dir(&repo_path)
        .output()?;

    // Create a source file with content to benchmark syntax highlighting
    let rust_content = r#"
// A sample Rust file for benchmarking syntax highlighting
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

struct Repository {
    name: String,
    path: String,
    branches: HashMap<String, String>,
    commits: Vec<String>,
}

impl Repository {
    fn new(name: &str, path: &str) -> Self {
        Self {
            name: name.to_string(),
            path: path.to_string(),
            branches: HashMap::new(),
            commits: Vec::new(),
        }
    }

    fn add_branch(&mut self, name: &str, commit_id: &str) {
        self.branches.insert(name.to_string(), commit_id.to_string());
    }

    fn add_commit(&mut self, commit_id: &str) {
        self.commits.push(commit_id.to_string());
    }

    fn get_branches(&self) -> &HashMap<String, String> {
        &self.branches
    }

    fn get_commits(&self) -> &[String] {
        &self.commits
    }
}

fn main() {
    let repo = Arc::new(Mutex::new(Repository::new("test-repo", "/path/to/repo")));

    let handles: Vec<_> = (0..10)
        .map(|i| {
            let repo_clone = Arc::clone(&repo);
            thread::spawn(move || {
                let mut repo = repo_clone.lock().unwrap();
                repo.add_branch(&format!("branch-{}", i), &format!("commit-{}", i));
                repo.add_commit(&format!("commit-{}", i));
                thread::sleep(Duration::from_millis(10));
            })
        })
        .collect();

    for handle in handles {
        let _ = handle.join();
    }

    let repo = repo.lock().unwrap();
    println!("Repository: {}", repo.name);
    println!("Branches: {}", repo.branches.len());
    println!("Commits: {}", repo.commits.len());
}
"#;

    fs::write(repo_path.join("sample.rs"), rust_content)?;

    // Add and commit the sample.rs file
    Command::new("git")
        .args(&["add", "sample.rs"])
        .current_dir(&repo_path)
        .output()?;

    Command::new("git")
        .args(&["commit", "-m", "Add sample Rust file"])
        .current_dir(&repo_path)
        .output()?;

    // Create multiple files to benchmark file listing
    for i in 1..50 {
        let filename = format!("file{}.txt", i);
        let content = format!("Content for file {}.\nThis file is used for benchmarking file listing.", i);

        fs::write(repo_path.join(&filename), content)?;

        // Add the file
        Command::new("git")
            .args(&["add", &filename])
            .current_dir(&repo_path)
            .output()?;
    }

    // Commit all the files
    Command::new("git")
        .args(&["commit", "-m", "Add multiple files for benchmarking"])
        .current_dir(&repo_path)
        .output()?;

    // Create a branch
    Command::new("git")
        .args(&["branch", "feature"])
        .current_dir(&repo_path)
        .output()?;

    // Create a tag
    Command::new("git")
        .args(&["tag", "-a", "v1.0", "-m", "Version 1.0"])
        .current_dir(&repo_path)
        .output()?;

    Ok(repo_path)
}

// Benchmark opening a repository
#[bench]
fn bench_open_repository(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();

    b.iter(|| {
        let _ = git.open(repo_name, &repo_path);
    });

    Ok(())
}

// Benchmark listing repository branches
#[bench]
fn bench_list_branches(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    b.iter(|| {
        let _ = repo.branches();
    });

    Ok(())
}

// Benchmark listing repository files
#[bench]
fn bench_list_files(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    b.iter(|| {
        let _ = repo.list_files("", "master");
    });

    Ok(())
}

// Benchmark getting repository info
#[bench]
fn bench_repository_info(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    b.iter(|| {
        let _ = repo.info();
    });

    Ok(())
}

// Benchmark syntax highlighting
#[bench]
fn bench_syntax_highlighting(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    // Get the sample Rust file
    let file_content = repo.file("sample.rs", "master")?;
    let content = String::from_utf8_lossy(&file_content.content).to_string();

    b.iter(|| {
        let _ = highlight::highlight_syntax(std::path::Path::new("sample.rs"), &content);
    });

    Ok(())
}

// Benchmark database operations
#[bench]
fn bench_database_operations(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let db_path = temp_dir.path().join("bench.db");

    let db_config = DatabaseConfig {
        path: db_path,
        use_cache: false, // Disable cache for benchmarking raw DB performance
        cache_max_entries: 0,
        cache_ttl_seconds: 0,
    };

    let db = Database::new(&db_config)?;

    // Benchmark a sequence of database operations
    b.iter(|| {
        // Index a repository
        let _ = db.index_repository("bench-repo", "Benchmark Repository", "A repository for benchmarking");

        // Update repository stats
        let _ = db.update_repository_stats("bench-repo", 2, 1, 3);

        // Index a commit
        let _ = db.index_commit(
            "bench-repo",
            "abc123",
            "Benchmark commit",
            "Bench User",
            "bench@example.com",
            chrono::Utc::now().timestamp(),
        );

        // Search repositories
        let _ = db.search_repositories("bench");

        // Search commits
        let _ = db.search_commits("bench-repo", "benchmark");
    });

    Ok(())
}

// Benchmark cache operations
#[bench]
fn bench_cache_operations(b: &mut Bencher) {
    // Create a cache with reasonable settings
    let cache = Cache::<String, String>::new(1000, 60);

    // Populate the cache with some initial values
    let runtime = tokio::runtime::Runtime::new().unwrap();

    for i in 0..100 {
        let key = format!("key{}", i);
        let value = format!("value{}", i);
        runtime.block_on(async {
            cache.insert(key, value).await;
        });
    }

    // Benchmark a mix of operations
    b.iter(|| {
        runtime.block_on(async {
            // Get some existing values
            for i in 0..10 {
                let key = format!("key{}", i);
                let _ = cache.get(&key).await;
            }

            // Insert some new values
            for i in 100..110 {
                let key = format!("key{}", i);
                let value = format!("value{}", i);
                cache.insert(key, value).await;
            }

            // Invalidate a value
            let key = "key1".to_string();
            cache.invalidate(&key).await;

            // Get a non-existent value
            let _ = cache.get("non-existent-key").await;
        });
    });
}

// Benchmark template rendering
#[bench]
fn bench_template_rendering(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    // Get repository information for the template
    let repo_info = repo.info()?;

    // Get branches for the template
    let branches = repo.branches()?;
    let branch_vec: Vec<(&str, &str)> = branches.iter()
        .map(|(name, id)| (name.as_str(), id.as_str()))
        .collect();

    // Get tags for the template
    let tags = repo.tags()?;
    let tag_vec: Vec<(&str, &str)> = tags.iter()
        .map(|(name, id)| (name.as_str(), id.as_str()))
        .collect();

    // Benchmark repository detail template rendering
    b.iter(|| {
        let template = art::template::RepoDetailTemplate::new(
            &repo_info,
            "master",
            branch_vec.clone(),
            tag_vec.clone(),
        );

        let _ = template.get_content();
    });

    Ok(())
}

// Benchmark file reading performance
#[bench]
fn bench_file_reading(b: &mut Bencher) -> Result<()> {
    // Set up the test environment
    let temp_dir = TempDir::new()?;
    let repo_path = create_benchmark_repo(&temp_dir)?;

    let repo_config = RepositoryConfig {
        repo_dir: temp_dir.path().to_path_buf(),
        max_commits: 100,
        default_branch: "main".to_string(),
    };

    let git = Git::new(&repo_config)?;
    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let repo = git.open(repo_name, &repo_path)?;

    b.iter(|| {
        // Read the sample.rs file
        let _ = repo.file("sample.rs", "master");
    });

    Ok(())
}
