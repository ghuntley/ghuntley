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

          enableBackups = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to include this mount in restic backups";
          };

          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional arguments to pass to geesefs";
          };

          uidAttr = mkOption {
            type = types.str;
            default = "root";
            description = "User ID metadata attribute name";
          };

          gidAttr = mkOption {
            type = types.str;
            default = "wheel";
            description = "Group ID metadata attribute name";
          };

          dirMode = mkOption {
            type = types.ints.between 0 511; # 0-777 in octal
            default = 493; # 0755 in octal
            description = "Default permission bits for directories (octal)";
          };

          fileMode = mkOption {
            type = types.ints.between 0 511; # 0-777 in octal
            default = 420; # 0644 in octal
            description = "Default permission bits for files (octal)";
          };

          cluster = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable cluster mode";
            };

            enableGrpcReflection = mkOption {
              type = types.bool;
              default = false;
              description = "Enable gRPC reflection (only valid when cluster mode is enabled)";
            };

            nodeId = mkOption {
              type = types.str;
              description = "Node ID for this cluster node";
              example = "node1";
            };

            address = mkOption {
              type = types.str;
              description = "Address for this cluster node";
              example = "127.0.0.0";
            };

            port = mkOption {
              type = types.int;
              description = "Port for this cluster node";
              example = 5619;
            };

            peers = mkOption {
              type = types.listOf (types.submodule {
                options = {
                  nodeId = mkOption {
                    type = types.str;
                    description = "Peer node ID";
                    example = "node2";
                  };
                  address = mkOption {
                    type = types.str;
                    description = "Peer node address";
                    example = "192.168.1.11:5000";
                  };
                };
              });
              default = [ ];
              description = "List of peer nodes in the cluster";
            };
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
                -f \
                --cache /var/cache/geesefs \
                --endpoint ${mount.endpoint} \
                --region ${mount.region} \
                --uid-attr ${mount.uidAttr} \
                --gid-attr ${mount.gidAttr} \
                --dir-mode ${toString mount.dirMode} \
                --file-mode ${toString mount.fileMode} \
                ${lib.optionalString mount.cluster.enable "--cluster"} \
                ${lib.optionalString (mount.cluster.enable && mount.cluster.enableGrpcReflection) "--grpc-reflection"} \
                ${lib.optionalString mount.cluster.enable "--cluster-me ${mount.cluster.nodeId}:${mount.cluster.address}:${toString mount.cluster.port}"} \
                ${lib.concatMapStrings (peer: " --cluster-peer ${peer.nodeId}:${peer.address}") mount.cluster.peers} \
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

    # Open tailscale firewall ports for GeeseFS cluster communication
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.optionals (any (mount: mount.cluster.enable) (attrValues cfg.mounts))
      (lib.unique (map (mount: mount.cluster.port) (filter (mount: mount.cluster.enable) (attrValues cfg.mounts)))); # GeeseFS cluster ports

    # Add the mount points to restic backup paths
    services.depot.restic.paths = mapAttrsToList
      (name: mount: if mount.enableBackups then mount.mountPoint else null)
      (filterAttrs (name: mount: mount.enableBackups) cfg.mounts);

  };
}
