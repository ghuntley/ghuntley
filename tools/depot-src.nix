# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  depot-src = pkgs.writeShellScriptBin "depot-src" ''
    exec ${pkgs.niv}/bin/niv -s $DEPOT_ROOT/third_party/sources/sources.json show
  '';


in
depot-src.overrideAttrs (_: { })
