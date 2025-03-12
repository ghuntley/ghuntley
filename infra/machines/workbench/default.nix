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
      kernel = mediaMachine.kernel;
      kernelFile = "bzImage";
      toplevel = mediaMachine.toplevel;
    };

    # ghuntley.com machine with actual configuration
    "ghuntley" = {
      macAddress = "bc:24:11:97:45:4b";
      netboot = ghuntleyMachine.netboot;
      netbootIpxe = ghuntleyMachine.netbootIpxe;
      description = "ghuntley.com Website";
      kernel = ghuntleyMachine.kernel;
      kernelFile = "bzImage";
      toplevel = ghuntleyMachine.toplevel;
    };
  };

  # Helper for properly escaping iPXE variables in Nix strings
  dollar = "$";
  ipxeVar = name: "${dollar}{${name}}";

  # Helper for literal iPXE variables (no Nix interpolation)
  ipxeLiteral = name: "''${" + name + "}";

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

            # Define sed command with full path
            SED="${pkgs.gnused}/bin/sed"

            echo "Setting up TFTP boot environment..."

            # Helper function to normalize MAC address for PXELinux config
            normalize_mac() {
              echo "01-$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr ':' '-')"
            }

            # Create a simple default iPXE script
            cat > /srv/tftp/default.ipxe << 'EOF'
      #!ipxe
      # Default boot menu

      :start
      echo =======================================
      echo PXE BOOT MENU
      echo =======================================
      echo MAC address: ''${net0/mac}
      echo

      menu Select a machine to boot:
      EOF

            # Add menu items for each machine
            ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
              echo "item ${name} Boot ${name} (${machine.description})" >> /srv/tftp/default.ipxe
            '') machines)}

            # Add shell and reboot options
            cat >> /srv/tftp/default.ipxe << 'EOF'
      item shell Drop to iPXE shell
      item reboot Reboot system

      choose --timeout 30000 target && goto ''${target} || goto timeout

      EOF

            # Add machine-specific sections
            ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
              echo ":${name}" >> /srv/tftp/default.ipxe
              echo "chain ${name}.ipxe || goto boot_failed" >> /srv/tftp/default.ipxe
              echo "exit" >> /srv/tftp/default.ipxe
              echo "" >> /srv/tftp/default.ipxe
            '') machines)}

            # Add shell, reboot, and boot_failed sections
            cat >> /srv/tftp/default.ipxe << 'EOF'
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
      EOF

            # Generate MAC-specific boot scripts for each machine
            ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
              # Create directory for ${name}'s boot files
              mkdir -p /srv/tftp/${name}

              # Copy netboot files
              if [ -d "${machine.netboot}" ]; then
                echo "Copying netboot files for ${name}..."
                cp -rf ${machine.netboot}/* /srv/tftp/${name}/ || echo "Warning: Some files might not have copied"
              else
                echo "Warning: Netboot directory for ${name} not found"
              fi

              # Copy kernel files
              if [ -d "${machine.kernel}" ]; then
                echo "Copying kernel files for ${name}..."
                cp -f ${machine.kernel}/${machine.kernelFile} /srv/tftp/${name}/bzImage || echo "Warning: Failed to copy kernel file"
                ln -sf bzImage /srv/tftp/${name}/vmlinuz
              else
                echo "Warning: Kernel directory for ${name} not found, trying fallback method"
                # Fallback method - try to find the kernel in the toplevel output
                if [ -d "${machine.toplevel}" ]; then
                  KERNEL_PATH=$(find ${machine.toplevel} -name bzImage -o -name vmlinuz | head -n 1)
                  if [ -n "$KERNEL_PATH" ]; then
                    echo "Found kernel at $KERNEL_PATH"
                    cp -f "$KERNEL_PATH" /srv/tftp/${name}/bzImage || echo "Warning: Failed to copy kernel file"
                    ln -sf bzImage /srv/tftp/${name}/vmlinuz
                  else
                    echo "ERROR: Could not find kernel file for ${name}"
                  fi
                else
                  echo "ERROR: Could not find toplevel directory for ${name}"
                fi
              fi

              # Copy iPXE script
              if [ -f "${machine.netbootIpxe}" ]; then
                echo "Copying iPXE script for ${name}..."
                # Instead of simply copying the file, customize it to use our own paths
                cat ${machine.netbootIpxe} | sed "s|initrd|${name}/initrd|g" > /srv/tftp/${name}.ipxe || echo "Warning: Failed to copy iPXE script"
                # Ensure the proper toplevel path is in the script
                if ! grep -q "${machine.toplevel}" /srv/tftp/${name}.ipxe; then
                  $SED -i "s|init=|init=${machine.toplevel}/init |g" /srv/tftp/${name}.ipxe
                fi
                # Make sure the path to the kernel is correct
                $SED -i "s|kernel .*linux-.*|kernel ${name}/bzImage|g" /srv/tftp/${name}.ipxe
              else
                echo "Creating fallback script for ${name}..."
                cat > /srv/tftp/${name}.ipxe << 'INNER'
      #!ipxe
      # Netboot script for ${name} machine

      echo ===================================
      echo Booting ${name} (${machine.description})
      echo MAC Address: ''${net0/mac}
      echo ===================================

      # Set some network options for better performance
      set retry:int32 5
      set keep-san 0
      set blksize 512

      # Load the kernel and initrd from the ${name} directory
      echo Loading kernel and initrd...

      # Standard NixOS-style boot command with required netboot parameters
      kernel ${name}/bzImage \
        init=${machine.toplevel}/init \
        initrd=${name}/initrd \
        root=/dev/ram0 \
        console=ttyS0,115200n8 console=tty1 \
        loglevel=7 \
        boot.shell_on_fail \
        boot.debug1 \
        boot.trace \
        systemd.log_level=debug \
        systemd.log_target=console \
        rd.debug=1 \
        debug ignore_loglevel

      initrd ${name}/initrd

      # Boot the system
      echo Booting ${name}...
      boot || goto boot_failed

      :boot_failed
      echo ===================================
      echo ERROR: Boot failed!
      echo ===================================
      echo Network status:
      ifstat
      route
      echo
      echo Press any key to return to menu...
      prompt
      chain default.ipxe
      INNER
                # Inject the correct machine values
                $SED -i "s/\${name}/${name}/g" /srv/tftp/${name}.ipxe
                $SED -i "s/\${machine.description}/${machine.description}/g" /srv/tftp/${name}.ipxe
                $SED -i "s|\${machine.toplevel}|${machine.toplevel}|g" /srv/tftp/${name}.ipxe
              fi

              # Create MAC-specific script for direct boot
              MAC_LOWER=$(echo ${machine.macAddress} | tr '[:upper:]' '[:lower:]')
              cat > /srv/tftp/$MAC_LOWER.ipxe << 'INNER'
      #!ipxe
      # Direct boot script

      # TFTP optimization settings
      set retry 5
      set keep-san 0
      set blksize 512

      echo Loading machine-specific boot...
      chain MACHINE_NAME.ipxe || goto boot_failed
      exit

      :boot_failed
      echo ======================================
      echo ERROR: Failed to load boot script
      echo ======================================
      echo Network information:
      ifstat
      route
      echo
      echo Press any key to retry...
      prompt
      chain boot.ipxe || reboot
      INNER
              # Inject the correct machine name - make sure to properly handle the replacement
              $SED -i "s/MACHINE_NAME/${name}/g" /srv/tftp/$MAC_LOWER.ipxe

              # Create PXE boot configuration for this MAC
              mkdir -p /srv/tftp/pxelinux.cfg
              MAC_FILE=$(normalize_mac "${machine.macAddress}")
              cat > /srv/tftp/pxelinux.cfg/$MAC_FILE << INNER
      DEFAULT ${name}
      LABEL ${name}
        KERNEL ipxe.lkrn
        APPEND dhcp && chain $MAC_LOWER.ipxe
      INNER

              echo "Setup complete for ${name}"
            '') machines)}

            # Generate timeout MAC matching code
            echo "" >> /srv/tftp/default.ipxe
            echo "# Get current MAC address" >> /srv/tftp/default.ipxe
            echo "set curr-mac ''${net0/mac}" >> /srv/tftp/default.ipxe

            # Add MAC address comparisons
            ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
              echo "echo Checking against ${name} (${machine.macAddress})" >> /srv/tftp/default.ipxe
              echo "iseq ''${curr-mac} ${machine.macAddress} && chain ${name}.ipxe ||" >> /srv/tftp/default.ipxe
            '') machines)}

            # Add fallback
            echo "" >> /srv/tftp/default.ipxe
            echo "echo Unknown MAC address, booting to menu..." >> /srv/tftp/default.ipxe
            echo "goto start" >> /srv/tftp/default.ipxe

            # Create boot.ipxe for clients that look for this filename
            cat > /srv/tftp/boot.ipxe << 'EOF'
      #!ipxe
      # Boot selector

      echo Checking MAC address: ''${net0/mac}
      EOF

            # Add MAC address specific boot logic
            ${concatStringsSep "\n" (lib.mapAttrsToList (name: machine: ''
              echo "iseq ''${net0/mac} ${machine.macAddress} && echo \"Found match: ${name}\" && chain ${name}.ipxe ||" >> /srv/tftp/boot.ipxe
            '') machines)}

            # Add fallback to menu
            cat >> /srv/tftp/boot.ipxe << 'EOF'

      # If no match found, load menu
      echo "No MAC match found, going to menu..."
      chain default.ipxe || goto error

      :error
      echo ======================================
      echo ERROR: All boot attempts failed
      echo ======================================
      echo Network information:
      ifstat
      route
      echo
      echo Press any key to retry...
      prompt
      reboot
      EOF

            # Set up PXE configuration
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

            # Copy iPXE binaries
            echo "Copying iPXE binaries..."
            cp -f ${pkgs.ipxe}/ipxe.lkrn /srv/tftp/ipxe.lkrn || echo "Warning: Failed to copy ipxe.lkrn"
            cp -f ${pkgs.ipxe}/undionly.kpxe /srv/tftp/undionly.kpxe || echo "Warning: Failed to copy undionly.kpxe"
            cp -f ${pkgs.ipxe}/ipxe.efi /srv/tftp/ipxe.efi || echo "Warning: Failed to copy ipxe.efi"

            # Add common PXE boot filenames
            echo "Creating common PXE boot filename symlinks..."
            ln -sf undionly.kpxe /srv/tftp/pxelinux.0
            ln -sf ipxe.efi /srv/tftp/bootx64.efi

            # Set permissions
            chmod -R 755 /srv/tftp
            chown -R nobody:nogroup /srv/tftp

            echo "TFTP setup complete. Contents of /srv/tftp:"
            ls -la /srv/tftp/
    '';
  };

  # Ensure the machine netboot artifacts are built
  system.extraDependencies = lib.flatten (
    lib.mapAttrsToList
      (name: machine: [
        machine.netboot
        machine.netbootIpxe
        machine.kernel
        machine.toplevel
      ])
      machines
  );
}
