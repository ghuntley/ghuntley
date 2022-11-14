# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);

in
{
  imports = [
    (mod "boot.nix")
    (mod "fail2ban.nix")
    (mod "i18n.nix")
    (mod "known-hosts.nix")
    (mod "microcode.nix")
    (mod "nvme.nix")
    (mod "pkgs.nix")
    (mod "sshd.nix")
    (mod "sudo.nix")
    (mod "sysctl.nix")
    (mod "tailscale.nix")
    (mod "time.nix")
    (mod "timezone.nix")
    (mod "users.nix")

    (depot.third_party.agenix.src + "/modules/age.nix")


  ];

  boot.cleanTmpDir = true;

  boot.loader.grub = {
    enable = true;
    version = 2;
    device = "/dev/vda";
  };


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
    "ata_piix"
    "cryptd"
    "igb"
    "nvme"
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

  boot.initrd.luks.devices.root = {
    device = "/dev/vda2";

    # WARNING: Leaks some metadata, see cryptsetup man page for --allow-discards.
    allowDiscards = true;

    # Set your own key with:
    # cryptsetup luksChangeKey /dev/vda2 --key-file=/dev/zero --keyfile-size=1
    # You can then delete the rest of this block.
    keyFile = "/dev/zero";
    keyFileSize = 1;

    fallbackToPassword = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "ext4";
  };

  networking = {
    hostName = "net";
    domain = "fediversehosting.net";
    useDHCP = true;

    # firewall.allowedTCPPorts = [ 22 80 443 ];
    firewall.enable = false;
  };

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 100; # GiB
    maxFreed = 16; # 159
    preserveGenerations = "90d";
  };

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.ops.secrets."${name}.age";
    in
    {

      depot-ops-buildkite-secrets.file = secretFile "depot-ops-buildkite-secrets";
      depot-ops-dns-secrets.file = secretFile "depot-ops-dns-secrets";

    };

  services.monit.enable = true;
  services.monit.config = ''
    set daemon 120 with start delay 60
    set mailserver
        localhost

    set httpd port 2812 read-only and use address localhost
        allow localhost

    check filesystem root with path /
          if space usage > 80% then alert
          if inode usage > 80% then alert

    check system $HOST
          if cpu usage > 95% for 10 cycles then alert
          if memory usage > 75% for 5 cycles then alert
          if swap usage > 20% for 10 cycles then alert
          if loadavg (1min) > 90 for 15 cycles then alert
          if loadavg (5min) > 80 for 10 cycles then alert
          if loadavg (15min) > 70 for 8 cycles then alert

    # services

    check process fail2ban with matching "fail2ban"
          start program = "${pkgs.systemd}/bin/systemctl start fail2ban"
          stop program = "${pkgs.systemd}/bin/systemctl stop fail2ban"

    check process nginx with pidfile /var/run/nginx/nginx.pid
          start program  "${pkgs.systemd}/bin/systemctl start nginx"
          stop program  "${pkgs.systemd}/bin/systemctl stop nginx"
          if failed port 80 protocol http for 2 cycles then restart
          if failed port 443 protocol https for 2 cycles then restart

    check process ntpd with matching "ntpd -g -c"
          start program  "${pkgs.systemd}/bin/systemctl start ntpd"
          stop program  "${pkgs.systemd}/bin/systemctl stop ntpd"
          if failed host 127.0.0.1 port 123 type udp for 2 cycles then restart

    check process sshd with pidfile /var/run/sshd.pid
          start program  "${pkgs.systemd}/bin/systemctl start sshd"
          stop program  "${pkgs.systemd}/bin/systemctl stop sshd"
          if failed port 22 protocol ssh for 2 cycles then restart
  '';

  system.stateVersion = "20.05";

}
