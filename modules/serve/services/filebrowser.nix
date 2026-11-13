/**
  Read-only Filebrowser media service without public ingress policy.
  Only its database directory and cache are writable; media remains read-only
  even when the underlying storage permits writes.
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
        enable = lib.mkEnableOption "the local Filebrowser media service";

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

      config = lib.mkIf cfg.enable {
        services.filebrowser = {
          enable = true;
          settings = {
            inherit (cfg) address port root;
          };
        };

        # `root` usually lives on a network share. Without this, nothing stops
        # Filebrowser before that share is unmounted, and the unmount fails
        # against its open files.
        systemd.services.filebrowser = {
          unitConfig.RequiresMountsFor = [ cfg.root ];
          serviceConfig = {
            ProtectSystem = lib.mkDefault "strict";
            ProtectHome = lib.mkDefault true;
            PrivateTmp = lib.mkDefault true;
            CapabilityBoundingSet = lib.mkDefault "";
            ReadWritePaths = [ (builtins.dirOf config.services.filebrowser.settings.database) ];
            # StateDirectory and CacheDirectory are writable automatically.
            # Protect runtime mounts explicitly rather than relying on strict
            # to cover them when combined with the other namespace settings.
            ReadOnlyPaths = [ "/run" cfg.root ];
          };
        };
      };
    };
}
