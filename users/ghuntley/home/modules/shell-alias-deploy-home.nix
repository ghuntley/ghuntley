# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file."bin/deploy-home" = {
    text = ''
      #!/usr/bin/env bash
      cd ~/code/ghuntley
      direnv exec . deploy-home
    '';
    executable = true;
  };
}
