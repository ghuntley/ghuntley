# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs;
  inherit (lib) range;

  auth = name: depot.path.origSrc + ("/infra/auth/" + name);
  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);
  nix-cache = name: depot.path.origSrc + ("/infra/nix-cache/nixos-modules/" + name);
  scm = name: depot.path.origSrc + ("/infra/scm/nixos-modules/" + name);

in
{
  imports = [
    (mod "defaults-qemu.nix")
    (mod "harmonia.nix")
    (mod "keycloak.nix")
    (mod "podman.nix")
    (mod "restic.nix")
    (mod "geesefs.nix")
    # (mod "nixos-mailserver.nix")

    (auth "ponderoos/slapd")

    (scm "cgit.nix")
    (scm "gerrit.nix")
    (scm "josh.nix")
    (scm "buildkite.nix")
    (scm "livegrep.nix")
    (scm "wastebin.nix")
    (scm "upterm.nix")
  ];

  boot.tmp.cleanOnBoot = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/46f15764-b489-4599-b566-c5abe81ed429";
      fsType = "ext4";
    };

  swapDevices = [ ];

  networking.hostName = "overalls";
  networking.domain = "servers";

  networking.useDHCP = false;

  #networking.firewall.interfaces."eno1".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  networking.firewall.enable = true;
  networking.firewall.interfaces."ens18".allowedTCPPorts = [ 22 80 443 29418 ];
  networking.firewall.interfaces."ens18".allowedUDPPorts = [ 22 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 22 80 443 29418 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 22 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.defaultGateway.address = "51.161.213.254";
  networking.nameservers = [ "1.1.1.1" ];

  networking.interfaces."ens18".ipv4.addresses = [
    {
      address = "51.161.213.234";
      prefixLength = 24;
    }
  ];

  # Automatically collect garbage from the Nix store.
  services.depot.automatic-nix-gc = {
    enable = true;
    interval = "1 hour";
    diskThreshold = 64; # GiB
    maxFreed = 64; # GiB
    preserveGenerations = "90d";
  };

  # Offsite backups to OVH
  services.depot.restic.enable = true;
  services.depot.restic.interval = "*:0/10"; # Every 10 minutes

  services.depot.restic.paths = [
    "/etc"
    "/depot"
    "/var/lib/acme"
  ];

  # Local databases
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_16;

    authentication = lib.mkForce ''
      local all all trust
      host all all 127.0.0.1/32 password
      host all all ::1/128 password
      hostnossl all all 127.0.0.1/32 password
      hostnossl all all ::1/128  password
    '';
  };

  services.postgresqlBackup = {
    enable = true;
  };

  # Run a mailserver
  # services.depot.mail = {
  #   enable = true;
  #   fqdn = "mail.ponderoos.com";
  #   domains = [ "ponderoos.com" ];
  #   certificateDomains = [ "imap.ponderoos.com" "pop3.ponderoos.com" ];
  #   sendingFqdn = "ponderoos.com";

  #   loginAccounts = {
  #       "hello@ponderoos.com" = {
  #         hashedPasswordFile = config.age.secrets.inbox-hello-credentials.path;
  #         aliases = [
  #           "invoices@ponderoos.com"
  #           "postmaster@ponderoos.com"
  #           "security@ponderoos.com"
  #           "services@ponderoos.com"
  #           "support@ponderoos.com"
  #         ];
  #       };
  #     };
  # };

  services.nginx.enable = true;
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "security@ponderoos.com";

  # Run keycloak
  services.depot.keycloak = {
    enable = true;
    hostname = "auth.ponderoos.com";
    database.passwordFile = config.age.secrets.postgres-keycloak-credentials.path;
  };

  # Run cgit & josh to serve git
  services.depot = {
    cgit = {
      enable = true;
      user = "git"; # run as the same user as gerrit
    };
    josh.enable = true;
  };

  # Run a handful of Buildkite agents to support parallel builds.
  services.depot.buildkite = {
    enable = true;
    agentCount = 32;
  };

  # Run a livegrep code search instance
  services.depot.livegrep.enable = true;

  # Run a wastebin instance
  services.depot.wastebin.enable = true;

  # Run Harmonia to serve public nix-cache
  services.depot.harmonia = {
    enable = true;
    hostname = "nix-cache.ponderoos.com";
    signKeyPath = config.age.secrets.nix-cache-signkey.path;
  };

  # Run GeeseFS to serve S3 buckets
  services.depot.geesefs = {
    enable = true;
    mounts = {
      "files" = {
        bucket = "ponderoos-files";
        endpoint = "https://s3.gra.io.cloud.ovh.net/";
        mountPoint = "/mnt/files.ponderoos.com";
        enableBackups = true;
        credentialsFile = config.age.secrets.ovh-files-credentials.path;
        region = "GRA";
        cluster = {
          enable = true;
          nodeId = "000";
          address = "overalls.lorikeet-bangus.ts.net";
          port = 5619;
          peers = [
            { nodeId = "100"; address = "crowbar.lorikeet-bangus.ts.net:5619"; }
          ];
        };
      };
    };
  };

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.infra.secrets.ponderoos."${name}.age";
    in
    {

      backup-cli-credentials.file = secretFile "backup-cli-credentials";
      backup-cli-credentials.symlink = false;

      ovh-backup-credentials.file = secretFile "ovh-backup-credentials";
      ovh-backup-credentials.symlink = false;

      ovh-files-credentials.file = secretFile "ovh-files-credentials";
      ovh-files-credentials.symlink = false;

      ovh-backup-encryption-key.file = secretFile "ovh-backup-encryption-key";
      ovh-backup-encryption-key.symlink = false;

      nix-cache-pubkey.file = secretFile "nix-cache-pubkey";
      nix-cache-pubkey.symlink = false;

      nix-cache-signkey.file = secretFile "nix-cache-signkey";
      nix-cache-signkey.symlink = false;

      postgres-keycloak-credentials.file = secretFile "postgres-keycloak-credentials";
      postgres-keycloak-credentials.symlink = false;

      inbox-hello-credentials.file = secretFile "inbox-hello-credentials";
      inbox-hello-credentials.symlink = false;

      wastebin-secret-file.file = secretFile "wastebin-secret-file";
      wastebin-secret-file.symlink = false;

      buildkite-agent-token = {
        file = secretFile "buildkite-agent-token";
        mode = "0440";
        group = "buildkite-agents";
        symlink = false;
      };

      buildkite-graphql-token = {
        file = secretFile "buildkite-graphql-token";
        mode = "0440";
        group = "buildkite-agents";
        symlink = false;
      };


      buildkite-ssh-private-key = {
        file = secretFile "buildkite-ssh-private-key";
        mode = "0440";
        group = "buildkite-agents";
        symlink = false;
      };

      buildkite-ssh-public-key = {
        file = secretFile "buildkite-ssh-public-key";
        mode = "0440";
        group = "buildkite-agents";
        symlink = false;
      };

      buildkite-besadii-config = {
        file = secretFile "buildkite-besadii-config";
        mode = "0440";
        group = "buildkite-agents";
        symlink = false;
      };

      gerrit-besadii-config = {
        file = secretFile "gerrit-besadii-config";
        owner = "git";
        symlink = false;
      };

    };

  services.depot.nix-cache.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05";
}
