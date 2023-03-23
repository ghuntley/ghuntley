# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, depot, ... }: {

  services.cachix-agent.enable = true;

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.ops.secrets."${config.networking.hostName}-${name}.age";
    in
    {
      cachix-agent-token.file = secretFile "cachix-agent-token";
      cachix-agent-token.path = "/etc/cachix-agent.token";
      cachix-agent-token.symlink = false;
    };

}
