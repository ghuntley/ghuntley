# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# This file defines the root of all external dependency imports (i.e.
# third-party code) in the package tree.
#
# There are two categories of third-party programs:
#
# 1) Programs in nixpkgs, the NixOS package set. For these, you might
#    want to look at //third_party/nixpkgs (for the package set
#    imports) and //third_party/overlays (for modifications in these
#    imported package sets).
#
# 2) Third-party software packaged in this repository. This is all
#    other folders below //third_party, other than the ones mentioned
#    above.

{ pkgs, depot, ... }:

{
  # Expose a partially applied NixOS, expecting an attribute set with
  # a `configuration` key. Exposing it like this makes it possible to
  # modify some of the base configuration used by NixOS.
  #
  # This partially reimplements the code in
  # <nixpkgs/nixos/default.nix> as we need to modify its internals to
  # be able to pass `specialArgs`. We depend on this because `depot`
  # needs to be partially evaluated in NixOS configuration before
  # module imports are resolved.
  nixos =
    { configuration, specialArgs ? { }, system ? builtins.currentSystem, ... }:
    let
      eval = import (pkgs.path + "/nixos/lib/eval-config.nix") {
        inherit specialArgs system;
        modules = [
          configuration
          (import (depot.path.origSrc + "/ops/nixos-modules/defaults.nix"))
        ];
      };

      # This is for `nixos-rebuild build-vm'.
      vmConfig = (import (pkgs.path + "/nixos/lib/eval-config.nix") {
        inherit specialArgs system;
        modules = [
          configuration
          (pkgs.path + "/nixos/modules/virtualisation/qemu-vm.nix")
        ];
      }).config;
    in
    {
      inherit (eval) pkgs config options;
      system = eval.config.system.build.toplevel;
      vm = vmConfig.system.build.vm;
    };
}
