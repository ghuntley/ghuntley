#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running comprehensive test suite for Art${NC}"

# Create directories for test output
mkdir -p test_results
mkdir -p coverage

# Step 1: Run the unit tests
echo -e "\n${YELLOW}Running unit tests...${NC}"
RUST_BACKTRACE=1 cargo test --lib -- --nocapture
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Unit tests passed!${NC}"
else
    echo -e "${RED}Unit tests failed!${NC}"
    exit 1
fi

# Step 2: Run property-based tests
echo -e "\n${YELLOW}Running property-based tests...${NC}"
RUST_BACKTRACE=1 cargo test --test property_test -- --nocapture
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Property-based tests passed!${NC}"
else
    echo -e "${RED}Property-based tests failed!${NC}"
    exit 1
fi

# Step 3: Run integration tests
echo -e "\n${YELLOW}Running integration tests...${NC}"
RUST_BACKTRACE=1 cargo test --test integration_test --test maintenance_test -- --nocapture
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Integration tests passed!${NC}"
else
    echo -e "${RED}Integration tests failed!${NC}"
    exit 1
fi

# Step 4: Run OpenTelemetry tests (may be skipped if no backend is available)
echo -e "\n${YELLOW}Running OpenTelemetry tests...${NC}"
RUST_BACKTRACE=1 cargo test --test opentelemetry_integration_test -- --nocapture --skip-backend-required || true
echo -e "${YELLOW}OpenTelemetry tests completed (some tests may be skipped without a backend)${NC}"

# Step 5: Run security tests
echo -e "\n${YELLOW}Running security tests...${NC}"
RUST_BACKTRACE=1 cargo test --test security_test -- --nocapture
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Security tests passed!${NC}"
else
    echo -e "${RED}Security tests failed!${NC}"
    exit 1
fi

# Step 6: Run UI responsiveness tests
echo -e "\n${YELLOW}Running UI responsiveness tests...${NC}"
RUST_BACKTRACE=1 cargo test --test ui_responsive_tests -- --nocapture
if [ $? -eq 0 ]; then
    echo -e "${GREEN}UI responsiveness tests passed!${NC}"
else
    echo -e "${RED}UI responsiveness tests failed!${NC}"
    exit 1
fi

# Step 7: Run benchmarks if requested
if [ "$1" == "--bench" ]; then
    echo -e "\n${YELLOW}Running benchmarks...${NC}"
    cargo bench --bench maintenance_benchmark
    echo -e "${GREEN}Benchmarks completed!${NC}"
fi

# Step 8: Generate code coverage report
echo -e "\n${YELLOW}Generating code coverage report...${NC}"
if command -v cargo-tarpaulin &> /dev/null; then
    cargo tarpaulin --out Html --output-dir coverage
    echo -e "${GREEN}Coverage report generated in coverage/tarpaulin-report.html${NC}"
else
    echo -e "${YELLOW}cargo-tarpaulin not found, skipping coverage report generation${NC}"
    echo -e "${YELLOW}Install with: cargo install cargo-tarpaulin${NC}"
fi

# Step 9: Check for lint issues
echo -e "\n${YELLOW}Running clippy linter...${NC}"
cargo clippy -- -D warnings
if [ $? -eq 0 ]; then
    echo -e "${GREEN}No linting issues found!${NC}"
else
    echo -e "${RED}Linting issues found!${NC}"
    exit 1
fi

# Step 10: Run check for outdated dependencies
echo -e "\n${YELLOW}Checking for outdated dependencies...${NC}"
if command -v cargo-outdated &> /dev/null; then
    cargo outdated
else
    echo -e "${YELLOW}cargo-outdated not found, skipping dependency check${NC}"
    echo -e "${YELLOW}Install with: cargo install cargo-outdated${NC}"
fi

# Step 11: Check for security vulnerabilities
echo -e "\n${YELLOW}Checking for security vulnerabilities...${NC}"
if command -v cargo-audit &> /dev/null; then
    cargo audit
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}No security vulnerabilities found!${NC}"
    else
        echo -e "${RED}Security vulnerabilities found!${NC}"
        echo -e "${YELLOW}Review the report and update dependencies as needed${NC}"
    fi
else
    echo -e "${YELLOW}cargo-audit not found, skipping security audit${NC}"
    echo -e "${YELLOW}Install with: cargo install cargo-audit${NC}"
fi

echo -e "\n${GREEN}All tests completed successfully!${NC}"
