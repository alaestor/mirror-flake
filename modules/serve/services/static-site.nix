/**
  Reusable local content root for a static website.
*/
{
  flake.modules.nixos.serve-static-site =
    { config, lib, options, ... }:
    let
      hasVaultMountpoint = lib.hasAttrByPath [ "nas" "vault" "mountpoint" ] options;
    in
    {
      options.serve.static-site = {
        enable = lib.mkEnableOption "the local static-site content root";

        root = lib.mkOption {
          type = lib.types.str;
          default =
            if hasVaultMountpoint then
              "${config.nas.vault.mountpoint}/services/www/0x04cc"
            else
              "/mnt/Vault/services/www/0x04cc";
          defaultText = lib.literalExpression ''
            if the NAS module is present
            then "''${config.nas.vault.mountpoint}/services/www/0x04cc"
            else "/mnt/Vault/services/www/0x04cc"
          '';
          description = "Root directory of the static website.";
        };
      };
    };
}
