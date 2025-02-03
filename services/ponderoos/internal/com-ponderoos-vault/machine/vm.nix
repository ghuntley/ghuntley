# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  nixosSystem = (import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = builtins.currentSystem;
    pkgs = pkgs;
    modules = [
      ({ modulesPath, pkgs, ... }: {
        imports = [
          (modulesPath + "/virtualisation/qemu-vm.nix")
          (modulesPath + "/installer/cd-dvd/iso-image.nix")
        ];

        system.stateVersion = "23.11";

        # Set empty root password
        users.users.root.initialPassword = "";

        virtualisation = {
          memorySize = 2048;
          cores = 2;
          graphics = false;
        };

        services.vault = {
          enable = true;
          package = pkgs.vault;
          address = "127.0.0.1:8200";
          dev = true; # Enable dev mode
          devRootTokenID = "root";
        };

        networking.firewall.allowedTCPPorts = [ 8200 ];

        isoImage.makeEfiBootable = true;
        isoImage.makeUsbBootable = true;
      })
    ];
  }).config;
in
{
  vm = nixosSystem.system.build.vm;
  iso = nixosSystem.system.build.isoImage;
}
