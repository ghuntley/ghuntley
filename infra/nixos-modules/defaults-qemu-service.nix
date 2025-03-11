# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);

in
{
  imports = [
    (mod "default-imports.nix")

    (mod "automatic-nix-gc.nix")
    (mod "boot.nix")
    (mod "netdata.nix")
    (mod "restic.nix")
    (mod "sshd.nix")

  ];

  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];
  boot.initrd.availableKernelModules = [ "virtio_net" "virtio_pci" "virtio_mmio" "virtio_blk" "virtio_scsi" "9p" "9pnet_virtio" ];
  boot.initrd.kernelModules = [ "virtio_balloon" "virtio_console" "virtio_rng" ];

  boot.initrd.postDeviceCommands =
    ''
      # Set the system time from the hardware clock to work around a
      # bug in qemu-kvm > 1.5.2 (where the VM clock is initialised
      # to the *boot time* of the host).
      hwclock -s
    '';

  # Force boot loader timeout to resolve conflict
  boot.loader.timeout = lib.mkForce 16;

  # # Configure root filesystem size
  # fileSystems."/" = {
  #   device = "/dev/disk/by-label/nixos";
  #   fsType = "ext4";
  #   autoResize = true;
  # };

  # boot.growPartition = true;


  # Enable the QEMU guest agent
  virtualisation.qemu.guestAgent.enable = true;

  boot.tmp.cleanOnBoot = true;

  networking.useDHCP = true;

  # Firewall rules
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];
  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  # Use the ponderoos nix-cache
  services.depot.nix-cache.enable = true;

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-nix-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 64; # GiB
    maxFreed = 16; # GiB
    preserveGenerations = "7d";
  };

  # Offsite backups to OVH
  services.depot.restic.enable = true;
  services.depot.restic.interval = "*:0/10"; # Every 10 minutes

  services.depot.restic.paths = [
    "/etc"
    "/var/lib/acme"
  ];

  services.depot.restic.exclude = [ ];

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.infra.secrets.ponderoos."${name}.age";
    in
    {
      nix-cache-pubkey.file = secretFile "nix-cache-pubkey";
      nix-cache-pubkey.symlink = false;

      ovh-backup-credentials.file = secretFile "ovh-backup-credentials";
      ovh-backup-credentials.symlink = false;

      ovh-backup-encryption-key.file = secretFile "ovh-backup-encryption-key";
      ovh-backup-encryption-key.symlink = false;

    };
}
