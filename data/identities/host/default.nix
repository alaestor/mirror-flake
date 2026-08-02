let
  inherit (builtins) readFile attrValues;
  /**
    # Host identities

    These keys are created automatically during deployment or manually by the system administrator.

    default.nix is an attrset that exposes the following string values:

    - noblesse
  */
  hosts = {
    noblesse = readFile ./id_ed25519_noblesse.pub;
    lanser = readFile ./id_ed25519_lanser.pub;
    apc = readFile ./id_ed25519_apc.pub;
  };
in
hosts
