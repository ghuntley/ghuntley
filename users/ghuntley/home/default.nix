# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ pkgs, depot, lib, ... }:

with lib;

rec {
  home = confPath: (import (pkgs.home-manager.src + "/modules") {
    inherit pkgs;

    configuration = { config, lib, ... }: {
      imports = [ confPath ];
      lib.depot = depot;

      # home-manager exposes no API to override the package set that
      # is used, unless called from the NixOS module.
      #
      # To get around it, the module argument is overridden here.
      _module.args.pkgs = mkForce pkgs;
    };
  });

  crowbar = home ./machines/crowbar.nix;
  crowbarHome = crowbar.activation-script;

  prybar = home ./machines/prybar.nix;
  prybarHome = crowbar.activation-script;

  meta.ci.targets = [
    "crowbar"
    "crowbarHome"
    "prybar"
    "prybarHome"
  ];
}
