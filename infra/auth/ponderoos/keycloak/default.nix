# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot, lib, pkgs, ... }:

depot.nix.readTree.drvTargets rec {
  # Provide a Terraform wrapper with the right provider installed.
  terraform = pkgs.terraform.withPlugins (p: [
    p.keycloak
  ]);

  validate = depot.tools.checks.validateTerraform {
    inherit terraform;
    name = "ponderoos-terraform-keycloak";
    src = lib.cleanSource ./.;
  };
}
