# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

let
  nixpkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  };
in
import (nixpkgs.path + "/nixos/tests/make-test-python.nix") (
  { pkgs, ... }: {
    name = "com-ghuntley-media";

    nodes.machine = { config, pkgs, ... }: {
      virtualisation.memorySize = 8192;
      virtualisation.cores = 16;
    };

    testScript = ''
      start_all()
    '';
  }
)
