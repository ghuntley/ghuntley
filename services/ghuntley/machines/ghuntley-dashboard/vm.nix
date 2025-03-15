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

        networking.hostName = "dashboard";
        networking.domain = "ghuntley";


        fileSystems."/var/lib/tailscale" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-dashboard/tailscale";
        };

        fileSystems."/var/lib/netdata" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-dashboard/netdata";
        };


        fileSystems."/srv" = makeNFSMount {
          nfsServer = "10.10.10.254";
          nfsPath = "/mnt/dpool/vms/ghuntley-dashboard/srv";
        };

        networking = {
          firewall = {
            allowedTCPPorts = [
              80 # HTTP
            ];
          };
        };

        # Homarr container configuration
        virtualisation.oci-containers.containers."homearr" = {
          image = "ghcr.io/homarr-labs/homarr:latest";
          ports = [
            "80:7575"
          ];
          volumes = [
            "/srv:/appdata:cached"
          ];
          environment = {
            # Not really a secret but it needs to be a constant value.
            SECRET_ENCRYPTION_KEY = "e06c520f1b8c10e7218f40d634bf85217ed8c9919a5a82d50d4da19bec254662";
          };
          extraOptions = [ "--network=host" ];
        };

        # Update service configuration
        systemd.services.docker-pull-homearr = {
          serviceConfig.User = "root";
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.docker
            pkgs.systemd
          ];
          script = ''
            ${pkgs.docker}/bin/docker pull ghcr.io/homarr-labs/homarr:latest
            ${pkgs.systemd}/bin/systemctl restart docker-homearr
          '';
        };

        systemd.timers.docker-pull-homearr = {
          wantedBy = [ "timers.target" ];
          partOf = [ "docker-pull-homearr.service" ];
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
