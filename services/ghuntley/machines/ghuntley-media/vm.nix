# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  makeNFSMount = { nfsServer, nfsPath }: {
    device = "${nfsServer}:${nfsPath}";
    fsType = "nfs";
    options = [
      "noatime"
      "nodiratime"
      "rsize=1048576"
      "wsize=1048576"
      "actimeo=600"
      "timeo=600"
      "retrans=2"
      "vers=4.2"
      "rw"
      "x-systemd.requires=network-online.target"
      "x-systemd.after=network-online.target"
      "x-systemd.required-by=multi-user.target"
      "x-systemd.before=multi-user.target"
      "_netdev"
    ];
  };

  nixosSystem = (import (pkgs.path + "/nixos/lib/eval-config.nix")) {
    system = builtins.currentSystem;
    pkgs = pkgs;
    specialArgs = { inherit depot; };
    modules = [
      ({ modulesPath, pkgs, lib, config, ... }: {
        imports = [
          (modulesPath + "/installer/netboot/netboot.nix")
          (depot.path + "/infra/nixos-modules/defaults-netboot-service.nix")
        ];

        networking.hostName = "ghuntley-media";
        networking.domain = "ghuntley";

        # Ensure mount point exists before NFS mount
        systemd.tmpfiles.rules = [
          "d /mnt/media 0777 nobody nogroup -"
        ];

        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/netdata";
        };


        fileSystems."/var/lib/plex" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/plex";
        };

        fileSystems."/var/lib/ombi" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/ombi";
        };

        fileSystems."/var/lib/sonarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/sonarr";
        };

        fileSystems."/var/lib/radarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/radarr";
        };

        fileSystems."/var/lib/lidarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/lidarr";
        };

        fileSystems."/var/lib/sabnzbd" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-media/sabnzbd";
        };

        fileSystems."/mnt/media" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/ghuntley/media";
        };

        networking = {
          firewall = {
            allowedTCPPorts = [
              80 # HTTP
              8080 # Sabnzbd
              5000 # Ombi
              8989 # Sonarr
              7878 # Radarr
              8686 # Lidarr
              32400 # Plex Media Server
            ];
            allowedUDPPorts = [
              32400 # Plex Media Server
            ];
          };
        };

        services.plex = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.plex = {
          after = [ "var-lib-plex.mount" "mnt-media.mount" ];
          requires = [ "var-lib-plex.mount" "mnt-media.mount" ];
        };

        services.sabnzbd = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.sabnzbd = {
          wantedBy = [ "multi-user.target" ];
          after = [ "var-lib-sabnzbd.mount" ];
          requires = [ "var-lib-sabnzbd.mount" ];

          serviceConfig = {
            PrivateMounts = lib.mkForce false;
            MountFlags = lib.mkForce "shared";
            StateDirectory = lib.mkForce "";
            RuntimeDirectory = lib.mkForce "sabnzbd";
            CacheDirectory = lib.mkForce "sabnzbd";
            PrivateTmp = lib.mkForce false;
          };
        };

        services.ombi = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.ombi = {
          after = [ "var-lib-ombi.mount" "mnt-media.mount" ];
          requires = [ "var-lib-ombi.mount" "mnt-media.mount" ];
        };

        services.sonarr = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.sonarr = {
          after = [ "var-lib-sonarr.mount" "mnt-media.mount" ];
          requires = [ "var-lib-sonarr.mount" "mnt-media.mount" ];
        };

        services.radarr = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.radarr = {
          after = [ "var-lib-radarr.mount" "mnt-media.mount" ];
          requires = [ "var-lib-radarr.mount" "mnt-media.mount" ];
        };

        services.lidarr = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.lidarr = {
          after = [ "var-lib-lidarr.mount" "mnt-media.mount" ];
          requires = [ "var-lib-lidarr.mount" "mnt-media.mount" ];
        };

      })
    ];
  };
in
{
  vm = nixosSystem.config.system.build.vm;
  netboot = nixosSystem.config.system.build.netbootRamdisk;
  netbootIpxe = nixosSystem.config.system.build.netbootIpxeScript;
  kernel = nixosSystem.config.system.build.kernel;
  toplevel = nixosSystem.config.system.build.toplevel;
}
