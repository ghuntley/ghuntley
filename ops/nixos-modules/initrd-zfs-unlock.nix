# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, lib, pkgs, ... }: # readTree options
{ config, ... }: # passed by module system

let
  secretFile = name: depot.ops.secrets."${name}.age";

in
{
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      hostKeys = [ age.secrets.ssh-initrd-ed25519-key.file =  secretFile "ssh-initrd-ed25519-key"; ];
      authorizedKeys = [ depot.users.mgmt.keys.all ++ depot.users.ghuntley.keys.all ];
    };

    postCommands = ''
      cat <<EOF > /root/unlock.sh
      if pgrep -x "zfs" > /dev/null
      then
          zfs load-key -a
          killall zfs
      else
          echo "zfs not running -- maybe the pool is taking some time to load for some unforseen reason."
      fi
      EOF

      cat <<EOF > /root/.profile
      zpool import -a
      zpool status
      echo

      chmod u+x /root/unlock.sh
      cat /root/unlock.sh

      ls -ltr
      EOF
    '';
  };

}
