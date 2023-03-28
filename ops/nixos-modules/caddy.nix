# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, config, lib, ... }: {

  services.caddy.enable = true;
  services.caddy.package = depot.third_party.caddy;

  services.caddy.dataDir = "/srv/ghuntley.net";
  services.caddy.email = "ghuntley@ghuntley.com";
  services.caddy.globalConfig = ''
    servers {
      protocols h1 h2 h3
    }

    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  '';

  systemd.services.caddy = {
    serviceConfig = {
      # Required to use ports < 1024
      AmbientCapabilities = "cap_net_bind_service";
      CapabilityBoundingSet = "cap_net_bind_service";
      EnvironmentFile = config.age.secrets.ghuntley-net-caddy-environment-file.path;
      TimeoutStartSec = "5m";
    };
  };

}
