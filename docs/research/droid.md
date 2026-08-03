# Nix-on-Droid research notes

These notes describe the environment used by the `noblesse` configuration and
the constraints relevant to long-running network services. They are based on
the flake's pinned nix-on-droid 24.05 source and the linked upstream research.

## Execution model

Nix-on-Droid runs a Nix userland inside the Android application sandbox. Its
login environment uses `proot`; it is not NixOS and it does not boot an init
system. In particular:

- NixOS modules and options such as `systemd.services`, `users.users`,
  `services.openssh`, and the NixOS firewall do not exist.
- The one Android application user is represented inside the environment as
  `nix-on-droid`, with its home at
  `/data/data/com.termux.nix/files/home`.
- nix-on-droid modules can install packages, generate `/etc` entries, and add
  ordered activation snippets under `build.activation`.
- Activation is suitable for generating persistent state such as an SSH host
  key. It is not a service manager and does not provide restart or liveness
  guarantees.
- Android may stop background application processes. Starting a daemon from a
  login shell therefore cannot provide the same lifecycle guarantee as a
  systemd service.

The upstream project has long tracked the missing service-manager abstraction
in [issue 54](https://github.com/nix-community/nix-on-droid/issues/54). A
supervisord and OpenSSH module was proposed in
[pull request 203](https://github.com/nix-community/nix-on-droid/pull/203), but
has not been merged. We should not build feature modules against those proposed
options.

## SSH host design

The flake exports `nixOnDroidModules.ssh-host` alongside the NixOS
`modules.nixos.ssh-host`. Both expose the common `ssh-host` options. The droid
defaults differ where the platform requires it:

- `port` defaults to `8022`, an unprivileged port, instead of NixOS port 22.
- `hostKeyPath` defaults to
  `~/.local/state/ssh-host/ssh_host_ed25519_key_noblesse`. The app-private home is the
  persistent state boundary; nix-on-droid's generated `/etc` is not an
  appropriate home for a mutable private key.
- `allowUsers`, when set, can only name the single `nix-on-droid` user.
- initrd SSH remains NixOS-only.

On activation, the module generates a persistent Ed25519 host key if one does
not exist. It installs OpenSSH, a generated hardened configuration, and two
commands:

```console
ssh-host-start
ssh-host-stop
```

`ssh-host-start` lets `sshd` daemonize and records its PID and log beneath
`~/.local/state/ssh-host`. The operator must start it after the application or
device is restarted. This manual boundary is deliberate until nix-on-droid has
a supported service lifecycle.

Administrative public keys are authorized separately through
`ssh-host.allow-administrative-access`. Per-device client keys, such as
`id_ed25519_noblesse`, are only authorized when explicitly added to
`ssh-host.authorizedKeys`; SSH host identities are never login keys.

SFTP is retained as a common option, but should be considered experimental on
droid. Upstream users found that both the external server and `internal-sftp`
encounter proot behavior; see
[nix-on-droid issue 307](https://github.com/nix-community/nix-on-droid/issues/307)
and the underlying [proot issue 243](https://github.com/proot-me/proot/issues/243).

The upstream history also contains a useful activation-and-command prototype in
[nix-on-droid issue 156](https://github.com/nix-community/nix-on-droid/issues/156).
The local module follows the same proven shape while sharing policy options with
the NixOS implementation.

## Tailscale feasibility

### Recommended approach: Android application

Use the official Tailscale Android application for the tunnel, then connect to
the droid SSH daemon through the phone's tailnet address on port 8022. Android
provides VPN tunnels to applications through its privileged
[`VpnService` API](https://developer.android.com/develop/connectivity/vpn), and
the official app owns that Android lifecycle and permission flow. Tailscale's
[Android installation guide](https://tailscale.com/kb/1017/install) describes
the supported client.

This split leaves authentication imperative in the Android application but
keeps the SSH server, keys, and access policy declarative in this flake. It is
the lowest-maintenance design and does not require a rooted phone.

Nix-on-droid currently writes a static `/etc/resolv.conf` using public
resolvers. Consequently, MagicDNS names may not resolve inside its proot even
when the Android Tailscale application is connected. This exact interaction is
recorded in
[nix-on-droid issue 322](https://github.com/nix-community/nix-on-droid/issues/322).
Direct tailnet IP access is unaffected; using MagicDNS would require a separate,
conditional resolver change.

### A native droid module

A module can trivially install the `tailscale` package and generate wrapper
commands, but it cannot supply the missing Android VPN permission, TUN device,
or daemon supervision. Without root and a usable `/dev/net/tun`, `tailscaled`
cannot create the normal transparent network interface.

Tailscale supports
[userspace networking mode](https://tailscale.com/kb/1112/userspace-networking),
which exposes SOCKS5 and HTTP proxy endpoints instead of a TUN interface. A
droid module based on that mode could be useful for explicitly proxied outbound
programs, but it would not make the phone transparently reachable at its
tailnet IP and therefore does not solve the primary inbound SSH use case.

Running a conventional `tailscaled` from nix-on-droid may be possible on a
rooted device with manually arranged kernel access and capabilities, but that
would be device-specific, imperative infrastructure outside nix-on-droid's
normal guarantees. We should only add such a module if a concrete proxy-mode or
rooted-device use case appears. For noblesse, use the Android application.
