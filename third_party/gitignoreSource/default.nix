# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot, lib, ... }:

let
  gitignoreNix = import depot.third_party.sources."gitignore.nix" { inherit lib; };
in
{
  __functor = _: gitignoreNix.gitignoreSource;

  # expose extra functions here
  inherit (gitignoreNix)
    gitignoreFilter
    ;
}
