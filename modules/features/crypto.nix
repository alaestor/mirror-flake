/**
  YubiKey-backed cryptography tooling (GPG smartcard, age, SSH) for hosts
  that use one.
*/
{ inputs, self, ... }:
{
  # TODO: yubikey tooling should be its own module

  # Yubikey tooling
  flake.modules.nixos.crypto-yubikey-cli =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        pcsc-tools
        yubikey-manager
        age-plugin-yubikey
      ];
      hardware.gpgSmartcards.enable = true;
      services.pcscd.enable = true;
    };

  flake.modules.nixos.crypto-yubikey =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.crypto-yubikey.administrativeStubs;
      username = config.hostIdentity.primaryUser;
      user = config.users.users.${username};
      secrets = self.secrets.administrative;
      stubs = [
        {
          name = "administrative-age-primary";
          secret = secrets.agePrimary;
          path = "${user.home}/.config/age/yubikey-identity";
        }
        {
          name = "administrative-ssh-primary";
          secret = secrets.sshPrimary;
          path = "${user.home}/.ssh/ssh_sk";
        }
        {
          name = "administrative-pgp-encryption-card";
          secret = secrets.pgpEncryptionCardStub;
          path = "${user.home}/.gnupg/private-keys-v1.d/${secrets.pgpEncryptionCardStub.keygrip}.key";
        }
        {
          name = "administrative-pgp-signing-card";
          secret = secrets.pgpSigningCardStub;
          path = "${user.home}/.gnupg/private-keys-v1.d/${secrets.pgpSigningCardStub.keygrip}.key";
        }
      ];
      presentStubs = builtins.filter (stub: stub.secret.exists) stubs;
      missingStubs = builtins.filter (stub: !stub.secret.exists) stubs;
    in
    {
      imports = with inputs.self.modules.nixos; [
        agenix
        crypto-yubikey-cli
      ];

      options.crypto-yubikey.administrativeStubs.enable = lib.mkEnableOption
        "declarative deployment of the primary administrative YubiKey stubs";

      config = lib.mkMerge [
        {
          services.udev.packages = [ pkgs.yubikey-personalization ];
        }
        (lib.mkIf cfg.enable {
          warnings = map (
            stub: "crypto-yubikey: ${stub.secret.subpath} is absent; skipping ${stub.name} deployment"
          ) missingStubs;

          age.secrets = builtins.listToAttrs (
            map (stub: {
              inherit (stub) name;
              value = {
                inherit (stub.secret) file;
                inherit (stub) path;
                owner = username;
                group = user.group;
                mode = "0400";
              };
            }) presentStubs
          );
        })
      ];
    };

}
