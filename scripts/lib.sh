#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Common logging and utility functions for all scripts

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Log levels
readonly LOG_ERROR=0
readonly LOG_WARN=1
readonly LOG_INFO=2
readonly LOG_DEBUG=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-2}

# Get script name without path
SCRIPT_NAME=$(basename "${0}")

# Logging functions with timestamps and levels
log_error() {
    if [[ $LOG_LEVEL -ge $LOG_ERROR ]]; then
        echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR [${SCRIPT_NAME}]: $*${NC}" >&2
    fi
}

log_warn() {
    if [[ $LOG_LEVEL -ge $LOG_WARN ]]; then
        echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN  [${SCRIPT_NAME}]: $*${NC}" >&2
    fi
}

log_info() {
    if [[ $LOG_LEVEL -ge $LOG_INFO ]]; then
        echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO  [${SCRIPT_NAME}]: $*${NC}"
    fi
}

log_debug() {
    if [[ $LOG_LEVEL -ge $LOG_DEBUG ]]; then
        echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG [${SCRIPT_NAME}]: $*${NC}" >&2
    fi
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS [${SCRIPT_NAME}]: $*${NC}"
}

# Progress indicators
step_start() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] STEP  [${SCRIPT_NAME}]: ▶️  $*${NC}"
}

step_complete() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] STEP  [${SCRIPT_NAME}]: ✅ $*${NC}"
}

# Timer functions
timer_start() {
    TIMER_START=$(date +%s)
    log_debug "Timer started"
}

timer_end() {
    local TIMER_END
    TIMER_END=$(date +%s)
    local ELAPSED=$((TIMER_END - TIMER_START))
    local MINUTES=$((ELAPSED / 60))
    local SECONDS=$((ELAPSED % 60))
    
    if [[ $MINUTES -gt 0 ]]; then
        log_info "Completed in ${MINUTES}m ${SECONDS}s"
    else
        log_info "Completed in ${SECONDS}s"
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    exit $exit_code
}

# Set up error trap
trap 'handle_error ${LINENO}' ERR

# Utility functions
command_exists() {
    command -v "$1" &> /dev/null
}

require_command() {
    if ! command_exists "$1"; then
        log_error "Required command '$1' is not available"
        exit 1
    fi
}

# Validate environment
validate_devenv() {
    if [[ -z "${DEVENV_ROOT:-}" ]]; then
        log_error "This script must be run within a devenv environment"
        log_info "Run: devenv shell"
        exit 1
    fi
}

# Script header
script_header() {
    local description="$1"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}🔧 ${description}${NC}"
    echo -e "${BLUE}================================================================${NC}"
    log_info "Started at $(date)"
    timer_start
}

# Script footer
script_footer() {
    echo -e "${GREEN}================================================================${NC}"
    log_success "Script completed successfully"
    timer_end
    echo -e "${GREEN}================================================================${NC}"
}

# Docker availability check
check_docker() {
    if ! command_exists docker; then
        log_error "Docker is not available. Please start Docker daemon."
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Please start Docker daemon."
        exit 1
    fi
    
    log_debug "Docker is available and running"
}

# Registry availability check
check_registry() {
    local registry_url="$1"
    log_debug "Checking registry availability: ${registry_url}"
    
    if ! curl -f "${registry_url}/v2/" &>/dev/null; then
        log_error "Registry not available at ${registry_url}"
        return 1
    fi
    
    log_debug "Registry is available: ${registry_url}"
}

# Environment variable validation
require_env() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    
    if [[ -z "$var_value" ]]; then
        log_error "Environment variable '$var_name' is required but not set"
        exit 1
    fi
    
    log_debug "Environment variable '$var_name' is set"
}

# File existence check
require_file() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "Required file does not exist: $file_path"
        exit 1
    fi
    
    log_debug "Required file exists: $file_path"
}

# Directory existence check
require_directory() {
    local dir_path="$1"
    
    if [[ ! -d "$dir_path" ]]; then
        log_error "Required directory does not exist: $dir_path"
        exit 1
    fi
    
    log_debug "Required directory exists: $dir_path"
}

# Run command with logging
run_cmd() {
    local cmd="$*"
    log_debug "Running: $cmd"
    
    if [[ $LOG_LEVEL -ge $LOG_DEBUG ]]; then
        eval "$cmd"
    else
        eval "$cmd" &>/dev/null
    fi
}

# Run command with explicit output
run_cmd_verbose() {
    local cmd="$*"
    log_info "Running: $cmd"
    eval "$cmd"
}