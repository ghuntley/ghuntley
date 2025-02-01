# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


{ depot, lib, pkgs, ... }:

depot.nix.readTree.drvTargets rec {
  terraform = pkgs.terraform.withPlugins (p: [
    p.buildkite
  ]);

  validate = depot.tools.checks.validateTerraform {
    inherit terraform;
    name = "buildkite";
    src = lib.cleanSource ./.;
    env.BUILDKITE_API_TOKEN = "ci-dummy";
  };
}
