# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-keycloak-ponderoos = pkgs.writeShellScriptBin "deploy-keycloak-ponderoos" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    cd $DEPOT_ROOT/infra/secrets
    eval $(agenix --decrypt deploy-keycloak-ponderoos-credentials.age)

    cd $DEPOT_ROOT/infra/auth/ponderoos/terraform

    if [ ! -d ".terraform" ]; then
      terraform init
    fi
    terraform "$@"
  '';

in
deploy-keycloak-ponderoos.overrideAttrs (_: { })
