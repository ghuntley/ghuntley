# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  networking.firewall.extraCommands = ''
    iptables -P FORWARD ACCEPT \
    && iptables -t nat -A POSTROUTING -s 0.0.0.0/0 -j SNAT --to-source 0.0.0.0/0
  '';

  networking.firewall = {
    # always allow traffic from your docker0 network
    trustedInterfaces = [ "docker0" ];
  };

  virtualisation.podman.enable = false;
  virtualisation.docker = {
    enable = true;
    package = pkgs.docker;
    extraOptions = "--ip-masq=true --userland-proxy=true --iptables=false --ip6tables=false";
  };
  virtualisation.oci-containers.backend = "docker";
}
