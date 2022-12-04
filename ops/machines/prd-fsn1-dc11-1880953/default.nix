# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);

in
{
  imports = [
    (mod "defaults-baremetal.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    devices = [ "/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAG800126" "/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAG800130" ];
    copyKernels = true;
  };

  boot.initrd.kernelModules = [
    "kvm-amd"
    "kvm-intel"
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
  ];

  boot.initrd.availableKernelModules = [
    "9p"
    "9pnet_virtio"
    "aesni_intel"
    "ahci"
    "ata_piix"
    "cryptd"
    "igb"
    "nvme"
    "sd_mod"
    "sr_mod"
    "uhci_hcd"
    "usb_storage"
    "usbhid"
    "virtio_blk"
    "virtio_mmio"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
  ];

  boot.supportedFilesystems = [ "zfs" ];

  # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
  boot.kernelParams = [ "ip=148.251.233.2:148.251.233.2:148.251.233.1:255.255.255.224" ];


  fileSystems."/" =
    {
      device = "rpool/root";
      fsType = "zfs";
    };

  fileSystems."/etc" =
    {
      device = "rpool/root/etc";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    {
      device = "rpool/root/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    {
      device = "rpool/root/home";
      fsType = "zfs";
    };

  fileSystems."/depot" =
    {
      device = "rpool/root/depot";
      fsType = "zfs";
    };

  fileSystems."/srv" =
    {
      device = "rpool/root/srv";
      fsType = "zfs";
    };

  fileSystems."/data" =
    {
      device = "dpool/data";
      fsType = "zfs";
    };


  fileSystems."/var/lib/nixos-containers" =
    {
      device = "rpool/root/nixos-containers";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/e2ef0001-ede7-4d9e-b3a9-f9a08423527a";
      fsType = "ext4";
    };

  swapDevices = [ ];

  networking.hostName = "prd-fsn1-dc11-1880953";
  networking.domain = "servers";

  networking.hostId = "deadbeef";

  networking.useDHCP = false;

  # TODO(security): migrate from public ssh to tailscale only ssh
  networking.firewall.interfaces."enp4s0".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  networking.interfaces."enp4s0".ipv4.addresses = [
    {
      address = "148.251.233.2";
      prefixLength = 24;
    }
  ];

  # # https://docs.hetzner.com/robot/dedicated-server/network/vswitch/
  # networking.vlans = {
  #   enp4s0-vswitch = {
  #     id = 4000;
  #     interface = "enp4s0";
  #   };
  # };

  #   # https://docs.hetzner.com/robot/dedicated-server/network/vswitch/
  #   networking.interfaces."enp4s0-vswitch".ipv4.addresses = [
  #     {
  #       address = "192.168.100.1";
  #       prefixLength = 24;
  #       mtu = 1400;
  #     }
  #   ];

  networking.defaultGateway = "148.251.233.1";

  networking.nameservers = [ "8.8.8.8" ];


  # Automatically collect garbage from the Nix store.
  # services.depot.automatic-gc = {
  #   enable = true;
  #   interval = "1 hour";
  #   diskThreshold = 64; # GiB
  #   maxFreed = 128; # GiB
  #   preserveGenerations = "31d";
  # };

}
