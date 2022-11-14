# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  depot-src-drop = pkgs.writeShellScriptBin "depot-src-drop" ''
    exec ${pkgs.niv}/bin/niv -s $DEPOT_ROOT/third_party/sources/sources.json drop ''${@}
  '';


in
depot-src-drop.overrideAttrs (_: { })
