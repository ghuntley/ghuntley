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
  prd-bne-ca = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICS26s/wN6eyyM2/JcNAGA74bI54s5ALk0u8mOVbxSz+ root@ca";
  prd-bne-cache = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG root@cache";
  prd-bne-proxy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEG0iV1HBOqhR8J1AEMWFHB5WeBkMX6HN7n7EPF0Ap1e root@proxy";
  prd-bne-smtp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQEX+nJtbsJikHs5MqRGfPA1HzbSdqD0LPq9TcmBZdV root@smtp";
  prd-bne-time = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMeKTNstopArcJk5z7Ag6WO8MXlROSxWQ+4cP9rhlpUp root@time";
  prd-bne-ts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObx9zfI6Zk40Dxk2GvBoQzZukj41O5wdf4XnaF5cjOG root@ts";
  prd-fsn1-dc11-1880953 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGstvAIecEPv1bgozIC/faiCs3bwPWLn4sekKj+hbgN2 root@prd-fsn1-dc11-1880953";

  prdDefault.publicKeys = allDefault.publicKeys ++ [
    initrd-rescue
    prd-bne-ca
    prd-bne-cache
    prd-bne-proxy
    prd-bne-smtp
    prd-bne-time
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
