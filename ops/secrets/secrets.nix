# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

let
  # users
  ghuntley = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR ghuntley@ghuntley.com"
  ];

  mgmt = [
    "TBA";
  ];

  allDefault.publicKeys = [
    ghuntley
    mgmt
  ];

  # production
  prd-bne-ts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG root@ts";

  prd-fsn1-dc11-1880953 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGstvAIecEPv1bgozIC/faiCs3bwPWLn4sekKj+hbgN2 root@prd-fsn1-dc11-1880953";
  prd-fsn1-dc11-1880953-boot = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9wN51lVteNd8hUtx9QerSBZUFVI6K9U1yc3N97wbiv root@rescue";

  nixcache-core-corp.publicKeys = [
    allDefault.publicKeys
    prd-fsn1-dc11-1880953
  ];

  smtp-core-corp.publicKeys = [
    allDefault.publicKeys
    fsn1-dc11-1880953
  ];


  # development
  devDefault.publicKeys = ghuntley ++ [ dev ];

in
{
  "nix-cache-priv.age" = nixcache-core-corp;
  "nix-cache-pub.age" = nixcache-core-corp;
  "smtprelay.age" = smtp-core-corp;
}
