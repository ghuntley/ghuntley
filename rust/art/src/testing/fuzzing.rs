// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Fuzzing framework for Art
//!
//! This module provides fuzzing capabilities for input validation testing.

use crate::prelude::*;
use rand::{Rng, SeedableRng};
use rand::rngs::StdRng;
use rand::distributions::{Alphanumeric, Standard, Distribution};
use std::collections::HashSet;
use std::fmt;
use std::panic::{self, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// Result of a single fuzzing run
#[derive(Debug, Clone)]
pub enum FuzzResult {
    /// Success (no error)
    Success,

    /// Test case panicked
    Panic(String),

    /// Test case returned an error
    Error(String),

    /// Test case timed out
    Timeout,
}

impl fmt::Display for FuzzResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FuzzResult::Success => write!(f, "Success"),
            FuzzResult::Panic(msg) => write!(f, "Panic: {}", msg),
            FuzzResult::Error(msg) => write!(f, "Error: {}", msg),
            FuzzResult::Timeout => write!(f, "Timeout"),
        }
    }
}

/// Results of a fuzzing campaign
#[derive(Debug, Clone)]
pub struct FuzzingResults {
    /// Total number of test cases run
    pub total_cases: usize,

    /// Number of successful test cases
    pub successful_cases: usize,

    /// Number of failed test cases
    pub failed_cases: usize,

    /// Set of seeds that caused failures
    pub failing_seeds: HashSet<u64>,

    /// Unique failures found
    pub unique_failures: Vec<String>,

    /// Duration of the fuzzing campaign
    pub duration: Duration,
}

impl fmt::Display for FuzzingResults {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "Fuzzing Results:")?;
        writeln!(f, "Total test cases:   {}", self.total_cases)?;
        writeln!(f, "Successful cases:   {}", self.successful_cases)?;
        writeln!(f, "Failed cases:       {}", self.failed_cases)?;
        writeln!(f, "Unique failures:    {}", self.unique_failures.len())?;
        writeln!(f, "Duration:           {:?}", self.duration)?;

        if !self.unique_failures.is_empty() {
            writeln!(f, "\nUnique failures:")?;
            for (i, failure) in self.unique_failures.iter().enumerate() {
                writeln!(f, "{}. {}", i + 1, failure)?;
            }
        }

        if !self.failing_seeds.is_empty() {
            writeln!(f, "\nFailing seeds: {:?}", self.failing_seeds)?;
        }

        Ok(())
    }
}

/// Configuration for a fuzzing run
#[derive(Debug, Clone)]
pub struct FuzzConfig {
    /// Number of iterations to run
    pub iterations: usize,

    /// Maximum time to run fuzzing
    pub max_time: Option<Duration>,

    /// Timeout for each test case
    pub case_timeout: Duration,

    /// Random seed to use (None for random)
    pub seed: Option<u64>,

    /// Whether to stop on first failure
    pub stop_on_failure: bool,

    /// Whether to capture panics (prevents process termination)
    pub capture_panics: bool,

    /// Whether to record code coverage
    pub record_coverage: bool,
}

impl Default for FuzzConfig {
    fn default() -> Self {
        Self {
            iterations: 1000,
            max_time: Some(Duration::from_secs(60)),
            case_timeout: Duration::from_secs(5),
            seed: None,
            stop_on_failure: false,
            capture_panics: true,
            record_coverage: false,
        }
    }
}

/// A generator for fuzzing inputs
pub trait FuzzGenerator<T>: Send + Sync {
    /// Generate a new random value
    fn generate(&self, rng: &mut StdRng) -> T;

    /// Generate a value from a seed
    fn generate_from_seed(&self, seed: u64) -> T {
        let mut rng = StdRng::seed_from_u64(seed);
        self.generate(&mut rng)
    }

    /// Mutate an existing value
    fn mutate(&self, value: &T, rng: &mut StdRng) -> T;
}

/// Default implementation for standard types using rand::Distribution
pub struct StandardGenerator<T> where Standard: Distribution<T> {
    _phantom: std::marker::PhantomData<T>,
}

impl<T> StandardGenerator<T> where Standard: Distribution<T> {
    pub fn new() -> Self {
        Self {
            _phantom: std::marker::PhantomData,
        }
    }
}

impl<T> Default for StandardGenerator<T> where Standard: Distribution<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> FuzzGenerator<T> for StandardGenerator<T>
where
    Standard: Distribution<T>,
    T: Clone,
{
    fn generate(&self, rng: &mut StdRng) -> T {
        rng.gen()
    }

    fn mutate(&self, _value: &T, rng: &mut StdRng) -> T {
        // For standard generators, mutation is just creating a new value
        rng.gen()
    }
}

/// Generator for string inputs
pub struct StringGenerator {
    /// Minimum length of generated strings
    min_len: usize,

    /// Maximum length of generated strings
    max_len: usize,

    /// Whether to include non-ASCII characters
    include_non_ascii: bool,

    /// Whether to include control characters
    include_control_chars: bool,
}

impl StringGenerator {
    /// Create a new string generator
    pub fn new(min_len: usize, max_len: usize) -> Self {
        Self {
            min_len,
            max_len,
            include_non_ascii: false,
            include_control_chars: false,
        }
    }

    /// Allow non-ASCII characters in generated strings
    pub fn include_non_ascii(mut self, include: bool) -> Self {
        self.include_non_ascii = include;
        self
    }

    /// Allow control characters in generated strings
    pub fn include_control_chars(mut self, include: bool) -> Self {
        self.include_control_chars = include;
        self
    }

    /// Generate a random ASCII character
    fn random_ascii_char(&self, rng: &mut StdRng) -> char {
        let range = if self.include_control_chars {
            0..128
        } else {
            32..127
        };

        rng.gen_range(range) as u8 as char
    }

    /// Generate a random Unicode character
    fn random_unicode_char(&self, rng: &mut StdRng) -> char {
        if !self.include_non_ascii || rng.gen_bool(0.7) {
            self.random_ascii_char(rng)
        } else {
            // Generate unicode characters from common ranges
            let ranges = [
                // Latin-1 Supplement
                (0x0080, 0x00FF),
                // Latin Extended-A
                (0x0100, 0x017F),
                // Greek and Coptic
                (0x0370, 0x03FF),
                // Cyrillic
                (0x0400, 0x04FF),
                // Common CJK ideographs
                (0x4E00, 0x9FFF),
                // Emoji
                (0x1F300, 0x1F5FF),
            ];

            let (start, end) = ranges[rng.gen_range(0..ranges.len())];
            let code_point = rng.gen_range(start..=end);

            // Convert code point to char, handling invalid values
            std::char::from_u32(code_point).unwrap_or('�')
        }
    }
}

impl FuzzGenerator<String> for StringGenerator {
    fn generate(&self, rng: &mut StdRng) -> String {
        let len = rng.gen_range(self.min_len..=self.max_len);

        if !self.include_non_ascii && !self.include_control_chars {
            // Use efficient generator for simple ASCII
            return rng.sample_iter(&Alphanumeric)
                .take(len)
                .map(char::from)
                .collect();
        }

        // Generate with custom character selection
        (0..len)
            .map(|_| {
                if self.include_non_ascii {
                    self.random_unicode_char(rng)
                } else {
                    self.random_ascii_char(rng)
                }
            })
            .collect()
    }

    fn mutate(&self, value: &String, rng: &mut StdRng) -> String {
        // Mutation strategies:
        // 1. Change length
        // 2. Modify characters
        // 3. Insert special sequences

        let mut result = value.clone();

        // Apply 1-3 mutations
        let num_mutations = rng.gen_range(1..=3);
        for _ in 0..num_mutations {
            let strategy = rng.gen_range(0..5);

            match strategy {
                0 => {
                    // Delete a character
                    if !result.is_empty() {
                        let pos = rng.gen_range(0..result.len());
                        result.remove(pos);
                    }
                }
                1 => {
                    // Insert a character
                    if result.len() < self.max_len {
                        let pos = rng.gen_range(0..=result.len());
                        let ch = if self.include_non_ascii {
                            self.random_unicode_char(rng)
                        } else {
                            self.random_ascii_char(rng)
                        };
                        result.insert(pos, ch);
                    }
                }
                2 => {
                    // Modify a character
                    if !result.is_empty() {
                        let pos = rng.gen_range(0..result.len());
                        let ch = if self.include_non_ascii {
                            self.random_unicode_char(rng)
                        } else {
                            self.random_ascii_char(rng)
                        };
                        // This is inefficient but works for UTF-8
                        result = result[..pos].to_string() + &ch.to_string() + &result[pos+1..];
                    }
                }
                3 => {
                    // Insert a special sequence
                    if result.len() + 5 <= self.max_len {
                        let pos = rng.gen_range(0..=result.len());
                        let special_sequences = [
                            "%00", // Null byte
                            "../", // Path traversal
                            "\"'<>", // HTML/SQL injection
                            "/**/", // Comment
                            "\\\"\\", // Escape sequences
                            "👨‍👩‍👧‍👦", // Complex Unicode
                        ];
                        let seq = special_sequences[rng.gen_range(0..special_sequences.len())];
                        result.insert_str(pos, seq);
                    }
                }
                4 => {
                    // Duplicate a substring
                    if !result.is_empty() && result.len() * 2 <= self.max_len {
                        let start = rng.gen_range(0..result.len());
                        let len = rng.gen_range(1..=result.len() - start);
                        let substr = &result[start..start+len];
                        let pos = rng.gen_range(0..=result.len());
                        result.insert_str(pos, substr);
                    }
                }
                _ => unreachable!(),
            }
        }

        // Ensure min length
        while result.len() < self.min_len {
            let ch = if self.include_non_ascii {
                self.random_unicode_char(rng)
            } else {
                self.random_ascii_char(rng)
            };
            result.push(ch);
        }

        // Ensure max length
        if result.len() > self.max_len {
            result.truncate(self.max_len);
        }

        result
    }
}

/// Generator for HTTP paths
pub struct HttpPathGenerator {
    /// Base string generator
    string_gen: StringGenerator,
}

impl HttpPathGenerator {
    /// Create a new HTTP path generator
    pub fn new() -> Self {
        Self {
            string_gen: StringGenerator::new(1, 50)
                .include_non_ascii(false)
                .include_control_chars(false),
        }
    }
}

impl Default for HttpPathGenerator {
    fn default() -> Self {
        Self::new()
    }
}

impl FuzzGenerator<String> for HttpPathGenerator {
    fn generate(&self, rng: &mut StdRng) -> String {
        // Generate a base random string
        let segments = rng.gen_range(1..8);
        let mut path = String::new();

        // Ensure path starts with /
        path.push('/');

        for i in 0..segments {
            if i > 0 {
                path.push('/');
            }

            // Generate segment
            let segment_len = rng.gen_range(1..15);
            let segment: String = (0..segment_len)
                .map(|_| {
                    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.";
                    chars.chars().nth(rng.gen_range(0..chars.len())).unwrap()
                })
                .collect();

            path.push_str(&segment);
        }

        // Add query string sometimes
        if rng.gen_bool(0.3) {
            path.push('?');

            let params = rng.gen_range(1..4);
            for i in 0..params {
                if i > 0 {
                    path.push('&');
                }

                // Generate parameter
                let key_len = rng.gen_range(1..10);
                let key: String = (0..key_len)
                    .map(|_| {
                        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                        chars.chars().nth(rng.gen_range(0..chars.len())).unwrap()
                    })
                    .collect();

                path.push_str(&key);
                path.push('=');

                // Sometimes include malicious content in values
                if rng.gen_bool(0.2) {
                    let special_values = [
                        "1'%20OR%20'1'='1", // SQL injection
                        "../../../etc/passwd", // Path traversal
                        "<script>alert(1)</script>", // XSS
                        "*;ls%20-la", // Command injection
                        "%00", // Null byte
                    ];
                    path.push_str(special_values[rng.gen_range(0..special_values.len())]);
                } else {
                    let val_len = rng.gen_range(1..15);
                    let val: String = (0..val_len)
                        .map(|_| {
                            let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.";
                            chars.chars().nth(rng.gen_range(0..chars.len())).unwrap()
                        })
                        .collect();
                    path.push_str(&val);
                }
            }
        }

        // Add fragment sometimes
        if rng.gen_bool(0.1) {
            path.push('#');
            let fragment_len = rng.gen_range(1..10);
            let fragment: String = (0..fragment_len)
                .map(|_| {
                    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.";
                    chars.chars().nth(rng.gen_range(0..chars.len())).unwrap()
                })
                .collect();
            path.push_str(&fragment);
        }

        path
    }

    fn mutate(&self, value: &String, rng: &mut StdRng) -> String {
        // Mutation strategies:
        // 1. Use string general mutation
        // 2. Path-specific mutations

        let strategy = rng.gen_range(0..5);

        match strategy {
            0..=2 => {
                // Use general string mutation
                self.string_gen.mutate(value, rng)
            }
            3 => {
                // Insert path traversal
                let mut result = value.clone();
                let traversals = ["../", "..\\", "./../", "%2e%2e%2f"];
                let traversal = traversals[rng.gen_range(0..traversals.len())];

                if let Some(pos) = result.find('/') {
                    result.insert_str(pos + 1, traversal);
                } else {
                    result.insert_str(0, traversal);
                }

                result
            }
            4 => {
                // Duplicate path segments
                let mut result = value.clone();

                if let Some(pos) = result.find('/') {
                    let next_slash = result[pos+1..].find('/').map(|i| i + pos + 1);

                    if let Some(end) = next_slash {
                        let segment = &result[pos..=end];
                        result.insert_str(end, segment);
                    }
                }

                result
            }
            _ => unreachable!(),
        }
    }
}

/// Run a fuzzing campaign against a function
///
/// # Example
///
/// ```rust
/// let generator = StringGenerator::new(1, 100);
///
/// let results = fuzz(
///     |input: &String| -> Result<()> {
///         // Your function to test
///         validate_input(input)?;
///         Ok(())
///     },
///     generator,
///     FuzzConfig::default(),
/// ).await?;
///
/// println!("{}", results);
/// ```
pub async fn fuzz<F, T, G>(
    test_fn: F,
    generator: G,
    config: FuzzConfig,
) -> Result<FuzzingResults>
where
    F: Fn(&T) -> Result<()> + Send + Sync + 'static,
    T: Clone + Send + 'static,
    G: FuzzGenerator<T> + Send + Sync + 'static,
{
    // Initialize RNG
    let seed = config.seed.unwrap_or_else(|| rand::random());
    let mut rng = StdRng::seed_from_u64(seed);

    // Initialize counters
    let total_cases = Arc::new(AtomicUsize::new(0));
    let successful_cases = Arc::new(AtomicUsize::new(0));
    let failed_cases = Arc::new(AtomicUsize::new(0));

    // Keep track of failures
    let failing_seeds = Arc::new(tokio::sync::Mutex::new(HashSet::new()));
    let unique_failures = Arc::new(tokio::sync::Mutex::new(HashSet::new()));

    // Start time
    let start_time = Instant::now();

    // Clone for tasks
    let test_fn = Arc::new(test_fn);
    let generator = Arc::new(generator);

    // Create tasks
    let mut tasks = Vec::new();
    let stop_flag = Arc::new(AtomicUsize::new(0));

    for i in 0..config.iterations {
        // Check if we should stop
        if stop_flag.load(Ordering::SeqCst) > 0 {
            break;
        }

        // Check if we ran out of time
        if let Some(max_time) = config.max_time {
            if start_time.elapsed() > max_time {
                break;
            }
        }

        // Generate input from seed
        let case_seed = seed.wrapping_add(i as u64);
        let input = generator.generate_from_seed(case_seed);

        // Create task to run the test case
        let test_fn = test_fn.clone();
        let total_cases = total_cases.clone();
        let successful_cases = successful_cases.clone();
        let failed_cases = failed_cases.clone();
        let failing_seeds = failing_seeds.clone();
        let unique_failures = unique_failures.clone();
        let stop_flag = stop_flag.clone();
        let capture_panics = config.capture_panics;
        let stop_on_failure = config.stop_on_failure;
        let case_timeout = config.case_timeout;

        let task = tokio::spawn(async move {
            // Initialize timeout
            let timeout = tokio::time::timeout(case_timeout, async {
                let result = if capture_panics {
                    // Run with panic handling
                    match panic::catch_unwind(AssertUnwindSafe(|| {
                        test_fn(&input)
                    })) {
                        Ok(result) => match result {
                            Ok(_) => FuzzResult::Success,
                            Err(e) => FuzzResult::Error(e.to_string()),
                        },
                        Err(panic_msg) => {
                            let panic_msg = if let Some(msg) = panic_msg.downcast_ref::<String>() {
                                msg.clone()
                            } else if let Some(msg) = panic_msg.downcast_ref::<&str>() {
                                msg.to_string()
                            } else {
                                "Unknown panic".to_string()
                            };

                            FuzzResult::Panic(panic_msg)
                        }
                    }
                } else {
                    // Run without panic handling
                    match test_fn(&input) {
                        Ok(_) => FuzzResult::Success,
                        Err(e) => FuzzResult::Error(e.to_string()),
                    }
                };

                result
            });

            total_cases.fetch_add(1, Ordering::SeqCst);

            // Process result
            let result = match timeout.await {
                Ok(result) => result,
                Err(_) => FuzzResult::Timeout,
            };

            match result {
                FuzzResult::Success => {
                    successful_cases.fetch_add(1, Ordering::SeqCst);
                }
                FuzzResult::Panic(msg) | FuzzResult::Error(msg) | FuzzResult::Timeout => {
                    failed_cases.fetch_add(1, Ordering::SeqCst);

                    // Record failure
                    failing_seeds.lock().await.insert(case_seed);

                    // Record unique failure message
                    let msg = match result {
                        FuzzResult::Panic(ref msg) => format!("Panic: {}", msg),
                        FuzzResult::Error(ref msg) => format!("Error: {}", msg),
                        FuzzResult::Timeout => "Timeout".to_string(),
                        _ => unreachable!(),
                    };

                    unique_failures.lock().await.insert(msg);

                    // Stop if requested
                    if stop_on_failure {
                        stop_flag.store(1, Ordering::SeqCst);
                    }
                }
            }
        });

        tasks.push(task);
    }

    // Wait for tasks to complete
    for task in tasks {
        let _ = task.await;
    }

    // Collect results
    let failing_seeds = Arc::try_unwrap(failing_seeds)
        .unwrap_or_else(|_| panic!("Failed to unwrap failing_seeds"))
        .into_inner()
        .await;

    let unique_failures = Arc::try_unwrap(unique_failures)
        .unwrap_or_else(|_| panic!("Failed to unwrap unique_failures"))
        .into_inner()
        .await
        .into_iter()
        .collect();

    Ok(FuzzingResults {
        total_cases: total_cases.load(Ordering::SeqCst),
        successful_cases: successful_cases.load(Ordering::SeqCst),
        failed_cases: failed_cases.load(Ordering::SeqCst),
        failing_seeds,
        unique_failures,
        duration: start_time.elapsed(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_string_generator() {
        let gen = StringGenerator::new(5, 10);
        let mut rng = StdRng::seed_from_u64(42);

        // Generate several strings
        for _ in 0..10 {
            let s = gen.generate(&mut rng);

            // Verify constraints
            assert!(s.len() >= 5, "String too short: {}", s);
            assert!(s.len() <= 10, "String too long: {}", s);
        }

        // Test mutation
        let original = "Hello123".to_string();
        let mutated = gen.mutate(&original, &mut rng);

        // Mutations should respect length constraints
        assert!(mutated.len() >= 5, "Mutated string too short: {}", mutated);
        assert!(mutated.len() <= 10, "Mutated string too long: {}", mutated);
    }

    #[test]
    fn test_http_path_generator() {
        let gen = HttpPathGenerator::new();
        let mut rng = StdRng::seed_from_u64(42);

        // Generate several paths
        for _ in 0..10 {
            let path = gen.generate(&mut rng);

            // Verify constraints
            assert!(path.starts_with('/'), "Path should start with /: {}", path);
        }

        // Test mutation
        let original = "/api/users/123".to_string();
        let mutated = gen.mutate(&original, &mut rng);

        // Mutation should produce a valid-looking path
        assert!(!mutated.is_empty(), "Mutated path is empty");
    }

    #[tokio::test]
    async fn test_fuzz_success() {
        // Function that always succeeds
        let test_fn = |_s: &String| -> Result<()> { Ok(()) };

        // Run fuzzer
        let generator = StringGenerator::new(1, 10);
        let config = FuzzConfig {
            iterations: 100,
            min_time: Some(Duration::from_millis(100)),
            ..Default::default()
        };

        let results = fuzz(test_fn, generator, config).await.unwrap();

        // All cases should succeed
        assert_eq!(results.successful_cases, results.total_cases);
        assert_eq!(results.failed_cases, 0);
        assert!(results.unique_failures.is_empty());
    }

    #[tokio::test]
    async fn test_fuzz_failure() {
        // Function that fails on strings with '!'
        let test_fn = |s: &String| -> Result<()> {
            if s.contains('!') {
                bail!("String contains !");
            }
            Ok(())
        };

        // Custom generator that guarantees some failures
        struct FailGen;

        impl FuzzGenerator<String> for FailGen {
            fn generate(&self, rng: &mut StdRng) -> String {
                // Make 25% of strings contain !
                if rng.gen_bool(0.25) {
                    "test!string".to_string()
                } else {
                    "teststring".to_string()
                }
            }

            fn mutate(&self, _value: &String, rng: &mut StdRng) -> String {
                self.generate(rng)
            }
        }

        // Run fuzzer
        let config = FuzzConfig {
            iterations: 100,
            min_time: Some(Duration::from_millis(100)),
            ..Default::default()
        };

        let results = fuzz(test_fn, FailGen, config).await.unwrap();

        // Should have some failures
        assert!(results.failed_cases > 0);
        assert_eq!(results.unique_failures.len(), 1);
        assert_eq!(results.total_cases, results.successful_cases + results.failed_cases);
    }

    #[tokio::test]
    async fn test_fuzz_panic() {
        // Function that panics on strings with '!'
        let test_fn = |s: &String| -> Result<()> {
            if s.contains('!') {
                panic!("String contains !");
            }
            Ok(())
        };

        // Custom generator that guarantees some failures
        struct FailGen;

        impl FuzzGenerator<String> for FailGen {
            fn generate(&self, rng: &mut StdRng) -> String {
                // Make 25% of strings contain !
                if rng.gen_bool(0.25) {
                    "test!string".to_string()
                } else {
                    "teststring".to_string()
                }
            }

            fn mutate(&self, _value: &String, rng: &mut StdRng) -> String {
                self.generate(rng)
            }
        }

        // Run fuzzer
        let config = FuzzConfig {
            iterations: 100,
            min_time: Some(Duration::from_millis(100)),
            capture_panics: true,
            ..Default::default()
        };

        let results = fuzz(test_fn, FailGen, config).await.unwrap();

        // Should have some failures
        assert!(results.failed_cases > 0);
        assert_eq!(results.unique_failures.len(), 1);

        // Failure should be a panic
        let failure = results.unique_failures.first().unwrap();
        assert!(failure.starts_with("Panic:"));
    }
}
