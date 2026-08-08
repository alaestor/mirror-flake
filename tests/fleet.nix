{ inputs, pkgs, ... }:
let
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ../modules/fleet.nix
      ../modules/fleet/tailnet.nix
      ({ config, ... }: {
        flake.fleetFixture = config.flake.fleet.tailnets."0x04cc";
      })
    ];
  };

  expectedTailnet = {
    coordinationUrl = "https://headscale.0x04.cc";
    dnsSuffix = "tailnet.0x04.cc";
  };

  assertions = [
    {
      assertion = fixture.fleetFixture == expectedTailnet;
      message = "fleet declaration was unavailable to an outer composition module";
    }
    {
      assertion = fixture.nixosConfigurations == { };
      message = "fleet fixture unexpectedly constructed a NixOS configuration";
    }
  ];

  failures = map (result: result.message) (
    builtins.filter (result: !result.assertion) assertions
  );
in
pkgs.runCommand "fleet-test"
  {
    passAsFile = [ "failureReport" ];
    failureReport = builtins.concatStringsSep "\n" failures;
  }
  ''
    if [[ -s "$failureReportPath" ]]; then
      echo "Fleet assertions failed:" >&2
      sed 's/^/- /' "$failureReportPath" >&2
      exit 1
    fi
    touch "$out"
  ''
