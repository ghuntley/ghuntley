# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# `pkgs.srcOnly`.
{ pkgs, ... }:

pkgs.treefmt.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./001-skip-format.patch
  ];
})
