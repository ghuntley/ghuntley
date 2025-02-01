# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


{ config, depot, pkgs, lib, ... }:

let
  cfg = config.services.depot.buildkite;
  agents = lib.range 1 cfg.agentCount;
  description = "Buildkite agents for Ponderoos";
  hostname = config.networking.hostName;

  besadiiWithConfig = name: pkgs.writeShellScript "besadii-${hostname}" ''
    export BESADII_CONFIG=/run/agenix/buildkite-besadii-config
    exec -a ${name} ${depot.infra.scm.besadii}/bin/besadii "$@"
  '';

  # All Buildkite hooks are actually besadii, but it's being invoked
  # with different names.
  buildkiteHooks = pkgs.runCommand "buildkite-hooks" { } ''
    mkdir -p $out/bin
    ln -s ${besadiiWithConfig "post-command"} $out/bin/post-command
  '';

  credentialHelper = pkgs.writeShellScriptBin "git-credential-gerrit-creds" ''
    echo 'username=buildkite'
    echo "password=$(jq -r '.gerritPassword' ${config.age.secrets.buildkite-besadii-config.path})"
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
        name = "${hostname}-${toString n}";
        value = {
          inherit name;
          enable = true;
          tokenPath = config.age.secrets.buildkite-agent-token.path;
          privateSshKeyPath = config.age.secrets.buildkite-ssh-private-key.path;
          hooks.post-command = "${buildkiteHooks}/bin/post-command";
          hooks.environment = ''
            export PATH=$PATH:/run/wrappers/bin
          '';

          extraConfig = ''
            allowed-repositories="^https://cl.ponderoos.com/depot.*"
            metrics-datadog=true
            metrics-datadog-host=127.0.0.1:8125
            metrics-datadog-distributions=true
          '';

          tags.hostname = hostname;
          tags.queue = "x64";

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
          name = "buildkite-agent-${hostname}-${toString n}";
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
