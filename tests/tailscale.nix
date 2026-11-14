{ inputs, pkgs, system }:
let
  rawFixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ../nucleus/flake-module.nix
      ../modules/features/tailscale.nix
    ];
  };

  aspectFixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ../nucleus/flake-module.nix
      ../modules/fleet/fleet.nix
      { flake.fleet.tailnets."0x04cc" = {
        coordinationUrl = "https://coordination.example.test";
        dnsSuffix = "tailnet.example.test";
      }; }
      ../modules/features/tailscale.nix
      ../modules/aspects/tailnet-client.nix
    ];
  };

  userEnvironmentModule =
    { lib, ... }:
    {
      options.userEnvironment.sharedModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
      };
    };

  mkConfig = module:
    inputs.unstable-nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        module
        userEnvironmentModule
        {
          system.stateVersion = "24.11";
        }
      ];
    };

  rawConfig = (mkConfig rawFixture.modules.nixos.tailscale).config;
  aspectConfig = (mkConfig aspectFixture.modules.nixos.tailnet-client).config;
  customConfig = (inputs.unstable-nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      aspectFixture.modules.nixos.tailnet-client
      userEnvironmentModule
      { tailscale.loginServer = "https://override.example.test"; }
    ];
  }).config;
  tailnet = aspectFixture.fleet.tailnets."0x04cc";

  assertions = [
    {
      assertion = aspectConfig.telemetry.enable && !rawConfig.services.alloy.enable;
      message = "tailnet composition must enroll telemetry without changing the raw Tailscale feature";
    }
    {
      assertion = rawConfig.tailscale.loginServer == null;
      message = "raw Tailscale feature did not retain a neutral login-server default";
    }
    {
      assertion = rawConfig.tailscale.tailnetDomain == null;
      message = "raw Tailscale feature did not retain a neutral tailnet-domain default";
    }
    {
      assertion = aspectConfig.tailscale.enable;
      message = "tailnet-client aspect did not enable the Tailscale feature";
    }
    {
      assertion = !rawConfig.services.tailscale.enable
        && rawConfig.userEnvironment.sharedModules == [ ];
      message = "disabled Tailscale configured a daemon or attached user modules";
    }
    {
      assertion = aspectConfig.services.tailscale.enable
        && aspectConfig.services.tailscale.extraUpFlags == [ "--login-server=${tailnet.coordinationUrl}" ];
      message = "tailnet-client did not configure the daemon to enroll against the fleet server";
    }
    {
      assertion = customConfig.services.tailscale.extraUpFlags == [ "--login-server=https://override.example.test" ];
      message = "tailnet-client forced fleet policy over a host refinement";
    }
    {
      assertion = aspectConfig.tailscale.loginServer == tailnet.coordinationUrl;
      message = "tailnet-client aspect did not supply the fleet coordination URL";
    }
    {
      assertion = aspectConfig.tailscale.tailnetDomain == tailnet.dnsSuffix;
      message = "tailnet-client aspect did not supply the fleet DNS suffix";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) assertions
  );
in
pkgs.runCommand "tailscale-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      echo "Tailscale assertions failed:" >&2
      sed 's/^/- /' "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
