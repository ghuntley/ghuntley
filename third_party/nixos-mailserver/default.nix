# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  release = "ade37b2765032f83d2d4bd50b6204a40a4c05eb4";
in
pkgs.fetchFromGitLab {
  owner = "simple-nixos-mailserver";
  repo = "nixos-mailserver";
  rev = release;
  url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/${release}/nixos-mailserver-${release}.tar.gz";
  sha256 = "sha256:16fns3bqslzr4jsqw66dix152w0qvm73p6qafn8dfhi81zx7j614";
}
