/**
  Provides optional NFS mounts for the Cauldron, Vault, and Pocket NAS shares.
  Each share can be enabled independently and mounted read-only.
*/
{
  flake.modules.nixos.nas =
    { config, lib, ... }:
    let
      cfg = config.nas;

      shareOptions =
        name:
        {
          enable = lib.mkEnableOption "the ${name} NAS share";
          readonly = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to mount the ${name} NAS share read-only.";
          };
          mountpoint = lib.mkOption {
            type = lib.types.str;
            default = "/mnt/${name}";
            description = "Local mount point for the ${name} NAS share.";
          };
        };

      shares = [
        cfg.cauldron
        cfg.vault
        cfg.pocket
      ];

      mkFileSystem =
        optionName: shareName:
        lib.mkIf cfg.${optionName}.enable {
          "${cfg.${optionName}.mountpoint}" = {
            device = "${cfg.server}:/mnt/${shareName}/Storage";
            fsType = "nfs";
            options = [
              "nfsvers=4.2"
              "x-systemd.automount"
              "noauto"
              "noatime"
            ]
            ++ lib.optional cfg.${optionName}.readonly "ro";
          };
        };
    in
    {
      options.nas = {
        server = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "172.16.0.2"; # TODO(lan): nas ip
          description = "Hostname or address of the NAS server.";
        };

        cauldron = shareOptions "Cauldron";
        vault = shareOptions "Vault";
        pocket = shareOptions "Pocket";
      };

      config = lib.mkIf (lib.any (share: share.enable) shares) {
        boot = {
          supportedFilesystems.nfs = true;
          kernelModules = [
            "nfsv4"
            "rpcsec_gss_krb5"
          ];
        };

        fileSystems = lib.mkMerge [
          (mkFileSystem "cauldron" "Cauldron")
          (mkFileSystem "vault" "Vault")
          (mkFileSystem "pocket" "Pocket")
        ];

        userEnvironment.sharedModules = lib.optional cfg.vault.enable (
          { lib, ... }:
          {
            options.hostContext.nas.vaultMountpoint = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              internal = true;
              description = "Mount point of the host's enabled NAS Vault share.";
            };

            config.hostContext.nas.vaultMountpoint = cfg.vault.mountpoint;
          }
        );
      };
    };
}
