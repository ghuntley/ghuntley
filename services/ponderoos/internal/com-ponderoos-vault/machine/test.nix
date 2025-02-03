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
    name = "vault";

    nodes.machine = { config, pkgs, ... }: {
      nixpkgs.config.allowUnfree = true;
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;

      services.vault = {
        enable = true;
        package = pkgs.vault;
        address = "127.0.0.1:8100";
      };

      networking.firewall.allowedTCPPorts = [ 8200 ];
    };

    testScript = ''
      start_all()

      machine.wait_for_unit("vault.service")
      machine.wait_for_open_port(8200)

      # Check if vault is running and responding
      result = machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8200/v1/sys/health")
      assert "501" in result, "Vault health check should return 501 when sealed"

      # Check systemd service status
      machine.succeed("systemctl is-active vault.service")
    '';
  }
)
