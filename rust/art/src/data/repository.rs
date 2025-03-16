#[cfg(test)]
mod prop_tests {
    use super::*;
    use proptest::prelude::*;
    use std::path::Path;
    use tempfile::TempDir;

    // Helper to create a test Git repository
    fn create_test_repo() -> (TempDir, Repository) {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let repo_path = temp_dir.path();

        // Initialize a Git repository
        let git_repo = git2::Repository::init(repo_path).expect("Failed to init git repo");

        // Create an initial commit
        let signature = git2::Signature::now("Test User", "test@example.com").unwrap();
        let tree_id = {
            let mut index = git_repo.index().unwrap();
            index.write_tree().unwrap()
        };
        let tree = git_repo.find_tree(tree_id).unwrap();
        git_repo.commit(Some("HEAD"), &signature, &signature, "Initial commit", &tree, &[]).unwrap();

        // Create our Repository wrapper
        let repo = Repository::open(repo_path.to_string_lossy().to_string()).expect("Failed to open repository");

        (temp_dir, repo)
    }

    // Helper to add a file to a test Git repository and commit it
    fn add_file_to_repo(git_repo: &git2::Repository, filename: &str, content: &str) -> git2::Oid {
        let repo_path = git_repo.path().parent().unwrap();
        let file_path = repo_path.join(filename);

        // Write file
        std::fs::write(&file_path, content).expect("Failed to write file");

        // Stage file
        let mut index = git_repo.index().unwrap();
        index.add_path(Path::new(filename)).unwrap();
        index.write().unwrap();

        // Commit file
        let signature = git2::Signature::now("Test User", "test@example.com").unwrap();
        let tree_id = index.write_tree().unwrap();
        let tree = git_repo.find_tree(tree_id).unwrap();
        let parent = git_repo.head().unwrap().peel_to_commit().unwrap();

        git_repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            &format!("Add {}", filename),
            &tree,
            &[&parent]
        ).unwrap()
    }

    proptest! {
        /// Test that Repository::list_branches returns correct branches
        #[test]
        fn repository_list_branches(
            branch_names in prop::collection::vec("[a-zA-Z0-9_-]{3,20}", 1..5),
        ) {
            // Create a test repository
            let (temp_dir, repo) = create_test_repo();
            let git_repo = git2::Repository::open(temp_dir.path()).unwrap();

            // Create some branches
            let head = git_repo.head().unwrap();
            let head_commit = head.peel_to_commit().unwrap();

            for branch_name in &branch_names {
                git_repo.branch(branch_name, &head_commit, false).unwrap();
            }

            // List branches and check they match what we created
            let branches = repo.list_branches().unwrap();

            // Should contain at least "main" or "master" and all created branches
            assert!(branches.len() >= branch_names.len() + 1, "Branch count mismatch");

            // All our created branches should be in the list
            for branch_name in &branch_names {
                assert!(branches.iter().any(|b| b == branch_name),
                        "Branch '{}' should be in the list", branch_name);
            }
        }

        /// Test that Repository::list_files returns correct files
        #[test]
        fn repository_list_files(
            file_names in prop::collection::vec("[a-zA-Z0-9_-]{3,20}\\.txt", 1..5),
            file_content in "[a-zA-Z0-9_-]{10,100}",
        ) {
            // Create a test repository
            let (temp_dir, repo) = create_test_repo();
            let git_repo = git2::Repository::open(temp_dir.path()).unwrap();

            // Add some files
            for filename in &file_names {
                add_file_to_repo(&git_repo, filename, &file_content);
            }

            // List files and check they match what we created
            let files = repo.list_files("/", "HEAD").unwrap();

            // All our created files should be in the list
            for filename in &file_names {
                assert!(files.iter().any(|f| &f.path == filename),
                        "File '{}' should be in the list", filename);
            }

            // File attributes should be correct
            for file in &files {
                assert!(!file.is_binary, "Text files should not be marked as binary");
                assert_eq!(file.size, file_content.len() as u64, "File size should match content length");
            }
        }

        /// Test that Repository::get_file_content correctly retrieves file content
        #[test]
        fn repository_get_file_content(
            filename in "[a-zA-Z0-9_-]{3,20}\\.txt",
            content in "[a-zA-Z0-9_-\\n]{10,500}",
        ) {
            // Create a test repository
            let (temp_dir, repo) = create_test_repo();
            let git_repo = git2::Repository::open(temp_dir.path()).unwrap();

            // Add a file
            add_file_to_repo(&git_repo, &filename, &content);

            // Get the file content
            let file_content = repo.get_file_content(&filename, "HEAD").unwrap();

            // Content should match what we wrote
            assert_eq!(file_content, content.as_bytes(), "File content should match what was written");
        }

        /// Test that Repository::get_commit correctly retrieves commit info
        #[test]
        fn repository_get_commit(
            message in "[a-zA-Z0-9_-\\s]{5,50}",
            filename in "[a-zA-Z0-9_-]{3,20}\\.txt",
            content in "[a-zA-Z0-9_-]{10,100}",
        ) {
            // Create a test repository
            let (temp_dir, repo) = create_test_repo();
            let git_repo = git2::Repository::open(temp_dir.path()).unwrap();

            // Add a file with a custom commit message
            let signature = git2::Signature::now("Test User", "test@example.com").unwrap();
            let repo_path = git_repo.path().parent().unwrap();
            let file_path = repo_path.join(&filename);

            // Write file
            std::fs::write(&file_path, &content).expect("Failed to write file");

            // Stage file
            let mut index = git_repo.index().unwrap();
            index.add_path(Path::new(&filename)).unwrap();
            index.write().unwrap();

            // Commit file with custom message
            let tree_id = index.write_tree().unwrap();
            let tree = git_repo.find_tree(tree_id).unwrap();
            let parent = git_repo.head().unwrap().peel_to_commit().unwrap();

            let commit_id = git_repo.commit(
                Some("HEAD"),
                &signature,
                &signature,
                &message,
                &tree,
                &[&parent]
            ).unwrap();

            // Get the commit info
            let commit = repo.get_commit(&commit_id.to_string()).unwrap();

            // Verify commit attributes
            assert_eq!(commit.id, commit_id.to_string(), "Commit ID should match");
            assert_eq!(commit.message, message, "Commit message should match");
            assert_eq!(commit.author, "Test User <test@example.com>", "Author should match");
        }

        /// Test that Repository::list_commits returns correct commits
        #[test]
        fn repository_list_commits(
            commit_count in 1..5usize,
        ) {
            // Create a test repository
            let (temp_dir, repo) = create_test_repo();
            let git_repo = git2::Repository::open(temp_dir.path()).unwrap();

            // Create several commits
            let mut commit_ids = Vec::new();
            for i in 0..commit_count {
                let filename = format!("file_{}.txt", i);
                let content = format!("Content for file {}", i);
                let commit_id = add_file_to_repo(&git_repo, &filename, &content);
                commit_ids.push(commit_id.to_string());
            }

            // List commits
            let commits = repo.list_commits("HEAD", None, 100).unwrap();

            // Should have at least commit_count + 1 commits (including initial commit)
            assert!(commits.len() >= commit_count + 1, "Commit count mismatch");

            // All our created commits should be in the list
            for commit_id in &commit_ids {
                assert!(commits.iter().any(|c| &c.id == commit_id),
                        "Commit '{}' should be in the list", commit_id);
            }
        }
    }
}
