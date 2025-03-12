# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);

in
{
  imports = [
    (mod "default-imports.nix")
    (mod "pkgs-desktop.nix")

    (mod "automatic-nix-gc.nix")

    (mod "boot.nix")
    (mod "sshd.nix")

    (mod "netdata.nix")

    (mod "mdadm.nix")
    (mod "nvme.nix")
    (mod "smartd.nix")
    (mod "zfs.nix")

    (mod "microcode.nix")

  ];

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.auto-cpufreq.enable = true;
  #services.auto-cpufreq.settings = {
  #   ideapad_laptop_conservation_mode = true;
  #};
  environment.systemPackages = with pkgs; [
    auto-cpufreq
  ];


  services.logind.lidSwitch = "suspend-then-hibernate";
  services.logind.extraConfig = ''
    HandlePowerKey=suspend
  '';

}
