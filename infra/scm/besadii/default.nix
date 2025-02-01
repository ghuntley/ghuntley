# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# This program is used as a Gerrit hook to trigger builds on
# Buildkite and perform other maintenance tasks.
{ depot, ... }:

depot.nix.buildGo.program {
  name = "besadii";
  srcs = [ ./main.go ];
}
