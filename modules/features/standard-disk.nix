{lib, inputs, ...}:
let
  module-name = "standard-disk";

  /**
    A disko configuration set up with interactive LUKS and BTRFS for easy reuse.
    Persistent swap optional and preconfigured with `/root` `/nix` and `/persist`
    subvolumes for compatibility with impermanence et al.

    ## Semi-Impermanence

    When `impermanence.enable = true;` and with `old-roots-retention-days`, old root
    subvolumes are moved to `/old_roots/<timestamp>/` on each boot and pruned after
    the retention period. These are accessible by mounting the BTRFS device.

    ### Accessing old roots

    ```bash
    sudo mkdir -p /mnt/btrfs
    sudo mount /dev/mapper/<luks-name> /mnt/btrfs
    ls /mnt/btrfs/old_roots/
    sudo umount /mnt/btrfs
    ```

    ### Restore files from an old root

    Mount the top-level Btrfs filesystem as above and copy the required files from
    `/mnt/btrfs/old_roots/<timestamp>/`.

    ### Manually delete old roots

    ```bash
    sudo mkdir -p /mnt/btrfs
    sudo mount /dev/mapper/<luks-name> /mnt/btrfs
    sudo btrfs subvolume delete --recursive /mnt/btrfs/old_roots/<timestamp>
    sudo umount /mnt/btrfs
    ```

    ### Booting old roots (nope)

    Replacing the `root` subvolume itself is not a temporary rollback: with
    impermanence enabled, it will be archived and replaced again during the
    next boot. To boot a restored root, first deploy a configuration with
    `impermanence.enable = false`, then replace `root` while booted from
    external media.

    **Retained roots should be viewed as **recovery archives**, not bootable rollbacks.**

    ### Future Improvements

    These operations, and more, may be made into interactive quality-of-life
    applications in the future.
  */

in with lib;
{
  nucleus.inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      # inputs for development; not needed for module
      inputs.nixpkgs.follows = "";
      inputs.home-manager.follows = "";
    };
  };

  # I don't need to run disko stand-alone, so for now I'll keep things simple and tightly coupled.
  # The alternative would be to use the flake-parts disko module (flake.diskoConfigurations)
  flake.modules.nixos."${module-name}" = {config, pkgs, ...} : let cfg = config.${module-name}; in
  {
    options."${module-name}" = {

      device = mkOption {
        type = types.path;
        default = "/dev/nvme0n1";
        description = "The primary boot drive to partition";
      };

      esp-size = mkOption {
        type = types.str;
        default = "512M";
        description = "The size of the EFI System Partition.";
      };

      luks-name = mkOption {
        type = types.str;
        default = "crypted";
        description = "The name of the LUKS encrypted device.";
      };

      luks-setup-password-file = mkOption {
        type = types.path;
        default = "/tmp/secret.key";
        description = ''
          The path to a file containing the passphrase to encrypt the LUKS partition with.
          Ensure there's no trailing newline. For example, use `echo -n "password" > /tmp/secret.key`
        '';
      };

      persistent-swap-size = mkOption {
        default = null;
        example = "16G";
        type = types.nullOr types.str;
        description = ''
          If this option is set, a persistant subvolume will be created and
          mounted to `/swap` and this value is set to `swap.swapfile.size`.
          Being persistent, it is suitable for hibernation. For an ephemeral
          swap, you can simply create a swapfile in `/` or `/var/`.
        '';
      };

      impermanence = {
        enable = mkEnableOption "Impermanence (ephemeral root)";

        old-roots-retention-days = mkOption {
          type = types.nullOr types.int;
          default = 30;
          description = ''
            How many days to keep old root subvolumes around for rollback.
            - `null` means the root subvolume is deleted and recreated on every boot.
            - An integer means old roots are pruned after this many days.
          '';
        };

        persist-mountpoint = mkOption {
          type = types.str;
          default = "/persist";
          description = "Where the persistent btrfs subvolume is mounted.";
        };

        nix-mountpoint = mkOption {
          type = types.str;
          default = "/nix";
          description = "Where the nix store btrfs subvolume is mounted.";
        };

        persist = {
          directories = mkOption {
            type = types.listOf types.str;
            default = [ "/var/lib/nixos" ];
            description = ''
              System directories to persist. `/var/lib/nixos` is persisted by default
              so dynamically allocated user and group IDs remain stable across boots.
            '';
          };
          files = mkOption {
            type = types.listOf types.str;
            default = [ "/etc/machine-id" ] ++ map (k: k.path) (config.services.openssh.hostKeys or []);
            defaultText = literalExpression "[ \"/etc/machine-id\" ] ++ map (k: k.path) (config.services.openssh.hostKeys or []);";
            description = "System files to persist.";
          };
          users = mkOption {
            type = types.attrsOf (types.submodule ({ name, ... }: {
              options = {
                directories = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Directories under this user's home to persist.";
                };
                files = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Files under this user's home to persist.";
                };
              };
            }));
            default = {};
            description = "Per-user persistence.";
          };
        };
      };

    };

    imports = [
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
    ];

    config = {
      disko.devices.disk.main = {
        type = "disk";
        device = cfg.device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = cfg.esp-size;
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = cfg.luks-name;
                passwordFile = cfg.luks-setup-password-file;
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = let mountOptions = [ "compress=zstd" "noatime" ]; in {
                    "/root"    = { inherit mountOptions; mountpoint = "/"; };
                    "/nix"     = { inherit mountOptions; mountpoint = cfg.impermanence.nix-mountpoint; };
                  } // (optionalAttrs (cfg.impermanence.enable) {
                    "/persist" = { inherit mountOptions; mountpoint = cfg.impermanence.persist-mountpoint; };
                  }) // (optionalAttrs (cfg.persistent-swap-size != null) {
                    "/swap"    = { mountpoint = "/swap"; swap.swapfile.size = cfg.persistent-swap-size; };
                  });
                };
              };
            };
          };
        };
      };

      # Reset the root subvolume after LUKS is unlocked but before systemd mounts it
      # as /sysroot. This must be an initrd unit rather than a legacy stage-1 hook.
      boot.initrd.systemd = mkIf cfg.impermanence.enable {
        enable = true;
        services.reset-root = let
          mapperDevice = "/dev/mapper/${cfg.luks-name}";
        in {
          description = "Reset the ephemeral Btrfs root subvolume";
          wantedBy = [ "initrd.target" ];
          requires = [ "cryptsetup.target" ];
          after = [ "cryptsetup.target" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = false;
          path = with pkgs; [
            btrfs-progs
            coreutils
            findutils
            util-linux
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /btrfs_tmp
            mount -t btrfs ${mapperDevice} /btrfs_tmp
            trap 'umount /btrfs_tmp' EXIT

            ${optionalString (cfg.impermanence.old-roots-retention-days != null) ''
              if [[ -e /btrfs_tmp/root ]]; then
                mkdir -p /btrfs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%d_%H:%M:%S")
                mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
              fi

              while IFS= read -r old_root; do
                btrfs subvolume delete --recursive "$old_root"
              done < <(
                find /btrfs_tmp/old_roots \
                  -mindepth 1 -maxdepth 1 -type d \
                  -mtime +${toString cfg.impermanence.old-roots-retention-days} \
                  -print
              )
            ''}

            ${optionalString (cfg.impermanence.old-roots-retention-days == null) ''
              if [[ -e /btrfs_tmp/root ]]; then
                btrfs subvolume delete --recursive /btrfs_tmp/root
              fi
            ''}

            btrfs subvolume create /btrfs_tmp/root
          '';
        };
      };

      # Make /persist available early so impermanence's bind mounts can be set up
      # during boot, not just after the system is fully up.
      fileSystems."${cfg.impermanence.persist-mountpoint}" = mkIf cfg.impermanence.enable {
        device = "/dev/mapper/${cfg.luks-name}";
        fsType = "btrfs";
        options = [ "subvol=persist" ];
        neededForBoot = true;
      };

      # Impermanence: declare what to persist.
      environment.persistence."${cfg.impermanence.persist-mountpoint}" = mkIf cfg.impermanence.enable {
        hideMounts = true;
        directories = cfg.impermanence.persist.directories;
        files = cfg.impermanence.persist.files;
        users = cfg.impermanence.persist.users;
      };
    };
  };
}
