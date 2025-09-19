# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  # sops-nix is now imported via flake inputs in flake.nix

  # Default sops configuration
  sops.defaultSopsFormat = "yaml";
  
  # Machine-specific secrets files should be set in machine configs
  # sops.defaultSopsFile = path/to/machine-specific-secrets.yaml;
  
  # Use SSH host key for sops decryption
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  
  # Machine-specific secrets should be defined in machine configs
  # Each machine will automatically use its own secrets file: ../secrets/{hostname}.yaml
  
  # Install sops for managing secrets
  environment.systemPackages = with pkgs; [
    sops
    age
  ];
}