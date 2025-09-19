# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ tailscale ];

  services.tailscale.enable = true;

  networking.firewall = {
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];

    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];

    checkReversePath = "loose";
  };

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = "1"; # for tailscale exit node
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces."tailscale0".allowedUDPPortRanges = [
    { from = 60000; to = 60010; }
  ];
}