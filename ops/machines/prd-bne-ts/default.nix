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
    (mod "defaults.nix")
  ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" =
    {
      device = "/dev/mapper/root";
      fsType = "ext4";
    };

  boot.initrd.luks.devices.root = {
    device = "/dev/vda2";

    allowDiscards = true;

    keyFile = "/dev/zero";
    keyFileSize = 1;
    fallbackToPassword = true;
  };

  fileSystems."/boot" =
    {
      device = "/dev/vda1";
      fsType = "ext4";
    };

  swapDevices = [{
    device = "/.swap";
    size = (1024 * 6);
  }];


  networking.hostName = "ts";
  networking.domain = "dmz.corp";

  networking.useDHCP = true;
  networking.interfaces.ens3.useDHCP = true;

  # TODO(security): migrate from public ssh to tailscale only ssh
  networking.firewall.interfaces."ens3".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  # # Automatically collect garbage from the Nix store.
  # services.depot.automatic-gc = {
  #   enable = true;
  #   interval = "1 hour";
  #   diskThreshold = 64; # GiB
  #   maxFreed = 128; # GiB
  #   preserveGenerations = "31d";
  # };

  environment.systemPackages = with pkgs; [
    headscale
    tailscale
  ];

  services.headscale.enable = true;
  services.headscale.address = "0.0.0.0";
  services.headscale.port = 443;
  services.headscale.database.type = "sqlite3";
  services.headscale.derp.autoUpdate = true;
  services.headscale.derp.updateFrequency = "5m";
  services.headscale.dns.baseDomain = "corp.fediversehosting.net";
  services.headscale.dns.domains = [
    "core.corp.fediversehosting.net"
    "corp.fediversehosting.net"
  ];
  services.headscale.dns.magicDns = true;
  services.headscale.ephemeralNodeInactivityTimeout = "30m";
  services.headscale.logLevel = "debug";
  services.headscale.serverUrl = "https://ts.fediversehosting.net:443";
  services.headscale.tls.letsencrypt.hostname = "ts.fediversehosting.net";

  services.tailscale.enable = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 3478 41641 ];
  networking.firewall.checkReversePath = "loose";
  networking.firewall.enable = true;

  services.vector.enable = true;
  services.vector.journaldAccess = true;
  services.vector.settings = {

    #sources.vector = {
    #  type = "internal_metrics";
    #  scrape_interval_secs = 2;
    #};

    sources.host_metrics = {
      type = "host_metrics";
      collectors = [
        "cgroups"
        "cpu"
        "disk"
        "filesystem"
        "load"
        "host"
        "memory"
        "network"
      ];
      scrape_interval_secs = 15;
    };

    sources.journald = {
      type = "journald";
    };


    sources.var_log =
      {
        type = "file";
        include = [
          "/var/log/**/*.log"
          "/var/log/**/*.log"

        ];
        read_from = "beginning";
      };

    sources.opentelemetry = {
      type = "opentelemetry";
      grpc = {
        address = "127.0.0.1:4317";
      };
      http = {
        address = "127.0.0.1:4318";
      };
    };

    sources.headscale = {
      type = "http_client";
      endpoint = "https://ts.fediversehosting.net/health";
      scrape_interval_secs = 15;
    };


    sinks.logtail_sink = {
      type = "http";
      inputs = [ "*" ];
      uri = "https://in.logtail.com/";
      encoding.codec = "json";
      auth.strategy = "bearer";
      auth.token = "qos6rUyfEQnfxGimNi5cSUqC";
    };
  };


}
