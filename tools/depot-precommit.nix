# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  # helper tool for formatting the depot interactively
  depot-precommit = pkgs.writeShellScriptBin "depot-precommit" ''
    exec ${pkgs.pre-commit}/bin/pre-commit run
  '';

  # wrapper script for running pre-commit checks in CI
  check = pkgs.writeShellScriptBin "depot-precommit-check" ''
    exec ${pkgs.pre-commit}/bin/pre-commit run --all-files
  '';

in
depot-precommit.overrideAttrs (_: {
  passthru.meta.ci.extraSteps.check = {
    label = "depot pre-commit check";
    command = check;
    alwaysRun = true;
  };
})
