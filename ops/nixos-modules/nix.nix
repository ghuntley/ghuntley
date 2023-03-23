# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  nix.autoOptimiseStore = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

}
