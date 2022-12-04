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
    (mod "defaults-binarylane.nix")
    (mod "josh.nix")
    (mod "sourcegraph.nix")
  ];

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


  networking.hostName = "code";
  networking.domain = "dmz.corp";

  networking.useDHCP = true;
  networking.interfaces.ens3.useDHCP = true;

  # TODO(security): migrate from public ssh to tailscale only ssh
  networking.firewall.interfaces."ens3".allowedTCPPorts = [ 22 ];

  services.openssh.enable = true;

  # # Automatically collect garbage from the Nix store.
  services.depot.automatic-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 10; # GiB
    maxFreed = 5; # GiB
    preserveGenerations = "14d";
  };

  system.stateVersion = "22.11";

  services.depot.josh.enable = true;
  services.depot.sourcegraph.enable = true;

  services.nginx.virtualHosts.install = {
    serverName = "install.fediversehosting.net";

    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      location = / {
        return 301 https://temp.sh/bwCYU/nixos-23.05pre-git-x86_64-linux.iso;
      }
    '';
  };

  services.nginx.virtualHosts.search = {
    serverName = "search.fediversehosting.net";

    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      location = / {
        return 301 https://search.fediversehosting.net/depot;
      }

      location / {
        proxy_set_header X-Sg-Auth "Anonymous";
        proxy_pass http://localhost:${toString config.services.depot.sourcegraph.port};
      }

      location /users/Anonymous/settings {
        return 301 https://search.fediversehosting.net;
      }
    '';
  };

  services.nginx.virtualHosts.code = {
    serverName = "code.fediversehosting.net";
    serverAliases = [ "code" "code.dmz" ];
    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      # Git operations on depot.git hit josh
      location /depot.git {
          proxy_pass http://localhost:${toString config.services.depot.josh.port};
      }

      # Git clone operations on '/' should be redirected to josh now.
      location = /info/refs {
          return 302 https://code.fediversehosting.net/depot.git/info/refs$is_args$args;
      }

      # Static assets must always hit the root.
      location ~ ^/(favicon\.ico|cgit\.(css|png))$ {
         proxy_pass http://localhost:2448;
      }

      # Everything else is forwarded to cgit for the web view
      location / {
          proxy_pass http://localhost:2448/cgit.cgi/depot/;
      }
    '';
  };
}
