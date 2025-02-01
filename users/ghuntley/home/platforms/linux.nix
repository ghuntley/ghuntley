# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

let

  depot = config.lib.depot;

  theme = import ../themes/firewatch.nix;

in
{
  imports = [
    ../modules/default-imports.nix
    ../modules/hyprland.nix
    ../modules/firefox.nix
    ../modules/shell-alias-deploy-nixos.nix
    ../modules/shell-alias-cursor.nix
    ../modules/shell-alias-cider.nix
    ../modules/shell-alias-bottles.nix
  ];
}
