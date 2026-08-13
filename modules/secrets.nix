/**
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
*/
{ lib, self, ... }:
let
  inherit (lib) mkOption types;

  secretType = types.submodule {
    freeformType = types.attrsOf types.unspecified;

    options = {
      subpath = mkOption {
        type = types.nonEmptyStr;
        description = "Location of the encrypted file relative to `secrets/`.";
      };

      file = mkOption {
        type = types.nonEmptyStr;
        description = "Flake-rooted path of the encrypted file.";
      };

      exists = mkOption {
        type = types.bool;
        description = "Whether the encrypted file is present in the source tree.";
      };
    };
  };

  secretsType = types.submodule {
    options = {
      path = mkOption {
        type = types.functionTo types.nonEmptyStr;
        description = "Resolves a `secrets/`-relative subpath against the flake root.";
      };

      exists = mkOption {
        type = types.functionTo types.bool;
        description = "Whether the `secrets/`-relative subpath is present in the source tree.";
      };

      describe = mkOption {
        type = types.functionTo secretType;
        description = "Builds a secret record from a `secrets/`-relative subpath.";
      };

      sshClient = mkOption {
        type = types.functionTo secretType;
        description = "The per-host SSH client identity of the named host.";
      };

      sshHost = mkOption {
        type = types.functionTo secretType;
        description = "The SSH server identity of the named host.";
      };

      nixStoreSigning = mkOption {
        type = types.functionTo secretType;
        description = "The Nix store signing key of the named signing authority.";
      };

      administrative = mkOption {
        type = types.submodule {
          options = {
            agePrimary = mkOption {
              type = secretType;
              description = "The primary administrative age identity.";
            };

            sshPrimary = mkOption {
              type = secretType;
              description = "The primary administrative SSH identity.";
            };

            pgpEncryptionCardStub = mkOption {
              type = secretType;
              description = "The smartcard stub of the administrative PGP encryption key.";
            };

            pgpSigningCardStub = mkOption {
              type = secretType;
              description = "The smartcard stub of the administrative PGP signing key.";
            };
          };
        };
        description = "Administrative identities held by the repository operator.";
      };

      recipients = mkOption {
        type = types.submodule {
          options = {
            administrators = mkOption {
              type = types.listOf types.nonEmptyStr;
              description = "Age recipients that may decrypt administrative secrets.";
            };

            hosts = mkOption {
              type = types.attrsOf types.nonEmptyStr;
              description = "SSH host public keys, by host name, usable as age recipients.";
            };
          };
        };
        description = "Public recipients that encrypted secrets may be addressed to.";
      };
    };
  };

in
{
  options.flake.secrets = mkOption {
    type = secretsType;
    default = { };
    description = "Paths and public recipient metadata for encrypted secrets.";
  };

  config.flake.secrets = rec {
    path = subpath: "${self}/secrets/${subpath}";
    exists = subpath: builtins.pathExists (path subpath);
    describe = subpath: {
      inherit subpath;
      file = path subpath;
      exists = exists subpath;
    };

    sshClient = hostName:
      let
        host = lib.toLower hostName;
        fileName = "id_ed25519_${host}";
      in
      describe "ssh-client/${fileName}.age" // {
        inherit fileName host;
      };

    sshHost = hostName:
      let
        host = lib.toLower hostName;
        fileName = "ssh_host_ed25519_key_${host}";
      in
      describe "ssh-host/${fileName}.age" // {
        inherit fileName host;
      };

    nixStoreSigning = keyName:
      describe "nix-store-signing/${keyName}.nsk.age" // { inherit keyName; };

    administrative = {
      agePrimary = describe "administrative/age_primary.age";
      sshPrimary = describe "administrative/ssh_primary.age";
      pgpEncryptionCardStub =
        describe "administrative/pgp-encrypt-801E05AF720F05CE66A18FF1BCCD526CDAB3D166.key.age"
        // { keygrip = "801E05AF720F05CE66A18FF1BCCD526CDAB3D166"; };
      pgpSigningCardStub =
        describe "administrative/pgp-sign-8AC1E18B5C36D9A715E3790ADF75EE47A8DE311A.key.age"
        // { keygrip = "8AC1E18B5C36D9A715E3790ADF75EE47A8DE311A"; };
    };

    recipients = {
      administrators = self.data.vars.administrativeAgeRecipients;
      hosts = self.data.vars.sshHostPublicKeys;
    };
  };
}
