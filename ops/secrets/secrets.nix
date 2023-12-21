# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
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
  initrd-rescue = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOBXo4HvfT4cVCf3gmsiITUI+U3AeKZlH36qVUBHtvs";
  ghuntley-net = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImDI8vTJOtaRs/ZTh0J/eBVnV4hRoDQptWJXFPObk/8";
  ghuntley-com = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBawMvsd34U5tZawyD7LoYUn8PJw4gaXVwUeEoZP8kT9";
  ghuntley-dev = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBawMvsd34U5tZawyD7LoYUn8PJw4gaXVwUeEoZP8kT9";

  prdDefault.publicKeys = allDefault.publicKeys ++ [
    initrd-rescue
    ghuntley-net
    ghuntley-com
    ghuntley-dev
  ];

  service-smtp.publicKeys = allDefault.publicKeys ++ [
    ghuntley-net
    ghuntley-com
    ghuntley-dev
  ];


  # development
  devDefault.publicKeys = ghuntley;

in
{
  "acme-cloudflare-api-token.age" = prdDefault;

  "rsync-net-backups-ssh-key.age" = prdDefault;
  "rsync-net-backups-ssh-pub.age" = prdDefault;

  "ghuntley-net-cachix-agent-token.age" = prdDefault;

  "ghuntley-net-caddy-environment-file.age" = prdDefault;

  "coder-gcp-service-account-ghuntley-dev-token.age" = prdDefault;

  "ghuntley-dev-coder-secrets.age" = prdDefault;

  "ssh-initrd-ed25519-key.age" = prdDefault;
  "ssh-initrd-ed25519-pub.age" = prdDefault;
}
