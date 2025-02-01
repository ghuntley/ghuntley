# Copyright (c) 2020 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, ... }: {

  services.openssh.enable = true;
  services.openssh.passwordAuthentication = true;

  users.users.mgmt = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    password = "hunter2";
  };

  environment.systemPackages = with pkgs; [
    git
    htop
    lsof
    sshpass # remove later
    tmux
  ];

  nix.settings.experimental-features = "nix-command flakes";

  system.stateVersion = "22.11";
}
