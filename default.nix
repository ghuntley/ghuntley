# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# This file sets up the top-level package set by traversing the package tree
# (see //third_party/readTree for details) and constructing a matching attribute set
# tree.

{ nixpkgsBisectPath ? null
, parentTargetMap ? null
, nixpkgsConfig ? { }
, localSystem ? builtins.currentSystem
, ...
}@args:

let
  inherit (builtins) filter;

  readTree = import ./nix/readTree { };

  # Disallow access to //users from other depot parts.
  patternsFilter = readTree.restrictFolder {
    folder = "patterns";
    reason = ''
      Code under //patterns is not considered stable or dependable in the
      wider depot context. If a project under //patterns is required by
      something else, please move it to a different depot path.
    '';

    exceptions = [
    ];
  };

  compSciFilter = readTree.restrictFolder {
    folder = "compsci";
    reason = ''
      Code under //compsci is not considered stable or dependable in the
      wider depot context. If a project under //compsci is required by
      something else, please move it to a different depot path.
    '';

    exceptions = [
    ];
  };

  readDepot = depotArgs:
    readTree {
      args = depotArgs;
      path = ./.;
      filter = parts: args: patternsFilter parts (compSciFilter parts args);
      scopedArgs = {
        __findFile = _: _: throw "DEPOT: Do not import from NIX_PATH in the depot!";
        builtins = builtins // {
          currentSystem = throw "DEPOT: Use localSystem from the readTree args instead of builtins.currentSystem!";
        };
      };
    };

  # To determine build targets, we walk through the depot tree and
  # fetch attributes that were imported by readTree and are buildable.
  #
  # Any build target that contains `meta.ci.skip = true` will be skipped.

  # Is this tree node eligible for build inclusion?
  eligible = node: (node ? outPath) && !(node.meta.ci.skip or false);

in
readTree.fix (self:
(readDepot {
  inherit localSystem;
  depot = self;

  # Pass third_party as 'pkgs' (for compatibility with external
  # imports for certain subdirectories)
  pkgs = self.third_party.nixpkgs;

  # Expose lib attribute to packages.
  lib = self.third_party.nixpkgs.lib;

  # Pass arguments passed to the entire depot through, for packages
  # that would like to add functionality based on this.
  #
  # Note that it is intended for exceptional circumstance, such as
  # debugging by bisecting nixpkgs.
  externalArgs = args;
}) // {
  # Make the path to the depot available for things that might need it
  # (e.g. NixOS module inclusions)
  path = self.third_party.nixpkgs.lib.cleanSourceWith {
    name = "depot";
    src = ./.;
    filter = self.third_party.nixpkgs.lib.cleanSourceFilter;
  };

  # List of all buildable targets, for CI purposes.
  #
  # Note: To prevent infinite recursion, this *must* be a nested
  # attribute set (which does not have a __readTree attribute).
  ci.targets = readTree.gather eligible (self // {
    # remove the pipelines themselves from the set over which to
    # generate pipelines because that also leads to infinite
    # recursion.
    ops = self.ops // { pipelines = null; };

    # remove nixpkgs from the set, for obvious reasons.
    third_party = self.third_party // { nixpkgs = null; };
  });

  # Derivation that gcroots all depot targets.
  ci.gcroot = with self.third_party.nixpkgs;
    makeSetupHook
      {
        name = "depot-gcroot";
        deps = self.ci.targets;
      }
      emptyFile;
})
