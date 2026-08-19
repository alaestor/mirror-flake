/**
  # flake.lib.agents.vmChannels

  The constants both halves of a Phase 5 channel have to agree on, in one
  place so the guest (`vm.nix`) and the host (`vm-host.nix`) can never drift
  apart. Nothing here evaluates to a module; it is a plain lookup table plus
  the CID derivation.

  A channel is a unix socket in the guest proxied over `AF_VSOCK` to a
  listener on the host, which hands the connection to the real socket. The
  guest always dials the well-known host CID (2) on the channel's port; the
  host listener binds `VMADDR_CID_ANY`, so it serves every guest and nothing
  has to be re-derived when a second VM appears.

  **Ports are host-wide, CIDs are per-VM.** Two guests asking for the same
  channel dial the same port and reach the same listener — which is correct,
  since the thing behind it (this machine's nix daemon, this user's
  gpg-agent) is singular anyway. What must stay unique is `microvm.vsock.cid`,
  hence `cidFor`: derived from the VM's name the way `macFor` derives a MAC in
  `vm.nix`, so it is stable across evaluations and does not need a registry
  to hand out numbers. Collisions are a birthday problem over 65533 values,
  not a correctness guarantee; if two VMs ever collide, the second one fails
  to start with QEMU complaining about the CID, which is loud enough to fix
  by renaming.

  The port numbers themselves are arbitrary but must not move once a guest
  image is in the wild: a guest built before a renumbering would dial a port
  nothing listens on and hang rather than fail.

  **This is not an authenticated channel.** Any VM on this host with vsock
  access can dial these ports; the host side does not know which guest it is
  talking to. That is why the nix daemon listener runs as an *untrusted* nix
  user (see `vm-host.nix`) and why the gpg channel forwards the restricted
  `S.gpg-agent.extra` socket, which signs but refuses to export a key.
*/
{ lib, ... }:
let
  # VMADDR_CID_HOST. 0 is the hypervisor and 1 is loopback; guests start at 3.
  hostCid = 2;

  ports = {
    nixDaemon = 1050;
    gpgAgent = 1051;
  };

  hexValues = builtins.listToAttrs (
    lib.imap0 (i: c: {
      name = c;
      value = i;
    }) (lib.stringToCharacters "0123456789abcdef")
  );

  cidFor =
    name:
    let
      hash = builtins.hashString "sha256" name;
      digit = offset: hexValues.${builtins.substring offset 1 hash};
      # 16 bits of the digest is plenty of spread for a handful of VMs and
      # keeps the arithmetic readable; CIDs are u32 but nothing benefits from
      # using the whole range.
      n = ((digit 0 * 16 + digit 1) * 16 + digit 2) * 16 + digit 3;
    in
    3 + lib.mod n 65533;
in
{
  flake.lib.agents.vmChannels = {
    inherit hostCid ports cidFor;
  };
}
