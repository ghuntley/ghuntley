#!/bin/bash

# This script runs the test suite with coverage tracking and generates a coverage report.
# Requires grcov and rust nightly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$PROJECT_ROOT/target/coverage"

# Print banner
echo "======================================================================"
echo "                  Art Test Coverage Report Generator                  "
echo "======================================================================"

# Check for required tools
if ! command -v grcov &> /dev/null; then
    echo "Error: grcov is not installed. Please install it with:"
    echo "cargo install grcov"
    exit 1
fi

if ! command -v rustup &> /dev/null; then
    echo "Error: rustup is not installed. Please install it first."
    exit 1
fi

# Check if running on nightly
TOOLCHAIN=$(rustup show active-toolchain | grep -o 'nightly-.*')
if [ -z "$TOOLCHAIN" ]; then
    echo "Switching to nightly toolchain for coverage..."
    rustup override set nightly
fi

# Ensure llvm-tools are installed
if ! rustup component list --installed | grep -q "llvm-tools"; then
    echo "Installing llvm-tools-preview component..."
    rustup component add llvm-tools-preview
fi

# Clean previous coverage data
echo "Cleaning previous coverage data..."
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

# Set environment variables for coverage
export CARGO_INCREMENTAL=0
export RUSTFLAGS="-Zinstrument-coverage"
export LLVM_PROFILE_FILE="$REPORT_DIR/art-%p-%m.profraw"

# Run the tests
echo "Running tests with coverage instrumentation..."
pushd "$PROJECT_ROOT" > /dev/null

# Clean previous build to ensure all code is instrumented
cargo clean

# Run the unit tests
echo "Running unit tests..."
cargo test --lib --no-fail-fast

# Run the integration tests
echo "Running integration tests..."
cargo test --test '*' --no-fail-fast || true  # Don't fail if some tests are skipped

# Generate coverage report
echo "Generating coverage report..."
grcov . \
    --binary-path ./target/debug/ \
    -s . \
    -t html,lcov,cobertura \
    --branch \
    --ignore-not-existing \
    --ignore "/*" \
    --ignore "target/*" \
    --ignore "tests/*" \
    --ignore "benches/*" \
    -o "$REPORT_DIR"

# Generate summary for console output
echo "Generating coverage summary..."
if command -v lcov &> /dev/null; then
    lcov --summary "$REPORT_DIR/lcov.info"
else
    echo "lcov not found. Install it for a coverage summary in the console."
    echo "Coverage report available at: $REPORT_DIR/index.html"
fi

popd > /dev/null

# Reset to stable if we switched to nightly
if [ -z "$TOOLCHAIN" ]; then
    echo "Switching back to stable toolchain..."
    rustup override unset
fi

echo "======================================================================"
echo "Coverage report generated at: $REPORT_DIR/index.html"
echo "======================================================================"

# Open the report if we're on a graphical system
if [ -n "$DISPLAY" ] && command -v xdg-open &> /dev/null; then
    echo "Opening coverage report..."
    xdg-open "$REPORT_DIR/index.html"
elif [ "$(uname)" == "Darwin" ] && command -v open &> /dev/null; then
    echo "Opening coverage report..."
    open "$REPORT_DIR/index.html"
elif [ -n "$WSL_DISTRO_NAME" ] && command -v powershell.exe &> /dev/null; then
    echo "Opening coverage report..."
    powershell.exe -c "start $(wslpath -w "$REPORT_DIR/index.html")"
fi
