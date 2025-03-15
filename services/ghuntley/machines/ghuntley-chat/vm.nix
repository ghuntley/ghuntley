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
        ];

        networking.hostName = "chat";
        networking.domain = "ghuntley";


        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-chat/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-chat/netdata";
        };


        fileSystems."/srv" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-chat/srv";
        };

        networking = {
          firewall = {
            allowedTCPPorts = [
              80 # HTTP
            ];
          };
        };

        # Homarr container configuration
        virtualisation.oci-containers.containers."open-webui" = {
          image = "ghcr.io/open-webui/open-webui:main";
          ports = [
            "80:8080"
          ];
          volumes = [
            "/srv:/app/backend/data"
          ];
          environment = {
            # Not really a secret but it needs to be a constant value.
            SECRET_ENCRYPTION_KEY = "e06c520f1b8c10e7218f40d634bf85217ed8c9919a5a82d50d4da19bec254662";
          };
          extraOptions = [ "--network=host" ];
        };

        # Update service configuration
        systemd.services.docker-pull-open-webui = {
          serviceConfig.User = "root";
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.docker
            pkgs.systemd
          ];
          script = ''
            ${pkgs.docker}/bin/docker pull ghcr.io/open-webui/open-webui:main
            ${pkgs.systemd}/bin/systemctl restart docker-open-webui
          '';
        };

        systemd.timers.docker-pull-open-webui = {
          wantedBy = [ "timers.target" ];
          partOf = [ "docker-pull-open-webui.service" ];
          timerConfig.OnCalendar = "daily";
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
