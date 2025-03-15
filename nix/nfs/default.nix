# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Library for NFS mount configuration
# Provides utilities for creating standardized NFS mounts

{ lib, ... }:

{
  # makeNFSMount :: { nfsServer :: String, nfsPath :: String } -> AttrSet
  # Creates a standard NFS mount configuration with optimized parameters
  # Arguments:
  #   nfsServer: The IP address or hostname of the NFS server
  #   nfsPath: The path on the NFS server to mount
  # Returns an attribute set with device, fsType and options for use in fileSystems.*
  makeNFSMount = { nfsServer, nfsPath }: {
    device = "${nfsServer}:${nfsPath}";
    fsType = "nfs";
    options = [
      "noatime"
      "nodiratime"
      "rsize=1048576"
      "wsize=1048576"
      "actimeo=600"
      "timeo=600"
      "retrans=2"
      "vers=4.2"
      "rw"
      "x-systemd.requires=network-online.target"
      "x-systemd.after=network-online.target"
      "x-systemd.required-by=multi-user.target"
      "x-systemd.before=multi-user.target"
      "_netdev"
    ];
  };
}
