# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, config, lib, pkgs, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  nixpkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  };

in
{

  boot.initrd.kernelModules = [ "nvidia" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau
      libvdpau-va-gl
      nvidia-vaapi-driver
      vdpauinfo
      libva
      libva-utils
    ];
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
  };

}
