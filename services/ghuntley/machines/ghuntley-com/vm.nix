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
          (depot.path + "/infra/nixos-modules/podman.nix")
          (depot.path + "/infra/nixos-modules/goatcounter.nix")
          (depot.path + "/infra/nixos-modules/geoipupdate.nix")
        ];

        networking.hostName = "ghuntley-com";
        networking.domain = "ghuntley";

        networking.defaultGateway.address = "51.161.203.254";
        networking.nameservers = [ "1.1.1.1" ];

        networking.bridges."br0".interfaces = [ "eth1" ];
        networking.firewall.interfaces."br0".allowedTCPPorts = [ 80 443 ];

        networking.interfaces."br0".ipv4.addresses = [
          {
            address = "51.161.203.147";
            prefixLength = 24;
          }
        ];

        fileSystems."/var/lib/acme" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-com/acme";
        };

        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-com/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-com/netdata";
        };

        fileSystems."/var/lib/goatcounter" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-com/goatcounter";
        };

        fileSystems."/srv" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-com/srv";
        };

        services.depot.goatcounter = {
          enable = true;
          domain = "stats.ghuntley.com";
          port = 8010;
          stateDir = "/var/lib/goatcounter";
        };

        services.depot.geoipupdate = {
          enable = true;
          accountId = 1125904;
          stateDir = "/var/lib/goatcounter";
          licenseKey = "/var/lib/goatcounter/geoipupdate-license-key";
        };

        # Ghost container configuration
        virtualisation.oci-containers.containers."ghost" = {
          image = "ghost:latest";
          ports = [
            "3001:2368"
          ];
          volumes = [
            "/srv/ghuntley.com/ghost:/var/lib/ghost/content:cached"
            "/srv/ghuntley.com/ghost/config.production.json:/var/lib/ghost/config.production.json"
          ];
          environment = {
            url = "https://ghuntley.com";
            database__client = "sqlite3";
            database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
            #DEBUG = "ghost:*";
            #NODE_ENV = "development";
            #logging__level = "debug";
            #database__debug = "true";
          };
        };

        # Update service configuration
        systemd.services.docker-pull-ghost = {
          serviceConfig.User = "root";
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.docker
            pkgs.systemd
          ];
          script = ''
            ${pkgs.docker}/bin/docker pull ghost
            ${pkgs.systemd}/bin/systemctl restart docker-ghost
          '';
        };

        systemd.timers.docker-pull-ghost = {
          wantedBy = [ "timers.target" ];
          partOf = [ "docker-pull-ghost.service" ];
          timerConfig.OnCalendar = "daily";
        };

        security.acme.acceptTerms = true;
        security.acme.defaults.email = "ghuntley@ghuntley.com";

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
          '';
        };

        services.nginx.virtualHosts."ghuntley.com" = {
          serverAliases = [ "www.ghuntley.com" ];

          forceSSL = true;
          enableACME = true;

          locations."/" = {
            extraConfig = ''
              proxy_pass http://127.0.0.1:3001;
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


          locations."/linktree/" = {
            extraConfig = ''
              alias /srv/linktree/;
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
