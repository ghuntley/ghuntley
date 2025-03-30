# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  inherit (depot.nix.nfs) makeNFSMount;

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

        networking.defaultGateway.address = "139.99.136.254";
        networking.nameservers = [ "1.1.1.1" ];

        networking.bridges."br0".interfaces = [ "eth1" ];

        networking.interfaces."br0".ipv4.addresses = [
          {
            address = "139.99.136.165";
            prefixLength = 24;
          }
        ];

        # Ensure mount point exists before NFS mount
        systemd.tmpfiles.rules = [
          "d /mnt/media 0777 nobody nogroup -"
        ];

        fileSystems."/var/lib/acme" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/acme";
        };

        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/netdata";
        };


        fileSystems."/var/lib/plex" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/plex";
        };

        fileSystems."/var/lib/jellyfin" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/jellyfin";
        };

        fileSystems."/var/cache/jellyfin" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/jellyfin-cache";
        };

        fileSystems."/var/lib/ombi" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/ombi";
        };

        fileSystems."/var/lib/sonarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/sonarr";
        };

        fileSystems."/var/lib/radarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/radarr";
        };

        fileSystems."/var/lib/lidarr" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/lidarr";
        };

        fileSystems."/var/lib/sabnzbd" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-media/sabnzbd";
        };

        fileSystems."/mnt/media" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/ghuntley/media";
        };

        networking = {
          firewall = {
            allowedTCPPorts = [
              80 # HTTP
              443 # HTTPS
              32400 # Plex Media Server
            ];
            allowedUDPPorts = [
              32400 # Plex Media Server
            ];
          };
        };

        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
          80 # HTTP
          443 # HTTPS
          8080 # Sabnzbd
          5000 # Ombi
          8989 # Sonarr
          7878 # Radarr
          8686 # Lidarr
          32400 # Plex Media Server
        ];

        networking.firewall.interfaces."tailscale0".allowedUDPPorts = [
          32400 # Plex Media Server
        ];

        environment.systemPackages = [
          pkgs.ffmpeg
        ];

        services.plex = {
          enable = true;
          user = "nobody";
          group = "nogroup";
        };

        systemd.services.plex = {
          after = [ "var-lib-plex.mount" "mnt-media.mount" ];
          requires = [ "var-lib-plex.mount" "mnt-media.mount" ];
        };

        services.jellyfin = {
          enable = true;
          user = "nobody";
          group = "nogroup";
          cacheDir = "/var/cache/jellyfin";
          dataDir = "/var/lib/jellyfin";
        };

        systemd.services.jellyfin = {
          after = [ "var-lib-jellyfin.mount" "var-cache-jellyfin.mount" "mnt-media.mount" ];
          requires = [ "var-lib-jellyfin.mount" "var-cache-jellyfin.mount" "mnt-media.mount" ];
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

        security.acme.acceptTerms = true;
        security.acme.defaults.email = "ghuntley@ghuntley.com";

        systemd.services.nginx = {
          after = [ "var-lib-acme.mount" ];
          requires = [ "var-lib-acme.mount" ];
        };

        services.nginx = {
          enable = true;

          # Use recommended settings
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;

          # Only allow PFS-enabled ciphers with AES256
          sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

          commonHttpConfig = ''
            # Add HSTS header with preloading to HTTPS requests.
            # Adding this header to HTTP requests is discouraged
            map $scheme $hsts_header {
                https   "max-age=31536000; includeSubdomains; preload";
            }
            add_header Strict-Transport-Security $hsts_header;

            # Enable CSP for your services.
            #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

            # Minimize information leaked to other domains
            add_header 'Referrer-Policy' 'origin-when-cross-origin';

            # Disable embedding as a frame
            add_header X-Frame-Options DENY;

            # Prevent injection of code in other mime types (XSS Attacks)
            add_header X-Content-Type-Options nosniff;

            # Enable XSS protection of the browser.
            # May be unnecessary when CSP is configured properly (see above)
            add_header X-XSS-Protection "1; mode=block";

            # This might create errors
            proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";

            # Prevent search engines from indexing the site
            add_header X-Robots-Tag "none";
          '';
        };

        services.nginx.virtualHosts."media.ghuntley.net" = {

          forceSSL = true;
          enableACME = true;

          locations."/" = {
            extraConfig = ''
              proxy_pass http://127.0.0.1:8096;
              proxy_pass_header Authorization;
              proxy_http_version 1.1;
              proxy_ssl_server_name on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Host $host;

              # Disable buffering when the nginx proxy gets very resource heavy upon streaming
              proxy_buffering off;
            '';
          };

          locations."/socket" = {
            extraConfig = ''
              proxy_pass http://127.0.0.1:8096;
              proxy_pass_header Authorization;
              proxy_http_version 1.1;
              proxy_ssl_server_name on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Host $host;
            '';
          };

        };


        services.nginx.virtualHosts."requests.media.ghuntley.net" = {

          forceSSL = true;
          enableACME = true;

          locations."/" = {
            extraConfig = ''
              proxy_pass http://127.0.0.1:5000;
              proxy_pass_header Authorization;
              proxy_http_version 1.1;
              proxy_ssl_server_name on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Host $host;
            '';
          };
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
