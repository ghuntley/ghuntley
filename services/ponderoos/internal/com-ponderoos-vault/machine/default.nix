# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  machine = import ./vm.nix { inherit depot pkgs; };
in
rec {
  vm = machine.vm;

  tests = {
    vault = import ./test.nix { inherit depot pkgs; };
  };

  meta.ci = {
    inherit vm tests;
  };
}
