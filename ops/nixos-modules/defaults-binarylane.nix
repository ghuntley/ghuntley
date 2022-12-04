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

    (mod "automatic-gc.nix")

    (mod "boot.nix")
    # TODO(security): luks ssh unencrypt is currently broken
    #(mod "initrd-luks-unlock.nix")
    (mod "sshd.nix")

  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];

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
