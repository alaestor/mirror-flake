/**
  Installs YubiKey tooling, smartcard support, and device rules. Deploys
  administrative age, SSH, and OpenPGP stubs for the host's primary user
  by default; disable yubikey.administrativeStubs.enable for tooling alone.
*/
{ self, ... }:
{
  flake.modules.nixos.yubikey =
    { config, lib, pkgs, ... }:
    let
      cfg = config.yubikey.administrativeStubs;
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
      imports = [ self.modules.nixos.agenix ];

      options.yubikey.administrativeStubs.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Deploy the primary administrative YubiKey stubs for the host's primary user.";
      };

      config = {
        environment.systemPackages = with pkgs; [
          pcsc-tools
          yubikey-manager
          age-plugin-yubikey
        ];
        hardware.gpgSmartcards.enable = true;
        services.pcscd.enable = true;
        services.udev.packages = [ pkgs.yubikey-personalization ];

        warnings = lib.mkIf cfg.enable (map (
          stub: "yubikey: ${stub.secret.subpath} is absent; skipping ${stub.name} deployment"
        ) missingStubs);

        age.secrets = lib.mkIf cfg.enable (builtins.listToAttrs (
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
        ));
      };
    };
}
