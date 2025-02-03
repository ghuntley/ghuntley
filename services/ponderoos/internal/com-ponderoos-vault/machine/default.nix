# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ nixpkgs ? import <nixpkgs> { } }:

let
  machine = import ./vm.nix {
    inherit nixpkgs;
  };
in
{
  tests = {
    vault = import ./test.nix { inherit nixpkgs; };
  };

  tests = {
    machine = machine.vm;
  };
}
