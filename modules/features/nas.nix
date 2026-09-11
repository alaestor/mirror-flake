/**
  Provides optional NFS mounts for the Cauldron, Vault, Pocket, and Services
  NAS shares. Each share can be enabled independently and mounted read-only.

  Enabled shares stay mounted for the life of the boot. Services that read or
  write one are expected to declare `RequiresMountsFor` against their data
  root, which both waits for the share and, more importantly, stops them
  before it is unmounted.
*/
{ self, ... }:
{
  flake.modules.nixos.nas =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
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
        };

      shares = [
        cfg.cauldron
        cfg.vault
        cfg.pocket
        cfg.services
      ];

      enabledShares = lib.filter (share: share.enable) shares;
      mountpoints = map (share: share.mountpoint) enabledShares;
      mountUnits = map (mountpoint: "${utils.escapeSystemdPath mountpoint}.mount") mountpoints;

      mkFileSystem =
        optionName:
        lib.mkIf cfg.${optionName}.enable {
          "${cfg.${optionName}.mountpoint}" = {
            device = cfg.${optionName}.device;
            fsType = "nfs";
            options = [
              "nfsvers=4.2"
              "noatime"
              # Services that consume a share order themselves against its
              # mount unit, so the share is mounted for the whole time anything
              # needs it. `nofail` keeps an unreachable NAS from failing the
              # boot; only the consumers of that share degrade.
              "_netdev"
              "nofail"
              # `hard` so a transient NAS outage suspends I/O instead of
              # returning errors into live writers: these shares carry
              # torrent data and service state that `soft` can corrupt
              # silently. Shutdown hangs, the historical reason for `soft`,
              # are handled by stop ordering and `nas-detach` below rather
              # than by letting I/O fail.
              "hard"
              "x-systemd.mount-timeout=15s"
            ]
            ++ lib.optional cfg.${optionName}.readonly "ro";
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

      config = lib.mkIf (enabledShares != [ ]) {
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

        # A share can still be busy when systemd tries to unmount it: an
        # interactive shell may sit with its working directory inside one, and
        # no unit ordering can describe that. An ordinary unmount then fails,
        # the mount unit burns its stop timeout, and whatever is left mounted
        # is retried in the late shutdown phase, after the network is gone,
        # where an NFS unmount has no way to complete.
        #
        # Detaching lazily removes that whole class of hang: the mount is
        # detached from the tree immediately, while the NAS is still
        # reachable, no matter who holds it open. Starting after the mounts
        # means stopping before them, which is the ordering that matters.
        systemd.services.nas-detach = {
          description = "Detach NAS mounts before shutdown";
          wantedBy = [ "multi-user.target" ];
          after = mountUnits;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
            ExecStop = pkgs.writeShellScript "nas-detach" ''
              for mountpoint in ${lib.escapeShellArgs mountpoints}; do
                if ${pkgs.util-linux}/bin/mountpoint -q "$mountpoint"; then
                  ${pkgs.util-linux}/bin/umount --lazy --force "$mountpoint" || true
                fi
              done
            '';
          };
        };

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
