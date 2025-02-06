# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }:

let
  cfg = config.services.depot.healthchecks;
  mkStringOption = default: lib.mkOption {
    inherit default;
    type = lib.types.str;
  };
in
{
  options.services.depot.healthchecks = {
    enable = lib.mkEnableOption "Healthchecks";
    domain = mkStringOption "healthchecks.example.com";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port on which vaultwarden will listen";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/healthchecks";
      description = ''
        Directory where healthchecks stores its data.
        Will be created automatically with correct permissions.
      '';
    };
    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to run in debug mode";
    };
    registrationOpen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow new user registrations";
    };
    admins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "A list of email addresses to send code error notifications to.";
    };
    logoUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The URL of the logo to display in the Healthchecks UI.";
    };
    emailFrom = lib.mkOption {
      type = lib.types.str;
      default = "healthchecks@${cfg.domain}";
      description = "The email address to use for the Healthchecks service.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment variables which are read by healthchecks (local)_settings.py. Used to keep secrets out of the /nix/store.";
    };
    emailUseVerification = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to use email verification for new users.";
    };
  };

  config = lib.mkIf cfg.enable {

    services.healthchecks = {
      enable = true;
      port = cfg.port;
      settingsFile = cfg.environmentFile;
      settings = {
        DEBUG = cfg.debug;
        DB = "sqlite";
        EMAIL_USE_VERIFICATION = if cfg.emailUseVerification then "True" else "False";
        EMAIL_HOST = "127.0.0.1";
        EMAIL_USE_TLS = "False";
        EMAIL_PORT = "25";
        ADMINS = builtins.concatStringsSep "," cfg.admins;
        REGISTRATION_OPEN = cfg.registrationOpen;
        ALLOWED_HOSTS = [ "*" ];
        CSRF_TRUSTED_ORIGINS = "https://${cfg.domain}";
        SITE_NAME = cfg.domain;
        DEFAULT_FROM_EMAIL = cfg.emailFrom;
        PING_EMAIL_DOMAIN = "${cfg.domain}";
        SECURE_PROXY_SSL_HEADER = "HTTP_X_FORWARDED_PROTO,https";
        SHELL_ENABLED = "False";
        SITE_LOGO_URL = cfg.logoUrl;
        USE_PAYMENTS = "False";
        WEBHOOKS_ENABLED = "True";
      };
    };


    # Configure backups using depot.restic
    services.depot.restic = {
      enable = true;
      paths = [
        cfg.dataDir
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
