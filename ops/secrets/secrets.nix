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
  initrd-rescue = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9wN51lVteNd8hUtx9QerSBZUFVI6K9U1yc3N97wbiv root@rescue";

  prd-bne-ts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG root@ts";

  prd-bne-cache = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG root@cache":

  prd-fsn1-dc11-1880953 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGstvAIecEPv1bgozIC/faiCs3bwPWLn4sekKj+hbgN2 root@prd-fsn1-dc11-1880953";

  prdDefault.publicKeys = allDefault.publicKeys ++ [
    initrd-rescue
    prd-bne-cache
    prd-bne-ts
    prd-fsn1-dc11-1880953
  ];

  service-nixcache.publicKeys = allDefault.publicKeys ++ [
    prd-fsn1-dc11-1880953
  ];

  service-smtp.publicKeys = allDefault.publicKeys ++ [
    prd-bne-ts
    prd-fsn1-dc11-1880953
  ];


  # development
  devDefault.publicKeys = ghuntley;

in
{
  "nix-cache-priv.age" = service-nixcache;
  "nix-cache-pub.age" = service-nixcache;
  "smtprelay.age" = service-smtp;
  "ssh-initrd-ed25519-key.age" = prdDefault;
  "ssh-initrd-ed25519-pub.age" = prdDefault;
  "tailscale-ephemeral-server-bootstrap-key.age" = prdDefault;
}
