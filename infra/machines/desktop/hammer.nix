# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    ./nixos-modules/base.nix
    ./nixos-modules/depot-deploy-machine.nix
    ./nixos-modules/depot-deploy-home.nix
    ./nixos-modules/depot-sync.nix
    ./nixos-modules/desktop.nix
    ./nixos-modules/i18n.nix
    ./nixos-modules/known-hosts.nix
    ./nixos-modules/microcode.nix
    ./nixos-modules/nix-settings.nix
    ./nixos-modules/netdata.nix
    ./nixos-modules/secrets.nix
    ./nixos-modules/security-audit.nix
    ./nixos-modules/ssh.nix
    ./nixos-modules/sudo.nix
    ./nixos-modules/sysctl.nix
    ./nixos-modules/tailscale.nix
    ./nixos-modules/time.nix
    ./nixos-modules/user.nix
    ./nixos-modules/vscode-server.nix
    ./nixos-modules/zsh.nix
  ];

  # Machine-specific configuration
  networking.hostName = "hammer";

  # Networking
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;

  # Firewall
  networking.firewall.enable = true;

  # Hardware configuration
  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # Bootloader - machine specific
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-3c5ffe5f-cfd3-42f7-9c66-cd393a452ade".device = "/dev/disk/by-uuid/3c5ffe5f-cfd3-42f7-9c66-cd393a452ade";
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8959-0CFA";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  boot.initrd.luks.devices."luks-42194944-7885-457e-8904-c470517387dc".device = "/dev/disk/by-uuid/42194944-7885-457e-8904-c470517387dc";
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/9c6b5833-99f3-4803-823e-64ccd9ad9fec";
    fsType = "ext4";
  };

  swapDevices = [
    {device = "/dev/disk/by-uuid/ca386c49-06d5-4ae8-8aed-148b3dc457fa";}
  ];

  # Set hammer-specific secrets file
  sops.defaultSopsFile = ../secrets/hammer.yaml;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "25.05";
}
