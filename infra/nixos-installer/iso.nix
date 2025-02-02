# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot ? null
, targetSystem ? null
, nixos ? null
, ...
} @ args:

let
  inherit (depot.third_party.nixpkgs) lib;

  # Create ISO configuration
  isoNixos = depot.third_party.nixos {
    configuration = { ... }: {
      imports = [
        # Import base module to ensure consistent depot environment
        depot.infra.nixos.baseModule

        # Import the installation media module
        "${depot.third_party.nixpkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      ] ++ lib.optionals (targetSystem != null) [
        # Import target system configuration if provided
        targetSystem
        # Override target system settings for ISO
        ({ ... }: {
          # Override filesystem settings
          fileSystems = lib.mkForce {
            "/" = {
              device = "none";
              fsType = "tmpfs";
              options = [ "defaults" "mode=0755" ];
            };
          };

          # Override boot loader settings
          boot.loader = {
            timeout = lib.mkForce 10;
            grub.enable = lib.mkForce false;
          };

          # Override networking settings
          networking = {
            wireless.enable = lib.mkForce false;
            networkmanager.enable = lib.mkForce true;
          };
        })
      ];

      # ISO-specific configuration
      isoImage.makeEfiBootable = true;
      isoImage.makeUsbBootable = true;

      # Add installation tools
      environment.systemPackages = with depot.third_party.nixpkgs; [
        git
        vim
        parted
        gptfdisk
      ];

      system.stateVersion = lib.mkIf (targetSystem != null) (lib.mkDefault "23.11");
    };

    specialArgs = {
      inherit (args) depot;
    };
  };
in
if targetSystem != null
then isoNixos.config.system.build.isoImage
else isoNixos  # Return the default ISO if no target system specified
