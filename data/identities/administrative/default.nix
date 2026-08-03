let
  inherit (builtins)
    attrValues
    concatMap
    filter
    isString
    match
    readFile
    split
    ;

  recipientLines =
    value: filter (line: isString line && line != "" && match "#.*" line == null) (split "\n" value);
  /**
    # Administrative identities

    These keys are created and managed via the CryptID protocol; refer to it for maintenance details.

    default.nix is an attrset that exposes the following filedata string values:

    - pgp={certificate,fingerprint}
    - age={primary}
    - ssh={primary,recovery}

    as well as the primary consumer interfaces:

    - `age-keys`: all configured primary and recovery Age recipients
    - `ssh-keys`: all configured primary and recovery SSH public keys

    Consumers should normally use these complete lists. Select an individual
    identity only when an operation is explicitly specific to its primary or
    recovery role.
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
    fingerprint = "4E4AAED523F37DB64B329CCFA9B285CEFFACEEC5"; # update manually when cert changes
  };
in
{
  inherit age ssh pgp;
  age-keys = concatMap recipientLines (attrValues age);
  ssh-keys = concatMap recipientLines (attrValues ssh);
}
