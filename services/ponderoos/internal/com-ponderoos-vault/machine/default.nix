# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  machine = import ./vm.nix { inherit depot pkgs; };

  # Extract just the hash part from the store path
  isoHash = builtins.substring 11 32 (toString machine.iso);
  isoName = builtins.baseNameOf (toString machine.iso);
in
rec {
  vm = machine.vm;
  iso = machine.iso;

  # Script that prints store path and URL, and checks if ISO exists
  url = pkgs.writeScriptBin "iso-url" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    ISO_PATH="${iso}/iso/nixos-25.05pre-git-x86_64-linux.iso"
    # Extract just the hash part from the store path
    STORE_HASH="$(echo "$ISO_PATH" | cut -d'-' -f1 | cut -d'/' -f4)"
    NARINFO_URL="https://nix-cache.ponderoos.com/$STORE_HASH.narinfo"

    echo "Store path: $ISO_PATH"
    echo "Narinfo URL: $NARINFO_URL"
    echo ""

    if command -v curl >/dev/null 2>&1; then
      echo "Fetching .narinfo file..."
      if NARINFO=$(curl -sf "$NARINFO_URL"); then
        echo "Narinfo contents:"
        echo "$NARINFO"
        echo ""

        if ! NAR_URL=$(echo "$NARINFO" | grep "^URL:" | cut -d' ' -f2-); then
          echo "Failed to find URL field in .narinfo file" >&2
          exit 1
        fi

        # Remove any leading/trailing whitespace
        NAR_URL=$(echo "$NAR_URL" | xargs)

        echo "Download URL:"
        if [[ "$NAR_URL" == /* ]]; then
          # If URL starts with /, it's a relative path
          echo "https://nix-cache.ponderoos.com/$NAR_URL"
        else
          # If URL is already absolute or has a different format
          echo "https://nix-cache.ponderoos.com/$NAR_URL"
        fi
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
  '';

  tests = {
    machine = import ./test.nix { inherit depot pkgs; };
  };

  meta.ci = {
    inherit vm tests iso;
  };
}
