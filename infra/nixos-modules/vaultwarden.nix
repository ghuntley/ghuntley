# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for Vaultwarden password manager with backup configuration.
# This module:
# - Sets up the Vaultwarden service with proper directory permissions
# - Configures automated backups using restic
# - Sets up nginx reverse proxy with SSL
# - Implements security best practices for service accounts
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
    user = lib.mkOption {
      type = lib.types.str;
      default = "vaultwarden";
      description = "User under which vaultwarden runs";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "vaultwarden";
      description = "Group under which vaultwarden runs";
    };
    enableSignups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow new user registrations";
    };
    enableInvitations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow users to send invitations to others";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vaultwarden";
      description = ''
        Directory where vaultwarden stores its data.
        Will be created automatically with correct permissions.
      '';
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vaultwarden;
      description = "The vaultwarden package to use";
    };
    backupDir = mkStringOption "/var/backup/vaultwarden";
  };

  config = lib.mkIf cfg.enable {
    # Create required directories with proper ownership and restrictive permissions.
    # 0750 ensures only vaultwarden user/group can access these directories.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/attachments 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/icon_cache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/sends 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.backupDir} 0750 ${cfg.user} ${cfg.group} -"
      # Enable migration from bitwarden_rs
      "d /var/lib/vaultwarden 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Create a dedicated system user for the vaultwarden service.
    # This user:
    # - Cannot log in (shell set to shadow, password disabled)
    # - Has no interactive shell access
    # - Can only access its own data directories
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      shell = pkgs.shadow; # Disable shell access
      hashedPassword = "!"; # Disable password login
    };

    # Create a dedicated group for the service
    users.groups.${cfg.group} = { };

    services.vaultwarden = {
      enable = true;
      package = cfg.package;
      environmentFile = config.age.secrets.vaultwarden-credentials.path;
      config = {
        DATA_FOLDER = cfg.dataDir;
        DOMAIN = "https://${cfg.domain}";
        WEB_VAULT_URL = "http://127.0.0.1:${toString cfg.port}";
        ROCKET_PORT = cfg.port;
        SIGNUPS_ALLOWED = cfg.enableSignups;
        WEBSOCKET_ENABLED = true;
        INVITATIONS_ALLOWED = cfg.enableInvitations;
        PUSH_ENABLED = true;
      };
      backupDir = cfg.backupDir;
    };

    # Ensure proper permissions on service start
    systemd.services.vaultwarden = {
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        # Add security hardening
        ProtectSystem = "strict";
        ReadWritePaths = [
          cfg.dataDir
          cfg.backupDir
          "/var/lib/bitwarden_rs/" # Enable migration from bitwarden_rs
        ];
        NoNewPrivileges = true;
      };
    };

    # Configure backup service
    systemd.services.backup-vaultwarden = {
      description = "Backup vaultwarden";
      environment = lib.mkForce {
        DATA_FOLDER = cfg.dataDir;
        BACKUP_FOLDER = cfg.backupDir;
      };
      path = with pkgs; [
        sqlite # For database backup
        coreutils # For cp, mkdir, etc.
        bash # For shell script execution
      ];
      # if both services are started at the same time, vaultwarden fails with "database is locked"
      before = [ "vaultwarden.service" ];
      serviceConfig = {
        SyslogIdentifier = "backup-vaultwarden";
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = lib.mkForce cfg.group;
        # Add security hardening
        ProtectSystem = "strict";
        ReadWritePaths = [
          cfg.dataDir
          cfg.backupDir
          "/var/lib/bitwarden_rs" # For migration
          "${pkgs.sqlite}/bin" # For sqlite3
          "${pkgs.coreutils}/bin" # For cp
          "${pkgs.bash}/bin" # For bash
        ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ExecStart = lib.mkForce (
          let
            backupScript = pkgs.writeShellScript "backup-vaultwarden" ''
              #!/usr/bin/env bash

              # Allow use of !() when copying to not copy certain files
              shopt -s extglob

              # Based on: https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault
              if [ ! -d "$BACKUP_FOLDER" ]; then
                echo "Backup folder '$BACKUP_FOLDER' does not exist" >&2
                exit 1
              fi

              if [[ -f "$DATA_FOLDER"/db.sqlite3 ]]; then
                ${pkgs.sqlite}/bin/sqlite3 "$DATA_FOLDER"/db.sqlite3 ".backup '$BACKUP_FOLDER/db.sqlite3'"
              fi

              if [ ! -d "$DATA_FOLDER" ]; then
                echo "No data folder (yet). This will happen on first launch if backup is triggered before vaultwarden has started."
                exit 0
              fi

              ${pkgs.coreutils}/bin/cp -r "$DATA_FOLDER"/!(db.*) "$BACKUP_FOLDER"/
            '';
          in
          "${backupScript}"
        );
      };
      wantedBy = [ "multi-user.target" ];
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
        proxyWebsockets = true;
        extraConfig = ''
          add_header X-Robots-Tag "none";
        '';
      };
    };

  };
}
