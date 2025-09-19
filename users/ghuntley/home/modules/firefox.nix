# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  # This configuration sets up Firefox as the default application for web-related file types
  # and protocols using the XDG MIME applications system.

  xdg.mimeApps = rec {
    enable = true;
    # Define Firefox as the default application for various web-related MIME types
    defaultApplications = {
      # Standard web page formats
      "text/html" = ["firefox.desktop"];
      "application/xhtml+xml" = ["firefox.desktop"];

      # URL protocol handlers
      "x-scheme-handler/http" = ["firefox.desktop"];
      "x-scheme-handler/https" = ["firefox.desktop"];
      "x-scheme-handler/ftp" = ["firefox.desktop"];
      "x-scheme-handler/chrome" = ["firefox.desktop"];

      # Various HTML-related file extensions
      "application/x-extension-htm" = ["firefox.desktop"];
      "application/x-extension-html" = ["firefox.desktop"];
      "application/x-extension-shtml" = ["firefox.desktop"];
      "application/x-extension-xhtml" = ["firefox.desktop"];
      "application/x-extension-xht" = ["firefox.desktop"];
    };
    # Add these associations to the system
    associations.added = defaultApplications;
  };
}
