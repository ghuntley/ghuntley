# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for Vaultwarden password manager with backup configuration
{ config, lib, pkgs, ... }:

let
  cfg = config.services.depot.vaultwarden;
  mkStringOption = default: lib.mkOption {
    inherit default;
    type = lib.types.str;
  };
in
{
  options.services.depot.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";
    domain = mkStringOption "vault.example.com";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port on which vaultwarden will listen";
    };
    enableSignups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow new user registrations";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vaultwarden";
      description = "Directory where vaultwarden stores its data";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vaultwarden;
      description = "The vaultwarden package to use";
    };
    backupDir = mkStringOption "/var/backup/vaultwarden";
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      package = cfg.package;
      config = {
        WEB_VAULT_URL = "http://127.0.0.1:${toString cfg.port}";
        ROCKET_PORT = cfg.port;
        SIGNUPS_ALLOWED = cfg.enableSignups;
      };
      backupDir = cfg.backupDir;
      dataDir = cfg.dataDir;
    };

    # Configure backups using depot.restic
    services.depot.restic = {
      enable = true;
      paths = [
        cfg.dataDir
        cfg.backupDir
      ];
      exclude = [
        "*.tmp"
        "*.log"
        "**/cache/**"
      ];
    };

    # Configure nginx reverse proxy
    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";

        extraConfig = ''
          add_header X-Robots-Tag "none";
        '';
      };
    };

    # Open the port in the firewall for internal traffic
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];
  };
}
