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
      }
        };
    };

    nixpkgs.config.allowUnfree = true;

  }
