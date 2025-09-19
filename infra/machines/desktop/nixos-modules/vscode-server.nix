# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, ... }:

{
  # VS Code Server for remote development
  services.vscode-server.enable = true;
}