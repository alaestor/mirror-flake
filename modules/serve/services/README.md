## caddy

Shared Caddy instance built with the Cerberus challenge plugin.

## cinny

Cinny web artifact restricted to a configured Matrix homeserver.

## filebrowser

Local Filebrowser media service without public ingress policy.

## forgejo

Local Forgejo software-forge configuration.

Forgejo expects to be reached via shared Caddy reverse proxy (`serve.caddy`),
which terminates TLS itself. Git-over-SSH is served through
the host's existing OpenSSH daemon (the upstream module's default).

## headscale

Headscale coordination server with the Headplane administrative interface.

The services listen only on loopback by default. Hosts choose whether to
enable the service and publish it through their reverse proxy.

## jellyfin

Local Jellyfin media service and NAS alias-library builder without public
ingress policy.

## matrix

Local Tuwunel Matrix service without public ingress policy.

## nix-cache

Private HTTP Nix binary cache backed by the host's Nix store.

Exports `flake.modules.nixos.serve-nix-cache`. Importing it has no effect;
`serve.nix-cache.enable` must be set explicitly. The listener is exposed only
through the configured private firewall interface.

## torrenting

qBittorrent confined to a WireGuard VPN namespace.

This is a private host service, not a public domain composition.
