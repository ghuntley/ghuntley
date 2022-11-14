# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configuration for the TVL buildkite agents.
{ config, depot, pkgs, lib, ... }:

let
  cfg = config.services.depot.buildkite;
  agents = lib.range 1 cfg.agentCount;
  description = "Buildkite agents";

  besadiiWithConfig = name: pkgs.writeShellScript "besadii-dev" ''
    export BESADII_CONFIG=/run/agenix/buildkite-besadii-config
    exec -a ${name} ${depot.ops.besadii}/bin/besadii "$@"
  '';

  # All Buildkite hooks are actually besadii, but it's being invoked
  # with different names.
  buildkiteHooks = pkgs.runCommandNoCC "buildkite-hooks" { } ''
    mkdir -p $out/bin
    ln -s ${besadiiWithConfig "post-command"} $out/bin/post-command
  '';

  credentialHelper = pkgs.writeShellScriptBin "git-credential-gerrit-creds" ''
    echo 'username=buildkite'
    echo "password=$(jq -r '.gerritPassword' /run/agenix/buildkite-besadii-config)"
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
        name = "dev-${toString n}";
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
          name = "buildkite-agent-dev-${toString n}";
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
