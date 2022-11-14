# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

let
  ghuntley = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR"
  ];

  dev = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICtmnBGU6SJlT2eW2K7uxhV79/EkHy2kFKnEEkRIerxE";

  devDefault.publicKeys = ghuntley ++ [ dev ];
  allDefault.publicKeys = ghuntley ++ [ dev ];
in
{
  "depot-ops-dns-secrets.age" = devDefault;
  "tailscale-reusable-key.age" = devDefault;
}
