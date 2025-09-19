<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Secrets Management with sops-nix

This directory contains encrypted secrets managed with sops-nix. Each machine has its own secrets
file for security isolation.

## Per-Machine Secrets Structure

- `workbench.yaml` - Secrets for workbench machine
- `lathe.yaml` - Secrets for lathe machine
- `.sops.yaml` - SOPS configuration with per-machine encryption rules

Each machine can only decrypt its own secrets file using its SSH host key.

## Setup

1. **Install age and sops**:
   ```bash
   nix-shell -p age sops ssh-to-age
   ```

2. **Generate user age key**:
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

3. **Get machine SSH host keys**:
   ```bash
   # Get public key
   ssh-keyscan -t ed25519 <hostname>
   # Convert to age format
   echo "<ssh-public-key>" | ssh-to-age
   ```

4. **Update .sops.yaml** with machine keys

## Creating machine-specific secrets

1. **Create secrets file for a machine**:
   ```bash
   cp secrets.yaml.example <hostname>.yaml
   # Edit the file with machine-specific secrets
   ```

2. **Encrypt the machine secrets**:
   ```bash
   sops -e -i <hostname>.yaml
   ```

## Automatic secrets loading

The secrets module automatically loads secrets based on hostname:

- Machine with hostname "workbench" uses `workbench.yaml`
- Machine with hostname "lathe" uses `lathe.yaml`

No manual configuration needed in machine configs.

## Using secrets in NixOS

```nix
sops.secrets.example-secret = {
  path = "/run/secrets/example-secret";
  mode = "0440";
  owner = "root";
  group = "wheel";
};
```

Secrets will be available at `/run/secrets/` after system rebuild.
