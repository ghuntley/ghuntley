# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/ops/nixos-modules/" + name);
  dev = name: depot.path.origSrc + ("/ops/machines/dev/" + name);

in
{
  imports = [
    (mod "boot.nix")
    (mod "cache.nix")
    (mod "fail2ban.nix")
    (mod "i18n.nix")
    (mod "known-hosts.nix")
    (mod "microcode.nix")
    (mod "nixos-vscode-server.nix")
    (mod "nvme.nix")
    (mod "pkgs.nix")
    (mod "sshd.nix")
    (mod "sudo.nix")
    (mod "sysctl.nix")
    (mod "tailscale.nix")
    (mod "timezone.nix")
    (mod "users.nix")

    (depot.third_party.agenix.src + "/modules/age.nix")

    # nginx
    (mod "nginx/com-21kbh.nix")


    # roles
    (dev "./time/configuration.nix")

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
    hostName = "dev";
    domain = "21kbh.com";
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
      buildkite-agent-token = {
        file = secretFile "buildkite-agent-token";
        mode = "0440";
        group = "buildkite-agents";
      };

      buildkite-private-key = {
        file = secretFile "buildkite-ssh-private-key";
        mode = "0440";
        group = "buildkite-agents";
      };

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

    # services - buildkite agents

    check process buildkite-agent-dev-1 with matching "buildkite-agent-dev-1"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-1"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-1"

      check process buildkite-agent-dev-2 with matching "buildkite-agent-dev-2"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-2"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-2"

      check process buildkite-agent-dev-3 with matching "buildkite-agent-dev-3"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-3"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-3"

      check process buildkite-agent-dev-4 with matching "buildkite-agent-dev-4"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-4"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-4"

      check process buildkite-agent-dev-5 with matching "buildkite-agent-dev-5"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-5"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-5"

      check process buildkite-agent-dev-6 with matching "buildkite-agent-dev-6"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-6"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-6"

      check process buildkite-agent-dev-7 with matching "buildkite-agent-dev-7"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-7"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-7"

      check process buildkite-agent-dev-8 with matching "buildkite-agent-dev-8"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-8"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-8"

      check process buildkite-agent-dev-9 with matching "buildkite-agent-dev-9"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-9"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-9"

      check process buildkite-agent-dev-10 with matching "buildkite-agent-dev-10"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-10"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-10"

      check process buildkite-agent-dev-11 with matching "buildkite-agent-dev-11"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-11"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-11"

      check process buildkite-agent-dev-12 with matching "buildkite-agent-dev-12"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-12"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-12"

      check process buildkite-agent-dev-13 with matching "buildkite-agent-dev-13"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-13"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-13"

      check process buildkite-agent-dev-14 with matching "buildkite-agent-dev-14"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-14"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-14"

      check process buildkite-agent-dev-15 with matching "buildkite-agent-dev-15"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-15"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-15"

      check process buildkite-agent-dev-16 with matching "buildkite-agent-dev-16"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-16"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-16"

      check process buildkite-agent-dev-17 with matching "buildkite-agent-dev-17"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-17"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-17"

      check process buildkite-agent-dev-18 with matching "buildkite-agent-dev-18"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-18"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-18"

      check process buildkite-agent-dev-19 with matching "buildkite-agent-dev-19"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-19"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-19"

      check process buildkite-agent-dev-20 with matching "buildkite-agent-dev-20"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-20"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-20"

      check process buildkite-agent-dev-21 with matching "buildkite-agent-dev-21"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-21"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-21"

      check process buildkite-agent-dev-22 with matching "buildkite-agent-dev-22"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-22"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-22"

      check process buildkite-agent-dev-23 with matching "buildkite-agent-dev-23"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-23"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-23"

      check process buildkite-agent-dev-24 with matching "buildkite-agent-dev-24"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-24"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-24"

      check process buildkite-agent-dev-25 with matching "buildkite-agent-dev-25"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-25"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-25"

      check process buildkite-agent-dev-26 with matching "buildkite-agent-dev-26"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-26"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-26"

      check process buildkite-agent-dev-27 with matching "buildkite-agent-dev-27"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-27"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-27"

      check process buildkite-agent-dev-28 with matching "buildkite-agent-dev-28"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-28"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-28"

      check process buildkite-agent-dev-29 with matching "buildkite-agent-dev-29"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-29"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-29"

      check process buildkite-agent-dev-30 with matching "buildkite-agent-dev-30"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-30"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-30"

      check process buildkite-agent-dev-31 with matching "buildkite-agent-dev-31"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-31"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-31"

      check process buildkite-agent-dev-32 with matching "buildkite-agent-dev-32"
            start program = "${pkgs.systemd}/bin/systemctl start buildkite-agent-dev-32"
            stop program = "${pkgs.systemd}/bin/systemctl stop buildkite-agent-dev-32"
  '';

  system.stateVersion = "20.05";

}
