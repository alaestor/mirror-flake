# Cryptographic Identity Protocol

`cryptid` is inspired by [Gosin's YubiKey master
protocol](https://gist.github.com/Gosin/f1a2ea42bec672c842f60b0fa57ab1d1).

CRYPTID builds upon it by adding [age](https://github.com/FiloSottile/age), providing automated workflows and a reproducible environment, and encouraging physical redundancy by use of a cloneable, bootable dual-partition USB.

## Target Audience

This is a personal workflow and reference for a technically experienced
individual managing long-lived OpenPGP, SSH, and Age identities. It is not a
team or enterprise key-management system.

### Overview

The protocol uses bootable `cryptid` USB drives so recovery media contains both
the data and the tools needed to use it.

- **Dual Partitions:** 
  - **NixOS ISO bootable system**: an image preconfigured with all the relevant tools to create and manage identities and yubikeys from an airgapped machine; complete with "turn-key" style minimal-interaction scripts and workflows that implicitly test recovery paths.
  - **BTRFS data persistence:** A data-redundant partition (all files are versioned with datetime file extensions)
    - **Encrypted Vault:** (veracrypt container)
      - PGP root private key.
      - PGP signing private subkey.
      - PGP encryption private subkey.
      - emergency ssh "breakglass" private key.
      - emergency age "breakglass" private key.
      - YubiKey secrets in a `.env` file.
    - **Unencrypted Files:** (exposed beside the container `.VAULT` file)
      - PGP certificates.
      - PGP root revocation certificate (unencrypted by design).
      - ssh public keys (`authorized_keys` has both the resident and "breakglass").
      - age public keys (`recipients.txt` has both the resident and "breakglass").
      - copies of the resident private stubs (`ssh_sk` / `age_sk`) for convenience.

**Minimum requirements:** 
- One USB drive (minimum ~2GB)
- One YubiKey 5 (req: OpenPGP, FIDO, PIV)

**Recommended requirements:** 
- One USB drive (minimum ~2GB)
- One or more redundant USB drives (minimum ~2GB)
- One or more YubiKey 5 (req: OpenPGP, FIDO, PIV)
- One transfer drive (optional, to move public materials)

### Repository representation

The flake represents CryptID administrative material in two trees:

- `data/identities/administrative/` contains public material. Primary SSH and
  Age entries identify resident YubiKey keys. Recovery entries identify offline
  breakglass keys.
- `secrets/administrative/` contains Age-encrypted convenience copies of the
  primary SSH and Age resident-key stubs and the OpenPGP signing/encryption card
  stubs. These stubs still require the YubiKey; they are not exportable private
  keys.

Recovery private keys remain only in offline CryptID storage, so recovery
identities have no corresponding encrypted stub in `secrets/`. A recovery Age
identity will follow this convention when added.

Nix consumers normally use `identities.administrative.ssh-keys` and
`identities.administrative.age-keys`, which combine primary and recovery public
identities. Keeping them as a set ensures routine authorization and encryption
retain the breakglass path.

The ISO assembly point remains `modules/host/cryptid.nix`, including its
dedicated pinned nixpkgs input and USB-writer app. Conventional NixOS setup is
kept in `hosts/cryptid/system.nix` and `hosts/cryptid/storage.nix`: the former
defines the air-gapped runtime and operator account, while the latter mounts
the persistent BTRFS partition. Protocol constants and the native-language
automation live under `data/cryptid/`. In particular, `script-context.nix`
constructs the Bash and Expect fragments used by the individual protocol
scripts. The host assembly loads these values through `self.data` and passes
the storage facts to its storage fragment.

### Features and Layout

CRYPTID is designed as a reproducible system for managing cryptographic identities and keys. It leverages NixOS and bash scripts to orchestrate tools like `veracrypt`, `gpg`, `ssh-keygen`, `age`, `age-plugin-yubikey`, and `ykman` into (mostly) automated workflows.

Constructed with a careful balance of usability and security, CRYPTID is a solid cornerstone upon which a comprehensive system can be built. You still need to have a threat model, physical security considerations, disaster response procedures, and application-specific recovery protocols. But for simple needs, it's a strong start that encourages good patterns.

#### Automation

CRYPTID provides "greater" scripts to automate complex sequences for key generation, extension, and rotation. More granular control can be achieved by using the "lesser" component scripts separately as desired, or only using the underlying tools directly.

See the script definitions under `data/cryptid/scripts/` for specifics, or the in-system `?` help menu.

#### Redundancy
`cryptid` encourages physical redundancy by making it trivial to clone the entire drive with a single `dd` command. For best results, the clones should be geographically separated before practical usage begins.

#### Maintenance

Included scripts extend or rotate OpenPGP subkeys and replace Age or SSH keys.
Distribution is application-specific. Refresh the physical media periodically.

### Rationale

- Drives can be cloned at the block level, trivializing redundancy.

- Duplicate bootable drives with persistent partitions means that not only are you protecting the critical data, but also the tools to use it when you need to.

- The root revocation certificate is stored unencrypted so that the PGP identity can always be revoked even if the password to the vault is lost.

- Minimal exposure
  - Rare-use materials are held offline in the vault.
  - Frequent-use materials only exist off the YubiKey and can't be exported.
  - CRYPTID drives could be kept entirely isolated by using a one-way transfer drive for public materials, to avoid even exposing the encrypted vault or pgp rev cert.
  - If the persistent partitions needs to be used directly, CRYPTID alters permissions by default so only root can access it.

- age's encryption should be preferred where possible, but includes a PGP encryption subkey for when that's not possible.

- PGP subkey for signing; alternatives like [minisign](https://github.com/jedisct1/minisign) don't work with the YubiKey and aren't as ubiquitous or well-supported in various ecosystems.

- PGP subkeys are created locally and backed up before being moved (rather than created as resident keys) so they can be restored.

- ssh and age are created on-device as resident keys and use secondary cold-storage `breakglass` keys for emergency response if resident keys are lost; preferable since both ssh and age can be multi-keyed (`authorized_keys` and `recipients.txt` respectively)

- A compromised vault is game-over: keys don't require passphrases. This is a tradeoff for only needing to know a single password (the vault's); may make responding to disasters easier and more likely to succeed, but it has downsides that need to be weighed against your threat model.

### Weaknesses

- It's only suitable for individuals, not enterprises; there's no administrative control or scalability.

- It relies heavily on physical security. While secrets are encrypted, there is
  no deniability and a [$5 wrench](https://xkcd.com/538/) hurts.

- There's no obscurity built-in: you're reading this.

- No compliance; no specifications are referenced in this document.

- The revocation certificate is available to anyone with the drive. If
  malicious revocation is in scope, change the design before generating keys;
  deleting existing copies later is insufficient.

- Secrets require the vault password. This is intentional, but can be a drawback depending on your needs. Though, it could be offset by encrypting vault password with the public key of someone you trust, and leaving that in the unencrypted partition.

- The structure of CRYPTID and this protocol is likely to have a low "bus factor." It's highly technical and potential users must be familiar with bootable drives, the CLI tools involved, and be aware of the scheme and how to make use of it.

- Adoption is difficult: the workflow assumes creation of one new identity and
  does not attempt to integrate with broader YubiKey policies.

## Practical Instructions

Create the environment from one or more spare USB drives.

### Create the Environment

Create a bootable USB with the necessary tools and partitions, with networking disabled.

1. Plug in the drive you want to use and identify its block device by size

```
nix run nixpkgs#nushell -- -c "lsblk --json | from json | get blockdevices | where rm == true | select name size"
```

2. Make it bootable with a persistent partition by using the script provided in this flake.

> [!CAUTION]
>  **This will wipe the drive**
> ```
> nix run .#mkbootable-cryptid -- /dev/sdX
> ```

### Use CRYPTID's Automation

The scripts are intended only for this particular usecase and provide sensible defaults, but likely won't be suitable for more complex needs. In descending order of complexity and flexibility: you can use the tools directly, use the lesser-scripts as needed to help some but not all operations, or use the greater-scripts to automate entire sequences.

If you want details about the lesser scripts, refer to CRYPTID's `?` command for a generated summary or the definitions under `data/cryptid/scripts/` to see exactly what the scripts do.

For the intended use, simply:

1. Initialize
2. Prepare
3. Disseminate
4. Maintain (annually)
5. Respond (to emergencies)

#### Initialize

Using a trusted machine, boot into CRYPTID with your yubikey attached and perform the two-phase initialization. Run `first-time-init` and follow the prompts; you'll be asked to reboot at some point and run `init-yubikey`.

Private details will be saved in the encrypted vault file, while the public and revocation certificates will be stored alongside it in the unencrypted partition.

Ideally, copy public material with a transfer drive. Otherwise, use only a
trusted machine and return the CRYPTID media to secure storage afterward. The
persistence partition requires root access on Linux machines.

> [!CAUTION]
> **Only use CRYPTID with a trusted machine.** An untrusted host can capture
> secrets despite the protections provided by the bootable environment.

> [!CAUTION]
> **The scripts reset your YubiKey by design.** You must confirm and physically
> reinsert it first. If that is not intended, avoid the YubiKey workflows and
> use the underlying tools directly.

#### Prepare (optional steps and things to consider)
- Optionally, Print the yubikey passphrases and QR code and store them a safe place such as a bank deposit box.

  > [!CAUTION]
  >  devices (including the printer may leak or retain data; relevancy and precautions depend on your threatmodel and procedures

- Optionally, Clone the bootable USB drive in its entirety and store the clones in geographically separate locations before you begin using the new identities.

  > [!CAUTION]
  >  The drives contain the unencrypted revocation certificate. This usually isn't a problem, but it can be for some usecases

  > [!CAUTION]
  >  It's advisable to use drives from different vendors to avoid getting wiped out by a single bad batch.

- Optionally, keep a digital copy of the vault. This largely depends on your threat model and your confidence in Veracrypt's implementation.

  > [!CAUTION]
  >  The private keys don't require passphrases, so a compromised vault is likely to be catastrophic in terms of vulnerability. While you can always use the revoke certificate for your PGP identity, the age and ssh keys aren't so easily remedied.

- Optionally, store the Yubikey's user PIN and/or reset code in a password manager (e.g. keepass). This largely depends on your threatmodel and your confidence in the manager. Keeping the PIN and reset code separate is encouraged. Admin and management codes are best left in the cryptid vault; though it's usually best to just reset everything, it depends on your usecase.

- Optionally, Copy the public keys from the unencrypted persistent partition to another drive (without including the revocation cert, so it's safe for public exposure).

At this point you're done with CRYPTID. If you have a transfer drive for your public key, the bootable drives can be stashed until there's an emergency or you need to extend / rotate your keys.

#### Disseminate
- Install the `authorized_keys` onto any important machines (especially headless/remote)
- Encrypt using age with `recipients.txt` so your breakglass key functions as a backup to your resident key.
- Using `ssh-keygen -K` with your YubiKey will get your non-emergency ssh public key and create a private stub; install this public key where needed.
- Using `age-plugin-yubikey --identity` with your YubiKey will get your non-emergency age public key.
- Use `gpg --import` to install your root public key followed by `gpg --card-status` which will discover the yubikey and create private stubs for your subkeys.
- Optionally, publish your root public key to a keyserver and add the `url` field to the yubikey using `gpg --card-edit`.

#### Maintain
- Every year, boot and `extend-subkeys` or `rotate-subkeys`.

- Occasionally, refresh backups with new drives to prevent loss from deterioration and bitrot. 

  > [!CAUTION]
  >  The drives contain the unencrypted revocation certificate. This usually isn't a problem, but it can be for some usecases

  > [!CAUTION]
  >  It's advisable to use drives from different vendors to avoid getting wiped out by a single bad batch.

- You can rotate your age and ssh keys (includes breakglass emergency keys; all files are versioned, but you should be careful to not lock yourself out).

  > [!CAUTION]
  > age and ssh key rotation scripts also rotate the `breakglass` emergency keys. All files are versioned so you should still have the old ones, but still take care to not lock yourself out.

The need to rotate keys varies, but CRYPTID is intended for long-lived keys; as only resident keys are used outside of emergency contexts, it's rare for rotation to be required unless a YubiKey is lost (the YubiKey's resident keys still require your YubiKey PINs/passphrase to use, losing a key is relatively low-risk).

#### Respond
Exact disaster responses depend on the event and your planning & procedures, but CRYPTID gives you access to physically and digitally redundant copies of:

- a bootable Linux environment with the protocol runtime tools
- a copy of your public keys.
- the root revocation certificate, available even if you've forgotten the vault password.
- The encrypted vault, containing:
	- the private key for your "breakglass" emergency keys.
	- the private key for your root identity.
	- the user, admin, and reset codes for your yubikey.
- Any other data you choose to store on the `PERSIST` btrfs partition, e.g. a keepass database with recovery codes.
