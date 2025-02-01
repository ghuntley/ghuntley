# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{

  environment.systemPackages = with pkgs; [ ntp ];

  services.ntp.enable = true;
  services.ntp.servers = [
    "time.core"
  ];

  services.timesyncd.enable = true;
  networking.timeServers = [
    "time.core"
  ];
}
