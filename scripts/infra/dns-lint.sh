#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Lint Terraform configuration in infra/dns

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

main() {
    script_header "Linting Terraform configuration in infra/dns"
    
    validate_devenv
    require_command tofu
    require_directory "infra/dns"
    
    # Set Terraform logging for observability
    export TF_LOG=DEBUG
    
    step_start "Changing to infra/dns directory"
    cd infra/dns || exit 1
    
    step_start "Running terraform format check"
    if run_cmd "tofu fmt -check -diff"; then
        step_complete "Terraform configuration is properly formatted"
    else
        log_error "tofu fmt failed - configuration is not properly formatted"
        exit 1
    fi
    
    script_footer
}

main "$@"