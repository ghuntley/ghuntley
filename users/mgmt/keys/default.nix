# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, ... }:

let withAll = keys: keys // { all = builtins.attrValues keys; };
in
withAll {
  mgmt = depot.users.ghuntley.keys.one-password;
}
