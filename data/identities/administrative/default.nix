let
  inherit (builtins) readFile attrValues;
  /**
    # Administrative identities

    These keys are created and managed via the CryptID protocol; refer to it for maintenance details.

    default.nix is an attrset that exposes the following filedata string values:

    - pgp={certificate,fingerprint}
    - age={primary}
    - ssh={primary,recovery}

    as well as the convenience lists:

    - age-keys
    - ssh-keys
  */
  age = {
    primary = readFile ./age_primary;
    #recovery = builtins.readFile ./age_recovery; # TODO(secrets): add a recovery age key
  };
  ssh = {
    primary = readFile ./ssh_primary;
    recovery = readFile ./ssh_recovery;
  };
  pgp = {
    certificate = readFile ./pgp.pub;
    fingerprint = "4E4AAED523F37DB64B329CCFA9B285CEFFACEEC5"; # update manually
  };
in {
  inherit age ssh pgp;
  age-keys = attrValues age;
  ssh-keys = attrValues ssh;
}
