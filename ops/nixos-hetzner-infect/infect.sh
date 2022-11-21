#!/usr/bin/env bash

# Installs NixOS on a Hetzner server, wiping the server.
#
# This is for a specific server configuration; adjust where needed.
#
# Prerequisites:
#   * this script requires ubuntu installed
#   * Update the script to put in your SSH pubkey, adjust hostname, NixOS version etc.
#   * have the following packages installed
#   * - zfs-initramfs
#   * - parted
#   * - sudo
#   * - grub-efi-amd64-bin
# cat > /etc/apt/preferences.d/90_zfs <<EOF
# Package: libnvpair1linux libuutil1linux libzfs2linux libzpool2linux spl-dkms zfs-dkms zfs-test zfsutils-linux zfsutils-linux-dev zfs-zed
# Pin: release n=buster-backports
# Pin-Priority: 990
# EOF

apt update -y
apt install -y dpkg-dev linux-headers-$(uname -r) linux-image-amd64 sudo parted
echo y | zfs
modprobe zfs

#
# Usage:
#     scp zfs-encryption-key root@148.251.233.2:/tmp
#     ssh root@YOUR_SERVERS_IP bash -s < hetzner-dedicated-wipe-and-install-nixos.sh
#
# When the script is done, make sure to boot the server from HD, not rescue mode again.

# Explanations:
#
# * Following largely https://nixos.org/nixos/manual/index.html#sec-installing-from-other-distro.
# * and https://nixos.wiki/wiki/NixOS_on_ZFS
# * **Important:** First you need to boot in legacy-BIOS mode. Then ask for
# hetzner support to enable UEFI for you.
# * We set a custom `configuration.nix` so that we can connect to the machine afterwards,
#   inspired by https://nixos.wiki/wiki/Install_NixOS_on_Hetzner_Online
# * This server has 2 SSDs.
#   We put everything on mirror (RAID1 equivalent).
# * A root user with empty password is created, so that you can just login
#   as root and press enter when using the Hetzner spider KVM.
#   Of course that empty-password login isn't exposed to the Internet.
#   Change the password afterwards to avoid anyone with physical access
#   being able to login without any authentication.
# * The script reboots at the end.

set -euox pipefail

# Inspect existing disks
# Should give you something like
# NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
# nvme0n1     259:0    0 476.9G  0 disk
# ├─nvme0n1p1 259:2    0    32G  0 part
# │ └─md127       9:0    0    32G  0 raid1 [SWAP]
# ├─nvme0n1p2 259:3    0   512M  0 part
# │ └─md1       9:1    0   511M  0 raid1 /boot
# └─nvme0n1p3 259:4    0 444.4G  0 part
#   └─md2       9:2    0 444.3G  0 raid1 /
# nvme1n1     259:1    0 476.9G  0 disk
# ├─nvme1n1p1 259:5    0    32G  0 part
# │ └─md127       9:0    0    32G  0 raid1 [SWAP]
# ├─nvme1n1p2 259:6    0   512M  0 part
# │ └─md1       9:1    0   511M  0 raid1 /boot
# └─nvme1n1p3 259:7    0 444.4G  0 part
#   └─md2       9:2    0 444.3G  0 raid1 /
lsblk

# check the disks that you have available
# you have to use disks by ID with zfs
# see https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2020.04%20Root%20on%20ZFS.html#step-2-disk-formatting
ls /dev/disk/by-id
# should give you something like this
# md-name-rescue:0                             nvme-eui.0025388a01051b58-part1
# md-name-rescue:1                             nvme-eui.0025388a01051b58-part2
# md-name-rescue:2                             nvme-eui.0025388a01051b58-part3
# md-uuid-15391820:32e070f6:ecbfb99e:e983e018  nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00424
# md-uuid-48379d14:3c44fe11:e6528eec:ad784ade  nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00424-part1
# md-uuid-f2a894fc:9e90e3af:9af81d28:b120ae1f  nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00424-part2
# nvme-eui.0025388a01051b55                    nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00424-part3
# nvme-eui.0025388a01051b55-part1              nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00427
# nvme-eui.0025388a01051b55-part2              nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00427-part1
# nvme-eui.0025388a01051b55-part3              nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00427-part2
# nvme-eui.0025388a01051b58                    nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00427-part3
#
# we will use the two disks
# nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00424
# nvme-SAMSUNG_MZVLB512HBJQ-00000_S4GENA0NA00427

# The following variables should be replaced
DISK1=/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAG800126
DISK2=/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAG800130
# Replace with your key
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiX7qvQS3QjzL8y31KxMPn5EOyufjgz2YuRD3GNWcuR ghuntley@ghuntley.com"
# choose whatever you want, it doesn't matter
MY_HOSTNAME=hetzner-ghuntley-blank
MY_HOSTID=deadbeef

# Undo existing setups to allow running the script multiple times to iterate on it.
# We allow these operations to fail for the case the script runs the first time.
umount -a || true

umount /mnt/boot || true
vgchange -an || true
mdadm --stop --scan

umount /mnt/depot || true
umount /mnt/srv || true
umount /mnt/home || true
umount /mnt/nix || true
umount /mnt/etc || true
umount /mnt || true
zpool destroy -f rpool || true

wipefs -a $DISK1-part3
wipefs -a $DISK2-part3

# Prevent mdadm from auto-assembling arrays.
# Otherwise, as soon as we create the partition tables below, it will try to
# re-assemple a previous RAID if any remaining RAID signatures are present,
# before we even get the chance to wipe them.
# From:
#     https://unix.stackexchange.com/questions/166688/prevent-debian-from-auto-assembling-raid-at-boot/504035#504035
# We use `>` because the file may already contain some detected RAID arrays,
# which would take precedence over our `<ignore>`.
echo 'AUTO -all
ARRAY <ignore> UUID=00000000:00000000:00000000:00000000' > /etc/mdadm/mdadm.conf

# Create wrapper for parted >= 3.3 that does not exit 1 when it cannot inform
# the kernel of partitions changing (we use partprobe for that).
echo -e "#! /usr/bin/env bash\nset -e\n" 'parted $@ 2> parted-stderr.txt || grep "unable to inform the kernel of the change" parted-stderr.txt && echo "This is expected, continuing" || echo >&2 "Parted failed; stderr: $(< parted-stderr.txt)"' > parted-ignoring-partprobe-error.sh && chmod +x parted-ignoring-partprobe-error.sh

# Create partition tables (--script to not ask)
./parted-ignoring-partprobe-error.sh --script $DISK1 mklabel gpt
./parted-ignoring-partprobe-error.sh --script $DISK2 mklabel gpt

# Create partitions (--script to not ask)
#
# We create the 1MB BIOS boot partition at the front.
#
# Note we use "MB" instead of "MiB" because otherwise `--align optimal` has no effect;
# as per documentation https://www.gnu.org/software/parted/manual/html_node/unit.html#unit:
# > Note that as of parted-2.4, when you specify start and/or end values using IEC
# > binary units like "MiB", "GiB", "TiB", etc., parted treats those values as exact
#
# Note: When using `mkpart` on GPT, as per
#   https://www.gnu.org/software/parted/manual/html_node/mkpart.html#mkpart
# the first argument to `mkpart` is not a `part-type`, but the GPT partition name:
#   ... part-type is one of 'primary', 'extended' or 'logical', and may be specified only with 'msdos' or 'dvh' partition tables.
#   A name must be specified for a 'gpt' partition table.
# GPT partition names are limited to 36 UTF-16 chars, see https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_entries_(LBA_2-33).
# TODO the bios partition should not be this big
# however if it's less the installation fails with
# cannot copy /nix/store/d4xbrrailkn179cdp90v4m57mqd73hvh-linux-5.4.100/bzImage to /boot/kernels/d4xbrrailkn179cdp90v4m57mqd73hvh-linux-5.4.100-bzImage.tmp: No space left on device
./parted-ignoring-partprobe-error.sh --script --align optimal $DISK1 -- mklabel gpt \
    mkpart 'BIOS-boot-partition' 1MB 2MB set 1 bios_grub on \
    mkpart 'EFI-system-partition' 2MB 512MB set 2 esp on \
    mkpart 'data-partition' 512MB '100%'

./parted-ignoring-partprobe-error.sh --script --align optimal $DISK2 -- mklabel gpt \
    mkpart 'BIOS-boot-partition' 1MB 2MB set 1 bios_grub on \
    mkpart 'EFI-system-partition' 2MB 512MB set 2 esp on \
    mkpart 'data-partition' 512MB '100%'

# Reload partitions
partprobe

# Wait for all devices to exist
udevadm settle --timeout=5 --exit-if-exists=$DISK1-part1
udevadm settle --timeout=5 --exit-if-exists=$DISK1-part2
udevadm settle --timeout=5 --exit-if-exists=$DISK1-part3
udevadm settle --timeout=5 --exit-if-exists=$DISK2-part1
udevadm settle --timeout=5 --exit-if-exists=$DISK2-part2
udevadm settle --timeout=5 --exit-if-exists=$DISK2-part3

# Wipe any previous RAID signatures
# somehow the previous RAID signature is only on part1
mdadm --zero-superblock --force $DISK1-part1
mdadm --zero-superblock --force $DISK2-part1

# Creating file systems changes their UUIDs.
# Trigger udev so that the entries in /dev/disk/by-uuid get refreshed.
# `nixos-generate-config` depends on those being up-to-date.
# See https://github.com/NixOS/nixpkgs/issues/62444
udevadm trigger

# taken from https://nixos.wiki/wiki/NixOS_on_ZFS
zpool create -O mountpoint=none \
    -O atime=off \
    -O compression=lz4 \
    -O xattr=sa \
    -O acltype=posixacl \
    -o ashift=12 \
    -f rpool mirror $DISK1-part3 $DISK2-part3

# Create the filesystems. This layout is designed so that /home is separate from the root
# filesystem, as you'll likely want to snapshot it differently for backup purposes. It also
# makes a "nixos" filesystem underneath the root, to support installing multiple OSes if
# that's something you choose to do in future.

ZFS_ENCRYPTION_KEY=`cat /tmp/zfs-encryption-key`
for pool in rpool/root rpool/root/etc rpool/root/nix rpool/root/home rpool/root/depot rpool/root/srv
do
    echo "$ZFS_ENCRYPTION_KEY" | zfs create \
        -o canmount=off \
        -o mountpoint=legacy \
        -o encryption=on \
        -o keyformat=passphrase \
        -o keylocation=prompt \
        $pool
done

zfs create -o setuid=off -o devices=off -o sync=disabled -o mountpoint=legacy rpool/tmp

# add 1G of reseved space in case the disk gets full
# zfs needs space to delete files
zfs create -o refreservation=1G -o mountpoint=none rpool/reserved

# this creates a special volume for db data see https://wiki.archlinux.org/index.php/ZFS#Databases
# zfs create -o mountpoint=legacy \
#     -o recordsize=8K \
#     -o primarycache=metadata \
#     -o logbias=throughput \
#     rpool/postgres

# NixOS pre-installation mounts
#
# Mount the filesystems manually. The nixos installer will detect these mountpoints
# and save them to /mnt/nixos/hardware-configuration.nix during the install process.

mkdir /mnt || true
mount -t zfs rpool/root /mnt

mkdir /mnt/tmp || true
mount -t zfs rpool/tmp /tmp

mkdir /mnt/etc || true
mount -t zfs rpool/root/etc /mnt/etc

mkdir /mnt/nix || true
mount -t zfs rpool/root/nix /mnt/nix

mkdir /mnt/home || true
mount -t zfs rpool/root/home /mnt/home

mkdir -p /mnt/depot || true
mount -t zfs rpool/root/depot /mnt/depot

mkdir -p /mnt/srv || true
mount -t zfs rpool/root/srv /mnt/srv


# mkdir -p /mnt/var/lib/postgres
# mount -t zfs rpool/postgres /mnt/var/lib/postgres

# Create a raid mirror for the efi boot
# see https://docs.hetzner.com/robot/dedicated-server/operating-systems/efi-system-partition/
# TODO check this though the following article says it doesn't work properly
# https://outflux.net/blog/archives/2018/04/19/uefi-booting-and-raid1/ 
mdadm --create --run --verbose /dev/md127 \
    --level 1 \
    --raid-disks 2 \
    --metadata 1.0 \
    --homehost=$MY_HOSTNAME \
    --name=boot_efi \
    $DISK1-part2 $DISK2-part2

# Assembling the RAID can result in auto-activation of previously-existing LVM
# groups, preventing the RAID block device wiping below with
# `Device or resource busy`. So disable all VGs first.
vgchange -an

# Wipe filesystem signatures that might be on the RAID from some
# possibly existing older use of the disks (RAID creation does not do that).
# See https://serverfault.com/questions/911370/why-does-mdadm-zero-superblock-preserve-file-system-information
wipefs -a /dev/md127

# Disable RAID recovery. We don't want this to slow down machine provisioning
# in the rescue mode. It can run in normal operation after reboot.
echo 0 > /proc/sys/dev/raid/speed_limit_max

# Filesystems (-F to not ask on preexisting FS)
mkfs.ext4 /dev/md127

# Creating file systems changes their UUIDs.
# Trigger udev so that the entries in /dev/disk/by-uuid get refreshed.
# `nixos-generate-config` depends on those being up-to-date.
# See https://github.com/NixOS/nixpkgs/issues/62444
udevadm trigger

mkdir -p /mnt/boot
mount /dev/md127 /mnt/boot

# Installing nix

# Allow installing nix as root, see
#   https://github.com/NixOS/nix/issues/936#issuecomment-475795730
mkdir -p /etc/nix
echo "build-users-group =" > /etc/nix/nix.conf

sh <(curl -L https://nixos.org/nix/install) --daemon || true
set +u +x # sourcing this may refer to unset variables that we have no control over
. $HOME/.nix-profile/etc/profile.d/nix.sh
set -u -x

# Keep in sync with `system.stateVersion` set below!
nix-channel --add https://nixos.org/channels/nixos-22.05 nixpkgs
nix-channel --update

# Getting NixOS installation tools
nix-env -iE "_: with import <nixpkgs/nixos> { configuration = {}; }; with config.system.build; [ nixos-generate-config nixos-install nixos-enter manual.manpages ]"

unset LANGUAGE
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"

nixos-generate-config --root /mnt

# Find the name of the network interface that connects us to the Internet.
# Inspired by https://unix.stackexchange.com/questions/14961/how-to-find-out-which-interface-am-i-using-for-connecting-to-the-internet/302613#302613
RESCUE_INTERFACE=$(ip route get 8.8.8.8 | grep -Po '(?<=dev )(\S+)')

# Find what its name will be under NixOS, which uses stable interface names.
# See https://major.io/2015/08/21/understanding-systemds-predictable-network-device-names/#comment-545626
# NICs for most Hetzner servers are not onboard, which is why we use
# `ID_NET_NAME_PATH`otherwise it would be `ID_NET_NAME_ONBOARD`.
INTERFACE_DEVICE_PATH=$(udevadm info -e | grep -Po "(?<=^P: )(.*${RESCUE_INTERFACE})")
UDEVADM_PROPERTIES_FOR_INTERFACE=$(udevadm info --query=property "--path=$INTERFACE_DEVICE_PATH")
NIXOS_INTERFACE=$(echo "$UDEVADM_PROPERTIES_FOR_INTERFACE" | grep -o -E 'ID_NET_NAME_PATH=\w+' | cut -d= -f2)
echo "Determined NIXOS_INTERFACE as '$NIXOS_INTERFACE'"

IP_V4=$(ip route get 8.8.8.8 | grep -Po '(?<=src )(\S+)')
echo "Determined IP_V4 as $IP_V4"

# Determine Internet IPv6 by checking route, and using ::1
# (because Hetzner rescue mode uses ::2 by default).
# The `ip -6 route get` output on Hetzner looks like:
#   # ip -6 route get 2001:4860:4860:0:0:0:0:8888
#   2001:4860:4860::8888 via fe80::1 dev eth0 src 2a01:4f8:151:62aa::2 metric 1024  pref medium
IP_V6="$(ip route get 2001:4860:4860:0:0:0:0:8888 | head -1 | cut -d' ' -f7 | cut -d: -f1-4)::1"
echo "Determined IP_V6 as $IP_V6"

# From https://stackoverflow.com/questions/1204629/how-do-i-get-the-default-gateway-in-linux-given-the-destination/15973156#15973156
read _ _ DEFAULT_GATEWAY _ < <(ip route list match 0/0); echo "$DEFAULT_GATEWAY"
echo "Determined DEFAULT_GATEWAY as $DEFAULT_GATEWAY"


# Generate ssh boot unlock host key
# 
mkdir -p /mnt/etc/ssh
rm /mnt/etc/ssh/ssh_boot_ed25519_key || true
ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_boot_ed25519_key
# https://github.com/NixOS/nixpkgs/issues/73404
cp /mnt/etc/ssh/ssh_boot_ed25519_key /etc/ssh

# Generate `configuration.nix`. Note that we splice in shell variables.
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use GRUB2 as the boot loader.
  # We don't use systemd-boot because Hetzner uses BIOS legacy boot.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    devices = ["$DISK1" "$DISK2"];
    copyKernels = true; 
  };
  boot.supportedFilesystems = [ "zfs" ];

  # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
  boot.kernelParams=["ip=$IP_V4:$IP_V4:$DEFAULT_GATEWAY:255.255.255.224"];

  # Network card drivers.
  # https://unix.stackexchange.com/questions/41817/linux-how-to-find-the-device-driver-used-for-a-device
  boot.initrd.kernelModules = [ "igb" ];

  boot.initrd.network = {
    # Static ip addresses can be configured using the ip argument in kernel command line:
    # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
    enable = true;
    ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used,
        # a different port for ssh is useful (assuming the same host has also a regular sshd running)
        port = 2222; 

        # hostKeys paths must be unquoted strings, otherwise you'll run into issues with boot.initrd.secrets
        # the keys are copied to initrd from the path specified; multiple keys can be set
        # you can generate any number of host keys using 
        # `ssh-keygen -t ed25519 -N "" -f /path/to/ssh_host_ed25519_key`

        hostKeys = [ /etc/ssh/ssh_boot_ed25519_key ];

        # public ssh key used for login
        authorizedKeys = [ "$SSH_PUB_KEY" ];
    };

    # this will automatically load the zfs password prompt on login
    # and kill the other prompt so boot can continue
    postCommands = ''
    cat <<EOF > /root/.profile
    if pgrep -x "zfs" > /dev/null
    then
        zfs load-key -a
        killall zfs
    else
        echo "zfs not running -- maybe the pool is taking some time to load for some unforseen reason."
    fi
    EOF
    '';
  };

  networking.hostName = "$MY_HOSTNAME";
  networking.hostId = "$MY_HOSTID";

  # Network (Hetzner uses static IP assignments, and we don't use DHCP here)
  networking.useDHCP = false;
  networking.interfaces."$NIXOS_INTERFACE".ipv4.addresses = [
    {
      address = "$IP_V4";
      prefixLength = 24;
    }
  ];
  networking.interfaces."$NIXOS_INTERFACE".ipv6.addresses = [
    {
      address = "$IP_V6";
      prefixLength = 64;
    }
  ];
  networking.defaultGateway = "$DEFAULT_GATEWAY";
  networking.defaultGateway6 = { address = "fe80::1"; interface = "$NIXOS_INTERFACE"; };
  networking.nameservers = [ "8.8.8.8" ];

  # Initial empty root password for easy login:
  users.users.root.initialHashedPassword = "";
  services.openssh.permitRootLogin = "prohibit-password";

  users.users.root.openssh.authorizedKeys.keys = ["$SSH_PUB_KEY"];

  services.openssh.enable = true;

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  services.sanoid.enable = true;
  services.sanoid.interval = "hourly";
#   services.sanoid.settings = { 
#     autosnap=1;
#     autoprune="yes";
#     hourly=48;
#     daily=30;
#     weekly=0;
#     monthly=0;
#     yearly=0;
#   };

  services.sanoid.datasets."rpool/root/nix".autosnap = false;
  services.sanoid.datasets."rpool/root/tmp".autosnap = false;


  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "22.05"; # Did you read the comment?

}
EOF

# Install NixOS

# https://github.com/NixOS/nixpkgs/issues/126141#issuecomment-861720372
# https://discourse.nixos.org/t/nixos-21-05-installation-failed-installing-from-an-existing-distro/13627/3
nix-build '<nixpkgs/nixos>' -A config.system.build.toplevel -I nixos-config=/mnt/etc/nixos/configuration.nix

nixos-install --no-root-passwd --root /mnt --max-jobs 40


echo Done! Time to reboot
#reboot
