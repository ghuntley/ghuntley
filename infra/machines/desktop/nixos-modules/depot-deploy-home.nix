# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  pkgs,
  lib,
  ...
}: let
  depot = pkgs.depot // {third_party = pkgs.third_party;};
in {
  systemd.services.depot-deploy-home = {
    description = "Deploy Home Manager configuration from depot";
    after = ["network-online.target"];
    wants = ["network-online.target"];

    unitConfig = {
      ConditionACPower = true;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "ghuntley";
      Group = "users";
      TimeoutStartSec = "15min";
      ExecStart = "${depot.tools.deploy}/bin/deploy home";
    };
  };

  systemd.timers.depot-deploy-home = {
    description = "Run depot home deploy every hour";
    wantedBy = ["timers.target"];

    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "10m"; # Add some randomization and offset from system deploy
    };
  };
}
