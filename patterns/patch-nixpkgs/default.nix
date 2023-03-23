# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# addlicense with custom patches.
{ pkgs, ... }:

pkgs.addlicense.overrideAttrs
  (old: { patches = (old.patches or [ ]) ++ [ ./0001-feat-format-nix.patch ]; })
