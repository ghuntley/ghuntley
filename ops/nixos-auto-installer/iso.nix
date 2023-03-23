# Copyright (c) 2022 Kevin Cox. All rights reserved.
# SPDX-License-Identifier: Apache2

(import <nixpkgs/nixos/lib/eval-config.nix> {
  system = "x86_64-linux";
  modules = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    ./configuration.nix
    ({ config, pkgs, lib, ... }: {
      hardware.enableAllFirmware = true;

      systemd.services.install = {
        description = "Bootstrap a NixOS installation";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "polkit.service" ];
        path = [ "/run/current-system/sw/" ];
        script = with pkgs; ''

echo 'journalctl -fb -n100 -uinstall' >>~nixos/.bash_history

set -eux

wait-for() {
    for _ in seq 10; do
        if $@; then
            break
        fi
        sleep 1
    done
}

dev=/dev/vda

wait-for ${utillinux}/bin/wipefs --all --force $dev
sync

wait-for ${utillinux}/bin/sfdisk --force --wipe=always $dev <<-END
    label: mbr

    name=BOOT, size=512MiB,
    name=NIXOS
END

wait-for partprobe $dev
sync

wait-for mkfs.ext4 -L boot /dev/vda1
sync

wait-for ${cryptsetup}/bin/cryptsetup luksFormat --type=luks2 --label=root /dev/vda2 /dev/zero --keyfile-size=1
wait-for ${cryptsetup}/bin/cryptsetup luksOpen /dev/vda2 root --key-file=/dev/zero --keyfile-size=1
sync

wait-for mkfs.ext4 -L nixos /dev/mapper/root
sync

mount /dev/mapper/root /mnt

mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot

install -D ${./configuration.nix} /mnt/etc/nixos/configuration.nix
install -D ${./hardware-configuration.nix} /mnt/etc/nixos/hardware-configuration.nix

sed -i -E 's/(\w*)#installer-only /\1/' /mnt/etc/nixos/*

${config.system.build.nixos-install}/bin/nixos-install \
    --system ${(import <nixpkgs/nixos/lib/eval-config.nix> {
        system = "x86_64-linux";
        modules = [
            ./configuration.nix
            ./hardware-configuration.nix
        ];
    }).config.system.build.toplevel} \
    --no-root-passwd \
    --cores 0

echo 'Shutting off in 1min'
${systemd}/bin/shutdown +1

'';

        environment = config.nix.envVars // {
          inherit (config.environment.sessionVariables) NIX_PATH;
          HOME = "/root";
        };
        serviceConfig = {
          Type = "oneshot";
        };
      };
    })
  ];
}).config.system.build.isoImage
