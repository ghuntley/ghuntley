# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }:

let
  host = "${config.networking.hostName}.${config.networking.domain}";
in

 {

  environment.systemPackages = with pkgs; [ smartmontools ];

  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
    notifications.mail = {
      enable = true;
      sender = "${host}@noreply.fediversehosting.com";
      recipient = "support@fediversehosting.com";
    };
  };
}
