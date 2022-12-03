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
    (mod "cache.nix")
    (mod "documentation.nix")
    (mod "fail2ban.nix")
    (mod "i18n.nix")
    (mod "known-hosts.nix")
    (mod "pkgs.nix")
    (mod "sudo.nix")
    (mod "sysctl.nix")
    (mod "tailscale.nix")
    (mod "time.nix")
    (mod "timezone.nix")
    (mod "users.nix")

    (depot.third_party.agenix.src + "/modules/age.nix")

  ];
