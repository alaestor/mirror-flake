## airgap

Disables every network-facing service and driver class this repository
knows how to name, for a host that must never come up on a network.

This is best-effort, not a hard isolation guarantee: the
`blacklistedKernelModules` list names specific drivers (`iwlwifi`, an Intel
Wi-Fi chipset; `igc`, an Intel 2.5G Ethernet chipset; several Bluetooth
drivers), not device classes, so it is only as complete as this list is for
whatever hardware the host actually has. The `networking.*` overrides
(`interfaces = mkForce {}`, no DHCP client, no NetworkManager, no
networkd) are the real, hardware-independent guarantee — they mean an
unlisted interface comes up without an address rather than not at all.
Currently imported by exactly one host, `cryptid`
(`hosts/cryptid/scripts.nix`), whose ISO must handle arbitrary hardware; if
this module gains a second consumer with different hardware, audit the
blacklist against that hardware before trusting it.

## hifi-audio

Enables the standard PipeWire audio stack with ALSA, 32-bit ALSA, PulseAudio
compatibility, and realtime scheduling support.

## isolive-minimal

Creates a minimal NixOS installer ISO file no grub countdown, optimized for image size.

## isolive

Creates a minimal NixOS installer ISO file no grub countdown or `wpa_supplicant`.

Use `networking.wireless.enable = lib.mkForce true;` if you want to re-enable `wpa_supplicant`

## local-cache

# local-cache

Exports enabled-on-import NixOS and Nix-on-Droid modules for a trusted HTTP
binary cache. Defaults target APC's tailnet cache and first signing-key
rotation. If the public key has not been committed yet, the module warns and
leaves Nix's substituters unchanged.

## memory-manager

# memory-manager

Compressed swap plus userspace early-OOM killer.

The kernel's own OOM killer only acts once reclaim has already failed, by
which point the machine has usually spent minutes thrashing and is
unresponsive. `earlyoom` watches free memory from userspace and kills the
biggest consumer while the system is still interactive. Disables systemd.oom
by default to avoid unpredictable races.

zram gives that killer somewhere to fall back to: compressed swap in RAM
absorbs an allocation spike (a large `nix eval`, say) instead of turning it
straight into a kill. Both halves are independently switchable, because a
guest that wants swap headroom does not necessarily want desktop
notifications, and vice versa.

## nas

Provides optional NFS mounts for the Cauldron, Vault, Pocket, and Services
NAS shares. Each share can be enabled independently and mounted read-only.

## nix-store-signing

# nix-store-signing

Exports the disabled-by-default NixOS `nix-store-signing` feature and the
`provision-nix-store-signing-key` repository app.

The provisioning app generates a caller-named Nix binary-cache key, encrypts
its secret half to every administrative Age recipient plus any recipients
supplied by the caller, and writes only `<name>.nsk.age` and `<name>.nsk.pub`
in the current directory.

The NixOS feature deploys a configured encrypted signing key through Agenix
and installs `sign-nix-store`, which recursively signs the supplied
installables. Importing the module does not enable deployment.

## printers

Enables CUPS, a PDF printer, and the configured Brother HL-L2320D printer.

## server-hardening

Baseline kernel and service hardening for network-facing server hosts.

## ssh-client

Exports `flake.modules.nixos.ssh-client`, the dormant Home Manager option
interface `ssh-known-hosts`, and `flake.modules.homeManager.ssh-client`.
The NixOS feature deploys the
host-named client identity through Agenix when its ciphertext exists and
otherwise warns without blocking bootstrap. The Home Manager feature enables
the opinionated SSH program module and selects
`~/.ssh/id_ed25519_<lowercase-hostname>` for registered host user
environments. Consumers may prepend higher-priority identities through
`ssh-client.identityFiles`; an empty list disables identity selection.
`ssh-client.knownHosts` declares SSH host keys grouped by DNS domain, and
accepts additive entries from compositions such as `tailnet-client`.
Repository-managed common, tailnet, and fleet-wide host keys are enabled
independently through `knowCommonHosts`, `knowTailnetHosts`, and
`knowFleetHosts`.

## ssh-host

# ssh-host

Exports `flake.modules.nixos.ssh-host` and
`flake.modules.nixOnDroid.ssh-host`. Both module classes expose the common
`ssh-host` interface; only NixOS additionally exposes `ssh-host.initrd`.

Importing either module enables an SSH server. `allowUsers` selects the
accounts to which login keys are attached. `allow-administrative-access`
authorizes the complete administrative primary/recovery key set and defaults
to true. `authorizedKeys` is an empty-by-default, additive list for any other
login identities. Host public keys are never login identities and must not be
added to either set.

Each platform generates or consumes one persistent Ed25519 host key at
`hostKeyPath`. The default filename is `ssh_host_ed25519_key_<hostname>`,
where the hostname is normalized to lowercase. NixOS owns service and
firewall lifecycle. Nix-on-droid instead installs explicit start/stop
commands because Android provides no compatible service manager.

When NixOS initrd SSH is enabled, its root login receives the same additive
administrative and explicit authorization set. Its host key is always
distinct from the system host key.

Automates some opinionated configuration for providing remote ssh access. If more granular control is desired, you should avoid using this.

When configuring hosts for pre-boot ssh (`initrd.enable`):
- an ED25519 ssh key must be present at `initrd.hostKeyPath` to be passed along by `initrd.secrets`. Don't use your system host key (`hostKeyPath`).
- the system will probably need to configure `systemd.network`
- may need to set `boot.initrd.availableKernelModules` for network hardware availability (use `lspci -v | grep -iA8 'network\|ethernet'` for that).

> [!CAUTION]
> The initrd copy of this SSH host key is stored unencrypted in bootloader-accessible material. If an attacker gains physical access to it, they could impersonate the server and intercept your LUKS passphrase.

Configures an opinionated OpenSSH host for nix-on-droid using the same
`ssh-host` options as NixOS. It installs `ssh-host-start` and
`ssh-host-stop`; Android does not provide systemd or another reliable
nix-on-droid service lifecycle.

## standard-disk

A disko configuration set up with interactive LUKS and BTRFS for easy reuse.
Persistent swap optional and preconfigured with `/root` `/nix` and `/persist`
subvolumes for compatibility with impermanence et al.

## Semi-Impermanence

When `impermanence.enable = true;` and with `old-roots-retention-days`, old root
subvolumes are moved to `/old_roots/<timestamp>/` on each boot and pruned after
the retention period. These are accessible by mounting the BTRFS device.

### Accessing old roots

```bash
sudo mkdir -p /mnt/btrfs
sudo mount /dev/mapper/<luks-name> /mnt/btrfs
ls /mnt/btrfs/old_roots/
sudo umount /mnt/btrfs
```

### Restore files from an old root

Mount the top-level Btrfs filesystem as above and copy the required files from
`/mnt/btrfs/old_roots/<timestamp>/`.

### Manually delete old roots

```bash
sudo mkdir -p /mnt/btrfs
sudo mount /dev/mapper/<luks-name> /mnt/btrfs
sudo btrfs subvolume delete --recursive /mnt/btrfs/old_roots/<timestamp>
sudo umount /mnt/btrfs
```

### Booting old roots (nope)

Replacing the `root` subvolume itself is not a temporary rollback: with
impermanence enabled, it will be archived and replaced again during the
next boot. To boot a restored root, first deploy a configuration with
`impermanence.enable = false`, then replace `root` while booted from
external media.

**Retained roots should be viewed as **recovery archives**, not bootable rollbacks.**

### Future Improvements

These operations, and more, may be made into interactive quality-of-life
applications in the future.

## standard-terminal

Implements the interactive terminal feature and packages every direct
`data/features/standard-terminal/scripts/*.nix` declaration. Each script
file must return a script declaration whose name and package name match its
filename. Declarations can disable themselves from their supplied context.

# TODO(workaround): try nushell config with newer pinnned nixpkgs
`flake.modules.homeManager.standard-terminal-tailnet` is the dormant option
interface declaring `standard-terminal.tailscale.domain`; the Tailscale
feature imports it to supply the suffix. The Nix-on-Droid adapter provides Nushell and these script packages, but
omits other program integrations unavailable from its pinned Home Manager.
Bash and Nushell functions adapt the external ncd helper so it can change
the current shell's directory to the cached local flake root.

## steam-gaming

Steam gaming capability for NixOS hosts.

The feature keeps Steam activation, optional Remote Play ingress, and
optional crash-report suppression behind one typed, disabled-by-default
interface. Hosts retain ownership of unrelated GPU, kernel, and hardware
policy.

## tailscale

Reusable Tailscale client feature with neutral connection defaults.

Automatic enrollment still requires services.tailscale.authKeyFile; without
one, use `tailscale up --login-server <URL>` to authenticate interactively.

Attached user environments receive `standard-terminal.tailscale.domain`
through the dormant `standard-terminal-tailnet` option interface.
