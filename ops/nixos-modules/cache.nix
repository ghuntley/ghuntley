# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  config = {

    # TODO: configure nix.settings.substituters and nix.settings.trusted-public-keys

    # nix.settings.substituters = [
    #   "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    #   "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
    #   "ghuntley.cachix.org-1:SYPiX2s5cpz9JfySsQD7HkhQkUagmsdrtPFpKazS5a4="
    #   "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # ];


    # nix.settings.trusted-public-keys = [
    #   "https://cache.nixos.org"
    #   "https://cachix.cachix.org"
    #   "https://ghuntley.cachix.org"
    #   "https://nix-community.cachix.org"
    # ];

  };
}
