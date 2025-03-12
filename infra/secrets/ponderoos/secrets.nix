# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

let
  # users
  ghuntley = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR ghuntley@ghuntley.com";

  mgmt = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR ghuntley@ghuntley.com";

  allDefault.publicKeys = [
    ghuntley
    mgmt
  ];

  # production
  overalls = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+ADi60itKAWFkKDy1PbkIkgCHMcIcfpbeR0Pmq6kj8";

  prdDefault.publicKeys = allDefault.publicKeys ++ [
    overalls
  ];

  # home
  crowbar = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMBCGLUhUwafgC6Ol6l2sY5N0/PAdyDC89LgB2ptbf1q";
  prybar = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOiiQUUVG9ZMyfXCpv4pa1IfiZwYnZAB09wNj4hA+xw7";

  homeDefault.publicKeys = allDefault.publicKeys ++ [
    crowbar
    prybar
  ];

  # development
  devDefault.publicKeys = ghuntley;

in
{
  "netdata-cloud-claim-token.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;

  "geoipupdate-account-id.age".publicKeys = prdDefault.publicKeys;
  "geoipupdate-license-key.age".publicKeys = prdDefault.publicKeys;

  "archivebox-admin-password.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "vaultwarden-credentials.age".publicKeys = prdDefault.publicKeys;

  "inbox-hello-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;

  "nix-cache-signkey.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "nix-cache-pubkey.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;

  "wastebin-secret-file.age".publicKeys = prdDefault.publicKeys;

  "postgres-keycloak-credentials.age".publicKeys = prdDefault.publicKeys;

  "acme-cloudflare-api-token.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;

  "buildkite-agent-token.age".publicKeys = prdDefault.publicKeys;
  "buildkite-graphql-token.age".publicKeys = prdDefault.publicKeys;
  "buildkite-ssh-private-key.age".publicKeys = prdDefault.publicKeys;
  "buildkite-ssh-public-key.age".publicKeys = prdDefault.publicKeys;

  "buildkite-besadii-config.age".publicKeys = prdDefault.publicKeys;
  "gerrit-besadii-config.age".publicKeys = prdDefault.publicKeys;

  "deploy-buildkite-credentials.age".publicKeys = prdDefault.publicKeys;
  "deploy-dns-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "deploy-keycloak-ponderoos-credentials.age".publicKeys = prdDefault.publicKeys;

  "ovh-tfstate-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "ovh-backup-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "ovh-files-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "ovh-backup-encryption-key.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
  "backup-cli-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;

  "vscode-marketplace-credentials.age".publicKeys = prdDefault.publicKeys ++ homeDefault.publicKeys;
}
