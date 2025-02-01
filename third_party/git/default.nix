# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# git with custom patches. This is also used by cgit via
# `pkgs.srcOnly`.
{ pkgs, ... }:

pkgs.git.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # ./0001-feat-third_party-git-date-add-dottime-format.patch
  ];
})
