# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Provides utilities for working with ISO files and Nix store paths.
#
# Example:
#   let
#     iso = # ... some derivation containing an ISO file
#     isoUrlScript = getIsoUrl iso;
#   in
#     # The script can be run to get the download URL:
#     # ${isoUrlScript}/bin/iso-url
#
{ depot, pkgs, ... }:

let
  # getIsoUrl :: derivation -> derivation
  #
  # Creates a script that helps retrieve ISO files from the Nix store and cache.
  #
  # Arguments:
  #   iso: A derivation containing an ISO file in its iso/ subdirectory
  #
  # Returns:
  #   A derivation containing a script that:
  #   1. Locates the ISO file in the Nix store
  #   2. Constructs the narinfo URL for the cache
  #   3. Extracts and returns the download URL for the ISO
  getIsoUrl = iso:
    let
      debug = false; # Default value
    in
    pkgs.writeScriptBin "iso-url" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ISO_PATH=`ls ${iso}/iso/*.iso`
      STORE_HASH="$(echo "$ISO_PATH" | cut -d'-' -f1 | cut -d'/' -f4)"
      NARINFO_URL="https://nix-cache.ponderoos.com/$STORE_HASH.narinfo"

      ${if debug then ''
        echo "Store path: $ISO_PATH"
        echo "Narinfo URL: $NARINFO_URL"
        echo ""
      '' else ""}

      if command -v curl >/dev/null 2>&1; then
        ${if debug then "echo \"Fetching .narinfo file...\"" else ""}
        if NARINFO=$(curl -sf "$NARINFO_URL"); then
          ${if debug then ''
            echo "Narinfo contents:"
            echo "$NARINFO"
            echo ""
          '' else ""}

          if ! NAR_URL=$(echo "$NARINFO" | grep "^URL:" | cut -d' ' -f2-); then
            echo "Failed to find URL field in .narinfo file" >&2
            exit 1
          fi

          NAR_URL=$(echo "$NAR_URL" | xargs)

          ${if debug then "echo \"Download URL:\"" else ""}
          echo "https://nix-cache.ponderoos.com/$NAR_URL"
        else
          echo "Failed to fetch .narinfo file from $NARINFO_URL" >&2
          exit 1
        fi
      else
        echo "curl not found. Install curl to automatically fetch the NAR hash" >&2
        echo "Manually fetch the .narinfo from:"
        echo "$NARINFO_URL"
        exit 1
      fi

      ${if debug then ''
        echo ""
        echo "Checking if ISO exists:"
        if [ -f "$ISO_PATH" ]; then
          echo "✓ Found in store: $ISO_PATH"
          ls -lh "$ISO_PATH"
        else
          echo "✗ Not found in store: $ISO_PATH"
          echo "Try building it first with:"
          echo "depot build //services/ponderoos/internal/com-ponderoos-vault/machine:iso"
          exit 1
        fi
      '' else ''
        if [ ! -f "$ISO_PATH" ]; then
          echo "ISO not found in store: $ISO_PATH" >&2
          echo "Try building it first with:" >&2
          echo "depot build //services/ponderoos/internal/com-ponderoos-vault/machine:iso" >&2
          exit 1
        fi
      ''}
    '';
in
{
  inherit getIsoUrl;
}
