# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  inherit (builtins) listToAttrs concatStringsSep;
  inherit (lib) range mapAttrs' nameValuePair optionalAttrs;

  auth = name: depot.path.origSrc + ("/infra/auth/" + name);
  mod = name: depot.path.origSrc + ("/infra/nixos-modules/" + name);
  nix-cache = name: depot.path.origSrc + ("/infra/nix-cache/nixos-modules/" + name);
  scm = name: depot.path.origSrc + ("/infra/scm/nixos-modules/" + name);

  # Import machine configurations
  mediaMachine = import (depot.path.origSrc + "/services/ghuntley/machines/com-ghuntley-media/default.nix") {
    inherit depot pkgs;
  };

  ghuntleyMachine = import (depot.path.origSrc + "/services/ghuntley/machines/com-ghuntley/default.nix") {
    inherit depot pkgs;
  };

  # Machine configurations for PXE boot
  machines = {
    # Media server with actual configuration
    "media" = {
      macAddress = "bc:24:11:61:77:72";
      netboot = mediaMachine.netboot;
      netbootIpxe = mediaMachine.netbootIpxe;
      description = "Media Server";
    };

    # ghuntley.com machine with actual configuration
    "ghuntley" = {
      macAddress = "bc:24:11:97:45:4b";
      netboot = ghuntleyMachine.netboot;
      netbootIpxe = ghuntleyMachine.netbootIpxe;
      description = "ghuntley.com Website";
    };
  };

  # Helper functions for PXE/iPXE configuration
  helpers = {
    # Normalize MAC address for PXELinux (01-mac-with-dashes)
    normalizeMac = mac: "01-" + builtins.replaceStrings [ ":" ] [ "-" ] (lib.toLower mac);

    # Create a machine-specific iPXE script
    makeIpxeScript = name: machine: ''
      #!ipxe
      # ${machine.description} (MAC: ${machine.macAddress})

      # Set console for debugging
      console --x 1024 --y 768
      set timeout 5000

      # Network retry settings
      set retry:1
      set net-retry:3

      :retry_start
      echo Booting ${name} (${machine.description})...

      # Try local path first
      echo Trying local boot image...
      chain --timeout 5000 ${name}.ipxe && goto boot_success

      # If that fails, try remote URL (if we have network)
      echo Local boot failed, trying HTTPS boot...
      isset $${net0/ip} || goto net_error

      # Boot using HTTPS only
      chain --timeout 10000 https://pxe.ponderoos.com/${name}.ipxe || goto boot_failed

      goto boot_success

      :net_error
      echo Network error! No IP address.
      echo Retrying network in 5 seconds... (Attempt $${retry})
      iseq $${retry} 3 && goto boot_failed
      inc retry
      sleep 5
      goto retry_start

      :boot_failed
      echo ===========================================
      echo BOOT FAILED for ${name} (${machine.description})
      echo ===========================================
      echo
      echo Options:
      echo 1. Return to menu (default)
      echo 2. Retry this boot
      echo 3. Drop to iPXE shell
      echo
      echo Returning to menu in 10 seconds...
      choose --timeout 10000 --default 1 selected || set selected 1
      iseq $${selected} 1 && chain menu.ipxe
      iseq $${selected} 2 && goto retry_start
      iseq $${selected} 3 && shell
      chain menu.ipxe

      :boot_success
      exit
    '';

    # Create a main menu iPXE script (simplified without groups)
    makeMenuScript = machines:
      let
        # Generate menu items for all machines
        menuItems = concatStringsSep "\n" (lib.mapAttrsToList
          (name: machine:
            "item ${name} ${machine.description} (MAC: ${machine.macAddress})"
          )
          machines);

        # Generate goto handlers for all machines
        gotoHandlers = concatStringsSep "\n" (lib.mapAttrsToList
          (name: _:
            ":${name}\nchain ${name}.ipxe || goto boot_error"
          )
          machines);
      in
      ''
        #!ipxe
        # iPXE Boot Menu for Workbench Services

        # Configure console
        console --x 1024 --y 768
        set timeout 60000

        # Set defaults
        set menu-default media
        set menu-timeout 10000

        :start
        menu iPXE Boot Menu - Workbench Services
        item --gap -- ------------------------- Available Systems -------------------------
        ${menuItems}
        item --gap
        item shell Drop to iPXE shell
        item reboot Reboot machine
        item exit Exit to BIOS/firmware
        item --gap
        item --gap -- Press Ctrl+B for iPXE command line...
        choose --timeout $${menu-timeout} --default $${menu-default} selected || goto shell

        goto $${selected}

        ${gotoHandlers}

        :shell
        echo Type 'exit' to return to the menu
        shell
        goto start

        :reboot
        reboot

        :exit
        exit

        :boot_error
        echo Boot failed! Returning to menu in 5 seconds...
        sleep 5
        goto start
      '';
  };

in
{
  imports = [
    (mod "defaults-qemu.nix")
    (mod "harmonia.nix")
    (mod "keycloak.nix")
    (mod "podman.nix")
    (mod "restic.nix")

    (scm "buildkite.nix")
    (mod "vaultwarden.nix")

    (mod "geoipupdate.nix")
    (mod "goatcounter.nix")

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

  networking.hostName = "workbench";
  networking.domain = "servers";

  networking.useDHCP = false;

  #networking.firewall.interfaces."eno1".allowedTCPPorts = lib.optionals (config.services.openssh.enable) [ 22 ];

  networking.firewall.enable = true;
  networking.firewall.interfaces."ens18".allowedTCPPorts = [ 22 80 443 29418 ];
  networking.firewall.interfaces."ens18".allowedUDPPorts = [ 22 69 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

  networking.firewall.interfaces."tailscale".allowedTCPPorts = [ 22 80 443 29418 ];
  networking.firewall.interfaces."tailscale".allowedUDPPorts = [ 22 69 60000 60001 60002 60003 60004 60005 60006 60007 60008 60009 60010 ];

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
    maxFreed = 8; # GiB
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

  services.nginx.enable = true;
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "security@ponderoos.com";


  # Run Harmonia to serve public nix-cache
  services.depot.harmonia = {
    enable = true;
    hostname = "nix-cache.ponderoos.com";
    signKeyPath = config.age.secrets.nix-cache-signkey.path;
  };

  # Configure secrets for services that need them.
  age.secrets =
    let
      secretFile = name: depot.infra.secrets.ponderoos."${name}.age";
    in
    {

      geoipupdate-license-key = {
        file = secretFile "geoipupdate-license-key";
        symlink = false;
        mode = "0440";
        group = "geoip";
      };

      backup-cli-credentials.file = secretFile "backup-cli-credentials";
      backup-cli-credentials.symlink = false;

      ovh-backup-credentials.file = secretFile "ovh-backup-credentials";
      ovh-backup-credentials.symlink = false;

      ovh-files-credentials.file = secretFile "ovh-files-credentials";
      ovh-files-credentials.symlink = false;

      ovh-backup-encryption-key.file = secretFile "ovh-backup-encryption-key";
      ovh-backup-encryption-key.symlink = false;

      vaultwarden-credentials = {
        file = secretFile "vaultwarden-credentials";
        mode = "0440";
        group = "vaultwarden";
        symlink = false;
      };

      nix-cache-pubkey.file = secretFile "nix-cache-pubkey";
      nix-cache-pubkey.symlink = false;

      nix-cache-signkey.file = secretFile "nix-cache-signkey";
      nix-cache-signkey.symlink = false;

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

  services.depot.vaultwarden = {
    enable = true;
    domain = "vault.ponderoos.com";
    port = 8222;
    enableSignups = false;
  };

  services.depot.nix-cache.enable = false;

  services.depot.geoipupdate = {
    enable = true;
    accountId = 1125904;
    licenseKey = config.age.secrets.geoipupdate-license-key.path;
  };

  # services.depot.goatcounter = {
  #   enable = true;
  #   domain = "stats.ghuntley.com";
  #   port = 8010;
  #   stateDir = "/var/lib/goatcounter/com-ghuntley";
  # };

  boot.kernelModules = [ "kvm-intel" ]; # Use kvm-amd for AMD CPUs
  virtualisation.libvirtd.enable = true;
  users.extraGroups.libvirtd.members = [ "ghuntley" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05";

  # TFTP server for iPXE booting - using atftpd instead of netkitftp (tftpd)
  services.atftpd = {
    enable = true;
    root = "/srv/tftp";
    extraOptions = [
      "--daemon" # Run as daemon
      "--no-multicast" # Disable multicast support
      "--logfile /var/log/atftpd.log" # Log to file
      "--port 69" # Standard TFTP port
      "--verbose=6" # Verbose logging for debugging
    ];
  };

  # Set up TFTP directory with symlinks to the Nix store and enhanced iPXE scripts
  system.activationScripts.tftpSetup = ''
    # Create base TFTP directory
    mkdir -p /srv/tftp
    chmod 755 /srv/tftp

    # Create enhanced iPXE scripts for each machine
    ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
      # Create symlinks for ${name} iPXE files from the Nix store
      ln -sf ${machine.netbootIpxe} /srv/tftp/${name}.ipxe
      ln -sf ${machine.netboot} /srv/tftp/${name}.tar.gz

      # Create MAC-specific iPXE script
      cat > /srv/tftp/${lib.toLower machine.macAddress}.ipxe << EOF
      ${helpers.makeIpxeScript name machine}
      EOF

      # Create MAC-specific PXE configuration file
      mkdir -p /srv/tftp/pxelinux.cfg
      cat > /srv/tftp/pxelinux.cfg/${helpers.normalizeMac machine.macAddress} << EOF
      DEFAULT ${name}
      LABEL ${name}
        KERNEL ipxe.lkrn
        APPEND dhcp && chain ${lib.toLower machine.macAddress}.ipxe
      EOF
    '') machines)}

    # Create main menu iPXE script
    cat > /srv/tftp/menu.ipxe << EOF
    ${helpers.makeMenuScript machines}
    EOF

    # Create default iPXE entry that shows the menu
    cat > /srv/tftp/default.ipxe << EOF
    #!ipxe
    chain menu.ipxe
    EOF

    # Create a boot.ipxe script for direct boot requests
    cat > /srv/tftp/boot.ipxe << EOF
    #!ipxe
    echo Checking MAC address: $${net0/mac}

    # Try MAC-specific boot
    chain --timeout 3000 $${mac:hexhyp}.ipxe && exit

    # If no MAC-specific boot found, go to menu
    chain menu.ipxe
    EOF

    # Create default PXE configuration
    cat > /srv/tftp/pxelinux.cfg/default << EOF
    DEFAULT menu
    TIMEOUT 50
    PROMPT 0

    LABEL menu
      KERNEL ipxe.lkrn
      APPEND dhcp && chain boot.ipxe
    EOF

    # Add iPXE kernel for legacy PXE
    if [ ! -f /srv/tftp/ipxe.lkrn ]; then
      cp ${pkgs.ipxe}/ipxe.lkrn /srv/tftp/ipxe.lkrn || curl -L "https://boot.ipxe.org/ipxe.lkrn" -o /srv/tftp/ipxe.lkrn
    fi

    # Add additional iPXE utility files
    if [ ! -f /srv/tftp/undionly.kpxe ]; then
      cp ${pkgs.ipxe}/undionly.kpxe /srv/tftp/undionly.kpxe || curl -L "https://boot.ipxe.org/undionly.kpxe" -o /srv/tftp/undionly.kpxe
    fi

    if [ ! -f /srv/tftp/ipxe.efi ]; then
      cp ${pkgs.ipxe}/ipxe.efi /srv/tftp/ipxe.efi || curl -L "https://boot.ipxe.org/ipxe.efi" -o /srv/tftp/ipxe.efi
    fi

    # Ensure proper permissions for atftpd
    chmod -R 755 /srv/tftp
    chown -R nobody:nogroup /srv/tftp
  '';

  # Create a HTTP/HTTPS server to serve iPXE files as backup
  services.nginx.virtualHosts."pxe.ponderoos.com" = {
    # Enable HTTPS with Let's Encrypt
    forceSSL = true;
    enableACME = true;

    # Recommended settings for security
    http2 = true;

    # Serve files from the TFTP directory
    locations."/" = {
      root = "/srv/tftp";
      extraConfig = ''
        autoindex on;

        # Add appropriate MIME types for iPXE scripts
        types {
          application/octet-stream ipxe;
          application/octet-stream kpxe;
          application/octet-stream efi;
          application/octet-stream lkrn;
        }

        # Increase timeout for large files
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
      '';
    };
  };

  # Ensure the machine netboot artifacts are built
  system.extraDependencies = lib.flatten (
    lib.mapAttrsToList
      (name: machine: [
        machine.netboot
        machine.netbootIpxe
      ])
      machines
  );
}
