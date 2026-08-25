## secrets

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

### APC runtime secrets

| File | Runtime consumer |
|---|---|
| `vpn_APC-GT-18_key.age` | APC `wg-quick` private key |
| `administrative/age_primary.age` | User Age YubiKey identity stub |
| `administrative/ssh_primary.age` | User SSH security-key identity stub |
| `administrative/pgp-encrypt-*.key.age` | User OpenPGP encryption-card stub |
| `administrative/pgp-sign-*.key.age` | User OpenPGP signing-card stub |

### Lanser

| File | Runtime consumer |
|---|---|
| `vpn_P2PUSCA560.conf.age` | Lanser torrent VPN namespace |
| `headplane_cookie-secret.age` | Headplane session cookies |

### Noblesse

Noblesse has no Agenix runtime, so its client key is retained only as an
administratively recoverable backup.

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

### Agent VM guest host keys

`secrets/ssh-host-vm/` looks like `ssh-host/` but is not a host-key
backup: the agent microVM guest is not an Agenix host and holds no
identity of its own, so encrypting a guest's key to *itself* is
meaningless. This is a runtime secret that happens to be an SSH host
key — decrypted unattended by the host that runs the guest, the same
shape as `ssh-client/id_ed25519_apc.age` above — and it deliberately
deviates from the host-key-backup admin-only rule for that reason.

`<guest>` is the lowercase guest name from `data/identities/ssh-host-vm`.
Nothing should ever encrypt *to* a guest identity; only administrators
and the host(s) that run the guest are recipients here.
