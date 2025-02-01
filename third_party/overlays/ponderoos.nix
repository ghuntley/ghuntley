# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


# This overlay is used to make TVL-specific modifications in the
# nixpkgs tree, where required.
{ lib, depot, localSystem, ... }:

self: super:
depot.nix.readTree.drvTargets {

  home-manager = super.home-manager.overrideAttrs (_: {
    src = depot.third_party.sources.home-manager;
    version = "git-"
      + builtins.substring 0 7 depot.third_party.sources.home-manager.rev;
  });

  # dottime support for notmuch
  notmuch = super.notmuch.overrideAttrs (old: {
    passthru = old.passthru // {
      patches = old.patches ++ [ ./patches/notmuch-dottime.patch ];
    };
  });

  # Avoid builds of mkShell derivations in CI.
  mkShell = super.lib.makeOverridable (args: (super.mkShell args).overrideAttrs (_: {
    passthru = {
      meta.ci.skip = true;
    };
  }));

  crate2nix = super.crate2nix.overrideAttrs (old: {
    patches = old.patches or [ ] ++ [
      # TODO(Kranzes): Remove in next release.
      ./patches/crate2nix-0001-Fix-Use-mkDerivation-with-src-instead-of-runCommand.patch
      # https://github.com/nix-community/crate2nix/pull/301
      ./patches/crate2nix-tests-debug.patch
    ];
  });

  # https://gcc.gnu.org/gcc-14/porting_to.html#warnings-as-errors
  thttpd = super.thttpd.overrideAttrs (oldAttrs: {
    NIX_CFLAGS_COMPILE = oldAttrs.NIX_CFLAGS_COMPILE or [ ] ++ [
      "-Wno-error=implicit-int"
      "-Wno-error=implicit-function-declaration"
    ];
  });

}
