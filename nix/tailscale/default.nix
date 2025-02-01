# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# This file defines a Nix helper function to create Tailscale ACL files.
#
# https://tailscale.com/kb/1018/install-acls

{ depot, pkgs, ... }:

with depot.nix.yants;

let
  inherit (builtins) toFile toJSON;

  acl = struct "acl" {
    Action = enum [ "accept" "reject" ];
    Users = list string;
    Ports = list string;
  };

  acls = list entry;

  aclConfig = struct "aclConfig" {
    # Static group mappings from group names to lists of users
    Groups = option (attrs (list string));

    # Hostname aliases to use in place of IPs
    Hosts = option (attrs string);

    # Actual ACL entries
    ACLs = list acl;
  };
in
config: pkgs.writeText "tailscale-acl.json" (toJSON (aclConfig config))
