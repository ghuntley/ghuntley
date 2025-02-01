# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

let
  configuration = { ... }: {
    imports = [
      (pkgs.path + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      (pkgs.path + "/nixos/modules/installer/cd-dvd/channel.nix")
    ];

    networking.networkmanager.enable = true;
    networking.useDHCP = false;
    networking.firewall.enable = false;
    networking.wireless.enable = lib.mkForce false;
  };
in
(depot.third_party.nixos {
  inherit configuration;
}).config.system.build.isoImage
