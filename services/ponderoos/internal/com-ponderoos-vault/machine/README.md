<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Vault Machine

A NixOS VM configuration for running HashiCorp Vault.

## Usage

Build and run the VM:
```bash
depot build //services/ponderoos/internal/com-ponderoos-vault/machine
depot run //services/ponderoos/internal/com-ponderoos-vault/machine
```

Build specific components:
```bash
# Build the ISO
depot build //services/ponderoos/internal/com-ponderoos-vault/machine:iso

# Run the tests
depot test //services/ponderoos/internal/com-ponderoos-vault/machine:tests
```

## Getting the ISO URL

To get the URL where the ISO is stored:
```bash
# This will output the URL where the ISO can be downloaded
depot eval //services/ponderoos/internal/com-ponderoos-vault/machine:url
```

The URL is generated using Harmonia's storage system and can be used to download the ISO from any machine with appropriate access.
