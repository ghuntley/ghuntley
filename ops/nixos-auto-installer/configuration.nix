# Copyright (c) 2022 Kevin Cox. All rights reserved.
# SPDX-License-Identifier: Apache2

{ config, lib, pkgs, ... }: {
  imports = [
    #installer-only ./hardware-configuration.nix
  ];

  nixpkgs.config.allowUnfree = true;

  zramSwap.enable = true;
  services.logind.lidSwitch = "ignore";

  security.sudo.wheelNeedsPassword = false;

  networking.hostName = "install";

  services.openssh.enable = true;
  services.openssh.passwordAuthentication = true;
  services.openssh.permitRootLogin = "yes";

  users.mutableUsers = false;
  users.users.root = {
    # Password is "linux"
    hashedPassword = lib.mkForce "$6$VbYV0ad/Zmrx3mFz$2ywvFQ/fSOG.dbUCaImGUIg9gLi/BKnKzYhbO.rWLedq82GrzpIoSoi3hZm950kJy3FpcM0bcDbGwvbx4aLve1";
  };

  services.avahi = {
    enable = true;
    ipv4 = true;
    ipv6 = true;
    nssmdns = true;
    publish = { enable = true; domain = true; addresses = true; };
  };

  environment.systemPackages = with pkgs; [
    curl
    file
    git
    htop
    lsof
    nano
    openssl
    pciutils
    pv
    tmux
    tree
    unar
    vim_configurable
    wget
    zip
  ];
}
