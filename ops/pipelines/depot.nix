# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# This file configures the primary build pipeline used for the
# top-level list of depot targets.
{ depot, pkgs, externalArgs, ... }:

let
  # Protobuf check step which validates that changes to .proto files
  # between revisions don't cause backwards-incompatible or otherwise
  # flawed changes.
  protoCheck = {
    command = "${depot.nix.bufCheck}/bin/ci-buf-check";
    label = ":water_buffalo:";
  };

  pipeline = depot.nix.buildkite.mkPipeline {
    headBranch = "refs/heads/canon";
    drvTargets = depot.ci.targets;
    additionalSteps = [ protoCheck ];

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
      }
    ];
  };

  drvmap = depot.nix.buildkite.mkDrvmap depot.ci.targets;
in
pkgs.runCommandNoCC "depot-pipeline" { } ''
  mkdir $out
  cp -r ${pipeline}/* $out
  cp ${drvmap} $out/drvmap.json
''
