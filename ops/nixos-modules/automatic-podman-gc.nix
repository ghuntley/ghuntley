# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Defines a service for automatically collecting Podman garbage
{ config, lib, pkgs, ... }:

let
  cfg = config.services.depot.automatic-podman-gc;
  description = "Automatically collect Podman garbage";

  gcScript = pkgs.writeShellScript "automatic-podman-gc" ''
    set -ueo pipefail

    ${config.podman.package}/bin/podman \
        image prune --all --force
  '';
in
{
  options.services.depot.automatic-gc = {
    enable = lib.mkEnableOption description;

    interval = lib.mkOption {
      type = lib.types.str;
      example = "1h";
      description = ''
        Interval between garbage collection runs, specified in
        systemd.time(7) format.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.automatic-podman-gc = {
      inherit description;
      script = "${gcScript}";
      serviceConfig.Type = "oneshot";
    };

    systemd.timers.automatic-podman-gc = {
      inherit description;
      requisite = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];

      timerConfig = {
        OnActiveSec = "1";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
