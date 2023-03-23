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

  prdDefault.publicKeys = allDefault.publicKeys ++ [
    initrd-rescue
    ghuntley-net
  ];

  service-nixcache.publicKeys = allDefault.publicKeys ++ [
    ghuntley-net
  ];

  service-smtp.publicKeys = allDefault.publicKeys ++ [
    ghuntley-net
  ];


  # development
  devDefault.publicKeys = ghuntley;

in
{
  "ssh-initrd-ed25519-key.age" = prdDefault;
  "ssh-initrd-ed25519-pub.age" = prdDefault;
}
