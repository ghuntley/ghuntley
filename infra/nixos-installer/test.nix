# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot ? import ../../default.nix { }
, targetSystem ? null
, pkgs ? depot.third_party.nixpkgs
, lib ? pkgs.lib
, ...
} @ args:

let
  # Import the ISO configuration
  iso = import ./iso.nix {
    inherit depot targetSystem;
  };

  # Get nixpkgs path safely
  nixpkgsPath = toString pkgs.path;

  # Get hostname from target system or use default
  hostname =
    if targetSystem != null
    then targetSystem.networking.hostName or "nixos"
    else "nixos";
in
pkgs.nixosTest {
  name = "${hostname}-installer-test";

  # Enable OCR for screen text recognition
  enableOCR = true;

  nodes.machine = { config, pkgs, ... }: {
    virtualisation = {
      cores = 2;
      memorySize = 4096;
      qemu.options = [
        "-bios ${pkgs.OVMF.fd}/FV/OVMF.fd"
      ];
    };

    imports = [
      depot.infra.nixos.baseModule
      "${nixpkgsPath}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ];

    # ISO-specific configuration
    isoImage.makeEfiBootable = true;
    isoImage.makeUsbBootable = true;
    isoImage.isoName = iso.config.isoImage.isoName;

    # System configuration
    boot.loader = {
      timeout = 10;
      grub.enable = false;
    };

    networking = {
      wireless.enable = false;
      networkmanager.enable = true;
    };

    # Use pkgs from the module context
    environment.systemPackages = with pkgs; [
      git
      vim
      parted
      gptfdisk
    ];

    # User configuration
    users.mutableUsers = lib.mkForce true;
    users.users.root = {
      # Override all password-related options to avoid conflicts
      password = lib.mkForce "";
      hashedPassword = lib.mkForce null;
      hashedPasswordFile = lib.mkForce null;
      initialPassword = lib.mkForce null;
      initialHashedPassword = lib.mkForce null;
    };

    # Disable auto-login
    services.getty.autologinUser = lib.mkForce null;

    # Ensure system state version is set
    system.stateVersion = "23.11";
  };

  testScript = ''
    # Start the machine and wait for boot
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Switch to TTY1 explicitly
    machine.send_key("alt-f1")

    # Send enter a few times to ensure we get a fresh prompt
    machine.send_chars("\n\n\n")

    # Wait for login prompt
    machine.wait_for_text("login:")

    # Log in as root (no password needed in live environment)
    machine.send_chars("root\n")
    machine.wait_for_text("root@")

    # Basic system check
    machine.succeed("uname -a")

    # Test that we can run nix commands
    machine.succeed("nix-env --version")

    # Test that required tools are available
    machine.succeed("which git")
    machine.succeed("which vim")
    machine.succeed("which parted")
    machine.succeed("which gdisk")
    machine.succeed("which firefox")

    # Keep the machine running for a while to allow manual inspection if needed
    machine.sleep(10)
  '';
}
