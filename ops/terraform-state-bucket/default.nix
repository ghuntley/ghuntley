# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ depot, lib, pkgs, ... }:

depot.nix.readTree.drvTargets rec {
  terraform = pkgs.terraform.withPlugins (p: [
    p.google
  ]);

  validate = depot.tools.checks.validateTerraform {
    inherit terraform;
    name = "google";
    src = lib.cleanSource ./.;
  };

  meta.license = lib.licenses.mit;
}
