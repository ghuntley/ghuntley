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
    (mod "defaults-laptop.nix")
    (mod "podman.nix")
    (mod "restic.nix")
  ];

  services.vaultwarden.enable = true;
  services.alloy.enable = true;


  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.tmp.cleanOnBoot = true;

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
      device = "/dev/disk/by-uuid/4879-9866";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0022" ];
    };

  swapDevices = [ ];


  networking.hostId = "deadbeef";
  networking.hostName = "prybar";
  networking.domain = "laptop";

  #networking.useDHCP = true;
  networking.networkmanager.enable = true;

  networking.firewall.enable = false;

  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 22 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.nameservers = [ "1.1.1.1" ];

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  services.throttled.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vpl-gpu-rt
    ];
  };

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

      netdata-cloud-claim-token = {
        file = secretFile "netdata-cloud-claim-token";
        mode = "0440";
        group = "netdata";
        symlink = false;
      };

    };

  services.depot.nix-cache.enable = true;

  # Explicitly set the netdata claim token path
  services.netdata.claimTokenFile = config.age.secrets.netdata-cloud-claim-token.path;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
