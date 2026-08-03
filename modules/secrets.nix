{ lib, self, ... }:
{
  options.flake.secrets = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
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
