/**
  Steam gaming capability for NixOS hosts.

  The feature keeps Steam activation, optional Remote Play ingress, and
  optional crash-report suppression behind one typed, disabled-by-default
  interface. Hosts retain ownership of unrelated GPU, kernel, and hardware
  policy.
*/
{ ... }:
{
  flake.modules.nixos.steam-gaming =
    { config, lib, ... }:
    let
      cfg = config.steam-gaming;
    in
    {
      options.steam-gaming = {
        enable = lib.mkEnableOption "Steam gaming support";

        remotePlay.openFirewall = lib.mkEnableOption "Steam Remote Play firewall ports";

        suppressCrashReports = lib.mkEnableOption "local Steam crash-report collection and upload";
      };

      config = lib.mkIf cfg.enable {
        programs.steam = {
          enable = true;
          remotePlay.openFirewall = cfg.remotePlay.openFirewall;
        };

        networking.extraHosts = lib.mkIf cfg.suppressCrashReports ''
          0.0.0.0 crash.steampowered.com
        '';

        systemd.user.services.preventSteamDumps = lib.mkIf cfg.suppressCrashReports {
          description = "Symlink Steam crash reports to /dev/null";
          script = "ln -sfn /dev/null /tmp/dumps";
          # `multi-user.target` does not exist in the systemd *user* manager
          # (this is a `systemd.user` service); that name never activated
          # the unit, so /tmp/dumps was never symlinked to /dev/null.
          wantedBy = [ "default.target" ];
        };
      };
    };
}
