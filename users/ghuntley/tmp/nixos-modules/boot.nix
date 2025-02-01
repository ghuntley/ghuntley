# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  boot.tmp.cleanOnBoot = true;

  boot.loader.timeout = 16;
  boot.loader.systemd-boot.memtest86.enable = true;
  boot.loader.grub.memtest86.enable = true;

}
