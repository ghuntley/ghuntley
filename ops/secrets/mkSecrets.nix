# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Expose secrets as part of the tree, making it possible to validate
# their paths at eval time.
#
# Note that encrypted secrets end up in the Nix store, but this is
# fine since they're publicly available anyways.
{ depot, lib, ... }:

let
  inherit (depot.nix.yants)
    attrs
    any
    defun
    list
    path
    restrict
    string
    struct
    ;
  ssh-pubkey = restrict "SSH pubkey" (lib.hasPrefix "ssh-") string;
  agenixSecret = struct "agenixSecret" { publicKeys = list ssh-pubkey; };
in

defun [ path (attrs agenixSecret) (attrs any) ]
  (path: secrets:
  depot.nix.readTree.drvTargets
    # Import each secret into the Nix store
    (builtins.mapAttrs (name: _: "${path}/${name}") secrets))
