# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Configure restic backups to S3-compatible storage, in our case
# OVH object storage.
#
# Conventions:
# - restic's cache lives in /var/backup/restic/cache
# - repository password lives provided via //infra/secrets
# - object storage credentials provided via //infra/secrets
{ config, lib, pkgs, ... }:

let
  cfg = config.services.depot.restic;
  description = "Restic backups to OVH";
  mkStringOption = default: lib.mkOption {
    inherit default;
    type = lib.types.str;
  };
in
{
  options.services.depot.restic = {
    enable = lib.mkEnableOption description;
    bucketEndpoint = mkStringOption "s3.eu-west-par.io.cloud.ovh.net";
    bucketName = mkStringOption "ponderoos-backup";
    bucketCredentials = mkStringOption config.age.secrets.ovh-backup-credentials.path;
    encryptionKey = mkStringOption config.age.secrets.ovh-backup-encryption-key.path;
    repository = mkStringOption config.networking.hostName;
    interval = mkStringOption "hourly";

    # Retention policy options
    keep-last = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 60; # Keep last 60 snapshots for safety
      description = "Keep the last n snapshots";
    };

    keep-hourly = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 168; # 24 hours × 7 days = full week of hourly backups
      description = "Keep the last n hourly snapshots";
    };

    keep-daily = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 30; # Keep a month of daily backups
      description = "Keep the last n daily snapshots";
    };

    keep-weekly = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 52; # Keep a year of weekly backups
      description = "Keep the last n weekly snapshots";
    };

    keep-monthly = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 24; # Keep 2 years of monthly backups
      description = "Keep the last n monthly snapshots";
    };

    keep-yearly = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 10; # Keep a decade of yearly backups
      description = "Keep the last n yearly snapshots";
    };

    paths = with lib; mkOption {
      description = "Directories that should be backed up";
      type = types.listOf types.str;
    };

    exclude = with lib; mkOption {
      description = "Files that should be excluded from backups";
      type = types.listOf types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    # One-shot service for repository initialization
    systemd.services.restic-init = {
      description = "Initialize Restic repository on OVH";

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
      };

      script = "${pkgs.restic}/bin/restic init || true"; # || true because it's ok if repo already exists

      environment = {
        RESTIC_REPOSITORY = "s3:${cfg.bucketEndpoint}/${cfg.bucketName}/${cfg.repository}";
        AWS_SHARED_CREDENTIALS_FILE = cfg.bucketCredentials;
        RESTIC_PASSWORD_FILE = cfg.encryptionKey;
        RESTIC_CACHE_DIR = "/var/backup/restic/cache";
      };
    };

    systemd.services.restic = {
      description = "Backups to OVH";

      # Ensure we have network
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Basic service configuration
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";

        # Hardening options
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/backup/restic/cache" ];
        PrivateTmp = true;

        # Resource limits
        Nice = 19; # Use as little resources as possible
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
      };

      # Restart handling
      startLimitIntervalSec = 300;
      startLimitBurst = 3;

      script =
        let
          mkForgetFlag = name: value: if value != null then "--${name} ${toString value}" else "";
          forgetFlags = lib.concatStringsSep " " (lib.filter (x: x != "") [
            (mkForgetFlag "keep-last" cfg.keep-last)
            (mkForgetFlag "keep-hourly" cfg.keep-hourly)
            (mkForgetFlag "keep-daily" cfg.keep-daily)
            (mkForgetFlag "keep-weekly" cfg.keep-weekly)
            (mkForgetFlag "keep-monthly" cfg.keep-monthly)
            (mkForgetFlag "keep-yearly" cfg.keep-yearly)
          ]);
        in
        ''
          # First run backup
          ${pkgs.restic}/bin/restic backup ${lib.concatStringsSep " " cfg.paths}

          # Then run forget and prune if any retention policies are set
          if [ "${forgetFlags}" != "" ]; then
            ${pkgs.restic}/bin/restic forget --prune ${forgetFlags}
          fi
        '';

      environment = {
        RESTIC_REPOSITORY = "s3:${cfg.bucketEndpoint}/${cfg.bucketName}/${cfg.repository}";
        AWS_SHARED_CREDENTIALS_FILE = cfg.bucketCredentials;
        RESTIC_PASSWORD_FILE = cfg.encryptionKey;
        RESTIC_CACHE_DIR = "/var/backup/restic/cache";

        RESTIC_EXCLUDE_FILE =
          builtins.toFile "exclude-files" (lib.concatStringsSep "\n" cfg.exclude);
      };
    };

    systemd.timers.restic = {
      wantedBy = [ "multi-user.target" ];
      timerConfig.OnCalendar = cfg.interval;
    };

    # Ensure cache directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/backup/restic/cache 0700 root root -"
    ];

    environment.systemPackages = [ pkgs.restic ];
  };
}
