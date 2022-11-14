Current steps for my NixOS-on-ZFS installs with impermanence.

## Target layout (example from tverskoy):

Partitioning:

```
nvme0n1     259:0    0 238.5G  0 disk
├─nvme0n1p1 259:1    0   128M  0 part /boot (type: EFI system)
└─nvme0n1p2 259:2    0 238.3G  0 part       (type: Solaris root)
```

ZFS layout:

```
NAME                   USED  AVAIL     REFER  MOUNTPOINT
zpool                  212G  19.0G      248K  /zpool
zpool/ephemeral        668M  19.0G      192K  /zpool/ephemeral
zpool/ephemeral/home   667M  19.0G      667M  legacy
zpool/local           71.3G  19.0G      192K  /zpool/local
zpool/local/nix       71.3G  19.0G     71.3G  legacy
zpool/safe             140G  19.0G      192K  /zpool/safe
zpool/safe/depot       414M  19.0G      414M  legacy
zpool/safe/persist     139G  19.0G      139G  legacy
```

With reset-snapshots:

```
NAME                                USED  AVAIL     REFER  MOUNTPOINT
zpool/ephemeral/home@blank          144K      -      192K  -
zpool/ephemeral/home@tazjin-clean   144K      -      200K  -
```

Legacy mountpoints are used because the NixOS wiki advises that using
ZFS own mountpoints might lead to issues with the mount order during
boot.

## Install steps

1. First, get internet.

2. Use `fdisk` to set up the partition layout above (fwiw, EFI type
   should be `1`, Solaris root should be `66`).

3. Format the first partition for EFI: `mkfs.fat -F32 -n EFI $part1`

4. Init ZFS stuff:

   ```
   zpool create \
     # 2 SSD only settings
     -o ashift=12 \
     -o autotrim=on \
     -R /mnt \
     -O canmount=off \
     -O mountpoint=none \
     -O acltype=posixacl \
     -O compression=lz4 \
     -O atime=off \
     -O xattr=sa \
     -O encryption=aes-256-gcm \
     -O keylocation=prompt \
     -O keyformat=passphrase \
     zpool $part2
   ```

   Reserve some space for deletions:

   ```
   zfs create -o refreservation=1G -o mountpoint=none zpool/reserved
   ```

   Create the datasets as per the target layout:

   ```
   # Throwaway datasets
   zfs create -o canmount=off -o mountpoint=none zpool/ephemeral
   zfs create -o mountpoint=legacy zpool/ephemeral/root
   zfs create -o mountpoint=legacy zpool/ephemeral/home

   # Persistent datasets
   zfs create -o canmount=off -o mountpoint=none zpool/persistent
   zfs create -o mountpoint=legacy zpool/persistent/nix
   zfs create -o mountpoint=legacy zpool/persistent/depot
   zfs create -o mountpoint=legacy zpool/persistent/data
   ```

   Create completely blank snapshots of the ephemeral datasets:

   ```
   zfs snapshot zpool/ephemeral/root@blank
   zfs snapshot zpool/ephemeral/home@blank
   ```

   The ephemeral home volume needs the user folder already set up with
   permissions. Mount it and create the folder there:

   ```
   mount -t zfs zpool/ephemeral/root /mnt
   mkdir /mnt/home
   mount -t zfs zpool/ephemeral/home /mnt/home
   mkdir /mnt/home/tazjin
   chmod 1000:100 /mnt/home/tazjin
   zfs snapshot zpool/ephemeral/home@tazjin-clean
   ```

   Now the persistent Nix store volume can be mounted and installation
   can begin.

   ```
   mkdir /mnt/nix
   mount -t zfs zpool/persistent/nix /mnt/nix
   ```

4. Configure & install NixOS as usual.
