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

  # Helper for properly escaping iPXE variables in Nix strings
  dollar = "$";
  ipxeVar = name: "${dollar}{${name}}";

  # Helper functions for PXE/iPXE configuration
  helpers = {
    # Normalize MAC address for PXELinux (01-mac-with-dashes)
    normalizeMac = mac: "01-" + builtins.replaceStrings [ ":" ] [ "-" ] (lib.toLower mac);

    # Create a simple direct boot script for a machine with enhanced debug
    makeSimpleBootScript = name: machine: ''
      #!ipxe
      # Direct boot script for ${machine.description} (MAC: ${machine.macAddress})

      # Network and TFTP optimization settings
      set retry 3
      set keep-san 0
      set blksize 512

      echo ===== BOOT SCRIPT FOR ${name} =====
      echo MAC: ${machine.macAddress}
      echo

      # Direct boot from netboot iPXE script
      echo Loading ${name}.ipxe...
      chain --replace ${name}.ipxe || goto boot_failed

      :boot_failed
      echo ======================================
      echo ERROR: Failed to load ${name}.ipxe
      echo ======================================
      echo Network information:
      ifstat
      route
      echo
      echo Press any key to retry...
      prompt
      goto retry_boot

      :retry_boot
      echo Retrying...
      chain ${name}.ipxe || reboot
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

  # Configure ens19 for TFTP/PXE boot network
  networking.interfaces."ens19".ipv4.addresses = [
    {
      address = "10.10.10.253";
      prefixLength = 24;
    }
  ];


  # Allow DHCP and TFTP traffic on ens19
  networking.firewall.interfaces."ens19" = {
    allowedUDPPorts = [ 67 68 69 4011 ]; # DHCP and TFTP ports
    allowedTCPPorts = [ 80 443 ]; # HTTP/HTTPS for iPXE fallback
  };

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
  #    enable = true;
  #    domain = "stats.ghuntley.com";
  #    port = 8010;
  #    stateDir = "/var/lib/goatcounter/com-ghuntley";
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

  # Create TFTP directory for files
  systemd.tmpfiles.rules = [
    "d /srv/tftp 0755 nobody nogroup - -"
  ];

  # TFTP server for iPXE booting - using atftpd instead of netkitftp (tftpd)
  # Removing unsupported options (--timeout, --retry-timeout, etc.)
  services.atftpd = {
    enable = true;
    root = "/srv/tftp";
    extraOptions = [
      "--daemon" # Run as daemon
      "--no-multicast" # Disable multicast support
      "--logfile /var/log/atftpd.log" # Log to file
      "--port 69" # Standard TFTP port
      "--verbose=6" # Verbose logging for debugging
      "--bind-address 0.0.0.0" # Bind to all interfaces
      "--mcast-ttl 1" # TTL for multicast packets
      "--mcast-addr 224.0.1.2" # Multicast address
    ];
  };

  # Set up TFTP directory with symlinks to the Nix store and enhanced iPXE scripts
  system.activationScripts.tftpSetup = {
    deps = [ "specialfs" "var" "binsh" ];
    text = ''
      # Create base TFTP directory and remove any existing files
      mkdir -p /srv/tftp
      rm -rf /srv/tftp/*
      chmod 755 /srv/tftp

      echo "Setting up TFTP boot environment..."

      # Create a simple test file to verify TFTP access
      echo "TFTP test file - $(date)" > /srv/tftp/test.txt

      # Helper function to normalize MAC address for PXELinux config
      normalize_mac() {
        echo "01-$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr ':' '-')"
      }

      ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
        echo "Setting up boot files for ${name} (${machine.description})..."

        # Create directory for this machine's boot files
        mkdir -p /srv/tftp/${name}

        # Copy netboot files - explicitly copy, not symlink
        if [ -d "${machine.netboot}" ]; then
          echo "Copying netboot files from ${machine.netboot} to /srv/tftp/${name}/"
          cp -rf ${machine.netboot}/* /srv/tftp/${name}/ || echo "Warning: Some files might not have copied"
        else
          echo "Warning: Netboot directory for ${name} not found at ${machine.netboot}"
        fi

        # Copy iPXE boot script - explicitly copy, not symlink
        if [ -f "${machine.netbootIpxe}" ]; then
          echo "Copying iPXE boot script from ${machine.netbootIpxe} to /srv/tftp/${name}.ipxe"
          cp -f ${machine.netbootIpxe} /srv/tftp/${name}.ipxe || echo "Warning: Failed to copy iPXE script"
        else
          echo "Warning: iPXE script for ${name} not found at ${machine.netbootIpxe}"
          # Create a fallback script
          cat > /srv/tftp/${name}.ipxe << EOF
      #!ipxe
      # Fallback boot script (original not found)
      echo ERROR: No netboot script found for ${name}
      echo Machine: ${machine.description}
      echo MAC: ${machine.macAddress}
      echo
      echo Press any key to reboot...
      prompt
      reboot
      EOF
        fi

        # Create MAC-specific iPXE script that directly boots this machine
        cat > /srv/tftp/$(echo ${machine.macAddress} | tr '[:upper:]' '[:lower:]').ipxe << EOF
      #!ipxe
      # Direct boot script for ${machine.description} (MAC: ${machine.macAddress})

      echo ===== BOOTING ${name} (${machine.description}) =====
      echo MAC: ${machine.macAddress}
      echo Time: ${ipxeVar "time"}
      echo

      # Boot from the machine's iPXE script
      chain ${name}.ipxe || goto boot_failed
      exit

      :boot_failed
      echo ======================================
      echo ERROR: Failed to load ${name}.ipxe
      echo ======================================
      echo Network information:
      ifstat
      route
      echo
      echo Press any key to retry...
      prompt
      chain ${name}.ipxe || reboot
      EOF

        # Create PXE boot configuration for this MAC address
        mkdir -p /srv/tftp/pxelinux.cfg
        MAC_FILE=$(normalize_mac "${machine.macAddress}")
        cat > /srv/tftp/pxelinux.cfg/$MAC_FILE << EOF
      DEFAULT ${name}
      LABEL ${name}
        KERNEL ipxe.lkrn
        APPEND dhcp && chain $(echo ${machine.macAddress} | tr '[:upper:]' '[:lower:]').ipxe
      EOF

        echo "Setup complete for ${name}"
      '') machines)}

      # Create fallback/default iPXE script
      cat > /srv/tftp/default.ipxe << EOF
      #!ipxe
      # Default boot menu

      echo =======================================
      echo PXE BOOT MENU
      echo =======================================
      echo MAC address: ${ipxeVar "net0/mac"}
      echo

      menu Select a machine to boot:
      ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
      item ${name} Boot ${name} (${machine.description})
      '') machines)}
      item shell Drop to iPXE shell
      item reboot Reboot system

      choose --timeout 30000 target && goto ${ipxeVar "target"} || goto timeout

      ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
      :${name}
      chain ${name}.ipxe || goto boot_failed
      exit
      '') machines)}

      :shell
      echo Type 'exit' to return to the menu
      shell
      goto start

      :reboot
      reboot

      :boot_failed
      echo Boot failed! Press any key to return to menu...
      prompt
      goto start

      :timeout
      echo Boot menu timed out.
      echo Attempting to determine machine from MAC address...

      ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
      iseq ${ipxeVar "mac"} ${machine.macAddress} && chain ${name}.ipxe ||
      '') machines)}

      echo Unknown MAC address, booting to menu...
      goto start
      EOF

      # Create a boot.ipxe script to handle clients that look for this default name
      cat > /srv/tftp/boot.ipxe << EOF
      #!ipxe
      # Redirect script for clients that look for boot.ipxe by default

      echo Redirecting to default boot menu...
      chain default.ipxe || goto fallback
      exit

      :fallback
      echo ======================================
      echo ERROR: Failed to load default.ipxe
      echo ======================================
      echo Network information:
      ifstat
      route
      echo
      echo Press any key to retry...
      prompt
      chain default.ipxe || reboot
      EOF

      # Create default PXE configuration
      cat > /srv/tftp/pxelinux.cfg/default << EOF
      DEFAULT ipxe
      PROMPT 0
      TIMEOUT 100

      LABEL ipxe
        KERNEL ipxe.lkrn
        APPEND dhcp && chain boot.ipxe

      LABEL menu
        KERNEL ipxe.lkrn
        APPEND dhcp && chain default.ipxe

      LABEL shell
        KERNEL ipxe.lkrn
        APPEND dhcp && shell
      EOF

      # Copy iPXE binaries (explicitly copy, not symlink)
      echo "Copying iPXE binaries..."
      cp -f ${pkgs.ipxe}/ipxe.lkrn /srv/tftp/ipxe.lkrn || echo "Warning: Failed to copy ipxe.lkrn"
      cp -f ${pkgs.ipxe}/undionly.kpxe /srv/tftp/undionly.kpxe || echo "Warning: Failed to copy undionly.kpxe"
      cp -f ${pkgs.ipxe}/ipxe.efi /srv/tftp/ipxe.efi || echo "Warning: Failed to copy ipxe.efi"

      # Add common PXE boot filenames for compatibility with different clients
      echo "Creating common PXE boot filename symlinks..."
      ln -sf undionly.kpxe /srv/tftp/pxelinux.0
      ln -sf ipxe.efi /srv/tftp/bootx64.efi

      # Add verification for completeness
      echo "Verifying critical iPXE files..."
      for file in ipxe.lkrn undionly.kpxe ipxe.efi boot.ipxe default.ipxe; do
        if [ -e "/srv/tftp/$file" ]; then
          echo "✓ $file exists"
        else
          echo "✗ ERROR: $file is missing!"
        fi
      done

      # Verify MAC-specific boot files
      echo "Verifying machine-specific boot files..."
      ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
        if [ -e "/srv/tftp/${name}.ipxe" ]; then
          echo "✓ ${name}.ipxe exists"
        else
          echo "✗ ERROR: ${name}.ipxe is missing!"
        fi

        MAC_LOWER=$(echo ${machine.macAddress} | tr '[:upper:]' '[:lower:]')
        if [ -e "/srv/tftp/$MAC_LOWER.ipxe" ]; then
          echo "✓ $MAC_LOWER.ipxe exists"
        else
          echo "✗ ERROR: $MAC_LOWER.ipxe is missing!"
        fi
      '') machines)}

      # Set proper permissions
      chmod -R 755 /srv/tftp
      chown -R nobody:nogroup /srv/tftp

      echo "TFTP setup complete. Contents of /srv/tftp:"
      ls -la /srv/tftp/
    '';
  };

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
