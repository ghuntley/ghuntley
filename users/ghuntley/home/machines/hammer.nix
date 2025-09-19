# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:
let
  swap_escape = false;
  monitor = "HDMI-A-1";
  theme = import ../themes/firewatch.nix;
  ui_scale = 1;
  size = n: builtins.toString (builtins.floor n * ui_scale);
in
{
  imports = [
    ../platforms/linux.nix
  ];

  nixpkgs.config.allowUnfree = true;

  hyprland = { inherit theme; inherit monitor; inherit size; inherit swap_escape; };

  programs.home-manager.enable = true;

  home.username = "ghuntley";
  home.homeDirectory = "/home/ghuntley";

  home.stateVersion = "25.05";
}
