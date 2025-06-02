# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:
{
  imports = [
    ../platforms/darwin.nix
  ];

  programs.home-manager.enable = true;

  home.username = "ghuntley";
  home.homeDirectory = "/Users/ghuntley";

  home.stateVersion = "25.05";

  programs.git = {
    userEmail = lib.mkForce "geoff@sourcegraph.com";
  };

  programs.zsh = {
    initExtra = ''
      eval "$(/Users/ghuntley/.local/bin/mise activate zsh)"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };

}
