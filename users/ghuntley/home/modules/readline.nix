# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{

  programs.readline = {
    enable = true;
    extraConfig = ''
      set editing-mode vi
    '';
  };
}
