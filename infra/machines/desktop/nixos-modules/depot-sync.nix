# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, pkgs, lib, ... }:

{
  systemd.services.depot-sync = {
    description = "Sync depot repository";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    unitConfig = {
      ConditionACPower = true;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Nice = 10;
      TimeoutStartSec = "5min";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/depot" ];
      ExecStartPost = "${pkgs.systemd}/bin/systemctl start --no-block depot-deploy-machine.service";
    };

    script = ''
      ${pkgs.depot.deploy}/bin/deploy sync
    '';
  };

  systemd.timers.depot-sync = {
    description = "Run depot sync every 15 minutes";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnUnitInactiveSec = "15m";
      RandomizedDelaySec = "30s";
      AccuracySec = "30s";
    };
  };

  # Ensure /var/lib/depot directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/depot 0755 depot depot -"
  ];
}
