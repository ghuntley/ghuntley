# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  boot.extraModprobeConfig = "options kvm_intel nested=1";
  security.polkit.enable = true;

  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.onBoot = "start";
  virtualisation.libvirtd.onShutdown = "suspend";
  virtualisation.libvirtd.allowedBridges = [ "br0" ];

  environment.systemPackages = with pkgs; [
    qemu_kvm
    libguestfs
    virt-manager
  ];
}
