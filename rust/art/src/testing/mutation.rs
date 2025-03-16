// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Mutation testing framework for Art
//!
//! This module provides capabilities for mutation testing to evaluate the
//! effectiveness of a test suite by introducing artificial bugs (mutations)
//! and checking if the tests catch them.

use crate::prelude::*;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::marker::PhantomData;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Result of a mutation test
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MutationResult {
    /// The mutation was killed (detected by tests)
    Killed,

    /// The mutation survived (not detected by tests)
    Survived,

    /// The mutation caused an error during test execution
    Error(String),

    /// The mutation was skipped for some reason
    Skipped(String),
}

impl fmt::Display for MutationResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MutationResult::Killed => write!(f, "Killed"),
            MutationResult::Survived => write!(f, "Survived"),
            MutationResult::Error(msg) => write!(f, "Error: {}", msg),
            MutationResult::Skipped(msg) => write!(f, "Skipped: {}", msg),
        }
    }
}

/// A single mutation operation
#[derive(Debug, Clone)]
pub struct Mutation<T> {
    /// Unique identifier for this mutation
    pub id: String,

    /// Description of what this mutation does
    pub description: String,

    /// Original value
    pub original: T,

    /// Mutated value
    pub mutated: T,

    /// Result of applying this mutation
    pub result: Option<MutationResult>,

    /// Duration of the test with this mutation
    pub duration: Option<Duration>,
}

/// Results of a mutation testing campaign
#[derive(Debug, Clone)]
pub struct MutationResults {
    /// Total number of mutations applied
    pub total_mutations: usize,

    /// Number of mutations killed (detected by tests)
    pub killed: usize,

    /// Number of mutations survived (not detected by tests)
    pub survived: usize,

    /// Number of mutations that caused errors
    pub errors: usize,

    /// Number of mutations that were skipped
    pub skipped: usize,

    /// Mutation score (killed / (killed + survived))
    pub score: f64,

    /// Total duration of the mutation testing
    pub duration: Duration,

    /// Mutations grouped by result
    pub mutations_by_result: HashMap<MutationResult, Vec<String>>,
}

impl fmt::Display for MutationResults {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "Mutation Testing Results:")?;
        writeln!(f, "Total mutations:  {}", self.total_mutations)?;
        writeln!(f, "Killed:           {} ({:.1}%)", self.killed, (self.killed as f64 / self.total_mutations as f64) * 100.0)?;
        writeln!(f, "Survived:         {} ({:.1}%)", self.survived, (self.survived as f64 / self.total_mutations as f64) * 100.0)?;
        writeln!(f, "Errors:           {} ({:.1}%)", self.errors, (self.errors as f64 / self.total_mutations as f64) * 100.0)?;
        writeln!(f, "Skipped:          {} ({:.1}%)", self.skipped, (self.skipped as f64 / self.total_mutations as f64) * 100.0)?;
        writeln!(f, "Mutation score:   {:.1}%", self.score * 100.0)?;
        writeln!(f, "Duration:         {:?}", self.duration)?;

        if !self.mutations_by_result.is_empty() {
            // Show the survived mutations first as they are the most interesting
            if let Some(survived) = self.mutations_by_result.get(&MutationResult::Survived) {
                if !survived.is_empty() {
                    writeln!(f, "\nSurvived mutations:")?;
                    for (i, desc) in survived.iter().enumerate() {
                        writeln!(f, "{}. {}", i + 1, desc)?;
                    }
                }
            }

            // Then show errors
            let error_key = MutationResult::Error(String::new());
            if let Some(errors) = self.mutations_by_result.iter().find_map(|(k, v)| {
                if matches!(k, MutationResult::Error(_)) { Some(v) } else { None }
            }) {
                if !errors.is_empty() {
                    writeln!(f, "\nMutations that caused errors:")?;
                    for (i, desc) in errors.iter().enumerate() {
                        writeln!(f, "{}. {}", i + 1, desc)?;
                    }
                }
            }
        }

        Ok(())
    }
}

/// A mutator that can generate mutations for a specific type
pub trait Mutator<T> {
    /// Generate a set of mutations for the given value
    fn generate_mutations(&self, original: T) -> Vec<Mutation<T>>;
}

/// Configuration for a mutation testing run
#[derive(Debug, Clone)]
pub struct MutationConfig {
    /// Maximum number of mutations to apply
    pub max_mutations: usize,

    /// Maximum time to run mutation testing
    pub max_time: Option<Duration>,

    /// Timeout for each test run
    pub test_timeout: Duration,

    /// Whether to run tests in parallel
    pub parallel: bool,

    /// Number of threads for parallel execution
    pub threads: usize,

    /// Filter for mutation IDs to include
    pub include_mutations: Option<Vec<String>>,

    /// Filter for mutation IDs to exclude
    pub exclude_mutations: Option<Vec<String>>,
}

impl Default for MutationConfig {
    fn default() -> Self {
        Self {
            max_mutations: 100,
            max_time: Some(Duration::from_secs(3600)), // 1 hour
            test_timeout: Duration::from_secs(60),
            parallel: true,
            threads: num_cpus::get(),
            include_mutations: None,
            exclude_mutations: None,
        }
    }
}

/// Run mutation tests to evaluate the effectiveness of a test suite
///
/// # Example
///
/// ```rust
/// // Create a numeric mutator
/// let mutator = NumericMutator::new();
///
/// // Run mutation testing
/// let results = run_mutation_tests(
///     // Original value to mutate
///     42,
///     // Mutator to generate mutations
///     mutator,
///     // Test function that should fail for mutations
///     |value| {
///         assert_eq!(value, 42);
///         Ok(())
///     },
///     MutationConfig::default(),
/// ).await?;
///
/// println!("{}", results);
/// ```
pub async fn run_mutation_tests<T, M, F>(
    original: T,
    mutator: M,
    test_fn: F,
    config: MutationConfig,
) -> Result<MutationResults>
where
    T: Clone + Send + Sync + 'static,
    M: Mutator<T> + Send + Sync + 'static,
    F: Fn(&T) -> Result<()> + Send + Sync + 'static,
{
    // Generate mutations
    let mut mutations = mutator.generate_mutations(original);

    // Apply filters if specified
    if let Some(include) = &config.include_mutations {
        let include_set: HashSet<&String> = include.iter().collect();
        mutations.retain(|m| include_set.contains(&m.id));
    }

    if let Some(exclude) = &config.exclude_mutations {
        let exclude_set: HashSet<&String> = exclude.iter().collect();
        mutations.retain(|m| !exclude_set.contains(&m.id));
    }

    // Limit the number of mutations if necessary
    if mutations.len() > config.max_mutations {
        mutations.truncate(config.max_mutations);
    }

    // Create shared results
    let mutations = Arc::new(Mutex::new(mutations));
    let test_fn = Arc::new(test_fn);

    // Start time
    let start_time = Instant::now();

    // Run tests
    if config.parallel {
        // Create a thread pool
        let pool = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(config.threads)
            .build()?;

        // Create tasks
        let mut handles = Vec::new();

        for _ in 0..config.threads {
            let mutations = mutations.clone();
            let test_fn = test_fn.clone();
            let test_timeout = config.test_timeout;

            let handle = pool.spawn(async move {
                loop {
                    // Get the next mutation
                    let mutation = {
                        let mut mutations = mutations.lock().unwrap();

                        // Find a mutation without a result
                        let index = mutations.iter().position(|m| m.result.is_none());

                        if let Some(index) = index {
                            // Clone the mutation
                            let mut mutation = mutations[index].clone();

                            // Mark as in progress
                            mutations[index].result = Some(MutationResult::Skipped("In progress".to_string()));

                            Some(mutation)
                        } else {
                            None
                        }
                    };

                    if let Some(mut mutation) = mutation {
                        // Run the test with a timeout
                        let start = Instant::now();

                        // Run the test
                        let result = match tokio::time::timeout(test_timeout, async {
                            match test_fn(&mutation.mutated) {
                                Ok(_) => MutationResult::Survived,
                                Err(_) => MutationResult::Killed,
                            }
                        }).await {
                            Ok(result) => result,
                            Err(_) => MutationResult::Error("Test timed out".to_string()),
                        };

                        // Record the result
                        mutation.result = Some(result);
                        mutation.duration = Some(start.elapsed());

                        // Update the mutation in the list
                        let mut mutations = mutations.lock().unwrap();
                        let index = mutations.iter().position(|m| m.id == mutation.id);

                        if let Some(index) = index {
                            mutations[index] = mutation;
                        }
                    } else {
                        // No more mutations to process
                        break;
                    }
                }
            });

            handles.push(handle);
        }

        // Wait for all tasks to complete
        for handle in handles {
            let _ = handle.await;
        }
    } else {
        // Run mutations sequentially
        let mut mutations_guard = mutations.lock().unwrap();

        for mutation in mutations_guard.iter_mut() {
            // Check if we've run out of time
            if let Some(max_time) = config.max_time {
                if start_time.elapsed() > max_time {
                    mutation.result = Some(MutationResult::Skipped("Timeout".to_string()));
                    continue;
                }
            }

            // Run the test with a timeout
            let start = Instant::now();

            let result = match tokio::time::timeout(config.test_timeout, async {
                match test_fn(&mutation.mutated) {
                    Ok(_) => MutationResult::Survived,
                    Err(_) => MutationResult::Killed,
                }
            }).await {
                Ok(result) => result,
                Err(_) => MutationResult::Error("Test timed out".to_string()),
            };

            // Record the result
            mutation.result = Some(result);
            mutation.duration = Some(start.elapsed());
        }
    }

    // Compile results
    let mutations = Arc::try_unwrap(mutations).unwrap().into_inner().unwrap();

    let mut killed = 0;
    let mut survived = 0;
    let mut errors = 0;
    let mut skipped = 0;
    let mut mutations_by_result: HashMap<MutationResult, Vec<String>> = HashMap::new();

    for mutation in &mutations {
        if let Some(result) = &mutation.result {
            match result {
                MutationResult::Killed => {
                    killed += 1;
                    mutations_by_result.entry(MutationResult::Killed).or_default().push(mutation.description.clone());
                }
                MutationResult::Survived => {
                    survived += 1;
                    mutations_by_result.entry(MutationResult::Survived).or_default().push(mutation.description.clone());
                }
                MutationResult::Error(_) => {
                    errors += 1;
                    mutations_by_result.entry(MutationResult::Error(String::new())).or_default().push(mutation.description.clone());
                }
                MutationResult::Skipped(_) => {
                    skipped += 1;
                    mutations_by_result.entry(MutationResult::Skipped(String::new())).or_default().push(mutation.description.clone());
                }
            }
        } else {
            skipped += 1;
            mutations_by_result.entry(MutationResult::Skipped(String::new())).or_default().push(mutation.description.clone());
        }
    }

    let score = if killed + survived > 0 {
        killed as f64 / (killed + survived) as f64
    } else {
        0.0
    };

    Ok(MutationResults {
        total_mutations: mutations.len(),
        killed,
        survived,
        errors,
        skipped,
        score,
        duration: start_time.elapsed(),
        mutations_by_result,
    })
}

/// A mutator for boolean values
#[derive(Debug, Clone)]
pub struct BooleanMutator;

impl Mutator<bool> for BooleanMutator {
    fn generate_mutations(&self, original: bool) -> Vec<Mutation<bool>> {
        vec![
            Mutation {
                id: "bool-negate".to_string(),
                description: format!("Negate boolean value: {} -> {}", original, !original),
                original,
                mutated: !original,
                result: None,
                duration: None,
            },
        ]
    }
}

/// A mutator for numeric values
#[derive(Debug, Clone)]
pub struct NumericMutator<T> {
    _phantom: PhantomData<T>,
}

impl<T> NumericMutator<T> {
    pub fn new() -> Self {
        Self {
            _phantom: PhantomData,
        }
    }
}

impl<T> Default for NumericMutator<T> {
    fn default() -> Self {
        Self::new()
    }
}

macro_rules! impl_numeric_mutator {
    ($type:ty, $zero:expr, $one:expr) => {
        impl Mutator<$type> for NumericMutator<$type> {
            fn generate_mutations(&self, original: $type) -> Vec<Mutation<$type>> {
                let mut mutations = Vec::new();

                // Increment by 1
                mutations.push(Mutation {
                    id: format!("{}-increment", stringify!($type)),
                    description: format!("Increment {} by 1: {} -> {}", stringify!($type), original, original.saturating_add($one)),
                    original,
                    mutated: original.saturating_add($one),
                    result: None,
                    duration: None,
                });

                // Decrement by 1
                mutations.push(Mutation {
                    id: format!("{}-decrement", stringify!($type)),
                    description: format!("Decrement {} by 1: {} -> {}", stringify!($type), original, original.saturating_sub($one)),
                    original,
                    mutated: original.saturating_sub($one),
                    result: None,
                    duration: None,
                });

                // Set to 0
                if original != $zero {
                    mutations.push(Mutation {
                        id: format!("{}-zero", stringify!($type)),
                        description: format!("Set {} to zero: {} -> {}", stringify!($type), original, $zero),
                        original,
                        mutated: $zero,
                        result: None,
                        duration: None,
                    });
                }

                // Negate
                if original != $zero {
                    mutations.push(Mutation {
                        id: format!("{}-negate", stringify!($type)),
                        description: format!("Negate {}: {} -> {}", stringify!($type), original, -original),
                        original,
                        mutated: -original,
                        result: None,
                        duration: None,
                    });
                }

                // Max value
                let max_value = <$type>::MAX;
                if original != max_value {
                    mutations.push(Mutation {
                        id: format!("{}-max", stringify!($type)),
                        description: format!("Set {} to max value: {} -> {}", stringify!($type), original, max_value),
                        original,
                        mutated: max_value,
                        result: None,
                        duration: None,
                    });
                }

                // Min value
                let min_value = <$type>::MIN;
                if original != min_value {
                    mutations.push(Mutation {
                        id: format!("{}-min", stringify!($type)),
                        description: format!("Set {} to min value: {} -> {}", stringify!($type), original, min_value),
                        original,
                        mutated: min_value,
                        result: None,
                        duration: None,
                    });
                }

                mutations
            }
        }
    };
}

impl_numeric_mutator!(i8, 0, 1);
impl_numeric_mutator!(i16, 0, 1);
impl_numeric_mutator!(i32, 0, 1);
impl_numeric_mutator!(i64, 0, 1);
impl_numeric_mutator!(isize, 0, 1);
impl_numeric_mutator!(u8, 0, 1);
impl_numeric_mutator!(u16, 0, 1);
impl_numeric_mutator!(u32, 0, 1);
impl_numeric_mutator!(u64, 0, 1);
impl_numeric_mutator!(usize, 0, 1);

/// A mutator for string values
#[derive(Debug, Clone)]
pub struct StringMutator;

impl Mutator<String> for StringMutator {
    fn generate_mutations(&self, original: String) -> Vec<Mutation<String>> {
        let mut mutations = Vec::new();

        // Empty string
        if !original.is_empty() {
            mutations.push(Mutation {
                id: "string-empty".to_string(),
                description: format!("Replace string with empty string: \"{}\" -> \"\"", original),
                original: original.clone(),
                mutated: String::new(),
                result: None,
                duration: None,
            });
        }

        // Remove first character
        if original.len() > 1 {
            let mutated = original.chars().skip(1).collect();
            mutations.push(Mutation {
                id: "string-remove-first".to_string(),
                description: format!("Remove first character: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Remove last character
        if original.len() > 1 {
            let mutated = original.chars().take(original.len() - 1).collect();
            mutations.push(Mutation {
                id: "string-remove-last".to_string(),
                description: format!("Remove last character: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Uppercase
        if original.to_uppercase() != original {
            let mutated = original.to_uppercase();
            mutations.push(Mutation {
                id: "string-uppercase".to_string(),
                description: format!("Convert to uppercase: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Lowercase
        if original.to_lowercase() != original {
            let mutated = original.to_lowercase();
            mutations.push(Mutation {
                id: "string-lowercase".to_string(),
                description: format!("Convert to lowercase: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Reverse
        if original.len() > 1 {
            let mutated = original.chars().rev().collect();
            mutations.push(Mutation {
                id: "string-reverse".to_string(),
                description: format!("Reverse string: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Replace spaces with underscores
        if original.contains(' ') {
            let mutated = original.replace(' ', "_");
            mutations.push(Mutation {
                id: "string-spaces-to-underscores".to_string(),
                description: format!("Replace spaces with underscores: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Replace underscores with spaces
        if original.contains('_') {
            let mutated = original.replace('_', " ");
            mutations.push(Mutation {
                id: "string-underscores-to-spaces".to_string(),
                description: format!("Replace underscores with spaces: \"{}\" -> \"{}\"", original, mutated),
                original: original.clone(),
                mutated,
                result: None,
                duration: None,
            });
        }

        // Add common SQL injection string
        let sql_injection = original.clone() + "' OR '1'='1";
        mutations.push(Mutation {
            id: "string-sql-injection".to_string(),
            description: format!("Add SQL injection: \"{}\" -> \"{}\"", original, sql_injection),
            original: original.clone(),
            mutated: sql_injection,
            result: None,
            duration: None,
        });

        // Add common XSS string
        let xss = original.clone() + "<script>alert(1)</script>";
        mutations.push(Mutation {
            id: "string-xss".to_string(),
            description: format!("Add XSS injection: \"{}\" -> \"{}\"", original, xss),
            original: original.clone(),
            mutated: xss,
            result: None,
            duration: None,
        });

        // Add null byte
        let null_byte = original.clone() + "\0extra";
        mutations.push(Mutation {
            id: "string-null-byte".to_string(),
            description: format!("Add null byte: \"{}\" -> \"{}\\0extra\"", original, original),
            original: original.clone(),
            mutated: null_byte,
            result: None,
            duration: None,
        });

        mutations
    }
}

/// A mutator for Option values
pub struct OptionMutator<T, M> {
    inner_mutator: M,
    _phantom: PhantomData<T>,
}

impl<T, M> OptionMutator<T, M>
where
    M: Mutator<T>,
{
    pub fn new(inner_mutator: M) -> Self {
        Self {
            inner_mutator,
            _phantom: PhantomData,
        }
    }
}

impl<T, M> Mutator<Option<T>> for OptionMutator<T, M>
where
    T: Clone,
    M: Mutator<T>,
{
    fn generate_mutations(&self, original: Option<T>) -> Vec<Mutation<Option<T>>> {
        let mut mutations = Vec::new();

        match original {
            Some(ref value) => {
                // Convert Some to None
                mutations.push(Mutation {
                    id: "option-to-none".to_string(),
                    description: format!("Convert Some to None"),
                    original: original.clone(),
                    mutated: None,
                    result: None,
                    duration: None,
                });

                // Mutate inner value
                for inner_mutation in self.inner_mutator.generate_mutations(value.clone()) {
                    mutations.push(Mutation {
                        id: format!("option-inner-{}", inner_mutation.id),
                        description: format!("Mutate inner value: {}", inner_mutation.description),
                        original: original.clone(),
                        mutated: Some(inner_mutation.mutated),
                        result: None,
                        duration: None,
                    });
                }
            }
            None => {
                // Cannot create a Some without a default value
                // This would require a default instance of T
            }
        }

        mutations
    }
}

/// A mutator for Result values
pub struct ResultMutator<T, E, TM, EM> {
    ok_mutator: TM,
    err_mutator: EM,
    _phantom: PhantomData<(T, E)>,
}

impl<T, E, TM, EM> ResultMutator<T, E, TM, EM>
where
    TM: Mutator<T>,
    EM: Mutator<E>,
{
    pub fn new(ok_mutator: TM, err_mutator: EM) -> Self {
        Self {
            ok_mutator,
            err_mutator,
            _phantom: PhantomData,
        }
    }
}

impl<T, E, TM, EM> Mutator<Result<T, E>> for ResultMutator<T, E, TM, EM>
where
    T: Clone,
    E: Clone,
    TM: Mutator<T>,
    EM: Mutator<E>,
{
    fn generate_mutations(&self, original: Result<T, E>) -> Vec<Mutation<Result<T, E>>> {
        let mut mutations = Vec::new();

        match original {
            Ok(ref value) => {
                // Mutate inner Ok value
                for inner_mutation in self.ok_mutator.generate_mutations(value.clone()) {
                    mutations.push(Mutation {
                        id: format!("result-ok-{}", inner_mutation.id),
                        description: format!("Mutate Ok value: {}", inner_mutation.description),
                        original: original.clone(),
                        mutated: Ok(inner_mutation.mutated),
                        result: None,
                        duration: None,
                    });
                }

                // Cannot convert Ok to Err without a default error value
            }
            Err(ref error) => {
                // Mutate inner Err value
                for inner_mutation in self.err_mutator.generate_mutations(error.clone()) {
                    mutations.push(Mutation {
                        id: format!("result-err-{}", inner_mutation.id),
                        description: format!("Mutate Err value: {}", inner_mutation.description),
                        original: original.clone(),
                        mutated: Err(inner_mutation.mutated),
                        result: None,
                        duration: None,
                    });
                }

                // Cannot convert Err to Ok without a default success value
            }
        }

        mutations
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_boolean_mutator() {
        let mutator = BooleanMutator;

        // Test with true
        let mutations = mutator.generate_mutations(true);
        assert_eq!(mutations.len(), 1);
        assert_eq!(mutations[0].original, true);
        assert_eq!(mutations[0].mutated, false);

        // Test with false
        let mutations = mutator.generate_mutations(false);
        assert_eq!(mutations.len(), 1);
        assert_eq!(mutations[0].original, false);
        assert_eq!(mutations[0].mutated, true);
    }

    #[test]
    fn test_numeric_mutator() {
        let mutator = NumericMutator::<i32>::new();

        // Test with positive number
        let mutations = mutator.generate_mutations(42);

        // Should have mutations for:
        // - Increment by 1
        // - Decrement by 1
        // - Set to 0
        // - Negate
        // - Max value
        // - Min value
        assert_eq!(mutations.len(), 6);

        // Check that mutations are as expected
        assert!(mutations.iter().any(|m| m.mutated == 43)); // increment
        assert!(mutations.iter().any(|m| m.mutated == 41)); // decrement
        assert!(mutations.iter().any(|m| m.mutated == 0)); // zero
        assert!(mutations.iter().any(|m| m.mutated == -42)); // negate
        assert!(mutations.iter().any(|m| m.mutated == i32::MAX)); // max
        assert!(mutations.iter().any(|m| m.mutated == i32::MIN)); // min

        // Test with zero
        let mutations = mutator.generate_mutations(0);

        // Should have mutations for:
        // - Increment by 1
        // - Decrement by 1
        // - Max value
        // - Min value
        // (not negate or set to zero since it's already zero)
        assert_eq!(mutations.len(), 4);

        // Check that mutations are as expected
        assert!(mutations.iter().any(|m| m.mutated == 1)); // increment
        assert!(mutations.iter().any(|m| m.mutated == -1)); // decrement
        assert!(mutations.iter().any(|m| m.mutated == i32::MAX)); // max
        assert!(mutations.iter().any(|m| m.mutated == i32::MIN)); // min
    }

    #[test]
    fn test_string_mutator() {
        let mutator = StringMutator;

        // Test with normal string
        let mutations = mutator.generate_mutations("Hello World".to_string());

        // Should have mutations for:
        // - Empty string
        // - Remove first char
        // - Remove last char
        // - Uppercase
        // - Lowercase
        // - Reverse
        // - Replace spaces with underscores
        // - SQL injection
        // - XSS
        // - Null byte
        assert_eq!(mutations.len(), 10);

        // Check that mutations are as expected
        assert!(mutations.iter().any(|m| m.mutated == ""));
        assert!(mutations.iter().any(|m| m.mutated == "ello World"));
        assert!(mutations.iter().any(|m| m.mutated == "Hello Worl"));
        assert!(mutations.iter().any(|m| m.mutated == "HELLO WORLD"));
        assert!(mutations.iter().any(|m| m.mutated == "hello world"));
        assert!(mutations.iter().any(|m| m.mutated == "dlroW olleH"));
        assert!(mutations.iter().any(|m| m.mutated == "Hello_World"));
    }

    #[tokio::test]
    async fn test_mutation_testing() {
        // Create a simple function that checks if a number is positive
        let test_fn = |n: &i32| -> Result<()> {
            if *n > 0 {
                Ok(())
            } else {
                bail!("Number is not positive")
            }
        };

        // Create a mutator
        let mutator = NumericMutator::<i32>::new();

        // Run mutation testing on a positive number (42)
        let config = MutationConfig {
            max_mutations: 10,
            max_time: Some(Duration::from_secs(5)),
            test_timeout: Duration::from_secs(1),
            parallel: false,
            ..Default::default()
        };

        let results = run_mutation_tests(42, mutator, test_fn, config).await.unwrap();

        // We expect mutations that make the number non-positive to be killed
        // and mutations that keep it positive to survive
        println!("{}", results);

        // Check results
        assert!(results.killed > 0, "Should have killed some mutations");
        assert!(results.survived > 0, "Should have survived some mutations");

        // Ensure mutations that should be killed were killed
        let survived_mutations = results.mutations_by_result.get(&MutationResult::Survived).unwrap();
        for desc in survived_mutations {
            // Any survived mutation should not make the number non-positive
            assert!(!desc.contains("zero") && !desc.contains("negate") && !desc.contains("min"),
                "Mutation '{}' should have been killed", desc);
        }

        // Ensure mutations that should survive were not killed
        let killed_mutations = results.mutations_by_result.get(&MutationResult::Killed).unwrap();
        for desc in killed_mutations {
            // Any killed mutation should make the number non-positive
            assert!(desc.contains("zero") || desc.contains("negate") || desc.contains("min"),
                "Mutation '{}' should have survived", desc);
        }
    }
}
