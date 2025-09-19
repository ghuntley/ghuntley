# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PasswordAuthentication = lib.mkForce false;
    settings.PermitRootLogin = "prohibit-password";
    settings.UseDns = false;
  };

  # Prevent accidental shutdown/reboot via SSH
  environment.systemPackages = [pkgs.molly-guard];

  # Mosh
  programs.mosh.enable = true;
}
