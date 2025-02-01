# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file."bin/cursor" = {
    text = ''
      #!/usr/bin/env bash
      cd ~/Applications

      if ! ls cursor*.AppImage >/dev/null 2>&1; then
        echo "Downloading Cursor AppImage..."
        curl -L -o cursor.AppImage "https://download.todesktop.com/230313mzl4w4u92/cursor-0.45.7-build-250130nr6eorv84-x86_64.AppImage"
        chmod +x cursor.AppImage
      fi

      nohup appimage-run cursor*.AppImage "$@" >/dev/null 2>&1 &
      exit 0
    '';
    executable = true;
  };

  home.file = {
    ".icons/cursor.png".source = ../icons/cursor.png;
  };

  xdg.desktopEntries = {
    "cursor" = {
      name = "Cursor";
      genericName = "Text Editor";
      comment = "AI-first code editor";
      exec = "${config.home.homeDirectory}/bin/cursor %F";
      icon = "${config.home.homeDirectory}/.icons/cursor.png";
      terminal = false;
      type = "Application";
      mimeType = [
        "text/plain"
        "application/x-text-html"
        "text/x-c"
        "text/x-c++"
        "text/x-c-header"
        "text/x-c++-header"
        "text/x-java"
        "text/x-python"
        "text/x-javascript"
        "text/x-typescript"
        "text/x-php"
        "text/x-ruby"
        "text/x-rust"
        "text/x-go"
        "text/x-scala"
        "text/x-swift"
        "text/x-perl"
        "text/x-shellscript"
        "text/x-makefile"
        "text/x-cmake"
        "text/x-yaml"
        "text/x-json"
        "text/x-sql"
        "text/xml"
        "application/xml"
        "application/json"
        "application/javascript"
        "application/x-httpd-php"
        "application/x-yaml"
      ];
      startupNotify = true;
    };
  };
}
