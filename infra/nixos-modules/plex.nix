# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  services.plex.enable = true;
  networking.firewall.allowedTCPPorts = [ 32400 ];

  services.ombi.enable = true;
  services.ombi.port = 5001;

  services.sonarr.enable = true;
  services.radarr.enable = true;
  services.lidarr.enable = true;

  services.sabnzbd.enable = true;

  services.depot.restic = {
    paths = [
      "/var/lib/ombi"
      "/var/lib/plex"
      "/var/lib/sonarr"
      "/var/lib/radarr"
      "/var/lib/lidarr"
      "/var/lib/sabnzbd"
    ];
    exclude = [ "" ];
  };

  services.nginx.virtualHosts."media.ponderoos.com" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:5001";

      extraConfig = ''
        add_header X-Robots-Tag "none";
      '';
    };
  };

}
