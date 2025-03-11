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
          # We're overriding the problematic settings from this module directly
          (depot.path + "/infra/nixos-modules/defaults-qemu-service.nix")
        ];

        system.stateVersion = "24.11";

        networking.hostName = "com-ghuntley-media";
        networking.domain = "ghuntley";

        # PXE boot configuration
        # Include necessary packages in the netboot image
        netboot.storeContents = with pkgs; [
          stdenv
          busybox
          nix
          nixos-install-tools
        ];

        # Ensure required kernel modules for netboot are included
        boot.initrd.availableKernelModules = [
          "virtio_pci"
          "virtio_blk"
          "virtio_net"
          "virtio_rng"
          "virtio_console"
          "9p"
          "9pnet"
          "9pnet_virtio"
          "overlay"
          "squashfs"
        ];

        # Force inclusion of these modules
        boot.initrd.kernelModules = [
          "squashfs"
          "overlay"
          "9p"
          "9pnet"
          "9pnet_virtio"
        ];

        # Override any postDeviceCommands from other modules since we're using systemd in initrd
        boot.initrd.postDeviceCommands = lib.mkForce "";

        # Override problematic defaults in defaults-qemu-service.nix
        boot.initrd.systemd = {
          enable = true;
          # Make sure systemd handles the mounting of /dev
          services."dev-mount" = lib.mkForce {
            description = "Mount devtmpfs at /dev";
            wantedBy = [ "initrd-fs.target" ];
            before = [ "initrd-fs.target" ];
            unitConfig.DefaultDependencies = "no";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              if ! mountpoint -q /dev; then
                mkdir -p /dev
                mount -t devtmpfs none /dev
              fi
            '';
          };
        };

        # Add additional debugging options for netboot
        boot.kernelParams = [
          "console=ttyS0"
          "console=tty1"
          "loglevel=7" # Maximum log level
          "debug"
          "boot.shell_on_fail" # Drop to shell on failure
          "ip=dhcp" # Use DHCP for IP configuration
          "netboot.timeout=10" # Reduce timeout for faster boot
          "netboot.9p.windowsize=512" # Larger 9p window size for better performance
          "netboot.9p.msize=16384" # Larger message size for 9p protocol
          "netboot.9p.trans=virtio" # Use virtio transport for 9p
          "netboot.disable_ipv6=1" # Disable IPv6 to speed up boot
        ];

        # Ensure udev is enabled for device management
        services.udev.enable = true;

        # Filesystem configuration for netboot
        # Use an in-memory filesystem for root during PXE boot
        fileSystems."/" = lib.mkForce {
          device = "none";
          fsType = "tmpfs";
          options = [ "defaults" "mode=755" "size=50%" ];
        };

        # Define persistent storage for media data
        # This will be mounted after boot
        fileSystems."/var/lib/media" = lib.mkIf (config.virtualisation.useNixStoreImage or false) {
          device = "/dev/disk/by-label/media";
          fsType = "ext4";
          options = [ "defaults" "nofail" ];
          neededForBoot = false;
        };

        # Create symlinks for media service data directories to point to persistent storage
        system.activationScripts.mediaLinks = ''
          mkdir -p /var/lib/media/{plex,ombi,sonarr,radarr,lidarr,sabnzbd}

          # Create symlinks if they don't exist
          for svc in plex ombi sonarr radarr lidarr sabnzbd; do
            if [ ! -L /var/lib/$svc ]; then
              # Ensure target directory exists
              mkdir -p /var/lib/media/$svc

              # Create symlink
              ln -sfn /var/lib/media/$svc /var/lib/$svc
            fi
          done
        '';

        # Network configuration for proper PXE functionality
        networking = {
          useDHCP = true;
          dhcpcd.enable = true;
          firewall = {
            allowedTCPPorts = [ 32400 67 69 4011 5001 ]; # DHCP, TFTP, Plex, Ombi ports
            allowedUDPPorts = [ 67 68 69 4011 ]; # DHCP and TFTP ports
          };
        };

        # Run nginx
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
            # add_header X-Frame-Options DENY;

            # Prevent injection of code in other mime types (XSS Attacks)
            add_header X-Content-Type-Options nosniff;

            # Enable XSS protection of the browser.
            # May be unnecessary when CSP is configured properly (see above)
            add_header X-XSS-Protection "1; mode=block";

            # This might create errors
            proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";

            # Prevent indexing
            add_header X-Robots-Tag "none";
          '';
        };

        services.nginx.virtualHosts."media.ghuntley.com" = {

          forceSSL = true;
          enableACME = true;

          locations."/" = {
            extraConfig = ''
              proxy_pass http://localhost:5001;
              proxy_pass_header Authorization;
              proxy_http_version 1.1;
              proxy_ssl_server_name on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_buffering off;
            '';
          };
        };

        services.plex.enable = true;

        services.ombi.enable = true;
        services.ombi.port = 5001;

        services.sonarr.enable = true;
        services.radarr.enable = true;
        services.lidarr.enable = true;

        services.sabnzbd.enable = true;

        services.depot.restic = {
          paths = [
            "/var/lib/ombi"
            "/var/lib/plex"
            "/var/lib/sonarr"
            "/var/lib/radarr"
            "/var/lib/lidarr"
            "/var/lib/sabnzbd"
          ];
          exclude = [ "" ];
        };

        # Set empty root password
        users.users.root.initialPassword = "";

        isoImage.makeEfiBootable = true;
        isoImage.makeUsbBootable = true;

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
