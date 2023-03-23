# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# https://github.com/msteen/nixos-vscode-server
{ depot, lib, pkgs, ... }: # readTree options
{
  imports = [
    (import depot.third_party.sources.nixos-vscode-server)
  ];

  services.vscode-server.enable = true;
}
