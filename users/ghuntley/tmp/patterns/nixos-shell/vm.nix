# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, lib, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.openssh.enable = true;

  users.users.root = {
    # Password is "linux"
    hashedPassword = lib.mkForce "$6$VbYV0ad/Zmrx3mFz$2ywvFQ/fSOG.dbUCaImGUIg9gLi/BKnKzYhbO.rWLedq82GrzpIoSoi3hZm950kJy3FpcM0bcDbGwvbx4aLve1";
  };

  containers.database =
    {
      config =
        { config, pkgs, ... }:
        {
          services.postgresql.enable = true;
        };
    };

  containers.database.autoStart = true;

}
