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
    (mod "defaults-binarylane.nix")
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" =
    {
      device = "/dev/mapper/root";
      fsType = "ext4";
    };

  boot.initrd.luks.devices.root = {
    device = "/dev/vda2";

    allowDiscards = true;

    keyFile = "/dev/zero";
    keyFileSize = 1;
    fallbackToPassword = true;
  };

  fileSystems."/boot" =
    {
      device = "/dev/vda1";
      fsType = "ext4";
    };

  swapDevices = [{
    device = "/.swap";
    size = (1024 * 6);
  }];


  networking.hostName = "time";
  networking.domain = "core.corp";

  networking.useDHCP = true;
  networking.interfaces.ens3.useDHCP = true;

  # TODO(security): migrate from public ssh to tailscale only ssh
  networking.firewall.interfaces."ens3".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  services.openssh.enable = true;

  # # Automatically collect garbage from the Nix store.
  services.depot.automatic-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 10; # GiB
    maxFreed = 5; # GiB
    preserveGenerations = "14d";
  };

  system.stateVersion = "22.11";

}
