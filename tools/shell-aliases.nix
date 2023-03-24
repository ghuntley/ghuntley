# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  lg = pkgs.writeShellScriptBin "lg" ''
    exec ${pkgs.lazygit}/bin/lg "$@"
  '';

in
depot-src.overrideAttrs (_: { })
