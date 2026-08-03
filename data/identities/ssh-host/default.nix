let
  inherit (builtins) readFile;
  /**
    # Host identities

    These keys are created automatically during deployment or manually by the system administrator.

    Each attribute is a lowercase hostname and each value is that server's
    public system host key. Initrd identities, when present, remain distinct
    public files and interfaces.
  */
  hosts = {
    apc = readFile ./ssh_host_ed25519_key_apc.pub;
    lanser = readFile ./ssh_host_ed25519_key_lanser.pub;
    noblesse = readFile ./ssh_host_ed25519_key_noblesse.pub;
  };
in
hosts
