#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Check license headers on changed files

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Checking license headers on changed files"
    
    validate_devenv
    require_command license
    
    step_start "Checking license headers on changed files"
    run_cmd_verbose "license --check --verbose"
    step_complete "License header check completed"
    
    script_footer
}

main "$@"