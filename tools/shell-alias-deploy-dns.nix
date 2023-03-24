# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-dns = pkgs.writeShellScriptBin "deploy-dns" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    cd $DEPOT_ROOT/ops/dns
    if [ ! -d ".terraform" ]; then
      terraform init
    fi
    terraform "$@"
  '';

in
deploy-dns.overrideAttrs (_: { })
