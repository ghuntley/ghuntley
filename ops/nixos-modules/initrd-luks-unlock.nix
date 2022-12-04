# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, config, lib, pkgs, ... }:
{
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      hostKeys = [ config.age.secrets.ssh-initrd-ed25519-key.path ];
      authorizedKeys = depot.users.mgmt.keys.all;
    };

    postCommands = ''
      cat <<EOF > /root/unlock.sh
      cryptsetup open /dev/vda2 root --type luks && echo > /tmp/continue
      EOF

      cat <<EOF > /root/.profile
      chmod u+x /root/unlock.sh
      cat /root/unlock.sh

      ls -ltr
      EOF
    '';
};


boot.initrd.postDeviceCommands = ''
      echo 'waiting for root device to be opened...'
      mkfifo /tmp/continue
      cat /tmp/continue
    '';


}
