# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, pkgs, ... }:

let
  nixosSystem = (import (pkgs.path + "/nixos/lib/eval-config.nix")) {
    system = builtins.currentSystem;
    pkgs = pkgs;
    specialArgs = { inherit depot; };
    modules = [
      ({ modulesPath, pkgs, lib, config, ... }: {
        imports = [
          (modulesPath + "/virtualisation/qemu-vm.nix")
          (modulesPath + "/installer/cd-dvd/iso-image.nix")
          (modulesPath + "/installer/netboot/netboot.nix")
          # (depot.path + "/infra/nixos-modules/goatcounter.nix")
        ];

        system.stateVersion = "24.11";

        networking.hostName = "ghuntley-com";
        networking.domain = "ghuntley";

        # # PXE boot configuration
        # # Include necessary packages in the netboot image
        # netboot.storeContents = with pkgs; [
        #   stdenv
        #   busybox
        #   nix
        #   nixos-install-tools
        # ];

        # # Ensure required kernel modules for netboot are included
        # boot.initrd.availableKernelModules = [
        #   "virtio_pci"
        #   "virtio_blk"
        #   "virtio_net"
        #   "virtio_rng"
        #   "virtio_console"
        #   "9p"
        #   "9pnet"
        #   "9pnet_virtio"
        #   "overlay"
        #   "squashfs"
        # ];

        # # Force inclusion of these modules
        # boot.initrd.kernelModules = [
        #   "squashfs"
        #   "overlay"
        #   "9p"
        #   "9pnet"
        #   "9pnet_virtio"
        # ];

        # # Make sure all modules are included in the netboot
        # # netboot.includeSystemBuildDependencies = true;  # This option no longer exists

        # # Add additional debugging options for netboot
        # boot.kernelParams = [
        #   "console=ttyS0"
        #   "console=tty1"
        #   "loglevel=7" # Maximum log level
        #   "debug"
        #   "boot.shell_on_fail" # Drop to shell on failure
        # ];

        # # Network configuration for proper PXE functionality
        # networking = {
        #   useDHCP = true;
        #   dhcpcd.enable = true;
        #   firewall.allowedUDPPorts = [ 67 68 69 4011 ]; # DHCP and TFTP ports
        # };

        # system.activationScripts.createCustomDirs = ''
        #   mkdir -p /srv/ghost
        #   mkdir -p /srv/linktree
        #   chown -R nginx:nginx /srv/linktree
        #   chmod -R 0755 /srv/linktree
        # '';

        # # Run nginx
        # security.acme.acceptTerms = true;
        # security.acme.defaults.email = "ghuntley@ghuntley.com";

        # services.nginx = {
        #   enable = true;

        #   # Use recommended settings
        #   recommendedGzipSettings = true;
        #   recommendedOptimisation = true;
        #   recommendedProxySettings = true;
        #   recommendedTlsSettings = true;

        #   # Only allow PFS-enabled ciphers with AES256
        #   sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

        #   commonHttpConfig = ''
        #     # Add HSTS header with preloading to HTTPS requests.
        #     # Adding this header to HTTP requests is discouraged
        #     map $scheme $hsts_header {
        #         https   "max-age=31536000; includeSubdomains; preload";
        #     }
        #     add_header Strict-Transport-Security $hsts_header;

        #     # Enable CSP for your services.
        #     #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

        #     # Minimize information leaked to other domains
        #     add_header 'Referrer-Policy' 'origin-when-cross-origin';

        #     # Disable embedding as a frame
        #     # add_header X-Frame-Options DENY;

        #     # Prevent injection of code in other mime types (XSS Attacks)
        #     add_header X-Content-Type-Options nosniff;

        #     # Enable XSS protection of the browser.
        #     # May be unnecessary when CSP is configured properly (see above)
        #     add_header X-XSS-Protection "1; mode=block";

        #     # This might create errors
        #     proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
        #   '';
        # };

        # services.nginx.virtualHosts."ghuntley.com" = {

        #   forceSSL = true;
        #   enableACME = true;

        #   locations."/" = {
        #     extraConfig = ''
        #       proxy_pass http://localhost:3001;
        #       proxy_pass_header Authorization;
        #       proxy_http_version 1.1;
        #       proxy_ssl_server_name on;
        #       proxy_set_header Upgrade $http_upgrade;
        #       proxy_set_header Connection "upgrade";
        #       proxy_set_header X-Real-IP $remote_addr;
        #       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        #       proxy_set_header X-Forwarded-Proto $scheme;
        #       proxy_buffering off;
        #     '';
        #   };

        #   locations."/linktree/" = {
        #     extraConfig = ''
        #       alias /srv/linktree/;
        #     '';
        #   };
        # };

        # # Enable and configure containerd
        # virtualisation.containerd = {
        #   enable = true;
        #   settings = {
        #     version = 2;
        #     plugins."io.containerd.grpc.v1.cri" = {
        #       containerd.runtimes.runc = {
        #         runtime_type = "io.containerd.runc.v2";
        #       };
        #     };
        #   };
        # };

        # # Configure Docker through native NixOS options
        # systemd.services.docker = {
        #   description = "Docker Application Container Engine";
        #   wantedBy = [ "multi-user.target" ];
        #   after = [ "network-online.target" ];
        #   wants = [ "network-online.target" ];
        #   serviceConfig = {
        #     Type = "notify";
        #     Environment = [
        #       "DOCKER_TMPDIR=/var/run/docker"
        #     ];
        #     ExecStart = [
        #       "" # Clear any existing ExecStart
        #       "${pkgs.docker}/bin/dockerd --containerd=/run/containerd/containerd.sock --debug --log-level=debug"
        #     ];
        #     ExecReload = [
        #       "${pkgs.procps}/bin/kill -s HUP $MAINPID"
        #     ];
        #     LimitNOFILE = "infinity";
        #     LimitNPROC = "infinity";
        #     LimitCORE = "infinity";
        #     TimeoutStartSec = "0";
        #     TimeoutStopSec = "120";
        #     Restart = "always";
        #     RestartSec = "2s";
        #   };
        # };

        # # Ghost container configuration
        # virtualisation.oci-containers.containers."ghost" = {
        #   image = "ghost:latest";
        #   ports = [
        #     "3001:2368"
        #   ];
        #   volumes = [
        #     "/srv/ghost:/var/lib/ghost/content:cached"
        #     "/srv/ghost/config.production.json:/var/lib/ghost/config.production.json"
        #   ];
        #   environment = {
        #     url = "https://ghuntley.com";
        #     database__client = "sqlite3";
        #     database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
        #     #DEBUG = "ghost:*";
        #     #NODE_ENV = "development";
        #     #logging__level = "debug";
        #     #database__debug = "true";
        #   };
        # };

        # # Update service configuration
        # systemd.services.podman-pull-ghost = {
        #   serviceConfig.User = "root";
        #   serviceConfig.Type = "oneshot";
        #   path = [
        #     pkgs.docker
        #     pkgs.systemd
        #   ];
        #   script = ''
        #     ${pkgs.docker}/bin/docker pull ghost
        #     ${pkgs.systemd}/bin/systemctl restart podman-ghost
        #   '';
        # };

        # systemd.timers.podman-pull-ghost = {
        #   wantedBy = [ "timers.target" ];
        #   partOf = [ "podman-pull-ghost.service" ];
        #   timerConfig.OnCalendar = "daily";
        # };

        # # Configure secrets for services that need them.
        # age.secrets =
        #   let
        #     secretFile = name: depot.infra.secrets.ponderoos."${name}.age";
        #   in
        #   {
        #     ovh-backup-credentials.file = secretFile "ovh-backup-credentials";
        #     ovh-backup-credentials.symlink = false;

        #     ovh-backup-encryption-key.file = secretFile "ovh-backup-encryption-key";
        #     ovh-backup-encryption-key.symlink = false;

        #     nix-cache-pubkey.file = secretFile "nix-cache-pubkey";
        #     nix-cache-pubkey.symlink = false;
        #   };

        # virtualisation = {
        #   memorySize = 8192;
        #   cores = 16;
        #   graphics = false;
        #   diskSize = 98304; # Size in MiB (96 GiB)
        # };

        # # Set empty root password
        # users.users.root.initialPassword = "";

        # isoImage.makeEfiBootable = true;
        # isoImage.makeUsbBootable = true;

      })
    ];
  };
in
{
  vm = nixosSystem.config.system.build.vm;
  iso = nixosSystem.config.system.build.isoImage;
  netboot = nixosSystem.config.system.build.netbootRamdisk;
  netbootIpxe = nixosSystem.config.system.build.netbootIpxeScript;
  kernel = nixosSystem.config.system.build.kernel;
  toplevel = nixosSystem.config.system.build.toplevel;
}
