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
    name = "com-ghuntley-test";

    nodes.machine = { config, pkgs, ... }: {
      virtualisation.memorySize = 8192;
      virtualisation.cores = 16;
    };

    testScript = ''
      start_all()

      # machine.wait_for_unit("docker-ghost.service")
      machine.wait_for_open_port(3001)

      # Check if Ghost is running and responding
      result = machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/")
      assert "200" in result, "Ghost health check should return 200 when running"

      # Check systemd service status
      machine.succeed("systemctl is-active podman-pull-ghost.timer")
    '';
  }
)
