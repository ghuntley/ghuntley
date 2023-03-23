# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Builds treefmt for depot, with a hardcoded configuration that
# includes the right paths to formatters.
{ depot
, pkgs
, ...
}:

let
  # terraform fmt can't handle multiple paths at once, but treefmt
  # expects this
  terraformat = pkgs.writeShellScript "terraformat" ''
    echo "$@" >/tmp/a
  '';

  config = pkgs.writeText "depot-treefmt-config" ''

    [formatter.go]
    command = "${pkgs.go}/bin/gofmt"
    options = [ "-w" ]
    includes = ["*.go"]

    [formatter.hs]
    command = "${pkgs.ormolu}/bin/ormolu"
    includes = ["*.hs"]

    [formatter.nix]
    command = "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt"
    includes = [ "*.nix" ]

    [formatter.py]
    command = "${pkgs.python3.pkgs.black}/bin/black"
    includes = [ "*.py" ]

    [formatter.sh]
    command = "${pkgs.shfmt}/bin/shfmt"
    includes = [ "*.sh" ]

    [formatter.tf]
    command = "${terraformat}"
    includes = [ "*.tf" ]

    [formatter.rust]
    command = "${pkgs.rustfmt}/bin/rustfmt"
    includes = [ "*.rs" ]
  '';

  # helper tool for formatting the depot interactively
  depot-fmt = pkgs.writeShellScriptBin "depot-fmt" ''
    exec ${pkgs.treefmt}/bin/treefmt ''${@} \
      --config-file ${config} \
      --tree-root $(${pkgs.git}/bin/git rev-parse --show-toplevel)
  '';

  # wrapper script for running formatting checks in CI
  check = pkgs.writeShellScript "depot-fmt-check" ''
    ${pkgs.treefmt}/bin/treefmt \
      --clear-cache \
      --fail-on-change \
      --config-file ${config} \
      --tree-root .
  '';
in
depot-fmt.overrideAttrs (_: {
  passthru.meta.ci.extraSteps.check = {
    label = "depot formatting check";
    command = check;
    alwaysRun = true;
  };
})
