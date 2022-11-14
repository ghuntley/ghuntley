# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, depot, ... }: {
  environment.systemPackages = [
    pkgs.ack
    pkgs.bind
    pkgs.cachix
    pkgs.curl
    pkgs.direnv
    pkgs.dos2unix
    pkgs.git-lfs
    pkgs.gitAndTools.gitFull
    pkgs.htop
    pkgs.iftop
    pkgs.inetutils
    pkgs.iotop
    pkgs.lsof
    pkgs.neovim
    pkgs.ntp
    pkgs.opentelemetry-collector
    pkgs.p7zip
    pkgs.rpl
    pkgs.tmux
    pkgs.tree
    pkgs.unzip
    pkgs.wget
    pkgs.zip
    depot.third_party.agenix.cli
  ];


  programs.mtr.enable = true;

  nixpkgs.config.allowUnfree = true;

}
