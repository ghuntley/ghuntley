# layout

```
export DISK1=/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595
export DISK2=/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015


blkdiscard  -f $DISK1
blkdiscard  -f $DISK2

dd if=/dev/zero of=bs=1M count=1024 of=$DISK1
dd if=/dev/zero of=bs=1M count=1024 of=$DISK2

sgdisk --zap-all $DISK1
sgdisk --zap-all $DISK2

sgdisk -n1:1M:+1G -t1:EF00  $DISK1 # esp (/mnt/boot/efi)
sgdisk -n1:1M:+1G -t1:EF00  $DISK2 # esp (/mnt/boot/efi)

sgdisk -n2:0:+4G -t2:BE00 $DISK1 # bpool
sgdisk -n2:0:+4G -t2:BE00 $DISK2 # bpool

# sgdisk -n4:0:+4G -t3:8200 $DISK1 # swap
# sgdisk -n4:0:+4G -t3:8200 $DISK2 # swap

sgdisk -n3:0:0   -t3:BF00 $DISK1 # rpool
sgdisk -n3:0:0   -t3:BF00 $DISK2 # rpool

sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK1 # backup bios boot
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK2 # backup bios boot

sync && udevadm settle && partprobe && sleep 3

# export DISK="$DISK1 $DISK2"
# for i in ${DISK}; do

# cryptsetup open --type plain --key-file /dev/random $i-part4 ${i##*/}-part4
# mkswap /dev/mapper/${i##*/}-part4
# swapon /dev/mapper/${i##*/}-part4

# done


zpool create \
    -o compatibility=grub2 \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot \
    -R /mnt \
    bpool \
    mirror \
    $DISK1-part2 $DISK2-part2




zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -R /mnt \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O dedup=on \
    -O xattr=sa \
    -O mountpoint=/ \
    rpool \
    mirror \
    $DISK1-part3 $DISK2-part3

zfs create \
      -o canmount=off \
      -o mountpoint=none \
      -o encryption=on \
      -o keylocation=prompt \
      -o keyformat=passphrase \
      rpool/nixos

zfs create -o mountpoint=legacy     rpool/nixos/root
mkdir /mnt
mount -t zfs rpool/nixos/root /mnt/

zfs create -o mountpoint=legacy     rpool/nixos/etc
mkdir /mnt/etc
mount -t zfs rpool/nixos/etc /mnt/etc

zfs create -o mountpoint=legacy     rpool/nixos/nix
zfs set com.sun:auto-snapshot=false rpool/nixos/nix
mkdir /mnt/nix
mount -t zfs rpool/nixos/nix /mnt/nix

zfs create -o mountpoint=legacy rpool/nixos/home
mkdir /mnt/home
mount -t zfs  rpool/nixos/home /mnt/home

zfs create -o mountpoint=legacy  rpool/nixos/var
mkdir /mnt/var
mount -t zfs  rpool/nixos/var /mnt/var

zfs create -o mountpoint=legacy rpool/nixos/var/lib
mkdir /mnt/var/lib
mount -t zfs  rpool/nixos/var/lib /mnt/var/lib

zfs create -o mountpoint=legacy rpool/nixos/var/lib/postgresql
mkdir /mnt/var/lib/postgresql
mount -t zfs  rpool/nixos/var/lib/postgresql /mnt/var/lib/postgresql

zfs create -o mountpoint=legacy rpool/nixos/var/lib/libvirt
mkdir /mnt/var/lib/libvirt
mount -t zfs  rpool/nixos/var/lib/libvirt /mnt/var/lib/libvirt

zfs create -o mountpoint=legacy rpool/nixos/var/lib/libvirt/images
mkdir /mnt/var/lib/libvirt/images
mount -t zfs  rpool/nixos/var/lib/libvirt/images /mnt/var/lib/libvirt/images


zfs create -o mountpoint=legacy rpool/nixos/var/log
mkdir /mnt/var/log
mount -t zfs  rpool/nixos/var/log /mnt/var/log

zfs create -o mountpoint=none bpool/nixos
zfs create -o mountpoint=legacy bpool/nixos/root
mkdir /mnt/boot
mount -t zfs bpool/nixos/root /mnt/boot

zfs create -o mountpoint=legacy rpool/nixos/empty
zfs snapshot rpool/nixos/empty@start

zfs create \
      -o canmount=off \
      -o mountpoint=none \
      -o encryption=on \
      -o keylocation=prompt \
      -o keyformat=passphrase \
      rpool/data


zfs create -o mountpoint=legacy     rpool/data/depot
mkdir /mnt/depot
mount -t zfs rpool/data/depot /mnt/depot

zfs create -o mountpoint=legacy     rpool/data/srv
mkdir /mnt/srv
mount -t zfs rpool/data/srv /mnt/srv


export DISK="$DISK1 $DISK2"
for i in ${DISK}; do
 mkfs.vfat -n EFI ${i}-part1
 mkdir -p /mnt/boot/efis/${i##*/}-part1
 mount -t vfat ${i}-part1 /mnt/boot/efis/${i##*/}-part1
done
```

```

  boot.tmpOnTmpfs = true;
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id/";
  boot.zfs.forceImportRoot = false;
  networking.hostId = "cafebabe";

  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.generationsDir.copyKernels = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.copyKernels = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.zfsSupport = true;

  boot.loader.grub.devices = [
    "/mnt/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1"
    "/mnt/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1"
  ];


 boot.loader.grub.mirroredBoots = [
  {
    devices = [
      "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595"
    ];
    path = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1";
    efiSysMountPoint = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M800595-part1";
  }
  {
    devices = [
      "/dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015"
    ];
    path = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1";
    efiSysMountPoint = "/boot/efis/nvme-WDC_CL_SN720_SDAQNTW-1T00-2000_21116M801015-part1";
  }
];


nix.settings.experimental-features = [ "nix-command" "flakes" ];

```

Number  Start   End     Size    File system  Name  Flags
 5      24.6kB  1049kB  1024kB                     bios_grub
 1      1049kB  1075MB  1074MB  fat32              boot, esp
 2      1075MB  5370MB  4295MB
 3      5370MB  1024GB  1019GB
