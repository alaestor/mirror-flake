/**
  # nix-store-signing

  Exports the disabled-by-default NixOS `nix-store-signing` feature and the
  `provision-nix-store-signing-key` repository app.

  The provisioning app generates a caller-named Nix binary-cache key, encrypts
  its secret half to every administrative Age recipient plus any recipients
  supplied by the caller, and writes only `<name>.nsk.age` and `<name>.nsk.pub`
  in the current directory.

  The NixOS feature deploys a configured encrypted signing key through Agenix
  and installs `sign-nix-store`, which recursively signs the supplied
  installables. Importing the module does not enable deployment.
*/
{ inputs, self, ... }:

let
  provisionScript = self.data.path "features/nix-store-signing/provision.sh";
  testScript = self.data.path "features/nix-store-signing/test.sh";
  recipients = self.data.vars.administrativeAgeRecipients;
in
{
  flake.modules.nixos.nix-store-signing =
    { config, lib, pkgs, ... }:
    let
      cfg = config.nix-store-signing;
      secret = self.secrets.nixStoreSigning cfg.keyName;
      username = config.hostIdentity.primaryUser;
      user = config.users.users.${username};
      signer = pkgs.writeShellApplication {
        name = "sign-nix-store";
        runtimeInputs = [ config.nix.package ];
        text = ''
          exec nix store sign --recursive \
            --key-file ${lib.escapeShellArg cfg.secretPath} "$@"
        '';
      };
    in
    {
      imports = [ inputs.self.modules.nixos.agenix-host-identity ];

      options.nix-store-signing = {
        enable = lib.mkEnableOption "Nix store-path signing";
        keyName = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "${cfg.authority}-${toString cfg.rotation}";
          description = "Name embedded in the Nix signing key.";
        };
        authority = lib.mkOption {
          type = lib.types.str;
          default = config.networking.fqdn;
          defaultText = lib.literalExpression "config.networking.fqdn";
          description = "DNS-like authority used as the signing-key name prefix.";
        };
        rotation = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Signing-key rotation counter.";
        };
        secretPath = lib.mkOption {
          type = lib.types.str;
          default = "/run/agenix/nix-store-signing-key";
          description = "Runtime path of the decrypted Nix signing key.";
        };
      };

      config = lib.mkIf cfg.enable {
        warnings = lib.optional (!secret.exists)
          "nix-store-signing: ${secret.subpath} is absent; signing remains unavailable";

        age.secrets.nix-store-signing-key = lib.mkIf secret.exists {
          file = secret.file;
          path = cfg.secretPath;
          owner = username;
          group = user.group;
          mode = "0400";
        };

        environment.systemPackages = lib.optional secret.exists signer;
      };
    };

  perSystem =
    { lib, pkgs, ... }:
    let
      recipientArgs = lib.concatMapStringsSep " "
        (recipient: "--recipient ${lib.escapeShellArg recipient}")
        recipients;
      provisioner = pkgs.writeShellApplication {
        name = "provision-nix-store-signing-key";
        runtimeInputs = with pkgs; [ age age-plugin-yubikey coreutils nix ];
        text = ''
          exec ${provisionScript} \
            ${recipientArgs} \
            "$@"
        '';
      };
    in
    {
      packages.provision-nix-store-signing-key = provisioner;
      apps.provision-nix-store-signing-key = {
        meta.description = "Provision an encrypted Nix store signing key";
        program = lib.getExe provisioner;
      };
      checks.provision-nix-store-signing-key = pkgs.runCommand "provision-nix-store-signing-key-test" {
        nativeBuildInputs = with pkgs; [ age coreutils shellcheck ];
      } ''
        shellcheck ${provisionScript} ${testScript}
        bash ${testScript} ${provisionScript}
        touch $out
      '';
    };
}
