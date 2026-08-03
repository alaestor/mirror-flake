let
  identities = import ../data/identities;
  administrators = identities.administrative.age-keys;
  sshHost = name:
    builtins.head (
      builtins.filter builtins.isString (
        builtins.split "\n" identities.ssh-host.${name}
      )
    );

  /**
    # Encrypted secrets

    Only age-encrypted payloads and the public recipient rules belong here. Never add plaintext credentials or private keys. Add the corresponding rules to `secrets.nix` before creating or rekeying a payload.

    Secrets must use the complete `identities.administrative.age-keys` set, but are otherwise narrowly scoped to hosts that require them. Primary identities are resident YubiKey keys with encrypted convenience stubs under `administrative/`. Recovery identities are offline breakglass keys and deliberately have no corresponding encrypted stub here. A recovery Age identity is planned but not yet configured.

    Host-key backups exist only as an emergency recovery path, and therefore use only administrative recipients.

    ## Usage

    ### Rekeying

    Agenix cannot independently prove that the installed host private key matches a recipient. Verify the target fingerprint manually (at least once per host lifetime so it's known-good).

    e.g. for the `apc` host:
    ```sh
    sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key_apc
    ssh-keygen -lf data/identities/ssh-host/ssh_host_ed25519_key_apc.pub
    ```

    Edit `secrets.nix`'s secret `publicKeys`, then from the `secrets/` directory run:

    ```sh
    nix run ..#agenix -- -r -i /path/to/admin/agekey
    ```

    Finally, confirm with `git status --short && git diff --stat` before you stage and commit.

    ### Deploying

    Simply rebuild. Confirm manually by inspecting the expected paths:

    ```sh
    ls -l /run/agenix
    readlink ~/.config/some/secret.file
    ```

    ## Secrets catalogue

  */

in
{
  /**
    ### APC runtime secrets

    | File | Runtime consumer |
    |---|---|
    | `vpn_APC-GT-18_key.age` | APC `wg-quick` private key |
    | `administrative/age_primary.age` | User Age YubiKey identity stub |
    | `administrative/ssh_primary.age` | User SSH security-key identity stub |
    | `administrative/pgp-encrypt-*.key.age` | User OpenPGP encryption-card stub |
    | `administrative/pgp-sign-*.key.age` | User OpenPGP signing-card stub |

  */

  "vpn_APC-GT-18_key.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];
  #yubikey
  "administrative/age_primary.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];
  "administrative/ssh_primary.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];
  "administrative/pgp-encrypt-801E05AF720F05CE66A18FF1BCCD526CDAB3D166.key.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];
  "administrative/pgp-sign-8AC1E18B5C36D9A715E3790ADF75EE47A8DE311A.key.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];

  # APC consumes its device client identity at runtime.
  "ssh-client/id_ed25519_apc.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];

  # APC's private Nix store signing identity.
  "nix-store-signing/apc.tailnet.0x04.cc-1.nsk.age".publicKeys =
    administrators ++ [ (sshHost "apc") ];

  /**
    ### Lanser

    | File | Runtime consumer |
    |---|---|
    | `vpn_P2PUSCA560.conf.age` | Lanser torrent VPN namespace |
    | `headplane_cookie-secret.age` | Headplane session cookies |

  */
  "vpn_P2PUSCA560.conf.age".publicKeys =
    administrators ++ [ (sshHost "lanser") ];
  "headplane_cookie-secret.age".publicKeys =
    administrators ++ [ (sshHost "lanser") ];

  /**
    ### Noblesse

    Noblesse has no Agenix runtime, so its client key is retained only as an
    administratively recoverable backup.
  */
  "ssh-client/id_ed25519_noblesse.age".publicKeys = administrators;

  /**
    ### Host private keys

    Host-key backups are recoverable bootstrap material and therefore use only administrative recipients.

    One system host-key backup is kept per `ssh-host` capable configuration.
    Naming and placement conventions are:

    | Material | Repository path | Installed path |
    |---|---|---|
    | System private key backup | `secrets/ssh-host/ssh_host_ed25519_key_<host>.age` | `ssh-host.hostKeyPath` (normally `/etc/ssh/ssh_host_ed25519_key_<host>`) |
    | System public identity | `data/identities/ssh-host/ssh_host_ed25519_key_<host>.pub` | `<ssh-host.hostKeyPath>.pub` |
    | Initrd private key backup | `secrets/ssh-host/ssh_host_ed25519_key_<host>_initrd.age` | `ssh-host.initrd.hostKeyPath` |
    | Initrd public identity | `data/identities/ssh-host/ssh_host_ed25519_key_<host>_initrd.pub` | Used for client host verification; not installed as an SSH host key |

    `<host>` is the lowercase host registry name. System backups are declared
    below because Agenix manages their recipient rules. The deployment helper
    encrypts initrd backups directly to the administrative recipients.
  */
  "ssh-host/ssh_host_ed25519_key_apc.age".publicKeys = administrators;
  "ssh-host/ssh_host_ed25519_key_lanser.age".publicKeys = administrators;
  "ssh-host/ssh_host_ed25519_key_noblesse.age".publicKeys = administrators;
}
