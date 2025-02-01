# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file."bin/cursor" = {
    text = ''
      #!/usr/bin/env bash
      cd ~/Applications

      if ! ls cursor*.appimage >/dev/null 2>&1; then
        echo "Downloading Cursor AppImage..."
        curl -L -o cursor.appimage "https://download.todesktop.com/230313mzl4w4u92/cursor-0.45.7-build-250130nr6eorv84-x86_64.AppImage"
        chmod +x cursor.appimage
      fi

      appimage-run cursor*.appimage "$@"
    '';
    executable = true;
  };
}
