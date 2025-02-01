# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ makeSetupHook }:

makeSetupHook
{
  name = "rules_java_bazel_hook";
  substitutions = {
    local_java = ./local_java;
  };
} ./setup-hook.sh
