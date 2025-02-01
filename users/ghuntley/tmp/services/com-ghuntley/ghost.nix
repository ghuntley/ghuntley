# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, config, lib, ... }: {

  virtualisation.oci-containers.containers."ghost" = {
    image = "ghost:latest";
    ports = [ "3001:2368" ];
    volumes = [
      "/srv/ghuntley.com/ghost:/var/lib/ghost/content:cached"
      "/srv/ghuntley.com/ghost/config.production.json:/var/lib/ghost/config.production.json"
    ];
    environment = {
      url = "https://ghuntley.com";
      database__client = "sqlite3";
      database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
    };
  };

  systemd.services.docker-pull-ghost = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.docker
      pkgs.systemd
    ];

    script = ''
      ${pkgs.docker}/bin/docker pull ghost
      ${pkgs.systemd}/bin/systemctl restart docker-ghost
    '';
  };

  systemd.timers.docker-pull-ghost = {
    wantedBy = [ "timers.target" ];
    partOf = [ "docker-pull-ghost.service" ];
    timerConfig.OnCalendar = "daily";
  };

}
