# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  tmux-upterm = pkgs.writeShellScriptBin "tmux-upterm" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    if [ $# -eq 0 ]; then
        echo "Usage: tmux-upterm <github-username>"
        exit 1
    fi

    upterm host --github-user "$1" --server ssh://upterm.ponderoos.com:2323 \
      --force-command 'tmux attach -t pair-programming' \
      -- tmux new -t pair-programming
  '';
in
tmux-upterm.overrideAttrs (_: { })
