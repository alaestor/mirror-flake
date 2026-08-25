## apc

apc: primary desktop workstation. Declares its host record: modules,
capabilities, and the standalone Home Manager environment.

## armatus

armatus: laptop. Declares its host record: modules, capabilities, and
the standalone Home Manager environment.

## bootstrap

bootstrap: minimal NixOS installation ISO with remote SSH access, used
to install other hosts.

## cryptid

cryptid: air-gapped secrets/identity management ISO. Declares its host
record and pins a known-good nixpkgs revision around a btrfs mount bug.

Bootable installer ISO (~1.5GB) intended for offline management of cryptographic identities; not intended for system installation. Provides various commandline tools for working with pgp, yubikeys, and veracrypt containers.

Comes with a helper script to destructively provision a bootable USB flashdrive formatted with an additional btrfs partition for manually managed persistance. The rationale for this is a backup strategy which bundles data with the tools needed to use it. Encrypted containers can be made on the persistant partition and the entire drive can be cloned for redundancy.

> [!CAUTION]
> ```
> nix run .#mkbootable-cryptid -- /dev/sdX
> ```

Tip: use can use the following command to quickly enumerate removable blockdevices alongside their sizes.
```
nix run nixpkgs#nushell -- -c "lsblk --json | from json | get blockdevices | where rm == true | select name size"
```

## lanser

lanser: home server and public service host. Declares its host record:
modules, capabilities, and the integrated Home Manager environment.

## noblesse

noblesse: Android phone running nix-on-droid. Declares its host record.
