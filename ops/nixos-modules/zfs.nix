# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.supportedFilesystems = [ "zfs" ];

  nixpkgs.config.packageOverrides = pkgs: {
    zfsStable = pkgs.zfsStable.override { enableMail = true; };
  };

  services.zfs.zed.settings = {
    ZED_EMAIL_ADDR = [ "support@fediversehosting.com" ];
    ZED_NOTIFY_VERBOSE = true;
  };

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    autoSnapshot = {
      enable = true;
      frequent = 32; # 4 hours.
      daily = 14;
      weekly = 4;
      monthly = 4;
    };
    trim.enable = true;
  };

}
