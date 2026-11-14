## caddy

Shared Caddy instance built with the Cerberus challenge plugin.

## cinny

Cinny web artifact restricted to a configured Matrix homeserver.

## dufs

Authenticated, read-only media downloads with search and folder ZIPs.
A private filesystem root exposes only named shares and the Nix store.
Accounts come from a required runtime environment file, normally agenix;
missing, anonymous, plaintext, or writable account rules fail startup.

## filebrowser

Read-only Filebrowser media service without public ingress policy.
Only its database directory and cache are writable; media remains read-only
even when the underlying storage permits writes.

## forgejo

Local Forgejo software-forge configuration.

Forgejo expects to be reached via shared Caddy reverse proxy (`serve.caddy`),
which terminates TLS itself. Git-over-SSH is served through
the host's existing OpenSSH daemon (the upstream module's default).
State defaults to local storage. Hosts own NAS placement, NAS shutdown
ordering, and any storage-specific SSH authorized_keys workaround.

## headscale

Headscale coordination server with the Headplane administrative interface.

The services listen only on loopback by default. Hosts choose whether to
enable the service and publish it through their reverse proxy.

## jellyfin

Local Jellyfin media service and NAS alias-library builder without public
ingress policy. Uses a dedicated service account, read-only media, and
writable application directories. Accelerator devices must be declared
explicitly. Hosts own NAS grants and existing-state account migrations.

## matrix

Local Tuwunel Matrix service without public ingress policy.

## nix-cache

Private HTTP Nix binary cache backed by the host's Nix store via nix-serve-ng.

Exports `flake.modules.nixos.serve-nix-cache`. Importing it has no effect;
`serve.nix-cache.enable` must be set explicitly. The listener is exposed only
through the configured private firewall interface.

## torrenting

qBittorrent confined to a WireGuard VPN namespace.
Writes are limited to its profile, downloads, and private temporary storage.

This is a private host service, not a public domain composition.
