# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.file."bin/cursor" = {
    text = ''
      #!/usr/bin/env bash
      mkdir -p ~/Applications
      cd ~/Applications

      export CURSOR_APPIMAGE_URL="https://downloader.cursor.sh/linux/appImage/x64"
      export CURSOR_APPIMAGE_FILENAME="cursor.AppImage"
      export CURSOR_APPIMAGE_FILENAME_NEW="cursor.AppImage.new"

      # Download initial AppImage if it doesn't exist
      if ! ls cursor*.AppImage >/dev/null 2>&1; then
        echo "Downloading Cursor AppImage..."
        curl -L -o "$CURSOR_APPIMAGE_FILENAME" "$CURSOR_APPIMAGE_URL"
        chmod +x "$CURSOR_APPIMAGE_FILENAME"
      fi

      # Check if AppImage is older than 24 hours
      if [[ $(find cursor.AppImage -mmin +1440 2>/dev/null) ]]; then
        # Only download new version if it doesn't already exist
        if [[ ! -f cursor.AppImage.new ]]; then
          echo "Current AppImage is older than 24 hours. Starting background update..."
          (
            curl -L -o "$CURSOR_APPIMAGE_FILENAME_NEW" "$CURSOR_APPIMAGE_URL" && \
            chmod +x "$CURSOR_APPIMAGE_FILENAME_NEW" && \
            mv "$CURSOR_APPIMAGE_FILENAME_NEW" "$CURSOR_APPIMAGE_FILENAME"
          ) >/dev/null 2>&1 &
        fi
      fi

      nohup appimage-run cursor.AppImage "$@" >/dev/null 2>&1 &
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
