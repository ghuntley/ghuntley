# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary


{ pkgs, config, lib, ... }:
let
  # Enables emails for ZFS, and adds a patch to notify us on all state
  # changes.
  customizeZfs = zfs:
    (zfs.override { enableMail = true; }).overrideAttrs (oldAttrs: {
      patches = oldAttrs.patches ++
        [
          (pkgs.fetchpatch {
            name = "notify-on-unavail-events.patch";
            url = "https://github.com/openzfs/zfs/commit/f74604f2f0d76ee55b59f7ed332409fb128ec7e5.patch";
            sha256 = "1v25ydkxxx704j0gdxzrxvw07gfhi7865grcm8b0zgz9kq0w8i8i";
          })
        ];
    });
in
{

  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.supportedFilesystems = [ "zfs" ];

  nixpkgs.config.packageOverrides = pkgs: {
    zfsStable = customizeZfs pkgs.zfsStable.override { enableMail = true; };
  };

  services.zfs.zed.settings = {
    ZED_EMAIL_ADDR = [ "ghuntley@ghuntley.com" ];
    ZED_NOTIFY_VERBOSE = true;
  };

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "daily";
    };
    trim.enable = true;
  };

  services.sanoid.enable = true;
}
