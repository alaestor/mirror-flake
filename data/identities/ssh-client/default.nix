let
  inherit (builtins) readFile;
  /**
    Public SSH client identities keyed by the lowercase hostname on which their
    private counterparts live. These keys are not authorized implicitly; a
    consumer must add the required values to `ssh-host.authorizedKeys`.
  */
  hosts = {
    apc = readFile ./id_ed25519_apc.pub;
    noblesse = readFile ./id_ed25519_noblesse.pub;
  };
in
hosts
