# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ ... }:

let withAll = keys: keys // { all = builtins.attrValues keys; };
in
withAll {
  one-password = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR ghuntley@ghuntley.com";
}
