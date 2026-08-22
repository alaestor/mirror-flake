/**
  Reusable local content root for a static website.
*/
{
  flake.modules.nixos.serve-static-site-bokunopi =
    { config, lib, options, ... }:
    let
      hasVaultMountpoint = lib.hasAttrByPath [ "nas" "vault" "mountpoint" ] options;
    in
    {
      options.serve.static-site-bokunopi = {
        enable = lib.mkEnableOption "the local static-site content root for bokunopi";

        root = lib.mkOption {
          type = lib.types.str;
          default =
            if hasVaultMountpoint then
              "${config.nas.vault.mountpoint}/services/www/bokunopi"
            else
              "/mnt/Vault/services/www/bokunopi";
          defaultText = lib.literalExpression ''
            if the NAS module is present
            then "''${config.nas.vault.mountpoint}/services/www/bokunopi"
            else "/mnt/Vault/services/www/bokunopi"
          '';
          description = "Root directory of the static website.";
        };
      };
    };
}
