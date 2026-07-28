/**
  Local Filebrowser media service without public ingress policy.
*/
{
  flake.modules.nixos.serve-filebrowser =
    { config, lib, options, ... }:
    let
      cfg = config.serve.filebrowser;
      hasVaultMountpoint = lib.hasAttrByPath [ "nas" "vault" "mountpoint" ] options;
    in
    {
      options.serve.filebrowser = {
        root = lib.mkOption {
          type = lib.types.str;
          default =
            if hasVaultMountpoint then
              "${config.nas.vault.mountpoint}/Media"
            else
              "/mnt/Vault/Media";
          defaultText = lib.literalExpression ''
            if the NAS module is present
            then "''${config.nas.vault.mountpoint}/Media"
            else "/mnt/Vault/Media"
          '';
          description = "Directory served by Filebrowser.";
        };

        address = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Local Filebrowser listener address.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8087;
          description = "Local Filebrowser listener port.";
        };
      };

      config.services.filebrowser = {
        enable = true;
        settings = {
          inherit (cfg) address port root;
        };
      };
    };
}
