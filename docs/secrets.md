# Secrets management strategy

This document records the planned secrets-management architecture. It describes
the intended end state; unless noted otherwise, the integration is not yet
implemented.

## Goals

- Use plain [agenix](https://github.com/ryantm/agenix) for declarative runtime
  secrets.
- Keep recipient policy explicit and auditable. The fleet is small enough that
  automatically inferred recipients are not necessary.
- Allow each host to decrypt its own runtime secrets without an administrator's
  YubiKey.
- Ensure that administrative YubiKeys can always recover and rotate secrets.
- Preserve host identities across reinstalls and rotate them only deliberately.
- Keep first installation a single deployment operation.
- Hide the physical location of encrypted files behind a stable flake
  interface, so repository layout can change later.

This design does not currently require `agenix-rekey`. Its master-secret and
automatic rekeying model may be reconsidered if the fleet or recipient graph
becomes difficult to maintain.

## Identities and their roles

The design separates four kinds of identity:

1. **Administrative Age recipients** are backed by the primary and recovery
   YubiKeys. They allow secrets to be edited, recovered, and re-encrypted.
2. **System SSH host keys** identify installed hosts and decrypt their Agenix
   runtime secrets. They are persistent host state, not deployment credentials.
3. **Initrd SSH host keys** identify the pre-boot SSH service used for remote
   LUKS unlocking. They remain distinct from the system SSH host keys.
4. **Deployment SSH keys** are ephemeral credentials created for one
   `nixos-anywhere` invocation. They are not secret recipients and are deleted
   when deployment finishes.

System and initrd host keys are stable across reinstalls. Rotation is a manual,
intentional operation that updates encrypted secrets and client host-key
records as one coordinated change.

## Recipient policy

Every ordinary secret must be encrypted to:

- all hosts that consume it;
- the primary administrative YubiKey recipient; and
- at least one recovery administrative recipient.

For example, a secret used only by `armatus` has the conceptual recipient set:

```text
administrators + hosts.armatus
```

A secret shared by several hosts includes each of those hosts:

```text
administrators + hosts.armatus + hosts.example
```

Host private-key backups are a bootstrap exception. Encrypting a private host
key to its own public key does not provide recovery when that private key is
lost. Such backups are therefore encrypted to the administrative and recovery
recipients. Once provisioned, the system host key is used to decrypt ordinary
host secrets.

Removing a recipient from future ciphertext does not revoke access to
historical ciphertext that recipient already possessed. After a host or
recipient compromise, rotate both the affected identity and the underlying
secrets.

## Stable host-key provisioning

The deployment process will pre-provision both the system and initrd SSH host
keys. This avoids Agenix's first-boot identity problem: the target's public key
is known before the system closure is built, and its private key is present
when activation decrypts runtime secrets.

On first installation of a host:

1. Create a private temporary directory on the deployer.
2. Generate the system and initrd Ed25519 host-key pairs there.
3. Immediately encrypt backup copies of the private keys to all administrative
   recipients.
4. Retain the encrypted private-key backups and public keys in the secrets
   tree.
5. Stage the private system key at `ssh-host.hostKeyPath` and the private initrd
   key at `ssh-host.initrd.hostKeyPath`.
6. Run `nixos-anywhere` with the staged files in its extra-files tree.
7. Remove all plaintext staging and key-generation directories through a trap,
   on both success and failure.

On later installations, decrypt the stable host keys from their administrative
backups into the temporary staging tree and provision those same identities.
The YubiKey is consequently required for bare-metal installation or recovery,
but not for routine target-side Agenix decryption.

Generating keys on the target and returning only public keys and
administrator-encrypted backups would reduce exposure on the deployer. It would
also require splitting and orchestrating the `nixos-anywhere` phases so the
private keys survive disk formatting and are copied directly into the mounted
target. This is a possible future hardening measure, not the initial design.

Plaintext host keys are temporarily present on the deployer during provisioning.
The deployment script must use restrictive permissions, avoid logging paths or
contents unnecessarily, and reliably clean up temporary files. Swap and crash
dumps remain part of the deployer's threat model.

## Initrd key considerations

The initrd SSH key is a bootstrap secret rather than an ordinary runtime
secret. It is needed before the encrypted root is unlocked, so its provisioning
remains part of the deployment workflow even after Agenix is introduced.

NixOS ultimately places the initrd key in bootloader-accessible initrd material.
Encryption in the repository and during provisioning does not protect it from
an attacker with sufficient access to the unencrypted boot partition. Such an
attacker may be able to impersonate the pre-boot SSH server and capture a LUKS
passphrase. Secure Boot or another authenticated-boot design would be needed to
address that threat.

The system SSH host key must never be reused as the initrd SSH host key.

## Flake abstraction

A flake-parts module will expose a narrow `self.secrets` interface analogous to
`self.data`. Its intended responsibilities are:

- resolve encrypted-file paths;
- expose public administrative and host recipients; and
- hide whether the encrypted tree comes from the main repository, a nested
  repository, or a non-flake input.

Conceptually, consumers should use an interface such as:

```nix
self.secrets.path "hosts/armatus/example.age"
self.secrets.recipients.administrators
self.secrets.recipients.hosts.armatus
```

Unlike `self.data`, this interface must not expose `read`, `readJSON`, or other
helpers that encourage evaluating plaintext. Only encrypted paths and public
metadata belong in the flake interface.

Because every `.nix` file beneath `modules/` is discovered by `import-tree`, the
interface implementation there must be a flake-parts module. Value-only Agenix
rules or recipient tables belong outside `modules/`, under `data/` or in the
secrets repository.

## Repository layout

The encrypted secrets tree may initially be either:

- a manually cloned, gitignored `secrets/` directory; or
- a Git submodule at `secrets/`.

This choice is intentionally not settled yet. The `self.secrets` boundary should
allow a later migration to a pinned non-flake input without changing every
consumer.

There is an important evaluation boundary: a manually cloned, gitignored
directory is directly available to deployment shell code, but is not
automatically included in a Git-backed flake source. Agenix declarations can
refer to encrypted files only when those files are visible through the flake
source, a correctly included submodule, or an explicit input. The abstraction
does not bypass this Nix purity constraint.

Encrypted files may enter the world-readable Nix store as part of an Agenix
deployment; plaintext must never do so. A private sister repository can provide
an organizational and access-control boundary, but does not replace encryption.

## Planned implementation sequence

1. Add Agenix as a flake input and export reusable NixOS integration.
2. Add the `self.secrets` path and public-recipient boundary.
3. Define explicit Agenix recipient rules outside the auto-imported module tree.
4. Extend the deployment helper to provision the stable system host key in
   addition to the existing stable initrd key.
5. Migrate ordinary runtime secrets to Agenix incrementally.
6. Document and test the manual host-key and secret-rotation procedure before
   relying on it.

Until those steps are complete, the existing initrd-key deployment behavior
remains authoritative.

## Alternatives not selected

The following approaches were considered and are not part of the planned
design.

### Agenix-rekey

`agenix-rekey` would keep a master-encrypted source secret and derive
host-encrypted copies while inferring recipients from the evaluated
configurations. This is useful for a large or frequently changing recipient
graph, but the current fleet is small and its host keys are long-lived.

Explicit Agenix rules are preferred because they:

- make access policy directly reviewable;
- avoid rekey cache, derivation, and remote-copy concerns; and
- add less machinery to the deployment path.

This decision can be revisited if manually maintaining recipient sets becomes
error-prone.

### Two-phase host bootstrap

Installing a host without runtime secrets, allowing OpenSSH to generate its
identity, and then adding the resulting public key in a second deployment would
avoid pre-generating the system host key.

This was rejected because it makes a fresh installation depend on a second
configuration update and deployment. Pre-provisioning a stable system host key
keeps installation single-step and makes the target recipient known before the
initial system is built.

### Regenerating host keys on every installation

Treating host keys as disposable would reduce the amount of persistent identity
state to back up. It would also change the SSH identity after every reinstall,
require all affected secrets to be re-encrypted, and require client host-key
records to be updated.

Stable host keys with deliberate manual rotation provide a clearer identity and
recovery model.

### Target-side host-key generation

Generating host keys in the installer environment, returning only public keys
and encrypted backups, and copying the private keys directly into the mounted
target would keep plaintext private keys off the deployer's filesystem.

This was not selected for the initial implementation because
`nixos-anywhere`'s normal extra-files flow starts with local files. Keeping the
private keys target-side would require custom orchestration between the kexec,
disk, and installation phases. Local generation in a restrictive temporary
directory is simpler and acceptable for the current threat model. Target-side
generation remains a possible hardening step.

### A dedicated Age identity for each host

A separate per-host Age identity would decouple secret decryption from SSH
host-key rotation. It would also introduce another persistent private identity
that must be provisioned, backed up, and rotated.

The stable system SSH host key already provides the identity Agenix needs, so a
second host identity is unnecessary for the current fleet.

### Host-only recipients

Encrypting runtime secrets only to their consuming hosts would minimize the
recipient set, but loss or corruption of a host identity could make those
secrets unrecoverable.

Administrative and recovery YubiKey recipients are therefore mandatory for
ordinary secrets. They provide an independent recovery and rotation path.

### Treating the initrd key as an ordinary runtime secret

Agenix normally decrypts secrets during activation using an identity available
to the installed system. The initrd SSH key must be provisioned for use before
the encrypted root is unlocked and must be available on the first boot.

It therefore remains deployment bootstrap material rather than relying solely
on the ordinary runtime-secret path.

### Placing value-only secret rules under `modules/`

A conventional `secrets.nix` recipient table under `modules/` would be
discovered by `import-tree` and evaluated as a flake-parts module. Value-only
rules and recipient data must instead live under `data/` or in the secrets
repository, with a proper flake-parts module exposing the `self.secrets`
boundary.

### Repository topology

Keeping encrypted files in the main repository, a submodule, a manually cloned
directory, or a future non-flake input has not been decided. None of these
options is rejected by this decision record; the abstraction boundary is
intended to defer that choice.
