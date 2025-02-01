# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, config, lib, ... }:

let
  cfg = config.services.depot.keycloak;
  description = "Keycloak identity and access management server";
in
{
  options.services.depot.keycloak = {
    enable = lib.mkEnableOption description;

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "auth.ponderoos.com";
      description = "The hostname part of the public URL used as base for all frontend requests.";
    };

    local-http-port = lib.mkOption {
      type = lib.types.int;
      description = "On which local port Keycloak should listen for new HTTP connections.";
      default = 5925;
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Database name to use when connecting.";
        default = "keycloak";
      };

      passwordFile = lib.mkOption {
        type = lib.types.path;
        example = "config.age.secrets.postgres-keycloak-credentials.path";
        description = "The path to a file containing the database password.";
      };
    };

  };

  config = lib.mkIf cfg.enable {

    # Keycloak
    services.keycloak = {
      enable = true;

      settings = {
        http-port = cfg.local-http-port;
        hostname = cfg.hostname;
        http-relative-path = "/auth";
        proxy-headers = "xforwarded";
        http-enabled = true;
      };

      database = {
        type = "postgresql";
        name = cfg.database.name;
        passwordFile = cfg.database.passwordFile;
        createLocally = false;
      };
    };

    services.postgresqlBackup = {
      databases = [
        cfg.database.name
      ];
    };

    # Nginx
    services.nginx.virtualHosts."${cfg.hostname}" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        location / {
          proxy_pass http://localhost:${toString cfg.local-http-port};
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header Host $host;

          add_header X-Robots-Tag "none";
        }
      '';
    };

  };
}
