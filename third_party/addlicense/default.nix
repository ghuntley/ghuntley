# Copyright (c) 2024 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  # External dependencies
  doublestar = depot.nix.buildGo.package {
    name = "doublestar";
    path = "github.com/bmatcuk/doublestar/v4";
    srcs = let
      src = pkgs.fetchFromGitHub {
        owner = "bmatcuk";
        repo = "doublestar";
        rev = "v4.6.1";
        sha256 = "12rf4a9isgg2nh927gikgbmyaynaqp4kjahgscb4qnr04m3vpr41";
      };
    in [
      "${src}/doublestar.go"
      "${src}/glob.go"
      "${src}/globoptions.go"
      "${src}/globwalk.go"
      "${src}/match.go"
      "${src}/utils.go"
      "${src}/validate.go"
    ];
  };

  errgroup = depot.nix.buildGo.package {
    name = "errgroup";
    path = "golang.org/x/sync/errgroup";
    srcs = let
      src = pkgs.fetchFromGitHub {
        owner = "golang";
        repo = "sync";
        rev = "036812b2e83c0ddf193dd5a34e034151da389d09"; # v0.1.0
        sha256 = "1gl202py3s4gl6arkaxlf8qa6f0jyyg2f95m6f89qnfmr416h85b";
      };
    in [ "${src}/errgroup/errgroup.go" ];
  };

  # Common source files and dependencies
  commonSrcs = [
    ./main.go
    ./tmpl.go
  ];

  commonDeps = [
    doublestar
    errgroup
  ];

  program = depot.nix.buildGo.program {
    name = "addlicense";
    srcs = commonSrcs;
    deps = commonDeps;
  };

  tests = depot.nix.buildGo.test {
    name = "addlicense";
    path = "addlicense";
    srcs = commonSrcs;
    testSrcs = [ ./main_test.go ];
    deps = commonDeps;
    testFiles = [
      {
        src = ./testdata;
        dest = "testdata";
      }
    ];
    testScript = ''
      # Create a temporary directory for test execution
      TEST_TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TEST_TMPDIR"' EXIT

      # Run tests from the package directory
      cd "$TMPDIR/src/addlicense"
      TMPDIR="$TEST_TMPDIR" ${pkgs.go}/bin/go test -v .
    '';
  };

in {
  inherit program tests;
  default = program;
}
