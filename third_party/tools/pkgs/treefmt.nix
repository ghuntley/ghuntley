# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{pkgs}:
pkgs.symlinkJoin {
  name = "treefmt-with-formatters";
  paths = [pkgs.treefmt pkgs.nodePackages.prettier pkgs.rustfmt pkgs.alejandra];
  buildInputs = [pkgs.makeWrapper];
  postBuild = ''
    wrapProgram $out/bin/treefmt \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.nodePackages.prettier pkgs.rustfmt pkgs.alejandra]}
  '';
}
