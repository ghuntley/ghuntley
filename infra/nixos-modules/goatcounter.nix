# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for Open WebUI - a web interface for interacting with large language models
{ depot, pkgs, config, lib, ... }:

let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.depot.goatcounter;
  description = "GoatCounter - Web analytics";

  # Helper functions for argument preparation
  prepareArgs = args:
    concatStringsSep " "
      (attrValues (mapAttrs (key: value: "-${key} \"${toString value}\"")
        args));
in
{
  options.services.depot.goatcounter = {
    enable = mkEnableOption description;

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port on which Open WebUI will listen";
    };

    domain = mkOption {
      type = types.str;
      default = "stats.ponderoos.com";
      description = "Domain name for the GoatCounter instance";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/goatcounter/db";
      description = "Directory where GoatCounter stores its data";
    };

    smtp = mkOption {
      type = types.str;
      default = "smtp://localhost:25";
      description = "SMTP server to use for sending emails";
    };

    emailFrom = mkOption {
      type = types.str;
      default = "ghuntley@ghuntley.com";
      description = "Email address to use for sending emails";
    };

    errorsTo = mkOption {
      type = types.str;
      default = "no-reply+goatcounter@ponderoos.com";
      description = "Email address to use for sending errors";
    };
  };

  config = mkIf cfg.enable {

    services.goatcounter = {
      enable = true;
      package = depot.third_party.goatcounter;
      proxy = true;
      port = cfg.port;
      extraArgs = [
        "--db=sqlite+${cfg.stateDir}/db/goatcounter.sqlite3"
        "--geodb=${config.services.depot.geoipupdate.stateDir}/GeoLite2-City.mmdb"
        "-automigrate"
        # "-smtp=${cfg.smtp}"
        # "-email-from=${cfg.emailFrom}"
        # "-errors=mailto:${cfg.errorsTo}"
      ];
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

    # Configure backups using depot.restic
    services.depot.restic = {
      enable = true;
      paths = [
        cfg.stateDir
      ];
      exclude = [ ];
    };
  };
}
