# nixos-auto-install

A fully-automatic moderately-opinionated way to install [NixOS](https://nixos.org/).

**WARNING: Booting this ISO is intended to wipe a disk on the system. DO NOT plug it into any device that has important data.**

The logic is simple, NixOS configuration will completely describe a system, so the previous system isn't very important. Therefore the goal of this installer is to set up a NixOS system that is provisioned just enough that you can install whatever you like. The only real decision made for you is disk partitioning, disk encryption and filesystem; but these parameters can easily be modified by adjusting the config before building the image.

Features:

* Automatic
* Offline
* Disk Encryption

## Access

Both the installer and the installed system have only a root account with the password `linux`. You can SSH in (use the MDNS address `install.local`) to monitor the installer, make manual changes or access the installed system afterwards.

Tip: An entry is added to the shell history with a command to view the installer logs. Simply press `<Up><Enter>` to run it.

**WARNING: With a simple password like `linux` you should not expose the system to the internet. If you need to expose it to the internet consider removing the `hashedPassword`, setting [`users.users.root.openssh.authorizedKeys.keys`](https://search.nixos.org/options?show=users.users.%3Cname%3F%3E.openssh.authorizedKeys.keys&query=users.users%20openssh&sort=alpha_asc&channel=unstable) and building your own image.

## Disk

The installer assumes `/dev/vda` is the disk to install on. Adjust `boot.loader.grub.device` in `hardware-configuration.nix` and `dev=/dev/vda` in `default.nix` if this is not the case.


## Disk Encryption

The installer sets up LUKS disk encryption of the root partition. (`/boot` is unencrypted.) However the password is set to a single null byte and is set to automatically decrypt the disk. This already has the benifit that it is easy to wipe your disk by removing the key, however if you want to protect your data you should set your own key. Instructions to do this are in [`/etc/nixos/hardware-configuration.nix`](hardware-configuration.nix). The command there will let you set your own password however you can also consider [other options supported by NixOS](https://search.nixos.org/options?query=boot.initrd.luks.devices&sort=alpha_asc&channel=unstable) such as a [keyfile](https://search.nixos.org/options?show=boot.initrd.luks.devices.%3Cname%3F%3E.keyFile&query=boot.initrd.luks.devices%20keyFile&sort=alpha_asc&channel=unstable) or [HSM](https://search.nixos.org/options?show=boot.initrd.luks.devices.%3Cname%3F%3E.keyFile&query=boot.initrd.luks.devices%20yubikey&sort=alpha_asc&channel=unstable).

## Configuration

As any NixOS system you can install any configuration on top. The installer leaves two files described below. Of course there is no need to keep this system, you can replace them with whatever you prefer.

I have split the configuration into two files as I like to have high-level generic configuration in one file (`configuration.nix`) that I version control and device specific information in a second file (`hardware-configuration.nix`) that lives with each machine. This way I can share the settings in the first file across machines. However if you prefer you can replace (or just stop using) either or both files.

## /etc/nixos/configuration.nix

[`/etc/nixos/configuration.nix`](configuration.nix) contains basic services to let you set up your new configuration. (You can always use [`nix-env -i`](https://nixos.org/manual/nix/stable/#ch-basic-package-mgmt) to install more packages.) This file should be completely replaced by your desired configuration.

## /etc/nixos/hardware-configuration.nix

[`/etc/nixos/hardware-configuration.nix`](hardware-configuration.nix) contains the filesystem configuration as well as `hardware.enableAllFirmware = true` so that your device likely has all of the drivers you need. You should tweak the encryption settings as specified in the [Disk Encryption](#disk-encryption) section and if you want a leaner system you can replace the `enableAllFirmware` with configuration specific to your device.

## Building

To build the ISO image simply run `nix-build` in the repo root. This will pick up any local modifications you have made and the ISO will be in `result/iso/`.
