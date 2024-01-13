# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ depot, pkgs, lib, ... }:
let
  runExecline = import ./runExecline.nix {
    inherit (pkgs) stdenv;
    inherit (depot.nix) escapeExecline getBins;
    inherit pkgs lib;
  };

  runExeclineLocal = name: args: execline:
    runExecline name
      (args // {
        derivationArgs = args.derivationArgs or { } // {
          preferLocalBuild = true;
          allowSubstitutes = false;
        };
      })
      execline;

  tests = import ./tests.nix {
    inherit runExecline runExeclineLocal;
    inherit (depot.nix) getBins writeScript;
    inherit (pkgs) stdenv coreutils;
    inherit pkgs;
  };

in
{
  __functor = _: runExecline;
  local = runExeclineLocal;
  inherit tests;
}
