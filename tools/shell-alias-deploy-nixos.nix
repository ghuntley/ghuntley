# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-nixos = pkgs.writeShellScriptBin "deploy-nixos" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    DRV=$(${depot.tools.depot}/bin/depot build //infra/nixos | grep rebuild-system)
    exec sudo $DRV/bin/rebuild-system
  '';

in
deploy-nixos.overrideAttrs (_: { })
