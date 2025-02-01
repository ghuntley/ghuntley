# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

let

  depot = config.lib.depot;

in
{
  imports = [
    ../modules/default-imports.nix
    ../modules/firefox.nix
    ../modules/shell-alias-cursor.nix
  ];
}
