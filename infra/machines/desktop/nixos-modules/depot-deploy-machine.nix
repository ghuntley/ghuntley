# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, lib, ... }:

{
  systemd.services.depot-deploy-machine = {
    description = "Deploy NixOS configuration from depot";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    unitConfig = {
      ConditionACPower = true;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      TimeoutStartSec = "30min";
      ExecStart = "${pkgs.depot.tools.deploy}/bin/deploy machine";
    };
  };

  systemd.timers.depot-deploy-machine = {
    description = "Run depot machine deploy every hour";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };
}
