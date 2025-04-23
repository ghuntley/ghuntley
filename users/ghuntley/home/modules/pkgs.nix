# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    delta
    btop
    curl
    tmux
    wget
    unzip
    wget
    mosh
    nodejs_23
  ];

  programs.jq.enable = true;

  programs.bat.enable = true;

  programs.command-not-found.enable = true;

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.gh = {
    enable = true;
    settings = {
      editor = "vim";
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  programs.lazygit.enable = true;
}
