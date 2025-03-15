# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, config, ... }:

# Default set of modules that are imported in all Depot nixos systems
#
# All modules here should be properly gated behind a `lib.mkEnableOption` with a
# `lib.mkIf` for the config.

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);

in
{
  imports = [
    (mod "disable-documentation.nix")
    (mod "fail2ban.nix")
    (mod "fhs-compat.nix")
    (mod "i18n.nix")
    (mod "known-hosts.nix")
    (mod "netdata.nix")
    (mod "nix.nix")
    (mod "pkgs.nix")
    (mod "sshd.nix")
    (mod "sudo.nix")
    (mod "sysctl.nix")
    (mod "tailscale.nix")
    (mod "time.nix")
    (mod "timezone.nix")
    (mod "users.nix")
    (mod "zsh.nix")
  ];

  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];
  boot.initrd.availableKernelModules = [ "virtio_net" "virtio_pci" "virtio_mmio" "virtio_blk" "virtio_scsi" "9p" "9pnet_virtio" ];
  boot.initrd.kernelModules = [ "virtio_balloon" "virtio_console" "virtio_rng" ];

  boot.initrd.postDeviceCommands =
    ''
      # Set the system time from the hardware clock to work around a
      # bug in qemu-kvm > 1.5.2 (where the VM clock is initialised
      # to the *boot time* of the host).
      hwclock -s
    '';

  # Ensure NFS utilities are installed
  environment.systemPackages = with pkgs; [
    nfs-utils
  ];

  boot.loader.grub.enable = false;
  boot.supportedFilesystems = [ "tmpfs" "nfs" ];
  boot.tmp.useTmpfs = true;

  boot.kernel.sysctl = {
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.core.netdev_max_backlog" = 30000;
  };


  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "size=75%" ];
  };

  # Network configuration
  networking = {
    interfaces.eth0.mtu = 9000; # Jumbo frames
    useDHCP = true;
    dhcpcd.enable = true;
  };

  # Firewall rules
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];
  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  # Set empty root password
  users.users.root.initialPassword = "";

  # Netdata
  services.netdata = {
    user = "nobody";
    group = "nogroup";
  };

  # Tailscale
  systemd.services.tailscaled = {
    wantedBy = [ "multi-user.target" ];
    after = [ "var-lib-tailscale.mount" ];
    requires = [ "var-lib-tailscale.mount" ];

    serviceConfig = {
      PrivateMounts = lib.mkForce false;
      MountFlags = lib.mkForce "shared";
      StateDirectory = lib.mkForce "";
      RuntimeDirectory = lib.mkForce "tailscale";
      CacheDirectory = lib.mkForce "tailscale";
      PrivateTmp = lib.mkForce false;

      User = lib.mkForce "root";
      Group = lib.mkForce "wheel";
    };
  };

  # Netdata
  systemd.services.netdata = {
    wantedBy = [ "multi-user.target" ];
    after = [ "var-lib-netdata.mount" ];
    requires = [ "var-lib-netdata.mount" ];

    serviceConfig = {
      PrivateMounts = lib.mkForce false;
      MountFlags = lib.mkForce "shared";
      StateDirectory = lib.mkForce "";
      RuntimeDirectory = lib.mkForce "netdata";
      CacheDirectory = lib.mkForce "netdata";
      PrivateTmp = lib.mkForce false;
    };
  };


  # Goatcounter
  systemd.services.goatcounter = lib.mkIf (config.services ? depot && config.services.depot ? goatcounter && config.services.depot.goatcounter.enable) {
    wantedBy = [ "multi-user.target" ];
    after = [ "var-lib-goatcounter.mount" ];
    requires = [ "var-lib-goatcounter.mount" ];

    serviceConfig = {
      PrivateMounts = lib.mkForce false;
      MountFlags = lib.mkForce "shared";
      StateDirectory = lib.mkForce "";
      RuntimeDirectory = lib.mkForce "goatcounter";
      CacheDirectory = lib.mkForce "goatcounter";
      PrivateTmp = lib.mkForce false;
    };
  };


  system.stateVersion = "24.11";
}
