# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  imports = [
    ../platforms/linux.nix
  ];

  programs.home-manager.enable = true;

  home.username = "ghuntley";
  home.homeDirectory = "/home/ghuntley";

  home.stateVersion = "24.05";
}
