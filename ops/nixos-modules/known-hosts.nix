# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configure public keys for SSH hosts known.
{ ... }:

{
  programs.ssh = {

    extraConfig = ''
      VerifyHostKeyDNS yes
    '';

    knownHosts = {
      github = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
      ts = {
        hostNames = [ "ts.fediversehosting.net" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG";
      };
    };
  };
}
