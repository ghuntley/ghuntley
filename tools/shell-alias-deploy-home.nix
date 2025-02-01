# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-home = pkgs.writeShellScriptBin "deploy-home" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    DRV=$(${depot.tools.depot}/bin/depot build //users/ghuntley/home/$(hostname)Home)
    exec $DRV/activate
  '';

in
deploy-home.overrideAttrs (_: { })
