## channel

The release channels this repository tracks.

Input families that ship both a stable and an unstable edition pin the stable
edition to `stable`, so the release is stated once rather than repeated at
every input declaration, and consumers can read the pin from the flake
without evaluating a host.

## fleet

Typed, public, non-secret state shared by multiple repository consumers.

Fleet records are declarative flake outputs. They describe shared facts, not
evaluated hosts, credentials, storage paths, or machine topology.

## known-hosts

Fleet-wide known-hosts appendix.

Explicit SSH host-key aliases for fleet-hosted services reachable at a
public domain/port that differs from the host's own tailnet name (so a
TOFU prompt would otherwise appear despite the key already being known).
Shaped like `ssh-client.knownHosts`: domain, then hostname (as it would
appear in `known_hosts`), then a list of `type base64-data...` keys.
`ssh-client` consumes this fact directly; hosts don't need to import
anything beyond the default `ssh-client.knowFleetHosts = true`.

## lan

Public facts for the fleet's general LAN.

Before this, the same three addresses were written out independently in
seven places, in three different subnets, with no single source of truth
(`apc`'s gateway, `lanser`'s gateway, and the NAS's general-LAN address all
duplicated `172.16.0.0/24`/`.1`/`.2`). This is that source of truth for the
facts that are genuinely shared. It deliberately does not include
`lanser`'s direct-attach link to the NAS (`192.168.2.0/23`,
`192.168.2.200`): that is a dedicated point-to-point subnet between two
specific machines, not a fact about the LAN, and stays local to `lanser`'s
own fragment.

## tailnet

Public facts for the 0x04.cc tailnet.

Fleet declarations define shared facts only. Hosts retain ownership of
service credentials, storage paths, and machine-specific topology.
