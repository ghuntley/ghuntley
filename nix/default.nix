# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Main entry point for depot's Nix libraries

{ depot, lib, ... }@args:

{
  yants = import ./yants args;
  runTestsuite = import ./runTestsuite args;
  buildBazelPackageNG = import ./buildBazelPackageNG args;
  buildHaskell = import ./buildHaskell args;
  buildGo = import ./buildGo args;
  harmonia = import ./harmonia args;
  readTree = import ./readTree args;
  runExecline = import ./runExecline args;
  tailscale = import ./tailscale args;
  escapeExecline = import ./escapeExecline args;
  getBins = import ./getBins args;
  buildkite = import ./buildkite args;
  nfs = import ./nfs args;
}
