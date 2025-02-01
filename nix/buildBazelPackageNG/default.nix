# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


{ pkgs, ... }:

(pkgs.callPackage ./buildBazelPackageNG.nix { }) // {
  bazelRulesJavaHook = pkgs.callPackage ./bazelRulesJavaHook { };
  bazelRulesNodeJS5Hook = pkgs.callPackage ./bazelRulesNodeJS5Hook { };
}
