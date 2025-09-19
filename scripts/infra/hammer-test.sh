#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Test hammer configuration remotely

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Testing hammer configuration"
    
    validate_devenv
    require_command nixos-rebuild
    
    step_start "Testing hammer configuration remotely"
    log_info "Target: localhost"
    run_cmd_verbose "nixos-rebuild test --flake .#hammer --sudo --verbose"
    step_complete "Tested hammer configuration"
    
    script_footer
}

main "$@"