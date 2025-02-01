# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  nix.settings.sandbox = false;
  nix.settings.auto-optimise-store = true;

}
