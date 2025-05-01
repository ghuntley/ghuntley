# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{
  services = {
    syncthing = {
      enable = true;
      group = "users";
      user = "ghuntley";
      dataDir = "/home/ghuntley";
      configDir = "/home/ghuntley/Documents/.config/syncthing";
    };
  };
}
