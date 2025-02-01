# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Utility script to run a gerrit command on the depot host via ssh.
# Reads the username from PONDEROOS_USERNAME, or defaults to $(whoami)
{ pkgs, ... }:

pkgs.writeShellScriptBin "gerrit" ''
  PONDEROOS_USERNAME=''${PONDEROOS_USERNAME:-$(whoami)}
  if which ssh &>/dev/null; then
    ssh=ssh
  else
    ssh="${pkgs.openssh}/bin/ssh"
  fi
  exec $ssh $PONDEROOS_USERNAME@code.ponderoos.com -p 29418 -- gerrit $@
''
