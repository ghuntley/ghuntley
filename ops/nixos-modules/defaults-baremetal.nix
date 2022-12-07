# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);

in
{
  imports = [
    (mod "defaults.nix")

    (mod "nginx/self-redirect.nix")

    (mod "automatic-nix-gc.nix")

    (mod "boot.nix")
    (mod "initrd-zfs-unlock.nix")
    (mod "sshd.nix")

    (mod "mdadm.nix")
    (mod "nvme.nix")
    (mod "smartd.nix")
    (mod "zfs.nix")

    (mod "microcode.nix")
  ];

  powerManagement.cpuFreqGovernor = "performance";


  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.ops.secrets."${name}.age";
    in
    {
      ssh-initrd-ed25519-key.file = secretFile "ssh-initrd-ed25519-key";
      ssh-initrd-ed25519-pub.file = secretFile "ssh-initrd-ed25519-pub";
    };

}
