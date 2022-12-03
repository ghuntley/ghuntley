# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }:

{
  services.openssh = {
    enable = true;
    kbdInteractiveAuthentication = false;
    openFirewall = false;
    passwordAuthentication = false;
    permitRootLogin = "prohibit-password";

    useDns = false;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  # Mosh
  programs.mosh.enable = true;
  networking.firewall.interfaces."tailscale0".allowedUDPPortRanges = lib.optionals (config.services.openssh.enable) [
    { from = 60000; to = 60010; }
  ];

}
