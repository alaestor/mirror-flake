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
      assertion = enabled.programs.steam.enable && enabled.programs.steam.remotePlay.openFirewall;
      message = "steam-gaming did not enable Steam and Remote Play ingress";
    }
    {
      assertion = builtins.match ".*crash\\.steampowered\\.com.*" enabled.networking.extraHosts != null;
      message = "steam-gaming did not suppress Steam crash-report uploads";
    }
    {
      assertion = enabled.systemd.user.services ? preventSteamDumps;
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
