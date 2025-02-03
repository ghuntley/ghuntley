# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot ? null
, targetSystem ? null
, ...
} @ args:

let
  inherit (depot.third_party.nixpkgs) lib pkgs;

  # Create QEMU disk image configuration
  qemuNixos = depot.third_party.nixos {
    configuration = { pkgs, ... }: {
      imports = lib.optional (targetSystem != null) targetSystem;

      nixpkgs.pkgs = depot.third_party.nixpkgs;

      # Enable QEMU guest agent
      services.qemuGuest.enable = true;

      # Add basic tools
      environment.systemPackages = with pkgs; [
        vim
        git
        e2fsprogs # Add tools for ext4 filesystem
        parted # Add tools for partitioning
      ];

      # Configure bootloader
      boot.loader = {
        grub.enable = lib.mkForce false; # Force disable GRUB
        systemd-boot.enable = lib.mkForce true; # Force enable systemd-boot
        efi.canTouchEfiVariables = false;
        efi.efiSysMountPoint = "/boot";
      };

      # Configure disk for QEMU
      fileSystems = lib.mkForce {
        "/" = {
          device = "/dev/vda2";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/vda1";
          fsType = "vfat"; # EFI System Partition needs to be FAT
        };
      };

      # Build a fixed-size QCOW2 image
      system.build.qcow2 = pkgs.vmTools.runInLinuxVM (
        pkgs.runCommand "crowbar-qcow2"
          {
            buildInputs = with pkgs; [
              qemu
              e2fsprogs # Add tools for ext4 filesystem
              parted # Add tools for partitioning
              utillinux # Add tools for mounting
              systemd # Add udevadm
              dosfstools # Add tools for FAT filesystem
            ];
            QEMU_OPTS = toString ([
              "-cpu max"
              "-smp 2"
              "-m 2048"
              "-nographic"
              # Add UEFI firmware support
              "-bios ${pkgs.OVMF.fd}/FV/OVMF.fd"
              # Enable EFI vars
              "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
              "-drive if=pflash,format=raw,unit=1,file=$NIX_BUILD_TOP/OVMF_VARS.fd" # Use copied vars file
              # Main disk
              "-drive"
              "file=$NIX_BUILD_TOP/disk.img,if=virtio,format=raw,cache=writeback,werror=report"
            ]);
            preVM = ''
              mkdir -p $out
              # Create a temporary disk for the VM
              qemu-img create -f raw $NIX_BUILD_TOP/disk.img 8G
              # Copy OVMF vars file for writing
              cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd $NIX_BUILD_TOP/OVMF_VARS.fd
              chmod 644 $NIX_BUILD_TOP/OVMF_VARS.fd
            '';
          } ''
          # Create partition table
          parted -s /dev/vda -- mklabel gpt
          parted -s /dev/vda -- mkpart ESP fat32 1MiB 512MiB  # EFI System Partition
          parted -s /dev/vda -- mkpart primary ext4 512MiB 100%  # / partition
          parted -s /dev/vda -- set 1 esp on

          # Wait for device nodes to be created
          ${pkgs.systemd}/bin/udevadm settle || true

          # Format the partitions
          mkfs.vfat -n boot /dev/vda1
          mkfs.ext4 -L nixos /dev/vda2

          # Mount partitions
          mkdir -p /mnt
          mount /dev/vda2 /mnt
          mkdir -p /mnt/boot
          mount /dev/vda1 /mnt/boot

          # Copy system closure
          cp -r ${qemuNixos.config.system.build.toplevel}/* /mnt/

          # Install bootloader
          mkdir -p /mnt/boot/EFI/systemd
          cp ${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi /mnt/boot/EFI/systemd/

          sync
          umount /mnt/boot
          umount /mnt

          # Test the installation by booting into it
          cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd /tmp/test_OVMF_VARS.fd
          chmod 644 /tmp/test_OVMF_VARS.fd

          qemu-system-x86_64 \
            -cpu max \
            -smp 2 \
            -m 2048 \
            -nographic \
            -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
            -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
            -drive if=pflash,format=raw,unit=1,file=/tmp/test_OVMF_VARS.fd \
            -drive file=$NIX_BUILD_TOP/disk.img,if=virtio,format=raw,cache=writeback,werror=report \
            -kernel ${qemuNixos.config.system.build.kernel}/bzImage \
            -initrd ${qemuNixos.config.system.build.initialRamdisk}/initrd \
            -append "console=ttyS0 init=${qemuNixos.config.system.build.toplevel}/init" || exit 1

          rm /tmp/test_OVMF_VARS.fd  # Clean up

          # If we get here, the test was successful
          qemu-img convert -f raw -O qcow2 /dev/vda $out/crowbar.qcow2
        ''
      );
    };

    specialArgs = {
      inherit (args) depot;
    };
  };
in
if targetSystem != null
then qemuNixos.config.system.build.qcow2
else qemuNixos
