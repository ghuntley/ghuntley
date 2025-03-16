// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

//! Benchmarking framework for Art
//!
//! This module provides benchmarking capabilities for measuring performance.

use crate::prelude::*;
use std::time::{Duration, Instant};
use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::future::Future;
use tokio::sync::Mutex;
use tokio::task;
use std::pin::Pin;
use futures::future::BoxFuture;

/// Result of a benchmark run
#[derive(Debug, Clone)]
pub struct BenchmarkResult {
    /// Name of the benchmark
    pub name: String,

    /// Number of iterations run
    pub iterations: usize,

    /// Average time per iteration in microseconds
    pub avg_time_us: f64,

    /// Minimum time observed in microseconds
    pub min_time_us: f64,

    /// Maximum time observed in microseconds
    pub max_time_us: f64,

    /// Standard deviation of times in microseconds
    pub std_dev_us: f64,

    /// 95th percentile time in microseconds
    pub p95_time_us: f64,

    /// Throughput in operations per second
    pub throughput: f64,
}

impl fmt::Display for BenchmarkResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "Benchmark: {}", self.name)?;
        writeln!(f, "  Iterations: {}", self.iterations)?;
        writeln!(f, "  Average:    {:.3} μs", self.avg_time_us)?;
        writeln!(f, "  Min:        {:.3} μs", self.min_time_us)?;
        writeln!(f, "  Max:        {:.3} μs", self.max_time_us)?;
        writeln!(f, "  Std Dev:    {:.3} μs", self.std_dev_us)?;
        writeln!(f, "  P95:        {:.3} μs", self.p95_time_us)?;
        writeln!(f, "  Throughput: {:.2} ops/sec", self.throughput)?;
        Ok(())
    }
}

/// Configuration for benchmark runs
#[derive(Debug, Clone)]
pub struct BenchmarkConfig {
    /// Minimum number of iterations to run
    pub min_iterations: usize,

    /// Maximum number of iterations to run
    pub max_iterations: usize,

    /// Minimum time to run the benchmark for
    pub min_time: Duration,

    /// Number of warmup iterations to run
    pub warmup_iterations: usize,

    /// Maximum time for a single iteration
    pub max_iteration_time: Duration,

    /// Whether to run the benchmarks in parallel
    pub parallel: bool,

    /// Number of samples to collect
    pub sample_size: usize,
}

impl Default for BenchmarkConfig {
    fn default() -> Self {
        Self {
            min_iterations: 100,
            max_iterations: 10_000,
            min_time: Duration::from_secs(1),
            warmup_iterations: 10,
            max_iteration_time: Duration::from_secs(5),
            parallel: false,
            sample_size: 100,
        }
    }
}

/// Runs a benchmark and collects performance metrics
pub async fn benchmark<F, Fut>(
    name: &str,
    f: F,
    config: BenchmarkConfig,
) -> Result<BenchmarkResult>
where
    F: Fn() -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<()>> + Send + 'static,
{
    // Run warmup iterations
    for _ in 0..config.warmup_iterations {
        let _ = f().await?;
    }

    // Prepare for benchmark
    let mut times = Vec::with_capacity(config.sample_size);
    let start_time = Instant::now();
    let iterations = Arc::new(AtomicUsize::new(0));

    if config.parallel {
        // Parallel benchmark
        let tasks = (0..config.sample_size)
            .map(|_| {
                let f = Arc::new(f);
                let iterations = iterations.clone();
                task::spawn(async move {
                    let start = Instant::now();
                    let _ = f().await?;
                    let elapsed = start.elapsed();
                    iterations.fetch_add(1, Ordering::SeqCst);
                    Ok::<_, Error>(elapsed)
                })
            })
            .collect::<Vec<_>>();

        for task in tasks {
            let elapsed = task.await??;
            times.push(elapsed.as_secs_f64() * 1_000_000.0); // Convert to microseconds
        }
    } else {
        // Sequential benchmark
        let mut i = 0;
        let sample_interval = (config.max_iterations - config.min_iterations) / config.sample_size;

        while (i < config.max_iterations) &&
              (i < config.min_iterations || start_time.elapsed() < config.min_time) {
            // Only record samples at regular intervals
            let record_sample = i >= config.min_iterations &&
                               (i - config.min_iterations) % sample_interval == 0 &&
                               times.len() < config.sample_size;

            let start = Instant::now();
            let _ = f().await?;
            let elapsed = start.elapsed();

            if record_sample {
                times.push(elapsed.as_secs_f64() * 1_000_000.0); // Convert to microseconds
            }

            i += 1;
            iterations.fetch_add(1, Ordering::SeqCst);

            // Safety check to avoid infinite loops
            if elapsed > config.max_iteration_time {
                bail!("Benchmark iteration took too long: {:?}", elapsed);
            }
        }

        // If we didn't collect enough samples, collect the remainder
        while times.len() < config.sample_size && i < config.max_iterations {
            let start = Instant::now();
            let _ = f().await?;
            let elapsed = start.elapsed();
            times.push(elapsed.as_secs_f64() * 1_000_000.0);
            i += 1;
            iterations.fetch_add(1, Ordering::SeqCst);
        }
    }

    // Calculate statistics
    let total_iterations = iterations.load(Ordering::SeqCst);
    let total_time = start_time.elapsed();

    // Sort times for percentile calculation
    times.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let avg_time_us = times.iter().sum::<f64>() / times.len() as f64;
    let min_time_us = *times.first().unwrap_or(&0.0);
    let max_time_us = *times.last().unwrap_or(&0.0);

    // Calculate standard deviation
    let variance = times.iter()
        .map(|&t| (t - avg_time_us).powi(2))
        .sum::<f64>() / times.len() as f64;
    let std_dev_us = variance.sqrt();

    // Calculate 95th percentile
    let p95_idx = (0.95 * times.len() as f64).floor() as usize;
    let p95_time_us = times.get(p95_idx).copied().unwrap_or(0.0);

    // Calculate throughput (ops/sec)
    let throughput = if total_time.as_secs_f64() > 0.0 {
        total_iterations as f64 / total_time.as_secs_f64()
    } else {
        0.0
    };

    Ok(BenchmarkResult {
        name: name.to_string(),
        iterations: total_iterations,
        avg_time_us,
        min_time_us,
        max_time_us,
        std_dev_us,
        p95_time_us,
        throughput,
    })
}

/// A suite of benchmarks
pub struct BenchmarkSuite {
    /// Name of the benchmark suite
    name: String,

    /// Benchmarks to run
    benchmarks: Vec<Box<dyn BenchmarkFn>>,

    /// Configuration for the benchmarks
    config: BenchmarkConfig,
}

/// Trait for benchmark functions
pub trait BenchmarkFn: Send + Sync {
    /// Name of the benchmark
    fn name(&self) -> &str;

    /// Run the benchmark
    fn run<'a>(&'a self, config: BenchmarkConfig) -> BoxFuture<'a, Result<BenchmarkResult>>;
}

impl BenchmarkSuite {
    /// Create a new benchmark suite
    pub fn new(name: &str, config: BenchmarkConfig) -> Self {
        Self {
            name: name.to_string(),
            benchmarks: Vec::new(),
            config,
        }
    }

    /// Add a benchmark to the suite
    pub fn add_benchmark<F, Fut>(&mut self, name: &str, f: F)
    where
        F: Fn() -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<()>> + Send + 'static,
    {
        self.benchmarks.push(Box::new(SimpleBenchmark::new(name, f)));
    }

    /// Run all benchmarks in the suite
    pub async fn run(&self) -> Result<Vec<BenchmarkResult>> {
        let mut results = Vec::new();

        info!("Running benchmark suite: {}", self.name);

        for benchmark in &self.benchmarks {
            info!("Running benchmark: {}", benchmark.name());
            match benchmark.run(self.config.clone()).await {
                Ok(result) => {
                    info!("{}", result);
                    results.push(result);
                }
                Err(e) => {
                    error!("Benchmark '{}' failed: {}", benchmark.name(), e);
                }
            }
        }

        Ok(results)
    }
}

/// A simple benchmark implementation
struct SimpleBenchmark<F, Fut> {
    /// Name of the benchmark
    name: String,

    /// Benchmark function
    func: Arc<F>,

    /// Phantom data for the future type
    _phantom: std::marker::PhantomData<Fut>,
}

impl<F, Fut> SimpleBenchmark<F, Fut>
where
    F: Fn() -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<()>> + Send + 'static,
{
    /// Create a new simple benchmark
    fn new(name: &str, func: F) -> Self {
        Self {
            name: name.to_string(),
            func: Arc::new(func),
            _phantom: std::marker::PhantomData,
        }
    }
}

impl<F, Fut> BenchmarkFn for SimpleBenchmark<F, Fut>
where
    F: Fn() -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<()>> + Send + Sync + 'static,
{
    fn name(&self) -> &str {
        &self.name
    }

    fn run<'a>(&'a self, config: BenchmarkConfig) -> BoxFuture<'a, Result<BenchmarkResult>> {
        Box::pin(async move {
            let f = self.func.clone();
            let func = move || f();
            benchmark(&self.name, func, config).await
        })
    }
}

/// Run a micro-benchmark for a function that should execute within a specific time limit
pub async fn expect_time_bound<F, Fut, T>(
    f: F,
    max_time: Duration,
    iterations: usize,
) -> Result<Vec<T>>
where
    F: Fn() -> Fut + Send + Sync + Copy,
    Fut: Future<Output = Result<T>> + Send,
{
    let mut results = Vec::with_capacity(iterations);

    for _ in 0..iterations {
        let start = Instant::now();
        let result = f().await?;
        let elapsed = start.elapsed();

        // Check time bound
        if elapsed > max_time {
            bail!(
                "Function exceeded time bound: {:?} > {:?}",
                elapsed,
                max_time
            );
        }

        results.push(result);
    }

    Ok(results)
}

/// A memory usage tracker for benchmarking
pub struct MemoryTracker {
    /// Maximum resident set size observed
    max_rss: Arc<AtomicUsize>,

    /// Memory allocations tracked
    allocations: Arc<AtomicUsize>,
}

impl MemoryTracker {
    /// Create a new memory tracker
    pub fn new() -> Self {
        Self {
            max_rss: Arc::new(AtomicUsize::new(0)),
            allocations: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// Start tracking memory usage
    pub fn start(&self) {
        // Reset counters
        self.allocations.store(0, Ordering::SeqCst);

        // Get current RSS
        if let Ok(rss) = get_current_rss() {
            self.max_rss.store(rss, Ordering::SeqCst);
        }
    }

    /// Update memory usage
    pub fn update(&self) {
        // Count allocations (simplified as proxy)
        self.allocations.fetch_add(1, Ordering::SeqCst);

        // Update max RSS
        if let Ok(rss) = get_current_rss() {
            let current_max = self.max_rss.load(Ordering::SeqCst);
            if rss > current_max {
                self.max_rss.store(rss, Ordering::SeqCst);
            }
        }
    }

    /// Get the maximum resident set size observed
    pub fn max_rss(&self) -> usize {
        self.max_rss.load(Ordering::SeqCst)
    }

    /// Get the number of allocations tracked
    pub fn allocations(&self) -> usize {
        self.allocations.load(Ordering::SeqCst)
    }
}

/// Get the current resident set size
fn get_current_rss() -> Result<usize> {
    // Use proc-sys-crate for cross-platform support
    #[cfg(target_os = "linux")]
    {
        use std::fs::File;
        use std::io::Read;

        let mut buf = String::new();
        File::open("/proc/self/statm")?.read_to_string(&mut buf)?;

        let fields: Vec<&str> = buf.split_whitespace().collect();
        if fields.len() >= 2 {
            let rss_pages = fields[1].parse::<usize>()?;
            let page_size = 4096; // Typical page size
            return Ok(rss_pages * page_size);
        }
    }

    // Fallback for non-Linux platforms
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::sleep;

    #[tokio::test]
    async fn test_benchmark_simple() {
        // Define a simple benchmark function
        async fn test_fn() -> Result<()> {
            sleep(Duration::from_micros(100)).await;
            Ok(())
        }

        // Run the benchmark
        let config = BenchmarkConfig {
            min_iterations: 10,
            max_iterations: 100,
            min_time: Duration::from_millis(500),
            warmup_iterations: 3,
            sample_size: 10,
            ..Default::default()
        };

        let result = benchmark("test_benchmark", || test_fn(), config).await.unwrap();

        // Verify results
        assert_eq!(result.name, "test_benchmark");
        assert!(result.iterations >= 10, "Should run at least min_iterations");
        assert!(result.avg_time_us >= 100.0, "Average time should be at least 100μs");
        assert!(result.min_time_us <= result.max_time_us, "Min time should be <= max time");
        assert!(result.p95_time_us >= result.avg_time_us, "P95 should be >= average");
        assert!(result.throughput > 0.0, "Throughput should be positive");
    }

    #[tokio::test]
    async fn test_benchmark_suite() {
        // Create a benchmark suite
        let mut suite = BenchmarkSuite::new("test_suite", BenchmarkConfig {
            min_iterations: 10,
            max_iterations: 50,
            min_time: Duration::from_millis(200),
            warmup_iterations: 2,
            sample_size: 5,
            ..Default::default()
        });

        // Add benchmarks
        suite.add_benchmark("fast_bench", || async {
            sleep(Duration::from_micros(50)).await;
            Ok(())
        });

        suite.add_benchmark("slow_bench", || async {
            sleep(Duration::from_micros(200)).await;
            Ok(())
        });

        // Run the suite
        let results = suite.run().await.unwrap();

        // Verify results
        assert_eq!(results.len(), 2, "Should have 2 benchmark results");
        assert_eq!(results[0].name, "fast_bench");
        assert_eq!(results[1].name, "slow_bench");

        // The slow benchmark should be slower
        assert!(results[1].avg_time_us > results[0].avg_time_us,
            "Slow benchmark should have higher average time");
    }

    #[tokio::test]
    async fn test_expect_time_bound() {
        // Function within time bound
        let within_bound = || async {
            sleep(Duration::from_millis(10)).await;
            Ok(42)
        };

        let results = expect_time_bound(within_bound, Duration::from_millis(50), 5).await.unwrap();
        assert_eq!(results.len(), 5);
        assert!(results.iter().all(|&r| r == 42));

        // Function exceeding time bound
        let exceeds_bound = || async {
            sleep(Duration::from_millis(100)).await;
            Ok(42)
        };

        let result = expect_time_bound(exceeds_bound, Duration::from_millis(50), 5).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_memory_tracker() {
        let tracker = MemoryTracker::new();

        // Start tracking
        tracker.start();
        assert_eq!(tracker.allocations(), 0);

        // Allocate something
        let _data = vec![0u8; 1024 * 1024]; // 1MB allocation
        tracker.update();

        // Check that we tracked the allocation
        assert_eq!(tracker.allocations(), 1);

        // The RSS value depends on the platform, but should be non-zero on Linux
        #[cfg(target_os = "linux")]
        assert!(tracker.max_rss() > 0);
    }
}
