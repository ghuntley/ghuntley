# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-buildkite = pkgs.writeShellScriptBin "deploy-buildkite" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    cd $DEPOT_ROOT/infra/secrets
    eval $(agenix --decrypt deploy-buildkite-credentials.age)

    cd $DEPOT_ROOT/infra/scm/buildkite/terraform
    if [ ! -d ".terraform" ]; then
      terraform init
    fi
    terraform "$@"
  '';

in
deploy-buildkite.overrideAttrs (_: { })
