# Copyright (c) 2022 Kevin Cox. All rights reserved.
# SPDX-License-Identifier: Apache2

{ config, pkgs, ... }: {
  hardware.enableAllFirmware = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/vda";

  boot.initrd.kernelModules = [
    "kvm-intel"
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
  ];

  boot.initrd.availableKernelModules = [
    "9p"
    "9pnet_virtio"
    "aesni_intel"
    "ata_piix"
    "cryptd"
    "nvme"
    "sr_mod"
    "uhci_hcd"
    "virtio_blk"
    "virtio_mmio"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
  ];

  fileSystems."/boot" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  boot.initrd.luks.devices.root = {
    device = "/dev/vda2";

    # WARNING: Leaks some metadata, see cryptsetup man page for --allow-discards.
    allowDiscards = true;

    # Set your own key with:
    # cryptsetup luksChangeKey /dev/vda2 --key-file=/dev/zero --keyfile-size=1
    # You can then delete the rest of this block.
    keyFile = "/dev/zero";
    keyFileSize = 1;

    fallbackToPassword = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "ext4";
  };
}
