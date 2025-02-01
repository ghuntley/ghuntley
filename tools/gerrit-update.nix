# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Utility script to perform a Gerrit update.
{ pkgs, ... }:

pkgs.writeShellScriptBin "gerrit-update" ''
  set -euo pipefail

  if [[ $EUID -ne 0 ]]; then
    echo "Oh no! Only root is allowed to update Gerrit!" >&2
    exit 1
  fi

  gerrit_war="$(find "${pkgs.gerrit}/webapps" -name 'gerrit*.war')"
  java="${pkgs.jdk}/bin/java"
  backup_path="/root/gerrit_preupgrade-$(date +"%Y-%m-%d").tar.bz2"

  # Take a safety backup of Gerrit into /root's homedir. Just in case.
  echo "Backing up Gerrit to $backup_path"
  tar -cjf "$backup_path" /var/lib/gerrit

  # Stop Gerrit (and its activation socket).
  echo "Stopping Gerrit"
  systemctl stop gerrit.service gerrit.socket

  # Ask Gerrit to do a schema upgrade...
  echo "Performing schema upgrade"
  "$java" -jar "$gerrit_war" \
    init --no-auto-start --batch --skip-plugins --site-path "/var/lib/gerrit"

  # Restart Gerrit.
  echo "Restarting Gerrit"
  systemctl start gerrit.socket gerrit.service

  echo "...done"
''
