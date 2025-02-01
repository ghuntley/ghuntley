# Copyright (c) 2020 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ ... }:

{
  name = "integration-tests";

  # For faster dev cycles it's also possible to disable the code-linters (this shouldn't be commited though)
  # skipLint = true;

  enableOCR = true;

  nodes.machine = ./configuration.nix;

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
    machine.screenshot("postboot")

    with subtest("mgmt user exists"):
        machine.succeed("getent passwd mgmt")
        machine.screenshot("assert_user_exists")

    with subtest("mgmt can login via ssh"):
        machine.wait_for_unit("sshd")

        machine.succeed(
            "sshpass -p hunter2 ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no mgmt@localhost 'echo hello world' >&2"
        )

    with subtest("git is installed"):
        machine.succeed("git --help")

    with subtest("nix flakes are enabled"):
        machine.succeed("grep 'nix-command flakes' /etc/nix/nix.conf")

  '';
}
