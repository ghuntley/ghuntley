# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ config, depot, pkgs, lib, ... }:

let
  cfg = config.services.depot.buildkite;
  agents = lib.range 1 cfg.agentCount;
  description = "Buildkite agents";

  post-command = name: pkgs.writeShellScript "post-command" ''
    echo ""
  '';

  buildkiteHooks = pkgs.runCommandNoCC "buildkite-hooks" { } ''
    mkdir -p $out/bin
    ln -s ${post-command "post-command"} $out/bin/post-command
  '';
in
{
  options.services.depot.buildkite = {
    enable = lib.mkEnableOption description;
    agentCount = lib.mkOption {
      type = lib.types.int;
      description = "Number of Buildkite agents to launch";
    };
  };

  config = lib.mkIf cfg.enable {
    # Run the Buildkite agents using the default upstream module.
    services.buildkite-agents = builtins.listToAttrs (map
      (n: rec {
        name = "buildkite-agent-${toString n}";
        value = {
          inherit name;
          enable = true;
          tokenPath = config.age.secretsDir + "/buildkite-agent-token";
          privateSshKeyPath = config.age.secretsDir + "/buildkite-private-key";
          # hooks.post-command = "${buildkiteHooks}/bin/post-command";

          runtimePackages = with pkgs; [
            bash
            coreutils
            credentialHelper
            curl
            git
            gnutar
            gzip
            jq
            nix
          ];
        };
      })
      agents);

    # Set up a group for all Buildkite agent users
    users = {
      groups.buildkite-agents = { };
      users = builtins.listToAttrs (map
        (n: rec {
          name = "buildkite-agent-${toString n}";
          value = {
            isSystemUser = true;
            group = lib.mkForce "buildkite-agents";
            extraGroups = [ name "docker" ];
          };
        })
        agents);
    };
  };
}
