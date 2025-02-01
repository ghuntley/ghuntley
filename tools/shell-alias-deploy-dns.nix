# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-dns = pkgs.writeShellScriptBin "deploy-dns" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    cd $DEPOT_ROOT/infra/secrets/ponderoos
    eval $(agenix --decrypt deploy-dns-credentials.age)

    cd $DEPOT_ROOT/infra/dns
    if [ ! -d ".terraform" ]; then
      terraform init
    fi
    terraform "$@"
  '';

in
deploy-dns.overrideAttrs (_: { })
