# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);
  service = name: depot.path.origSrc + ("/services/" + name);

in
{
  imports = [
    (mod "defaults-baremetal.nix")
    (mod "cachix-agent.nix")
    (mod "podman.nix")
    (mod "libvirt.nix")
    (mod "tailscale-exit-node.nix")
    (mod "caddy.nix")
    (service "net-ghuntley/webserver.nix")
    (service "net-ghuntley/libvirt/guests.nix")
    (service "com-ghuntley/ghost.nix")
    (service "dev-ghuntley/coder.nix")
  ];

  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  boot.tmpOnTmpfs = true;

  boot.zfs.devNodes = "/dev/disk/by-id/";
  boot.zfs.forceImportRoot = true;

  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.generationsDir.copyKernels = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.copyKernels = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.zfsSupport = true;

  boot.loader.grub.mirroredBoots = [
    {
      devices = [
        "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595"
      ];
      path = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1";
      efiSysMountPoint = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1";
    }
    {
      devices = [
        "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015"
      ];
      path = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1";
      efiSysMountPoint = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1";
    }
  ];

  boot.initrd.kernelModules = [
    "kvm-amd"
    "kvm-intel"
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
  ];

  boot.initrd.availableKernelModules = [
    "9p"
    "9pnet_virtio"
    "aesni_intel"
    "ahci"
    "ata_piix"
    "cryptd"
    "igb"
    "ixgbe"
    "nvme"
    "sd_mod"
    "sr_mod"
    "uhci_hcd"
    "usb_storage"
    "usbhid"
    "virtio_blk"
    "virtio_mmio"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
  ];

  boot.supportedFilesystems = [ "zfs" ];

  # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
  boot.kernelParams = [ "ip=dhcp" ];

  fileSystems."/" =
    {
      device = "rpool/nixos/root";
      fsType = "zfs";
    };

  fileSystems."/etc" =
    {
      device = "rpool/nixos/etc";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    {
      device = "rpool/nixos/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    {
      device = "rpool/nixos/home";
      fsType = "zfs";
    };

  fileSystems."/var" =
    {
      device = "rpool/nixos/var";
      fsType = "zfs";
    };

  fileSystems."/var/lib" =
    {
      device = "rpool/nixos/var/lib";
      fsType = "zfs";
    };

  fileSystems."/var/lib/libvirt" =
    {
      device = "rpool/nixos/var/lib/libvirt";
      fsType = "zfs";
    };

  fileSystems."/var/lib/libvirt/images" =
    {
      device = "rpool/nixos/var/lib/libvirt/images";
      fsType = "zfs";
    };

  fileSystems."/var/log" =
    {
      device = "rpool/nixos/var/log";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "bpool/nixos/root";
      fsType = "zfs";
    };

  fileSystems."/depot" =
    {
      device = "rpool/data/depot";
      fsType = "zfs";
    };

  fileSystems."/srv" =
    {
      device = "rpool/data/srv";
      fsType = "zfs";
    };

  fileSystems."/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1" =
    {
      device = "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1";
      fsType = "vfat";
      options = [ "nofail" ]; # We want to still be able to boot without one of these
    };

  fileSystems."/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1" =
    {
      device = "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1";
      fsType = "vfat";
      options = [ "nofail" ]; # We want to still be able to boot without one of these
    };

  swapDevices = [ ];

  networking.hostName = "ghuntley-net";
  networking.domain = "servers";

  networking.hostId = "cafebabe";

  networking.useDHCP = false;

  #networking.firewall.interfaces."eno1".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  networking.firewall.enable = true;
  networking.firewall.interfaces."br0".allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces."br0".allowedUDPPorts = [ 80 443 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.defaultGateway.address = "51.161.196.254";
  networking.nameservers = [ "1.1.1.1" ];

  networking.bridges."br0".interfaces = [ "eno1" ];
  networking.interfaces."br0".ipv4.addresses = [
    {
      address = "51.161.196.125";
      prefixLength = 24;
    }
    {
      address = "51.161.213.234";
      prefixLength = 24;
    }
    {
      address = "172.16.65.1";
      prefixLength = 24;
    }
  ];

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-nix-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 64; # GiB
    maxFreed = 128; # GiB
    preserveGenerations = "31d";
  };

  services.sanoid = {
    enable = true;

    templates.extra = {
      hourly = 48;
      daily = 31;
      monthly = 1;
      yearly = 0;

      autosnap = true;
    };

    templates.libvirt = {
      hourly = 24;
      daily = 14;
      monthly = 0;
      yearly = 0;

      autosnap = true;
    };

    templates.postgresql = {
      hourly = 168;
      daily = 14;
      monthly = 0;
      yearly = 0;

      autosnap = true;
    };

    templates.standard = {
      hourly = 24;
      daily = 7;
      monthly = 0;
      yearly = 0;

      autosnap = true;
    };

    templates.none = {
      hourly = 0;
      daily = 0;
      monthly = 0;
      yearly = 0;

      autosnap = false;
    };
  };

  services.sanoid.datasets."rpool/nixos/root".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/nixos/etc".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/nixos/nix".useTemplate = [ "none" ];
  services.sanoid.datasets."rpool/nixos/home".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/nixos/var".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/nixos/var/lib".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/nixos/var/lib/postgresql".useTemplate = [ "postgresql" ];
  services.sanoid.datasets."rpool/nixos/var/lib/libvirt".useTemplate = [ "libvirt" ];
  services.sanoid.datasets."rpool/nixos/var/lib/libvirt/images".useTemplate = [ "libvirt" ];
  services.sanoid.datasets."rpool/nixos/var/log".useTemplate = [ "standard" ];
  services.sanoid.datasets."bpool/nixos/root".useTemplate = [ "standard" ];
  services.sanoid.datasets."rpool/data/depot".useTemplate = [ "extra" ];
  services.sanoid.datasets."rpool/data/srv".useTemplate = [ "extra" ];

  systemd.services.backups = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.rsync
      pkgs.openssh
    ];

    script = ''
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /depot zh2297@zh2297.rsync.net:machines/ghuntley.net/depot
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /srv zh2297@zh2297.rsync.net:machines/ghuntley.net/srv
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /home zh2297@zh2297.rsync.net:machines/ghuntley.net/home
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /var/lib/libvirt zh2297@zh2297.rsync.net:machines/ghuntley.net/var/lib/libvirt
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /var/lib/postgresql zh2297@zh2297.rsync.net:machines/ghuntley.net/var/lib/postgresql
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress /var/log zh2297@zh2297.rsync.net:machines/ghuntley.net/var/lib/log
    '';
  };

  systemd.timers.backup = {
    wantedBy = [ "timers.target" ];
    partOf = [ "backups.service" ];
    timerConfig.OnCalendar = "hourly";
  };

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.ops.secrets."${name}.age";
    in
    {
      ssh-initrd-ed25519-key.file = secretFile "ssh-initrd-ed25519-key";
      ssh-initrd-ed25519-key.symlink = false;

      acme-cloudflare-api-token.file = secretFile "acme-cloudflare-api-token";
      acme-cloudflare-api-token.symlink = false;

      cachix-agent-token.file = secretFile "ghuntley-net-cachix-agent-token";
      cachix-agent-token.path = "/etc/cachix-agent.token";
      cachix-agent-token.symlink = false;

      ghuntley-net-caddy-environment-file.file = secretFile "ghuntley-net-caddy-environment-file";
      ghuntley-net-caddy-environment-file.owner = "caddy";
      ghuntley-net-caddy-environment-file.symlink = false;

      ghuntley-dev-coder-secrets.file = secretFile "ghuntley-dev-coder-secrets";
      ghuntley-dev-coder-secrets.owner = "mgmt";
      ghuntley-dev-coder-secrets.symlink = false;

      coder-gcp-service-account-ghuntley-dev-token.file = secretFile "coder-gcp-service-account-ghuntley-dev-token";
      coder-gcp-service-account-ghuntley-dev-token.path = "/srv/ghuntley.dev/coder-gcp-service-account-ghuntley-dev-token";

      coder-gcp-service-account-ghuntley-dev-token.owner = "mgmt";
      coder-gcp-service-account-ghuntley-dev-token.symlink = false;

      rsync-net-backups-ssh-key.file = secretFile "rsync-net-backups-ssh-key";
      rsync-net-backups-ssh-key.symlink = false;
    };


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11";
}
