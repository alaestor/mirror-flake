let
  inherit (builtins) readFile;
  /**
    # Agent VM guest host identities

    Distinct from `../ssh-host`: these are not backups of a real host's
    identity, they are the committed public half of the agent microVM
    guest's sshd host key (`__reference/review/vm-host-key-age.md`). The
    guest holds no identity of its own and nothing should ever encrypt *to*
    one of these keys — the private half is a runtime secret decrypted by
    the host that runs the guest, not a recovery artifact.

    Each attribute is a lowercase guest name and each value is that guest's
    public sshd host key, used to pin `agent-vm-session`'s scratch
    `known_hosts` so no session ever prompts for or writes a TOFU entry.
  */
  guests = {
    agentvm = readFile ./ssh_host_ed25519_key_agentvm.pub;
  };
in
guests
