/**
  Reusable local content root for a static website.
*/
{
  flake.modules.nixos.serve-static-site-0x04 =
    { config, lib, options, ... }:
    let
      hasVaultMountpoint = lib.hasAttrByPath [ "nas" "vault" "mountpoint" ] options;
    in
    {
      options.serve.static-site-0x04 = {
        enable = lib.mkEnableOption "the local static-site content root for 0x04.cc";

        root = lib.mkOption {
          type = lib.types.str;
          default =
            if hasVaultMountpoint then
              "${config.nas.vault.mountpoint}/services-static/0x04"
            else
              "/mnt/Vault/services-static/0x04";
          defaultText = lib.literalExpression ''
            if the NAS module is present
            then "''${config.nas.vault.mountpoint}/services-static/0x04"
            else "/mnt/Vault/services-static/0x04"
          '';
          description = "Root directory of the static website.";
        };
      };
    };
}
