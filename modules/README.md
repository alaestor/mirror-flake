## data

# Repository data boundary

Exposes public, non-secret repository data as `flake.data`. `path`, `read`,
and `readJSON` resolve data relative to the flake root so consumers do not
depend on their own source location. `vars` provides named normalized views
for data shared by multiple modules.

`data/` must never contain credentials or other secret material. Public
identity metadata belongs here and is separated by operational role:

- `identities.administrative` contains public administrator identities.
- `identities.ssh-client` contains public per-host SSH client identities.
- `identities.ssh-host` contains public SSH server identities.
- `data/features/ssh-client/known-hosts.nix` constructs declarative public
SSH known-host entries from domain-specific files.
- `sshAdminKeys` contains only administrative SSH login identities.
- `sshClientPublicKeys` contains only per-host SSH client identities.
- `sshHostPublicKeys` contains only SSH host identities.

Host identities must never be folded into `sshAdminKeys`. Encrypted
private material belongs behind `flake.secrets`, not this interface.

Common representations of frequently used data files

## secrets

# Repository secret boundary

Exposes the location and public recipient metadata of encrypted secrets as
`flake.secrets`. This interface never carries plaintext secret material; it
resolves `secrets/` paths relative to the flake root and reports whether a
given encrypted file is present in the current source tree.

Every record is a `secret` submodule: `subpath`, `file`, and `exists`.
Constructors may add identifying detail to a record (a key name, a host, a
keygrip); the freeform space of the record type carries that detail without
each constructor needing its own type.

Encrypted private material belongs behind this interface. Public identity
metadata belongs in `flake.data`.
