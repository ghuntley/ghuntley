<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Media Machine

A NixOS VM configuration for running media services.

## Usage

Build and run the VM:
```bash
depot build //services/ghuntley/com-ghuntley-media/machine
depot run //services/ghuntley/com-ghuntley-media/machine
```

Build specific components:
```bash
# Build the ISO
depot build //services/ghuntley/com-ghuntley-media/machine:iso

# Run the tests
depot test //services/ghuntley/com-ghuntley-media/machine:tests
```

## Getting the ISO URL

To get the URL where the ISO is stored:
```bash
# This will output the URL where the ISO can be downloaded
depot eval //services/ghuntley/com-ghuntley-media/machine:url
```

The URL is generated using Harmonia's storage system and can be used to download the ISO from any machine with appropriate access.
