# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Defines an overlay for overriding Haskell packages, for example to
# avoid breakage currently present in nixpkgs or to modify package
# versions.

{ lib, ... }:

self: super: # overlay parameters for the nixpkgs overlay

let
  overrides = hsSelf: hsSuper:
    with self.haskell.lib.compose;
    {
      # No overrides for the default package set necessary at the moment
    };
in
{
  haskellPackages = super.haskellPackages.override { inherit overrides; };

  haskell = lib.recursiveUpdate super.haskell {
    packages.ghc8107 = super.haskell.packages.ghc8107.override {
      overrides = lib.composeExtensions overrides (hsSelf: hsSuper:
        with self.haskell.lib.compose;
        {
          # example = hsSelf.callPackage ./extra-pkgs/example.nix { };
        });
    };
  };
}
