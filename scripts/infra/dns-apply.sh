#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Apply Terraform changes in infra/dns

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Applying Terraform changes in infra/dns"
    
    validate_devenv
    require_command tofu
    require_directory "infra/dns"
    
    # Set Terraform logging for observability
    export TF_LOG=DEBUG
    
    step_start "Changing to infra/dns directory"
    cd infra/dns || exit 1
    
    step_start "Initializing Terraform"
    if ! run_cmd_verbose "tofu init -v"; then
        log_error "tofu init failed"
        exit 1
    fi
    step_complete "Terraform initialized"
    
    step_start "Applying Terraform changes"
    log_warn "This will make changes to DNS infrastructure"
    if ! run_cmd_verbose "tofu apply -auto-approve -v"; then
        log_error "tofu apply failed"
        exit 1
    fi
    step_complete "Terraform changes applied"
    
    script_footer
}

main "$@"