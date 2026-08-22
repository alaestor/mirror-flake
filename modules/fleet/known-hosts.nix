/**
  Fleet-wide known-hosts appendix.

  Explicit SSH host-key aliases for fleet-hosted services reachable at a
  public domain/port that differs from the host's own tailnet name (so a
  TOFU prompt would otherwise appear despite the key already being known).
  Shaped like `ssh-client.knownHosts`: domain, then hostname (as it would
  appear in `known_hosts`), then a list of `type base64-data...` keys.
  `ssh-client` consumes this fact directly; hosts don't need to import
  anything beyond the default `ssh-client.knowFleetHosts = true`.
*/
{ self, ... }:
{
  flake.fleet.knownHosts."git.0x04.cc" = {
    # lanser's Forgejo instance; git-over-SSH via the router's external
    # NAT port-forward (see serve.forgejo.sshPort on lanser).
    "[git.0x04.cc]:38502" = [ self.data.vars.sshHostPublicKeys.lanser ];
  };
}
