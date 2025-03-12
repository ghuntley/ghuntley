# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  auth = name: depot.path.origSrc + ("/infra/auth/" + name);
  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);
  nix-cache = name: depot.path.origSrc + ("/infra/nix-cache/nixos-modules/" + name);
  scm = name: depot.path.origSrc + ("/infra/scm/nixos-modules/" + name);

in
{
  imports = [
    (mod "defaults-bare-metal.nix")
    (mod "nvidia.nix")
    (mod "podman.nix")
    (mod "restic.nix")
    (mod "geesefs.nix")
  ];

  boot.tmp.cleanOnBoot = true;

  boot.initrd.availableKernelModules = [ "nvme" "thunderbolt" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  boot.loader.grub = {
    enable = true;
    zfsSupport = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [
      { devices = [ "nodev" ]; path = "/boot"; }
    ];

  };

  fileSystems."/" =
    {
      device = "rpool/root";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    {
      device = "rpool/nix";
      fsType = "zfs";
    };

  fileSystems."/var" =
    {
      device = "rpool/var";
      fsType = "zfs";
    };

  fileSystems."/home" =
    {
      device = "rpool/home";
      fsType = "zfs";
    };

  fileSystems."/depot" =
    {
      device = "rpool/depot";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/F546-0D9A";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  networking.hostId = "deadbeef";
  networking.hostName = "crowbar";
  networking.domain = "desktop";

  #networking.useDHCP = true;
  networking.networkmanager.enable = true;

  networking.firewall.enable = true;

  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 22 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.nameservers = [ "1.1.1.1" ];

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-nix-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 64; # GiB
    maxFreed = 64; # GiB
    preserveGenerations = "90d";
  };

  # Offsite backups to OVH
  services.depot.restic = {
    enable = true;
    interval = "*:0/10"; # Every 10 minutes
    keep-last = 1;
    keep-hourly = 24;
    keep-daily = 2;
    keep-weekly = 0;
    keep-monthly = 0;
    keep-yearly = 0;
    paths = [
      "/etc"
      "/depot"
      "/home/ghuntley"
    ];
    exclude = [
      ".Trash*"
      "/home/ghuntley/go"
      "/home/ghuntley/Downloads"
      "/home/ghuntley/.1password"
      "/home/ghuntley/.cache"
      "/home/ghuntley/.cargo"
      "/home/ghuntley/.cursor"
      "/home/ghuntley/.cursor-server"
      "/home/ghuntley/.steam"
      "/home/ghuntley/.mozilla"
      "/home/ghuntley/.var"
      "/home/ghuntley/.local"
    ];
  };

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.infra.secrets.ponderoos."${name}.age";
    in
    {

      backup-cli-credentials.file = secretFile "backup-cli-credentials";
      backup-cli-credentials.symlink = false;

      ovh-backup-credentials.file = secretFile "ovh-backup-credentials";
      ovh-backup-credentials.symlink = false;

      ovh-backup-encryption-key.file = secretFile "ovh-backup-encryption-key";
      ovh-backup-encryption-key.symlink = false;

      nix-cache-pubkey.file = secretFile "nix-cache-pubkey";
      nix-cache-pubkey.symlink = false;

      nix-cache-signkey.file = secretFile "nix-cache-signkey";
      nix-cache-signkey.symlink = false;

      postgres-keycloak-credentials.file = secretFile "postgres-keycloak-credentials";
      postgres-keycloak-credentials.symlink = false;

      inbox-hello-credentials.file = secretFile "inbox-hello-credentials";
      inbox-hello-credentials.symlink = false;

      netdata-cloud-claim-token = {
        file = secretFile "netdata-cloud-claim-token";
        mode = "0440";
        group = "netdata";
        symlink = false;
      };

    };

  services.depot.nix-cache.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
