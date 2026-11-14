## ai-coding-local

Host-level (non-microVM) agent coding setup pointed at a local LM Studio
server, with a curated favorites list of local models.

## ai-coding

Bundles the Claude Code, Codex, and DeepSeek Harness agent modules for a
user environment.

## coding

Home Manager aspect for a coding environment.

This composes developer-oriented capabilities without introducing a new
configuration interface of its own.

## crypto

Composes cryptographic capabilities, currently YubiKey tooling and stubs.

## tailnet-client

Fleet-aware Tailscale client composition.

Configures the shared tailnet's coordination URL and DNS suffix for NixOS
clients, and enables telemetry collection by default on NixOS. Both
compositions add known-host entries for every registered SSH host identity
at its tailnet DNS name, through the shared
`homeManager.tailnet-known-hosts` module. SSH client identity deployment
remains an explicit host concern. The Nix-on-Droid composition otherwise
configures terminal integration only: Android's Tailscale application owns
the VPN lifecycle.

## workstation

Home Manager aspect for a general-purpose workstation.

This composes terminal, remote-access, and desktop application
capabilities without introducing a new configuration interface of its own.
