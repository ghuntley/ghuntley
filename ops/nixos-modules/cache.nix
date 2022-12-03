# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  config = {

    # TODO(nixcache): configure nixcache.corp substituters
    nix.settings.substituters = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # TODO(nixcache): configure nixcache.corp trusted-public-keys
    nix.settings.trusted-public-keys = [
      "https://cache.nixos.org"
      "https://cachix.cachix.org"
      "https://nix-community.cachix.org"
    ];

  };
}
