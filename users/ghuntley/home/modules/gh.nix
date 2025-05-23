# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  programs.gh = {
    enable = true;
    settings = {
      editor = "vim";
      git_protocol = "https";
      prompt = "enabled";
    };
  };
}
