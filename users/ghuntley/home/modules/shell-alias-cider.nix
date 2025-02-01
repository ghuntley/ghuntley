# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{
  home.file."bin/cider" = {
    text = ''
      #!/usr/bin/env bash
      cd ~/Applications
      if ! ls cider*.AppImage >/dev/null 2>&1; then
        echo "Downloading Cider AppImage..."
        curl -L -o cider.AppImage "https://github.com/ciderapp/cider-releases/releases/latest/download/Cider-linux-x86_64.AppImage"
        chmod +x cider.AppImage
      fi

      nohup appimage-run cider*.AppImage "$@" >/dev/null 2>&1 &
      exit 0
    '';
    executable = true;
  };
}
