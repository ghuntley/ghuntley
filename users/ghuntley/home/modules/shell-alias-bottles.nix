# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file."bin/bottles" = {
    text = ''
      flatpak install --noninteractive flathub com.usebottles.bottles

      nohup flatpak run com.usebottles.bottles >/dev/null 2>&1 &
      exit 0
    '';
    executable = true;
  };

  home.file = {
    ".icons/bottles.png".source = ../icons/bottles.png;
  };

  xdg.desktopEntries = {
    "bottles" = {
      name = "Bottles";
      genericName = "Wine prefix manager";
      comment = "Wine prefix manager";
      exec = "${config.home.homeDirectory}/bin/bottles %F";
      icon = "${config.home.homeDirectory}/.icons/bottles.png";
      terminal = false;
      type = "Application";
      categories = [ "Utility" ];
      startupNotify = true;
    };
  };

}
