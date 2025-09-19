# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

{
  # Nix configuration
  nix.settings.auto-optimise-store = true;
  nix.settings.trusted-users = [ "root" "ghuntley" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Configure binary cache settings
  nix.settings.require-sigs = true;
  nix.settings.substituters = [
    "https://cache.nixos.org/"
    "https://devenv.cachix.org"
    "https://nix-community.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}