# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.file."bin/deploy-nixos" = {
    text = ''
      #!/usr/bin/env bash
      cd /depot
      direnv exec . deploy-nixos
    '';
    executable = true;
  };
}
