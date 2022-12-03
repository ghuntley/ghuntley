# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

{

  services.timesyncd.enable = true;
  networking.timeServers = [
    "time.core"
  ];

  services.openntpd = {
    enable = true;
    servers = [
      "0.au.pool.ntp.org"
      "1.au.pool.ntp.org"
      "2.au.pool.ntp.org"
      "3.au.pool.ntp.org"
    ];
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [ 123 ];
  };


}
