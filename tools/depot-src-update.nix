# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  depot-src-update = pkgs.writeShellScriptBin "depot-src-update" ''
    exec ${pkgs.niv}/bin/niv -s $DEPOT_ROOT/third_party/sources/sources.json update
  '';


in
depot-src-update.overrideAttrs (_: { })
