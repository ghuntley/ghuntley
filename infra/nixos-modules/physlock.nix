# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  environment.systemPackages = with pkgs; [ nvme-cli ];

  security.sudo.extraConfig = ''
    # Allow any user to execute systemctl start physlock without a password
    Cmnd_Alias PHYSLOCK = /bin/systemctl start physlock
    ALL ALL=NOPASSWD: PHYSLOCK
  '';

  services.physlock.enable = true;
  services.physlock.lockOn.suspend = true;
  services.physlock.lockOn.hibernate = true;
  services.physlock.allowAnyUser = true;
  services.physlock.muteKernelMessages = true;
  services.physlock.lockMessage = "Only those who pay the Golden Price may bear The Wheel <ghuntley@ghuntley.com>";

}
