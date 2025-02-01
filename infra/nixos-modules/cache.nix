# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  options = {
    services.depot.nix-cache.enable = lib.mkEnableOption "the Ponderoos binary cache";
    # depot.nix-cache.builderball = lib.mkEnableOption "use experimental builderball cache";
  };

  config = lib.mkIf config.services.depot.nix-cache.enable {
    nix.settings = {
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cache.tvl.su:kjc6KOMupXc1vHVufJUoDUYeLzbwSr9abcAKdn/U1Jk="
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "nix-cache.ponderoos.com-1:vEk9xwqywdl9jS/KBz0mbaRF/Qnxrfsi1i5Jhsy4BSs="
      ];

      substituters = [
        (if config.services.depot.nix-cache.enable
        then
          "https://nix-cache.ponderoos.com"
        else
          "https://cache.nixos.org"
            "https://cachix.cachix.org"
            "https://cache.tvl.fyi"
        )
      ];
    };
  };
}
