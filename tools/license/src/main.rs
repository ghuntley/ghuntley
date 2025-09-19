use anyhow::{anyhow, Result};
use clap::{Arg, Command};
use git2::Repository;
use ignore::WalkBuilder;
use std::path::{Path, PathBuf};

mod license;
mod file_types;

use license::LicenseChecker;

fn main() -> Result<()> {
    let matches = Command::new("license")
        .version("0.1.0")
        .about("A program which ensures source code files have copyright license headers")
        .arg(
            Arg::new("check")
                .long("check")
                .help("Check mode: verify presence of license headers and exit with non-zero code if missing")
                .action(clap::ArgAction::SetTrue),
        )
        .arg(
            Arg::new("all")
                .long("all")
                .help("Scan all files recursively (ignoring git status), respecting .gitignore")
                .action(clap::ArgAction::SetTrue),
        )
        .arg(
            Arg::new("verbose")
                .long("verbose")
                .short('v')
                .help("Verbose mode: print the name of files that are processed")
                .action(clap::ArgAction::SetTrue),
        )
        .arg(
            Arg::new("ignore")
                .long("ignore")
                .help("File patterns to ignore (glob patterns)")
                .action(clap::ArgAction::Append)
                .value_name("PATTERN"),
        )
        .arg(
            Arg::new("paths")
                .help("Paths to scan (if not provided, uses git status for changed files)")
                .action(clap::ArgAction::Append)
                .value_name("PATH"),
        )
        .get_matches();

    let recursive = true; // Always recursive
    let check_only = matches.get_flag("check");
    let add_mode = !check_only; // Default is add mode, unless --check is specified
    let all_files = matches.get_flag("all");
    let verbose = matches.get_flag("verbose");
    let ignore_patterns: Vec<&str> = matches
        .get_many::<String>("ignore")
        .unwrap_or_default()
        .map(|s| s.as_str())
        .collect();
    let paths: Vec<&str> = matches
        .get_many::<String>("paths")
        .unwrap_or_default()
        .map(|s| s.as_str())
        .collect();

    let checker = LicenseChecker::new(ignore_patterns, verbose);

    let files_to_check = if all_files {
        // --all flag: scan all files recursively, respecting .gitignore
        if verbose {
            println!("Scanning all files recursively...");
        }
        get_files_recursive(&["."])?
    } else if paths.is_empty() {
        // Default mode: check files that have changed according to git status
        // If not in git repo, scan current directory
        match get_changed_files() {
            Ok(files) if !files.is_empty() => files,
            _ => {
                if verbose {
                    println!("Not in git repo or no changed files, scanning current directory...");
                }
                get_files_recursive(&["."])?
            }
        }
    } else {
        // Explicit paths provided
        if recursive {
            get_files_recursive(&paths)?
        } else {
            paths.into_iter().map(PathBuf::from).collect()
        }
    };

    let mut missing_license = false;
    let mut processed_count = 0;
    let mut modified_count = 0;

    for file_path in files_to_check {
        if checker.should_skip(&file_path) {
            if verbose {
                println!("Skipping: {}", file_path.display());
            }
            continue;
        }

        processed_count += 1;
        
        if add_mode {
            // Add mode: first check if license is missing, then try to add it
            let has_license = checker.has_license(&file_path)?;
            if !has_license {
                println!("✗ Missing license: {}", file_path.display());
                match checker.add_license(&file_path) {
                    Ok(true) => {
                        println!("✓ Added license: {}", file_path.display());
                        modified_count += 1;
                    }
                    Ok(false) => {
                        // This shouldn't happen since we already checked it's missing
                        if verbose {
                            println!("✓ License already present: {}", file_path.display());
                        }
                    }
                    Err(e) => {
                        eprintln!("✗ Error adding license to {}: {}", file_path.display(), e);
                    }
                }
            } else {
                if verbose {
                    println!("✓ License already present: {}", file_path.display());
                }
            }
        } else {
            // Check mode (default): just check for license presence
            if checker.has_license(&file_path)? {
                if verbose {
                    println!("✓ License found: {}", file_path.display());
                }
            } else {
                println!("✗ Missing license: {}", file_path.display());
                missing_license = true;
            }
        }
    }

    if verbose {
        if add_mode {
            println!("\nProcessed {} files, added licenses to {} files", processed_count, modified_count);
        } else {
            println!("\nProcessed {} files", processed_count);
        }
    }

    if check_only && missing_license {
        std::process::exit(1);
    }

    Ok(())
}

fn get_changed_files() -> Result<Vec<PathBuf>> {
    let repo = Repository::open_from_env()
        .map_err(|_| anyhow!("Not in a git repository or git not available"))?;
    
    let mut files = Vec::new();
    let mut status_options = git2::StatusOptions::new();
    status_options.include_untracked(true);
    status_options.include_ignored(false);
    
    let statuses = repo.statuses(Some(&mut status_options))?;
    
    for entry in statuses.iter() {
        if let Some(path) = entry.path() {
            // Only include modified, added, or new files
            let status = entry.status();
            if status.is_wt_modified() 
                || status.is_wt_new() 
                || status.is_index_modified() 
                || status.is_index_new() {
                let path_buf = PathBuf::from(path);
                
                // If it's a directory (untracked directories show up as single entries),
                // expand it to include all files within it
                if path_buf.is_dir() {
                    let dir_files = get_files_recursive(&[path])?;
                    files.extend(dir_files);
                } else {
                    files.push(path_buf);
                }
            }
        }
    }
    
    Ok(files)
}

fn get_files_recursive(paths: &[&str]) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    
    for path_str in paths {
        let path = Path::new(path_str);
        
        if path.is_file() {
            files.push(path.to_path_buf());
        } else if path.is_dir() {
            // Use ignore crate to respect .gitignore files
            let walker = WalkBuilder::new(path)
                .follow_links(false)
                .build();
            
            for result in walker {
                match result {
                    Ok(entry) => {
                        if entry.file_type().map_or(false, |ft| ft.is_file()) {
                            files.push(entry.into_path());
                        }
                    }
                    Err(err) => {
                        eprintln!("Warning: {}", err);
                    }
                }
            }
        }
    }
    
    Ok(files)
}
