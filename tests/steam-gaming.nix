{
  inputs,
  pkgs,
  system,
  ...
}:
let
  feature = inputs.self.modules.nixos.steam-gaming;
  evaluate = modules: inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ feature ] ++ modules;
  };

  disabled = (evaluate [ ]).config;
  ordinary = (evaluate [ { steam-gaming.enable = true; } ]).config;
  enabled = (evaluate [ {
    steam-gaming = {
      enable = true;
      remotePlay.openFirewall = true;
      suppressCrashReports = true;
    };
  } ]).config;

  assertions = [
    {
      assertion = !disabled.programs.steam.enable;
      message = "steam-gaming unexpectedly enabled Steam by default";
    }
    {
      assertion = ordinary.programs.steam.enable
        && !ordinary.programs.steam.remotePlay.openFirewall
        && !(ordinary.systemd.user.services ? preventSteamDumps)
        && !(inputs.nixpkgs.lib.hasInfix "crash.steampowered.com" ordinary.networking.extraHosts);
      message = "ordinary Steam activation applied opt-in ingress or crash suppression";
    }
    {
      assertion = enabled.programs.steam.enable && enabled.programs.steam.remotePlay.openFirewall;
      message = "steam-gaming did not enable Steam and Remote Play ingress";
    }
    {
      assertion = inputs.nixpkgs.lib.hasInfix "0.0.0.0 crash.steampowered.com" enabled.networking.extraHosts;
      message = "steam-gaming did not suppress Steam crash-report uploads";
    }
    {
      assertion =
        enabled.systemd.user.services ? preventSteamDumps
        && enabled.systemd.user.services.preventSteamDumps.wantedBy == [ "default.target" ];
      message = "steam-gaming did not suppress local Steam crash dumps";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) assertions
  );
in
pkgs.runCommand "steam-gaming-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      cat "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
