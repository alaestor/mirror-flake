## isolive-minimal

Creates a minimal NixOS installer ISO file no grub countdown, optimized for image size.

## isolive

Creates a minimal NixOS installer ISO file no grub countdown or `wpa_supplicant`.

Use `networking.wireless.enable = lib.mkForce true;` if you want to re-enable `wpa_supplicant`

## ssh-host

Automates some opinionated configuration for providing remote ssh access. If more granular control is desired, you should avoid using this.

When configuring hosts for pre-boot ssh (`initrd.enable`):
- an ED25516 ssh key must be present at `initrd.HostKeyPath` to be passed along by `initrd.secrets`. Don't use your system host key (`HostKeyPath`).
- the system will probably need to configure `systemd.network`
- may need to set `boot.initrd.availableKernelModules` for network hardware availability (use `lspci -v | grep -iA8 'network\|ethernet'` for that).

> [!CAUTION]
> The initrd ssh host key is stored unencrypted in `/boot/secrets/`. If an attacker was to gain access to it (particularly through physical access) they could impersonate the server and intercept your LUKS passphrase.

## standard-disk

A disko configuration set up with interactive LUKS and BTRFS for easy reuse.
Persistent swap optional and preconfigured with `/root` `/nix` and `/persist`
subvolumes for compatibility with impermanence et al.
