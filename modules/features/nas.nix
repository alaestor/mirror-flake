/**
  Provides optional NFS mounts for the Cauldron, Vault, Pocket, and Services
  NAS shares. Each share can be enabled independently and mounted read-only.
*/
{ self, ... }:
{
  flake.modules.nixos.nas =
    { config, lib, ... }:
    let
      cfg = config.nas;

      shareOptions =
        name: device:
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
          device = lib.mkOption {
            type = lib.types.str;
            default = device;
            description = "Remote NFS export path for the ${name} NAS share.";
          };
          idleTimeoutSec = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = 600;
            description = ''
              Seconds of inactivity before the automount unmounts the
              ${name} share. Set to `null` to keep it mounted indefinitely
              once triggered, e.g. for services that need it available on
              short notice and can't tolerate remount cycles.
            '';
          };
        };

      shares = [
        cfg.cauldron
        cfg.vault
        cfg.pocket
        cfg.services
      ];

      mkFileSystem =
        optionName:
        lib.mkIf cfg.${optionName}.enable {
          "${cfg.${optionName}.mountpoint}" = {
            device = cfg.${optionName}.device;
            fsType = "nfs";
            options = [
              "nfsvers=4.2"
              "x-systemd.automount"
              "noauto"
              "noatime"
              # Avoid indefinite hangs on shutdown/suspend if the NAS is
              # slow or unreachable: fail fast instead of retrying forever,
              # and auto-unmount when idle so it's rarely mounted at all.
              #
              # `timeo=30`/`retrans=2` used to live here to shorten that
              # failure window (3s), but it was a workaround for shutdowns
              # not releasing the mount cleanly in the first place, and its
              # side effect was a kernel log line every few seconds for the
              # whole span of any NAS outage. Removed pending an actual
              # diagnosis of why shutdown hangs on this mount; NFS's default
              # timeo (600 deciseconds/60s) applies until then.
              "soft"
              "x-systemd.mount-timeout=15s"
            ]
            ++ lib.optional cfg.${optionName}.readonly "ro"
            ++ lib.optional (
              cfg.${optionName}.idleTimeoutSec != null
            ) "x-systemd.idle-timeout=${toString cfg.${optionName}.idleTimeoutSec}";
          };
        };
    in
    {
      options.nas = {
        server = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = self.fleet.lan.nas;
          description = "Hostname or address of the NAS server.";
        };

        cauldron = shareOptions "Cauldron" "${cfg.server}:/mnt/Cauldron/Storage";
        vault = shareOptions "Vault" "${cfg.server}:/mnt/Vault/Storage";
        pocket = shareOptions "Pocket" "${cfg.server}:/mnt/Pocket/Storage";
        # Same underlying export as `vault`, mounted separately (and
        # writable) so hosts don't need read-write access to all of Vault
        # just to write into its `services` folder.
        services = shareOptions "Services" "${cfg.server}:/mnt/Vault/Storage/services";
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
          (mkFileSystem "cauldron")
          (mkFileSystem "vault")
          (mkFileSystem "pocket")
          (mkFileSystem "services")
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
