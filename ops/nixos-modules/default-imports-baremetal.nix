# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);

in
{
  imports = [
    (mod "default-imports.nix")

    (mod "nginx/self-redirect.nix")

    (mod "nvme.nix")
    (mod "mdadm.nix")
    (mod "smartd.nix")
    (mod "zfs.nix")

  ];
