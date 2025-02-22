# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, depot, services, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.depot.thelounge;
in
{
  options.services.depot.thelounge = {
    enable = mkEnableOption "The Lounge chat server";

    port = mkOption {
      type = types.int;
      default = 3000;
      description = "Port to listen on for The Lounge";
    };

    domain = mkOption {
      type = types.str;
      default = "irc.ponderoos.com";
      description = "Domain name for Convos";
    };

  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.thelounge ];

    services.thelounge = {
      enable = true;
      port = cfg.port;
      plugins = [
        pkgs.theLoungePlugins.themes.solarized
      ];
      extraConfig = {
        debug = true;
      };
    };

    # Configure backups using depot.restic
    services.depot.restic = {
      enable = true;
      paths = [
        "/var/lib/thelounge"
      ];
      exclude = [ ];
    };

    # Configure nginx reverse proxy
    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          add_header X-Robots-Tag "none";
        '';
      };
    };
  };
}
