# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
  programs.mosh.enable = true;

  networking.firewall.allowedUDPPortRanges = lib.optionals (config.services.openssh.enable) [
    # Mosh
    { from = 60000; to = 60010; }
  ];

  # This enables "lingering" for the user.
  # Inspired by the discussion (and linked code)
  # in https://github.com/NixOS/nixpkgs/issues/3702
  # This should just be a NixOS option really.
  system.activationScripts = {
    enableLingering = ''
      # remove all existing lingering users
      rm -r /var/lib/systemd/linger
      mkdir /var/lib/systemd/linger
      # enable for the subset of declared users
      touch /var/lib/systemd/linger/mgmt
    '';
  };
}
