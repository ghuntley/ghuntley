# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ pkgs, depot, ... }:

let
  src = depot.third_party.sources.flake-compat;

  microvm = import src {
    inherit pkgs;
  };
in
{
  inherit src;
  cli = microvm.microvm;
}
