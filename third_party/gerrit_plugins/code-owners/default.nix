# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot, pkgs, ... }@args:

let
  inherit (import ../builder.nix args) buildGerritBazelPlugin;
in
buildGerritBazelPlugin rec {
  name = "code-owners";
  version = "f6751981258a3ebe77497a615d01a3730ae288d2";
  src = pkgs.fetchgit {
    url = "https://gerrit.googlesource.com/plugins/code-owners";
    rev = "f6751981258a3ebe77497a615d01a3730ae288d2";
    hash = "sha256-46TEuQQTifUCJjWzu6D3sxWY83xZ2eLbzT96TRGnjuo=";
  };
  patches = [
  ];
}
