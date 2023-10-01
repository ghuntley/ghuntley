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
    (mod "defaults-qemu.nix")
    (mod "podman.nix")
    (mod "tailscale-exit-node.nix")
    (mod "caddy.nix")
    (service "com-ghuntley/ghost.nix")
    (service "com-ghuntley/webserver.nix")
  ];

  boot.tmp.useTmpfs = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/46f15764-b489-4599-b566-c5abe81ed429";
      fsType = "ext4";
    };

  swapDevices = [ ];

  networking.hostName = "ghuntley-com";
  networking.domain = "servers";

  networking.useDHCP = false;

  #networking.firewall.interfaces."eno1".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  networking.firewall.enable = true;
  networking.firewall.interfaces."ens18".allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces."ens18".allowedUDPPorts = [ 80 443 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.defaultGateway.address = "51.161.203.254";
  networking.nameservers = [ "1.1.1.1" ];

  networking.interfaces."ens18".ipv4.addresses = [
    {
      address = "51.161.203.147";
      prefixLength = 24;
    }
  ];

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-nix-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 32; # GiB
    maxFreed = 16; # GiB
    preserveGenerations = "31d";
  };

  systemd.services.backup = {
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";

    path = [
      pkgs.rsync
      pkgs.openssh
    ];

    script = ''
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress  -e "ssh -i ${config.age.secrets.rsync-net-backups-ssh-key.path}"  /depot zh2297@zh2297.rsync.net:machines/ghuntley.com/
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress -e "ssh -i ${config.age.secrets.rsync-net-backups-ssh-key.path}" /srv zh2297@zh2297.rsync.net:machines/ghuntley.com/
      ${pkgs.rsync}/bin/rsync --archive --verbose --human-readable --delete-after --stats --compress -e "ssh -i ${config.age.secrets.rsync-net-backups-ssh-key.path}" /etc zh2297@zh2297.rsync.net:machines/ghuntley.com/
    '';
  };

  systemd.timers.backup = {
    wantedBy = [ "timers.target" ];
    partOf = [ "backup.service" ];
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

      rsync-net-backups-ssh-key.file = secretFile "rsync-net-backups-ssh-key";
      rsync-net-backups-ssh-key.symlink = false;
    };


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05";
}
