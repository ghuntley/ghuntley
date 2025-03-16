# Testing Guide for Art

This document provides a comprehensive guide to testing the Art Git Repository Browser.

## Table of Contents

- [Testing Philosophy](#testing-philosophy)
- [Prerequisites](#prerequisites)
- [Types of Tests](#types-of-tests)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
  - [Property-Based Tests](#property-based-tests)
  - [Security Tests](#security-tests)
  - [Benchmarks](#benchmarks)
  - [Load Testing](#load-testing)
- [Code Coverage](#code-coverage)
- [Continuous Integration](#continuous-integration)
- [Writing New Tests](#writing-new-tests)
- [Test Organization](#test-organization)
- [Troubleshooting](#troubleshooting)

## Testing Philosophy

The Art project adheres to a comprehensive testing approach designed to ensure reliability, security, and performance. We follow these key principles:

1. **Test Driven Development (TDD)**: When feasible, we write tests before implementing features.
2. **High Coverage**: We aim for high test coverage across all core functionality.
3. **Multiple Test Types**: We use various types of tests to ensure different aspects of quality.
4. **Security First**: We actively test for security vulnerabilities.
5. **Performance Awareness**: We continuously benchmark critical operations.

## Prerequisites

To run the full test suite, you need:

- Rust toolchain (stable and nightly for some tests)
- Python 3.7+ (for load testing)
- `grcov` (for coverage reporting): `cargo install grcov`
- Additional packages for load testing: `pip install aiohttp`

## Types of Tests

### Unit Tests

Unit tests verify that individual components work as expected in isolation.

**Location:** Inside source modules using `#[cfg(test)]` modules and in the `tests/` directory with file names like `test_*.rs`.

**Run with:**
```bash
# Run all unit tests
cargo test

# Run tests for a specific module
cargo test --lib config

# Run a specific test
cargo test --lib config::test_load_config
```

### Integration Tests

Integration tests verify that components work together correctly.

**Location:** `tests/integration_test.rs`

**Run with:**
```bash
# Run all integration tests
cargo test --test integration_test

# Run a specific integration test
cargo test --test integration_test test_repository_workflow
```

### Property-Based Tests

Property-based tests verify that functions maintain certain invariants across a wide range of inputs.

**Location:** `tests/property_test.rs`

**Run with:**
```bash
# Run all property tests
cargo test --test property_test

# Run a specific property test
cargo test --test property_test test_normalize_path_prop
```

### Security Tests

Security tests verify that the application handles potentially malicious inputs safely and doesn't have common vulnerabilities.

**Location:** `tests/security_test.rs`

**Run with:**
```bash
# Run all security tests
cargo test --test security_test

# Run a specific security test
cargo test --test security_test test_xss_protection
```

### Benchmarks

Benchmarks measure the performance of critical operations to detect performance regressions.

**Location:** `benches/benchmarks.rs`

**Run with:**
```bash
# Run all benchmarks
cargo bench

# Run a specific benchmark
cargo bench bench_open_repository
```

### Load Testing

Load testing simulates many concurrent users to test the application under high load.

**Location:** `scripts/load_test.py`

**Run with:**
```bash
# Basic load test with default settings (50 clients for 60 seconds)
./scripts/load_test.py

# Custom load test
./scripts/load_test.py --clients 100 --duration 300 --scenario api

# See all options
./scripts/load_test.py --help
```

Available scenarios:
- `browse`: Simulates users browsing the web interface
- `api`: Simulates clients using the API endpoints
- `mixed`: A combination of web and API access (default)

## Code Coverage

We track code coverage to ensure our tests adequately verify the codebase.

**Generate coverage report:**
```bash
./scripts/coverage.sh
```

This script:
1. Runs all tests with coverage instrumentation
2. Generates HTML and LCOV reports
3. Displays a summary
4. Opens the HTML report if possible

The coverage report will be available in `target/coverage/`.

## Continuous Integration

Our CI pipeline runs all tests on every pull request and merge to main. The pipeline:

1. Runs all unit and integration tests
2. Runs property-based and security tests
3. Runs benchmarks and compares with baseline
4. Generates a coverage report
5. Runs the load test with a basic configuration

## Writing New Tests

When writing new tests, follow these guidelines:

1. **Unit Tests**: Place simple tests in the same file as the code under test. More complex tests should go in the `tests/` directory.
2. **Integration Tests**: Add to `tests/integration_test.rs` or create a new file if testing a distinct feature.
3. **Property Tests**: Add properties that should hold true for a function regardless of input.
4. **Security Tests**: Think about what could go wrong from a security perspective.
5. **Benchmarks**: Benchmark any performance-critical operation.

### Test Helper Functions

Common test helpers are available in `tests/helpers.rs`, including:
- `setup_test_repository()`: Creates a Git repository for testing
- `start_test_server()`: Starts a test server instance
- `make_request()`: Makes an HTTP request to a test server

## Test Organization

Our tests are organized as follows:

- **Unit tests**: Located in the same file as the implementation, or in `tests/test_<module>.rs`
- **Integration tests**: Located in `tests/integration_test.rs`
- **Property tests**: Located in `tests/property_test.rs`
- **Security tests**: Located in `tests/security_test.rs`
- **Benchmarks**: Located in `benches/benchmarks.rs`
- **Load tests**: Located in `scripts/load_test.py`

## Troubleshooting

### Common Issues

1. **Tests are slow**: Some tests create actual Git repositories and might be slow. Use `--no-run` to build without running.

   ```bash
   cargo test --no-run
   ```

2. **Tests fail with Git errors**: Ensure Git is installed and available in your PATH.

3. **Coverage report fails**: Ensure you have a nightly Rust toolchain and grcov installed.

   ```bash
   rustup toolchain install nightly
   cargo install grcov
   ```

4. **Load test fails**: Check you have Python 3.7+ and aiohttp installed.

   ```bash
   pip install aiohttp
   ```

5. **Benchmarks are unstable**: Run them multiple times with `--warm-up` flag.

   ```bash
   cargo bench -- --warm-up
   ```

### Test Failures

When a test fails:

1. Look at the exact assertion that failed
2. Check the expected vs actual values
3. Use `RUST_BACKTRACE=1` to get more context
4. Try running just that test with verbose output:

   ```bash
   RUST_LOG=debug cargo test <test_name> -- --nocapture
   ```

5. Use debugging prints if needed with `println!` or logging with `debug!`
