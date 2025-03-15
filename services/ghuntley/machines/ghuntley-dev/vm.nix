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
          (depot.path + "/infra/nixos-modules/libvirt.nix")
        ];

        networking.hostName = "dev";
        networking.domain = "ghuntley";

        networking.defaultGateway.address = "51.161.203.254";
        networking.nameservers = [ "1.1.1.1" ];

        networking.bridges."br0".interfaces = [ "eth1" ];
        networking.interfaces."br0".ipv4.addresses = [
          {
            address = "51.161.203.154";
            prefixLength = 24;
          }
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];

        fileSystems."/var/lib/acme" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/acme";
        };

        fileSystems."/var/lib/docker" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/docker";
        };

        fileSystems."/var/lib/libvirt/images" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/libvirt";
        };

        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/netdata";
        };


        fileSystems."/srv" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/rpool/vms/ghuntley-dev/srv";
        };

        networking = {
          firewall = {
            allowedTCPPorts = [
              443 # Coder
              80 # Coder
            ];
          };
        };

        # Coder container configuration
        virtualisation.oci-containers.containers."coder" = {
          image = "ghcr.io/coder/coder:latest";
          ports = [
            "7080:7080"
          ];
          volumes = [
            "/srv:/home/coder"
            "/var/run/docker.sock:/var/run/docker.sock"
            "/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock"
            "/var/lib/libvirt/images:/var/lib/libvirt/images"
            "/dev/kvm:/dev/kvm"
          ];
          environment = {
            CODER_ACCESS_URL = "https://ghuntley.dev";
            CODER_DISABLE_PASSWORD_AUTH = "false";
            CODER_EXPERIMENTS = "*";
            CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "true";
            CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = "true";
            CODER_OIDC_ALLOW_SIGNUPS = "true";
            CODER_REDIRECT_TO_ACCESS_URL = "false";
            CODER_SECURE_AUTH_COOKIE = "true";
            CODER_LOG_FILTER = ".*";
            CODER_TELEMETRY_ENABLED = "true";
            CODER_UPDATE_CHECK = "true";
            CODER_WILDCARD_ACCESS_URL = "*.ghuntley.dev";
          };
          extraOptions = [
            "--network=host"
            "--user=nobody"
            "--group-add=${toString config.users.groups.docker.gid}"
          ];
        };

        # Update service configuration
        systemd.services.docker-pull-coder = {
          serviceConfig.User = "root";
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.docker
            pkgs.systemd
          ];
          script = ''
            ${pkgs.docker}/bin/docker pull ghcr.io/coder/coder:latest
            ${pkgs.systemd}/bin/systemctl restart docker-coder

            # wait for coder container to start before adding cdrkit
            sleep 5
            ${pkgs.docker}/bin/docker exec `docker ps -aqf "name=^coder$"` apk add cdrkit
          '';
        };

        systemd.timers.docker-pull-coder = {
          wantedBy = [ "timers.target" ];
          partOf = [ "docker-pull-coder.service" ];
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

            # Prevent search engines from indexing the site
            add_header X-Robots-Tag "none";
          '';
        };

        services.nginx.virtualHosts."ghuntley.dev" = {

          serverAliases = [ "*.ghuntley.dev" ];

          forceSSL = false;
          enableACME = true;

          locations."/" = {
            extraConfig = ''
              proxy_pass http://localhost:7080;
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
