# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Standard NixOS users for machines, as well as configuration that
# should following along when they are added to a machine.
{ depot, pkgs, ... }:

{
  users = {
    users.mgmt = {
      isNormalUser = true;
      extraGroups = [ "git" "wheel" "docker" "libvirtd" ];
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = depot.users.mgmt.keys.all;
    };
    users.ghuntley = {
      isNormalUser = true;
      extraGroups = [ "git" "wheel" "docker" "libvirtd" ];
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = depot.users.ghuntley.keys.all;
    };
  };

}
