# Copyright (c) 2024 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, ... }:

let
  kernel = pkgs.linux_latest;
in
pkgs.callPackage ./pkg.nix {
  inherit kernel;
  inherit (kernel) stdenv;
  inherit (pkgs) lib python3 fetchFromGitHub;
}
