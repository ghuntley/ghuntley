# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# This file sets up the top-level package set by traversing the package tree
# (see //nix/readTree for details) and constructing a matching attribute set
# tree.

{ nixpkgsBisectPath ? null
, parentTargetMap ? null
, nixpkgsConfig ? { }
, localSystem ? builtins.currentSystem
, crossSystem ? null
, ...
}@args:

let
  inherit (builtins)
    filter
    ;

  readTree = import ./nix/readTree { };

  # Disallow access to //users from other depot parts.
  usersFilter = readTree.restrictFolder {
    folder = "users";
    reason = ''
      Code under //users is not considered stable or dependable in the
      wider depot context. If a project under //users is required by
      something else, please move it to a different depot path.
    '';

    exceptions = [
      # overalls is allowed to access //users for several reasons:
      #
      # 1. User SSH keys are set in //users.
      [ "infra" "machines" "overalls" ]

      # Due to evaluation order this also affects these targets.
      # TODO(tazjin): Can this one be removed somehow?
      [ "infra" "nixos" ]
      [ "infra" "machines" "all-systems" ]
    ];
  };

  # Disallow access to //corp from other depot parts.
  corpFilter = readTree.restrictFolder {
    folder = "corp";
    reason = ''
      Code under //corp may use incompatible licensing terms with
      other depot parts and should not be used anywhere else.
    '';

    exceptions = [
      # For the same reason as above, overalls is exempt to serve the
      # corp website.
      [ "infra" "machines" "overalls" ]
      [ "infra" "nixos" ]
      [ "infra" "machines" "all-systems" ]
    ];
  };

  readDepot = depotArgs: readTree {
    args = depotArgs;
    path = ./.;
    filter = parts: args: corpFilter parts (usersFilter parts args);
    scopedArgs = {
      __findFile = _: _: throw "Do not import from NIX_PATH in the depot!";
      builtins = builtins // {
        currentSystem = throw "Use localSystem from the readTree args instead of builtins.currentSystem!";
      };
    };
  };

  # To determine build targets, we walk through the depot tree and
  # fetch attributes that were imported by readTree and are buildable.
  #
  # Any build target that contains `meta.ci.skip = true` or is marked
  # broken will be skipped.
  # Is this tree node eligible for build inclusion?
  eligible = node: (node ? outPath) && !(node.meta.ci.skip or (node.meta.broken or false));

in
readTree.fix (self: (readDepot {
  inherit localSystem crossSystem;
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

  # Additionally targets can be excluded from CI by adding them to the
  # list below.
  ci.excluded = [
    #self.corp.xyz
  ];

  # List of all buildable targets, for CI purposes.
  #
  # Note: To prevent infinite recursion, this *must* be a nested
  # attribute set (which does not have a __readTree attribute).
  ci.targets = readTree.gather
    (t: (eligible t) && (!builtins.elem t self.ci.excluded))
    (self // {
      # remove the pipelines themselves from the set over which to
      # generate pipelines because that also leads to infinite
      # recursion.
      infra = self.infra // { pipelines = null; };
    });

  # Derivation that gcroots all depot targets.
  ci.gcroot = with self.third_party.nixpkgs; writeText "depot-gcroot"
    (builtins.concatStringsSep "\n"
      (lib.flatten
        (map (p: map (o: p.${o}) p.outputs or [ ]) # list all outputs of each drv
          self.ci.targets)));
})
