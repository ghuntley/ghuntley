# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  depot-src-add = pkgs.writeShellScriptBin "depot-src-add" ''
    exec ${pkgs.niv}/bin/niv -s $DEPOT_ROOT/third_party/sources/sources.json add ''${@}
  '';


in
depot-src-add.overrideAttrs (_: { })
