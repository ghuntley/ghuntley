# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  z = pkgs.writeShellScriptBin "z" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    ${depot.tools.depot-addlicense}/bin/depot-addlicense
    ${depot.tools.depot-fmt}/bin/depot-fmt
    ${depot.tools.shell-alias-deploy-dns}/bin/deploy-dns validate
    ${pkgs.lazygit}/bin/lazygit
  '';

in
z.overrideAttrs (_: { })
