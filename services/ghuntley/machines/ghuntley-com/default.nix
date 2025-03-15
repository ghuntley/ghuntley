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
{
  # Default package should be the VM
  default = machine.vm;

  # Individual components
  vm = machine.vm;
  # iso = machine.iso;
  # url = getIsoUrl machine.iso;

  # PXE boot components
  netboot = machine.netboot;
  netbootIpxe = machine.netbootIpxe;
  kernel = machine.kernel;
  toplevel = machine.toplevel;

  tests = import ./test.nix { inherit depot pkgs; };

  meta.ci.targets = [
    "vm"
    "iso"
    "url"
    "netboot"
    "netbootIpxe"
    "kernel"
    "toplevel"
  ];
}
