# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;

  # Common git configuration
  gitConfig = {
    github.user = "ghuntley";
    merge.conflictstyle = "diff3";
    rerere.enabled = "true";
    advice.skippedCherryPicks = "false";
  };
in
{
  config = {
    programs.git = {
      enable = true;
      userEmail = "ghuntley@ghuntley.com";
      userName = "Geoffrey Huntley";

      extraConfig = gitConfig // lib.mkIf isDarwin {
        credential.helper = "osxkeychain";
        core.trustctime = false; # Recommended for APFS
      };

      delta = {
        enable = true;
        options = {
          hunk-style = "plain";
          commit-style = "box";
        };
      };
    };
  };
}
