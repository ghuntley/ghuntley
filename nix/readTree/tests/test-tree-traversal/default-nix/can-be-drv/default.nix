# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ ... }:
derivation {
  name = "im-a-drv";
  system = builtins.currentSystem;
  builder = "/bin/sh";
  args = [ "-c" ''echo "" > $out'' ];
}
