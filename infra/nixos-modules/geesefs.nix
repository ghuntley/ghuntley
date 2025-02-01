# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, depot, services, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.depot.geesefs;
in
{
  options.services.depot.geesefs = {
    enable = mkEnableOption "GeeseFS S3 FUSE filesystem";

    mounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          bucket = mkOption {
            type = types.str;
            description = "S3 bucket name to mount";
          };

          mountPoint = mkOption {
            type = types.str;
            description = "Local directory where the S3 bucket will be mounted";
          };

          endpoint = mkOption {
            type = types.str;
            default = "https://s3.amazonaws.com";
            description = "S3 endpoint URL";
          };

          credentialsFile = mkOption {
            type = types.path;
            description = "Path to file containing AWS credentials (access key ID and secret access key)";
          };

          region = mkOption {
            type = types.str;
            default = "us-east-1";
            description = "AWS region";
          };

          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional arguments to pass to geesefs";
          };
        };
      });
      default = { };
      description = "GeeseFS mount configurations";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.geesefs ];

    systemd.services = mapAttrs'
      (name: mount:
        nameValuePair "geesefs-${name}" {
          description = "GeeseFS mount for ${mount.bucket}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = {
            AWS_SHARED_CREDENTIALS_FILE = mount.credentialsFile;
          };

          serviceConfig = {
            Type = "simple";
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mount.mountPoint}";
            ExecStart = ''
              ${pkgs.geesefs}/bin/geesefs \
                --endpoint ${mount.endpoint} \
                --region ${mount.region} \
                ${toString mount.extraArgs} \
                ${mount.bucket} ${mount.mountPoint}
            '';
            ExecStop = "${pkgs.fuse}/bin/fusermount -u ${mount.mountPoint}";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        }
      )
      cfg.mounts;

    # Add the mount points to restic backup paths
    services.depot.restic.paths = mapAttrsToList
      (name: mount: mount.mountPoint)
      cfg.mounts;

  };


}
