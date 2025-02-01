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
  crowbar = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+ADi60itKAWFkKDy1PbkIkgCHMcIcfpbeR0Pmq6kj8";

  # development
  devDefault.publicKeys = ghuntley;

in
{
  "inbox-hello-credentials.age" = prdDefault;

  "nix-cache-signkey.age" = prdDefault;
  "nix-cache-pubkey.age" = prdDefault;

  "wastebin-secret-file.age" = prdDefault;

  "postgres-keycloak-credentials.age" = prdDefault;

  "acme-cloudflare-api-token.age" = prdDefault;

  "buildkite-agent-token.age" = prdDefault;
  "buildkite-graphql-token.age" = prdDefault;
  "buildkite-ssh-private-key.age" = prdDefault;
  "buildkite-ssh-public-key.age" = prdDefault;

  "buildkite-besadii-config.age" = prdDefault;
  "gerrit-besadii-config.age" = prdDefault;

  "deploy-buildkite-credentials.age" = prdDefault;
  "deploy-dns-credentials.age" = prdDefault;
  "deploy-keycloak-ponderoos-credentials.age" = prdDefault;

  "ovh-tfstate-credentials.age" = prdDefault;
  "ovh-backup-credentials.age" = prdDefault;
  "ovh-backup-encryption-key.age" = prdDefault;
  "backup-cli-credentials.age" = prdDefault;
}
