<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Media Machine

A NixOS VM configuration for running media services.

## Usage

Build and run the VM:
```bash
depot build //services/ghuntley/machines/com-ghuntley-media/machine
depot run //services/ghuntley/machines/com-ghuntley-media/machine
```

Build specific components:
```bash
# Build the ISO
depot build //services/ghuntley/machines/com-ghuntley-media/machine:iso

# Run the tests
depot test //services/ghuntley/machines/com-ghuntley-media/machine:tests
```

## Getting the ISO URL

To get the URL where the ISO is stored:
```bash
# This will output the URL where the ISO can be downloaded
depot eval //services/ghuntley/machines/com-ghuntley-media/machine:url
```

The URL is generated using Harmonia's storage system and can be used to download the ISO from any machine with appropriate access.

## Enhanced PXE Boot

This system is part of a multi-machine PXE boot configuration. The PXE boot files for all machines are automatically served by the workbench system's TFTP server directly from the Nix store, with a fallback HTTP server option.

### MAC Address Configuration

This machine is configured to boot with the MAC address: `BC:24:11:61:77:72`. The workbench TFTP server has MAC-specific boot configurations for this address and other machines in the network.

### Interactive Boot Menu

The iPXE configuration includes an interactive boot menu that lists all available machines:

- Media Server (this machine)
- Other machines configured in the workbench

Each machine is automatically booted based on its MAC address, or can be manually selected from the menu.

### Enhanced Error Handling

The improved iPXE scripts include:
- Automatic retry for network issues
- Fallback boot options if local boot fails
- Menu-based recovery options on boot failure
- Detailed boot status and error messages

### PXE Boot Files Location

The iPXE boot files are available on the workbench TFTP server at:
- `/srv/tftp/media.ipxe` - The main iPXE script for this machine
- `/srv/tftp/bc:24:11:61:77:72.ipxe` - MAC-specific iPXE script with error handling
- `/srv/tftp/pxelinux.cfg/01-bc-24-11-61-77-72` - MAC-specific PXELinux configuration
- `/srv/tftp/media.tar.gz` - The netboot ramdisk archive
- `/srv/tftp/menu.ipxe` - Interactive boot menu with all machines
- `/srv/tftp/boot.ipxe` - MAC-detection script

Additionally, these files are also available via HTTP at:
- `http://pxe.ponderoos.com/`

### UEFI Boot Support

The configuration includes UEFI boot support with:
- `/srv/tftp/ipxe.efi` - UEFI version of iPXE
- `/srv/tftp/undionly.kpxe` - Network-only version of iPXE for chainloading

### Booting Clients

For clients to PXE boot this system:

1. Configure the client's BIOS/UEFI to boot from network
2. The client should be configured to use the workbench as its TFTP server
3. When using network boot without DHCP, you need to manually configure:
   - Static IP settings for the client
   - TFTP server address (the workbench's IP)
   - Boot filename:
     - `ipxe.lkrn` for legacy BIOS
     - `ipxe.efi` for UEFI
     - `undionly.kpxe` for chainloading from an existing PXE environment

The system will automatically detect the MAC address of each machine and load the appropriate configuration. If MAC detection fails, it will present the interactive boot menu.

### Adding New Machines to PXE Boot

To add a new machine to the PXE boot configuration:

1. Create a new machine configuration similar to this one
2. Add the machine to the `machines` attribute set in the workbench configuration
3. Specify its MAC address and other parameters
4. Rebuild the workbench configuration

The new machine will automatically appear in the boot menu and be bootable via its MAC address.

### Using with External DHCP Server

If you have an external DHCP server (not on the workbench), configure it to point to the workbench's TFTP server:

```
# For legacy BIOS
filename "ipxe.lkrn";
next-server <WORKBENCH_IP>;

# For UEFI
filename "ipxe.efi";
next-server <WORKBENCH_IP>;
```

For MAC-specific configuration with an external DHCP server, add host entries for each machine:

```
host media {
  hardware ethernet BC:24:11:61:77:72;
  filename "ipxe.lkrn";  # or "ipxe.efi" for UEFI
  next-server <WORKBENCH_IP>;
}

host workstation {
  hardware ethernet AA:BB:CC:DD:EE:FF;
  filename "ipxe.lkrn";  # or "ipxe.efi" for UEFI
  next-server <WORKBENCH_IP>;
}

# Add more hosts as needed
```

### Troubleshooting PXE Boot Issues

If you encounter PXE boot issues:

1. Press Ctrl+B during iPXE boot to drop to the command shell
2. Use the menu option to select the iPXE shell
3. Check network connectivity with `dhcp` and `ifstat`
4. Try manual boot with `chain http://pxe.ponderoos.com/media.ipxe`
5. Review boot logs on the console for error messages

### Building the PXE Boot Files

The PXE boot files are automatically built and made available in the workbench configuration, but you can also manually build them with:

```bash
depot build //services/ghuntley/machines/com-ghuntley-media:netboot
depot build //services/ghuntley/machines/com-ghuntley-media:netbootIpxe
```
