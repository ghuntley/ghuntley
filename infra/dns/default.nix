# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ depot, lib, pkgs, ... }:

depot.nix.readTree.drvTargets rec {
  terraform = pkgs.terraform.withPlugins (p: [
    p.ovh
    p.cloudflare
  ]);

  validate = depot.tools.checks.validateTerraform {
    inherit terraform;
    name = "cloudflare";
    src = lib.cleanSource ./.;
    env.CLOUDFLARE_EMAIL = "ci-dummy";
    env.CLOUDFLARE_API_KEY = "ci-dummy";
    env.AWS_ACCESS_KEY_ID = "ci-dummy";
    env.AWS_SECRET_ACCESS_KEY = "ci-dummy";
  };

  meta.license = lib.licenses.mit;
}
