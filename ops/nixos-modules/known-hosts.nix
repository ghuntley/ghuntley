# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configure public keys for SSH hosts known.
{ ... }:

{
  programs.ssh = {

    extraConfig = ''
      VerifyHostKeyDNS yes
    '';

    # $ ssh-keyscan example.com
    knownHosts = {
      github = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
      rsync-net = {
        hostNames = [ "zh2297.rsync.net" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJtclizeBy1Uo3D86HpgD3LONGVH0CJ0NT+YfZlldAJd";
      };
    };
  };
}
