# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# This file imports the pinned nixpkgs sets and applies relevant
# modifications, such as our overlays.
#
# The actual source pinning happens via niv in //third_party/sources
#
# Note that the attribute exposed by this (third_party.nixpkgs) is
# "special" in that the fixpoint used as readTree's config parameter
# in //default.nix passes this attribute as the `pkgs` argument to all
# readTree derivations.

{ depot ? { }
, externalArgs ? { }
, depotOverlays ? true
, localSystem ? externalArgs.localSystem or builtins.currentSystem
, crossSystem ? externalArgs.crossSystem or localSystem
  # additional overlays to be applied.
  # Useful when calling this file in a view exported from depot.
, additionalOverlays ? [ ]
, ...
}:

let
  # Arguments passed to both the stable nixpkgs and the main, unstable one.
  # Includes everything but overlays which are only passed to unstable nixpkgs.
  commonNixpkgsArgs = {
    # allow users to inject their config into builds (e.g. to test CA derivations)
    config =
      (if externalArgs ? nixpkgsConfig then externalArgs.nixpkgsConfig else { })
      // {
        allowUnfree = true;
        allowUnfreeRedistributable = true;
        allowBroken = true;
        # Forbids our meta.ci attribute
        # https://github.com/NixOS/nixpkgs/pull/191171#issuecomment-1260650771
        checkMeta = false;
        permittedInsecurePackages = [
          "dotnet-sdk-6.0.428" # Sonarr's .NET SDK dependency
          "aspnetcore-runtime-6.0.36" # Sonarr's .NET SDK dependency
          "python3.12-django-3.1.14" # Required by archivebox
          "python3.12-youtube-dl-2021.12.17" # Required by archivebox for video archiving
        ];
      };

    inherit localSystem crossSystem;
  };

  # import the nixos-unstable package set, or optionally use the
  # source (e.g. a path) specified by the `nixpkgsBisectPath`
  # argument. This is intended for use-cases where the depot is
  # bisected against nixpkgs to find the root cause of an issue in a
  # channel bump.
  nixpkgsSrc = externalArgs.nixpkgsBisectPath or depot.third_party.sources.nixpkgs;

  # Stable package set is imported, but not exposed, to overlay
  # required packages into the unstable set.
  stableNixpkgs = import depot.third_party.sources.nixpkgs-stable commonNixpkgsArgs;

  # Overlay for packages that should come from the stable channel
  # instead (e.g. because something is broken in unstable).
  # Use `stableNixpkgs` from above.
  stableOverlay = _unstableSelf: unstableSuper: {
    # newer trunk fails somewhere within reqwest, trying to read a mystery file
    trunk = stableNixpkgs.trunk;

    # the big lisp package change breaks everything in //3p/lisp, undo it for now.
    lispPackages = stableNixpkgs.lispPackages;
  };

  # Overlay to expose the nixpkgs commits we are using to other Nix code.
  commitsOverlay = _: _: {
    nixpkgsCommits = {
      unstable = depot.third_party.sources.nixpkgs.rev;
      stable = depot.third_party.sources.nixpkgs-stable.rev;
    };
  };
in
import nixpkgsSrc (commonNixpkgsArgs // {
  overlays = [
    commitsOverlay
    stableOverlay
  ] ++ (if depotOverlays then [
    depot.third_party.overlays.ponderoos
    (import depot.third_party.sources.rust-overlay)
  ] else [ ] ++ additionalOverlays);
})
