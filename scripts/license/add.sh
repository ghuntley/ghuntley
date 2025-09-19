#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Add license headers to changed files

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Adding license headers to changed files"
    
    validate_devenv
    require_command license
    
    step_start "Adding license headers to changed files"
    run_cmd_verbose "license --verbose"
    step_complete "License headers added to changed files"
    
    script_footer
}

main "$@"