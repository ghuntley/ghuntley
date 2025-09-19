#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Deploy hammer machine

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Deploying hammer machine"
    
    validate_devenv
    require_command nixos-rebuild
    
    step_start "Deploying hammer machine"
    log_info "Target: localhost"
    run_cmd_verbose "nixos-rebuild switch --flake .#hammer --sudo --verbose"
    step_complete "Deployed hammer machine"
    
    script_footer
}

main "$@"