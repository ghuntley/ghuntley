# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
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
    options = ["--edition", "2021"]
    includes = [ "*.rs" ]
  '';

  # Script to check for .skip-format files and filter paths
  filterScript = pkgs.writeShellScript "filter-paths" ''
    # Function to check if a path should be skipped
    should_skip() {
      local path="$1"
      while [[ "$path" != "." && "$path" != "/" ]]; do
        if [[ -f "$path/.skip-format" ]]; then
          return 0
        fi
        path="$(dirname "$path")"
      done
      return 1
    }

    # Filter paths that should be formatted
    filter_paths() {
      local paths=("$@")
      local filtered_paths=()

      for path in "''${paths[@]}"; do
        if ! should_skip "$path"; then
          filtered_paths+=("$path")
        fi
      done

      echo "''${filtered_paths[@]}"
    }

    # Get filtered paths
    FILTERED_PATHS=$(filter_paths "$@")

    # If no paths remain after filtering, exit successfully
    if [[ -z "$FILTERED_PATHS" ]]; then
      exit 0
    fi

    # Run treefmt with filtered paths
    exec ${pkgs.treefmt}/bin/treefmt \
      --config-file ${config} \
      --tree-root $(${pkgs.git}/bin/git rev-parse --show-toplevel) \
      $FILTERED_PATHS
  '';

  # helper tool for formatting the depot interactively
  depot-fmt = pkgs.writeShellScriptBin "depot-fmt" ''
    exec ${filterScript} "''${@}"
  '';

  # wrapper script for running formatting checks in CI
  check = pkgs.writeShellScript "depot-fmt-check" ''
    ${filterScript} . \
      --clear-cache \
      --fail-on-change
  '';
in
depot-fmt.overrideAttrs (_: {
  passthru.meta.ci.extraSteps.check = {
    label = "depot formatting check";
    command = check;
    alwaysRun = true;
  };
})
