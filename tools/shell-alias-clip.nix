# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  clip = pkgs.writeShellScriptBin "clip" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    ${pkgs.jq}/bin/jq -Rns '{text: inputs}' | \
    ${pkgs.curl}/bin/curl  -s -H 'Content-Type: application/json' --data-binary @- https://clip.ponderoos.com | \
    ${pkgs.jq}/bin/jq -r '. | "https://clip.ponderoos.com\(.path)"'
  '';

in
clip.overrideAttrs (_: { })
