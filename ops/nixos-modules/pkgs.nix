# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, depot, ... }:

let
  host = "${config.networking.hostName}.${config.networking.domain}";
in
{

  environment.systemPackages = [
    depot.third_party.agenix.cli
    pkgs.bind
    pkgs.cachix
    pkgs.htop
    pkgs.iftop
    pkgs.inetutils
    pkgs.iotop
    pkgs.lazygit
    pkgs.lsof
    pkgs.molly-guard
    pkgs.neovim
    pkgs.nixpkgs-fmt
    pkgs.opentelemetry-collector
    pkgs.starship
    pkgs.tmux
    pkgs.tree
  ];

  programs.bash.interactiveShellInit = ''
    eval "$(starship init bash)"
  '';

  programs.mtr.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;
    config = {
      init = {
        defaultBranch = "trunk";
      };
      user = {
        email = "${host}@noreply.fediversehosting.com";
        name = "${host}";
      };
    };
  };

  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

}
