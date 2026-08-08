{ config, cryptidConstants, lib, ... }:
let
  inherit (cryptidConstants)
    path-mount-persist
    persist-partition-label;
in
{
  fileSystems = lib.mkOverride 59 (
    config.lib.isoFileSystems // {
      "${path-mount-persist}" = {
        device = "/dev/disk/by-label/${persist-partition-label}";
        fsType = "btrfs";
        neededForBoot = true;
        options = [ "defaults" "compress=zstd" "noatime" ];
      };
    }
  );
}
