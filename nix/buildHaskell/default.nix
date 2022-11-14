# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ pkgs, ... }:

{
  # Create a nix-shell for Haskell development.
  shell = { deps }:
    let
      ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: deps hpkgs);
    in
    pkgs.mkShell {
      buildInputs = [ ghc ];
    };

  # Build a Haskell executable. This assumes a project directory with a
  # top-level Main.hs.
  # - `name`: You can find the result at ./result/$name
  # - `srcs`: Will be passed to `srcs` field of `pkgs.stdenv.mkDerivation`.
  # - `deps`: A function that accepts `hpkgs` and returns a list of Haskell
  # - `ghcExtensions`: A list of strings representing the language extensions to
  #   use.
  program = { name, srcs, deps, ghcExtensions }:
    let
      ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: deps hpkgs);
    in
    pkgs.stdenv.mkDerivation {
      name = name;
      buildInputs = [ ];
      srcs = srcs;
      buildPhase = ''
        ${ghc}/bin/ghc -Wall Main.hs ${pkgs.lib.concatMapStrings (x: "-X${x} ") ghcExtensions}
      '';
      installPhase = ''
        mkdir -p $out && mv Main $out/${name}
      '';
    };
}
