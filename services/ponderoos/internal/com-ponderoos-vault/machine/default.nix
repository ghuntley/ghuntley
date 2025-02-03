# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

with depot.nix.harmonia;

let
  machine = import ./vm.nix { inherit depot pkgs; };

  # Extract just the hash part from the store path
  isoHash = builtins.substring 11 32 (toString machine.iso);
  isoName = builtins.baseNameOf (toString machine.iso);
in
rec {
  vm = machine.vm;
  iso = machine.iso;
  url = getIsoUrl iso;

  tests = {
    machine = import ./test.nix { inherit depot pkgs; };
  };

  meta.ci = {
    inherit vm tests iso;
  };
}
