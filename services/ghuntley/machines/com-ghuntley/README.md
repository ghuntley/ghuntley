<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Ghost Machine

A NixOS VM configuration for running Ghost.

## Usage

Build and run the VM:
```bash
depot build //services/ghuntley/machines/com-ghuntley/machine
depot run //services/ghuntley/machines/com-ghuntley/machine
```

Build specific components:
```bash
# Build the ISO
depot build //services/ghuntley/machines/com-ghuntley/machine:iso

# Run the tests
depot test //services/ghuntley/machines/com-ghuntley/machine:tests
```

## Getting the ISO URL

To get the URL where the ISO is stored:
```bash
# This will output the URL where the ISO can be downloaded
depot eval //services/ghuntley/machines/com-ghuntley/machine:url
```

The URL is generated using Harmonia's storage system and can be used to download the ISO from any machine with appropriate access.

## Enhanced PXE Boot

This system is part of a multi-machine PXE boot configuration. The PXE boot files for all machines are automatically served by the workbench system's TFTP server directly from the Nix store, with a fallback HTTP server option.

### MAC Address Configuration

This machine is configured to boot with the MAC address: `BC:24:11:97:45:4B`. The workbench TFTP server has MAC-specific boot configurations for this address and other machines in the network.

### Interactive Boot Menu

The iPXE configuration includes an interactive boot menu that lists all available machines:

- Ghuntley.com Website (this machine)
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
- `/srv/tftp/ghuntley.ipxe` - The main iPXE script for this machine
- `/srv/tftp/bc:24:11:97:45:4b.ipxe` - MAC-specific iPXE script with error handling
- `/srv/tftp/pxelinux.cfg/01-bc-24-11-97-45-4b` - MAC-specific PXELinux configuration
- `/srv/tftp/ghuntley.tar.gz` - The netboot ramdisk archive
- `/srv/tftp/menu.ipxe` - Interactive boot menu with all machines
- `/srv/tftp/boot.ipxe` - MAC-detection script

Additionally, these files are also available via HTTP at:
- `http://pxe.ponderoos.com/`

### Building the PXE Boot Files

The PXE boot files are automatically built and made available in the workbench configuration, but you can also manually build them with:

```bash
depot build //services/ghuntley/machines/com-ghuntley:netboot
depot build //services/ghuntley/machines/com-ghuntley:netbootIpxe
```
