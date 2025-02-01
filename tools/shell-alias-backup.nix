# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  deploy-dns = pkgs.writeShellScriptBin "backup" ''
    #!${pkgs.bash}
    set -euo pipefail
    IFS=$'\n\t'

    cd /depot/infra/secrets/ponderoos
    eval $(agenix --identity /etc/ssh/ssh_host_ed25519_key --decrypt backup-cli-credentials.age)
    restic --cache-dir /var/backup/restic/cache "$@"
  '';

in
deploy-dns.overrideAttrs (_: { })
