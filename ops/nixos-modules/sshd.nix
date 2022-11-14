# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }:

{
  imports = [
    ./mosh.nix
  ];



  services.openssh = {
    enable = true;
    forwardX11 = true;
    kbdInteractiveAuthentication = false;
    openFirewall = false;
    passwordAuthentication = false;
    permitRootLogin = "no";

    useDns = false;

    # unbind gnupg sockets if they exists
    extraConfig = ''
      StreamLocalBindUnlink yes
    '';
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  # Allow sudo-ing via the forwarded SSH agent.
  # security.pam.enableSSHAgentAuth = true;
}
