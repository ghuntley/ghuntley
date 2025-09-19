# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.starship pkgs.direnv];

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    interactiveShellInit = ''
      export PATH="$PATH:$HOME/bin:"
      eval "$(starship init zsh)"
    '';
  };
}
