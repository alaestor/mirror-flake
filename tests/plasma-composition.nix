{
  inputs,
  pkgs,
  ...
}:
let
  configuration = inputs.unstable-home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      inputs.plasma-manager.homeModules.plasma-manager
      (
        { lib, ... }:
        {
          home = {
            username = "plasma-fixture";
            homeDirectory = "/home/plasma-fixture";
            stateVersion = "24.11";
          };
          programs.plasma = {
            enable = true;
            configFile."fixturerc"."General"."first" = true;
            input.mice = lib.mkBefore [
              {
                name = "first";
                vendorId = "0000";
                productId = "0001";
              }
            ];
          };
        }
      )
      (
        { lib, ... }:
        {
          programs.plasma = {
            configFile."fixturerc"."General"."second" = true;
            input.mice = lib.mkAfter [
              {
                name = "second";
                vendorId = "0000";
                productId = "0002";
              }
            ];
          };
        }
      )
    ];
  };

  plasma = configuration.config.programs.plasma;
  assertions = [
    {
      assertion =
        plasma.configFile."fixturerc"."General".first.value == true
        && plasma.configFile."fixturerc"."General".second.value == true;
      message = "Plasma configFile definitions did not merge recursively";
    }
    {
      assertion = map (mouse: mouse.name) plasma.input.mice == [ "first" "second" ];
      message = "Plasma input.mice did not honor mkBefore and mkAfter priorities";
    }
  ];
  failures = map (result: result.message) (builtins.filter (result: !result.assertion) assertions);
in
pkgs.runCommand "plasma-composition-test"
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
