/**
  Wires a primary OpenPGP fingerprint into GPG and Git commit signing.
*/
{ inputs, ... }:
{
  flake.modules.homeManager.pgp =
    { config, lib, ... }:
    let
      cfg = config.pgp;
    in
    {
      imports = [ inputs.self.modules.homeManager.gpg ];

      options.pgp.primaryFingerprint = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[0-9A-Fa-f]{40}");
        default = null;
        apply = fingerprint: if fingerprint == null then null else lib.toUpper fingerprint;
        example = "0123456789ABCDEF0123456789ABCDEF01234567";
        description = "Primary OpenPGP fingerprint used for encryption and Git signing.";
      };

      config = lib.mkIf (cfg.primaryFingerprint != null) {
        programs.gpg.settings = {
          default-key = cfg.primaryFingerprint;
          trusted-key = cfg.primaryFingerprint;
        };

        programs.git.signing = {
          format = "openpgp";
          key = cfg.primaryFingerprint;
          signer = lib.getExe config.programs.gpg.package;
          signByDefault = true;
        };
      };
    };
}
