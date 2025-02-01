# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# This file configures the primary build pipeline used for the
# top-level list of depot targets.
{ depot, pkgs, externalArgs, ... }:

let
  pipeline = depot.nix.buildkite.mkPipeline {
    headBranch = "refs/heads/canon";
    drvTargets = depot.ci.targets;

    parentTargetMap =
      if (externalArgs ? parentTargetMap)
      then builtins.fromJSON (builtins.readFile externalArgs.parentTargetMap)
      else { };

    postBuildSteps = [
      # After successful builds, create a gcroot for builds on canon.
      #
      # This anchors *most* of the depot, in practice it's unimportant
      # if there is a build race and we get +-1 of the targets.
      #
      # Unfortunately this requires a third evaluation of the graph, but
      # since it happens after :duck: it should not affect the timing of
      # status reporting back to Gerrit.
      {
        label = ":anchor:";
        branches = "refs/heads/canon";
        command = ''
          nix-build -A ci.gcroot --out-link /nix/var/nix/gcroots/depot/canon
        '';

        # Ensure that anchoring happens on overalls, so that nix-cache-ponderoos.com
        # always has the full cache. Unanchored machines may garbage collect live
        # paths.
        agents.hostname = "overalls";
      }
    ];
  };

  drvmap = depot.nix.buildkite.mkDrvmap depot.ci.targets;
in
pkgs.runCommand "depot-pipeline" { } ''
  mkdir $out
  cp -r ${pipeline}/* $out
  cp ${drvmap} $out/drvmap.json
''
