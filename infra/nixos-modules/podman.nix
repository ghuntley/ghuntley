# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  virtualisation.docker.extraOptions = "--iptables=false --ip6tables=false";
  networking.firewall.extraCommands = ''
    iptables -P FORWARD ACCEPT \
    && iptables -t nat -A POSTROUTING -s 0.0.0.0/0 -j SNAT --to-source 0.0.0.0/0
  '';

  networking.firewall = {
    # always allow traffic from your docker0 network
    trustedInterfaces = [ "docker0" ];
  };

  virtualisation.podman.enable = false;
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker;
  virtualisation.oci-containers.backend = "docker";
}
