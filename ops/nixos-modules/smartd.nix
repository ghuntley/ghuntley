# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  environment.systemPackages = with pkgs; [ smartmontools ];

  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
  };
}
