# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  environment.systemPackages = with pkgs; [ nomad ];

  services.nomad.enable = false;
  services.nomad.dropPrivileges = false;

  services.nomad.settings = {
    # A minimal config example:
    server = {
      enabled = true;
      bootstrap_expect = 1; # for demo; no fault tolerance
    };
    client = {
      enabled = true;
    };
  };

}
