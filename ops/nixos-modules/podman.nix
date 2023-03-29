# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {
  virtualisation.docker.extraOptions = "--iptables=false --ip6tables=false";
  networking.firewall.extraCommands = ''iptables -P FORWARD ACCEPT && iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -j SNAT --to-source 51.161.196.125'';
  #networking.firewall.extraCommands = ''iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -j MASQUERADE && iptables -P FORWARD ACCEPT'';

  networking.firewall = {
    # always allow traffic from your docker0 network
    trustedInterfaces = [ "docker0" ];
  };

  virtualisation.podman.enable = false;
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker;
  virtualisation.oci-containers.backend = "docker";

  # virtualisation.podman.dockerCompat = true;
  # virtualisation.podman.dockerSocket.enable = true;
}
