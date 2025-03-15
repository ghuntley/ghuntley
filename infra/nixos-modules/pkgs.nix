# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, depot, ... }:

let
  host = "${config.networking.hostName}.${config.networking.domain}";
  nixpkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  };
in
{

  environment.systemPackages = [
    depot.third_party.agenix.cli # Age-encrypted secrets management tool
    pkgs.bind # DNS utilities like dig, nslookup, etc.
    pkgs.bitwarden-cli # Bitwarden CLI
    pkgs.btop # Interactive process viewer and system monitor
    pkgs.cachix # Binary cache hosting service for Nix
    pkgs.diff-so-fancy # Git diff output beautifier
    pkgs.direnv # Per-directory environment variable manager
    pkgs.elinks # Text-based web browser
    pkgs.gitAndTools.gitFull # Distributed version control system
    pkgs.iftop # Network bandwidth monitoring tool
    pkgs.inetutils # Collection of common network utilities
    pkgs.iotop # I/O monitoring tool
    pkgs.lazygit # Simple terminal UI for git commands
    pkgs.lsof # Lists open files and processes
    pkgs.molly-guard # Prevents accidental shutdowns/reboots
    pkgs.neovim # Modern, backwards-compatible vim fork
    pkgs.nixpkgs-fmt # Nix code formatter
    pkgs.opentelemetry-collector # Telemetry data collector and processor
    pkgs.pre-commit # Framework for managing git pre-commit hooks
    pkgs.starship # Cross-shell customizable prompt
    pkgs.sqlite # SQL database engine
    pkgs.stow # Symlink farm manager
    pkgs.tmux # Terminal multiplexer
    pkgs.tree # Directory listing as tree structure
  ];

  programs.bash.interactiveShellInit = ''
    eval "$(starship init bash)"
  '';


  services.lorri.enable = true;

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  #programs.home-manager.enable = true;

  programs.neovim.defaultEditor = true;
  programs.neovim.vimAlias = true;

  programs.mtr.enable = true;

  programs.mosh.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;
    config = {
      init = {
        defaultBranch = "trunk";
      };
      user = {
        email = "${host}@noreply.ghuntley.net";
        name = "${host}";
      };
    };
  };
}
