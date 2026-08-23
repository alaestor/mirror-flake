/**
  # memory-manager

  Compressed swap plus userspace early-OOM killer.

  The kernel's own OOM killer only acts once reclaim has already failed, by
  which point the machine has usually spent minutes thrashing and is
  unresponsive. `earlyoom` watches free memory from userspace and kills the
  biggest consumer while the system is still interactive. Disables systemd.oom
  by default to avoid unpredictable races.

  zram gives that killer somewhere to fall back to: compressed swap in RAM
  absorbs an allocation spike (a large `nix eval`, say) instead of turning it
  straight into a kill. Both halves are independently switchable, because a
  guest that wants swap headroom does not necessarily want desktop
  notifications, and vice versa.
*/
{ lib, ... }:
{
  flake.modules.nixos.memory-manager =
    { config, ... }:
    let
      cfg = config.memory-manager;
    in
    {
      options.memory-manager = {
        zram = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to provide compressed swap in RAM.";
          };

          memoryPercent = lib.mkOption {
            type = lib.types.ints.between 1 200;
            default = 30;
            description = ''
              Percentage of physical memory the zram device may hold once
              compressed. Values above 100 are legitimate — the device stores
              compressed pages — but the uncompressed working set still has
              to fit in what is left.
            '';
          };
        };

        earlyoom = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to kill memory hogs from userspace before the kernel's OOM killer engages.";
          };

          notifications = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to announce kills on the system D-Bus. Useful on a
              workstation with a notification daemon; pointless on a headless
              host, and any local user can spam the session with it.
            '';
          };

          freeMemThreshold = lib.mkOption {
            type = lib.types.ints.between 1 100;
            default = 10;
            description = "Available-memory percentage below which earlyoom starts sending SIGTERM.";
          };

          freeSwapThreshold = lib.mkOption {
            type = lib.types.ints.between 1 100;
            default = 10;
            description = "Free-swap percentage below which earlyoom starts sending SIGTERM.";
          };
        };
      };

      config = {
        zramSwap = lib.mkIf cfg.zram.enable {
          enable = true;
          inherit (cfg.zram) memoryPercent;
        };

        services.earlyoom = lib.mkIf cfg.earlyoom.enable {
          enable = true;
          enableNotifications = cfg.earlyoom.notifications;
          inherit (cfg.earlyoom) freeMemThreshold freeSwapThreshold;
        };

        systemd.oomd.enable = lib.mkIf cfg.earlyoom.enable (lib.mkDefault false);
      };
    };
}
