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

  cfg = config.services.depot.open-webui;
  description = "Open WebUI - Web interface for LLMs";

  # Helper functions for argument preparation
  prepareArgs = args:
    concatStringsSep " "
      (attrValues (mapAttrs (key: value: "-${key} \"${toString value}\"")
        args));
in
{
  options.services.depot.open-webui = {
    enable = mkEnableOption description;

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port on which Open WebUI will listen";
    };

    domain = mkOption {
      type = types.str;
      default = "chat.ponderoos.com";
      description = "Domain name for the Open WebUI instance";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = "Directory where Open WebUI stores its data";
    };
  };

  config = mkIf cfg.enable {

    services.ollama.enable = true;
    services.ollama.loadModels = [
      "deepseek-r1:8b"
    ];

    services.open-webui = {
      enable = true;
      port = cfg.port;
      stateDir = cfg.stateDir;
      environment = {
        ENABLE_SIGNUP = "False";
      };
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
