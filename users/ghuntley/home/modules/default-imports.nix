# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  modulesPath = toString ../modules;
  mod = name: modulesPath + "/${name}";

in
{
  imports = [
    (mod "pkgs.nix")
    (mod "editorconfig.nix")
    (mod "zsh.nix")
    (mod "bat.nix")
    (mod "gdb.nix")
    (mod "git.nix")
    (mod "neovim.nix")
    (mod "psql.nix")
    (mod "readline.nix")
    (mod "tmux.nix")
    (mod "shell-alias-deploy-home.nix")
  ];
}
